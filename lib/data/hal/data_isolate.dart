import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../../domain/entities/sensor_data.dart';
import '../../domain/entities/sensor_type.dart';
import '../../domain/math/signal_processor.dart';
import '../../core/logging.dart';

enum IsolateDeviceType {
  arduinoMultisensor,
  ftdiDistance,
  bleMultisensor,
}

/// Параметры для инициализации Isolate
class _DataIsolateParams {
  final SendPort parentSendPort;
  final IsolateDeviceType deviceType;
  final bool enableFiltering;

  const _DataIsolateParams({
    required this.parentSendPort,
    required this.deviceType,
    this.enableFiltering = true,
  });
}

/// Команды управления Isolate
abstract class _IsolateCommand {
  const _IsolateCommand();
}

class _RawDataCommand extends _IsolateCommand {
  final Uint8List data;
  const _RawDataCommand(this.data);
}

class _StopCommand extends _IsolateCommand {
  const _StopCommand();
}

/// Обработчик данных в отдельном Isolate для не блокировки UI
///
/// Выполняет CPU-intensive операции:
/// - Парсинг CSV/бинарных данных
/// - Валидация CRC8
/// - Фильтрация Калмана
/// - Накопление статистики
///
/// Архитектура:
/// ```
/// UI Thread               Data Isolate
///    │                         │
///    ├──> raw bytes ─────────>│
///    │                         ├─> parse
///    │                         ├─> filter
///    │                         ├─> validate
///    │<──── SensorPacket ──────┤
/// ```
class DataProcessingIsolate {
  Isolate? _isolate;
  ReceivePort? _receivePort;
  SendPort? _sendToIsolatePort;

  final StreamController<SensorPacket> _dataController =
      StreamController<SensorPacket>.broadcast();

  bool _isRunning = false;

  /// Stream готовых отфильтрованных пакетов
  Stream<SensorPacket> get dataStream => _dataController.stream;

  /// Статус Isolate
  bool get isRunning => _isRunning;

  /// Запустить обработку в отдельном Isolate.
  ///
  /// Возвращается только после получения SendPort от Isolate
  /// (handshake готовности). Это гарантирует, что
  /// processRawData() не потеряет первые пакеты.
  Future<void> start({
    required IsolateDeviceType deviceType,
    bool enableFiltering = true,
  }) async {
    if (_isRunning) {
      Logger.warning('DataIsolate: уже запущен');
      return;
    }

    _receivePort = ReceivePort();
    final readyCompleter = Completer<void>();

    // Слушаем результаты от Isolate
    _receivePort!.listen((message) {
      if (message is SendPort) {
        // Первое сообщение — SendPort для отправки команд
        _sendToIsolatePort = message;
        Logger.info('DataIsolate: готов к работе');
        if (!readyCompleter.isCompleted) readyCompleter.complete();
      } else if (message is SensorPacket) {
        // Готовый пакет
        _dataController.add(message);
      } else if (message is _IsolateLog) {
        Logger.info(message.message);
      } else if (message is _IsolateError) {
        Logger.error('DataIsolate: ошибка обработки', message.error);
      }
    });

    try {
      _isolate = await Isolate.spawn(
        _isolateEntry,
        _DataIsolateParams(
          parentSendPort: _receivePort!.sendPort,
          deviceType: deviceType,
          enableFiltering: enableFiltering,
        ),
        debugName: 'DataProcessingIsolate',
      );
      _isRunning = true;

      // M2 fix: ждём handshake от Isolate (SendPort), max 5с.
      // Без этого processRawData() может дропать первые пакеты.
      await readyCompleter.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          Logger.warning('DataIsolate: handshake timeout (5s), '
              'продолжаем без гарантии готовности');
        },
      );
      Logger.info('DataIsolate: запущен (type: $deviceType)');
    } catch (e, stack) {
      Logger.error('DataIsolate: ошибка запуска', e, stack);
      await stop();
      rethrow;
    }
  }

  /// Отправить сырые данные на обработку
  void processRawData(Uint8List data) {
    if (!_isRunning || _sendToIsolatePort == null) {
      Logger.warning('DataIsolate: не запущен, данные пропущены');
      return;
    }
    _sendToIsolatePort!.send(_RawDataCommand(data));
  }

  /// Остановить Isolate
  Future<void> stop() async {
    if (!_isRunning) return;

    _sendToIsolatePort?.send(const _StopCommand());
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;

    _receivePort?.close();
    _receivePort = null;
    _sendToIsolatePort = null;

    _isRunning = false;
    Logger.info('DataIsolate: остановлен');
  }

  /// Закрыть все ресурсы
  Future<void> dispose() async {
    await stop();
    await _dataController.close();
  }

  // ═══════════════════════════════════════════════════════════
  //  ISOLATE ENTRY POINT
  // ═══════════════════════════════════════════════════════════

  static Future<void> _isolateEntry(_DataIsolateParams params) async {
    final commandPort = ReceivePort();
    final parentPort = params.parentSendPort;

    // Отправляем SendPort для получения команд
    parentPort.send(commandPort.sendPort);

    // Состояние парсера
    String stringBuffer = '';
    final List<int> bleBuffer = <int>[];
    final processors = <SensorType, SignalProcessor>{};
    int packetsProcessed = 0;
    int crcErrors = 0;

    // Инициализация процессоров для основных каналов
    if (params.enableFiltering) {
      processors[SensorType.distance] = SignalProcessor(
        sensorType: SensorType.distance,
      );
      processors[SensorType.voltage] = SignalProcessor(
        sensorType: SensorType.voltage,
      );
      processors[SensorType.current] = SignalProcessor(
        sensorType: SensorType.current,
      );
      processors[SensorType.temperature] = SignalProcessor(
        sensorType: SensorType.temperature,
      );
    }

    try {
      await for (final command in commandPort) {
        if (command is _StopCommand) {
          break;
        } else if (command is _RawDataCommand) {
          // Обработка сырых данных
          try {
            if (params.deviceType == IsolateDeviceType.bleMultisensor) {
              bleBuffer.addAll(command.data);
              
              // Защита от переполнения
              if (bleBuffer.length > 84 * 16) {
                bleBuffer.clear();
                continue;
              }
              
              while (true) {
                final packet = _tryExtractBlePacket(bleBuffer);
                if (packet == null) break;
                
                parentPort.send(packet);
                packetsProcessed++;
              }
            } else {
              stringBuffer += utf8.decode(command.data, allowMalformed: true);

              while (stringBuffer.contains('\n')) {
                final lineEnd = stringBuffer.indexOf('\n');
                final line = stringBuffer.substring(0, lineEnd).trim();
                stringBuffer = stringBuffer.substring(lineEnd + 1);

                if (line.isEmpty) continue;

                SensorPacket? packet;
                switch (params.deviceType) {
                  case IsolateDeviceType.arduinoMultisensor:
                    packet = _parseMultisensorLine(
                      line,
                      processors,
                      params.enableFiltering,
                    );
                    if (packet == null) {
                      crcErrors++;
                    }
                    break;
                  case IsolateDeviceType.ftdiDistance:
                    packet = _parseDistanceLine(
                      line,
                      processors[SensorType.distance],
                      params.enableFiltering,
                    );
                    break;
                  case IsolateDeviceType.bleMultisensor:
                    break; // Handled above
                }

                if (packet != null) {
                  parentPort.send(packet);
                  packetsProcessed++;

                  // Периодическая статистика (каждые 100 пакетов)
                  if (packetsProcessed % 100 == 0) {
                    final crcRate = packetsProcessed > 0
                        ? (crcErrors / packetsProcessed * 100).toStringAsFixed(1)
                        : '0.0';
                    parentPort.send(
                      _IsolateLog(
                        'DataIsolate: обработано $packetsProcessed пакетов, '
                        'CRC ошибок: $crcErrors ($crcRate%)',
                      ),
                    );
                  }
                }
              }

              // Защита от переполнения буфера
              if (stringBuffer.length > 4096) {
                final lastNewline = stringBuffer.lastIndexOf('\n', stringBuffer.length - 512);
                stringBuffer = lastNewline > 0
                    ? stringBuffer.substring(lastNewline + 1)
                    : stringBuffer.substring(stringBuffer.length - 512);
              }
            }
          } catch (e, stack) {
            parentPort.send(_IsolateError(e, stack));
          }
        }
      }
    } finally {
      commandPort.close();
      parentPort.send(
        _IsolateLog(
          'DataIsolate: завершён (обработано $packetsProcessed пакетов, '
          'CRC ошибок: $crcErrors)',
        ),
      );
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  ПАРСИНГ: Arduino мультидатчик
  // ═══════════════════════════════════════════════════════════

  static SensorPacket? _parseMultisensorLine(
    String line,
    Map<SensorType, SignalProcessor> processors,
    bool enableFiltering,
  ) {
    // Формат: "V:12.34,A:0.56,T:23.4,N:1234,*AB"
    // *AB — CRC8 в hex

    if (!line.contains('*')) return null;

    final parts = line.split('*');
    if (parts.length != 2) return null;

    final data = parts[0];
    final crcHex = parts[1];

    // Валидация CRC8
    final expectedCrc = _crc8(data);
    final receivedCrc = int.tryParse(crcHex, radix: 16);
    if (receivedCrc == null || receivedCrc != expectedCrc) {
      return null; // CRC не совпадает
    }

    int timestampMs = 0;
    double? voltage, current, temperature, pressure, humidity;
    double? distance, acceleration, magneticField, force, lux, radiation;

    final fields = data.split(',');

    for (final field in fields) {
      if (!field.contains(':')) continue;

      final kv = field.split(':');
      if (kv.length != 2) continue;

      final key = kv[0].trim();
      final valueStr = kv[1].trim();
      final value = double.tryParse(valueStr);
      if (value == null) continue;

      switch (key) {
        case 'V':
          voltage = enableFiltering && processors[SensorType.voltage] != null
              ? processors[SensorType.voltage]!.process(value)
              : value;
          break;
        case 'A':
          current = enableFiltering && processors[SensorType.current] != null
              ? processors[SensorType.current]!.process(value)
              : value;
          break;
        case 'T':
          temperature = enableFiltering && processors[SensorType.temperature] != null
              ? processors[SensorType.temperature]!.process(value)
              : value;
          break;
        case 'P':
          pressure = value;
          break;
        case 'H':
          humidity = value;
          break;
        case 'DIST':
          distance = enableFiltering && processors[SensorType.distance] != null
              ? processors[SensorType.distance]!.process(value)
              : value;
          break;
        case 'ACC':
          acceleration = value;
          break;
        case 'MAG':
        case 'M':
          magneticField = value;
          break;
        case 'F':
          force = value;
          break;
        case 'LUX':
          lux = value;
          break;
        case 'RAD':
          radiation = value;
          break;
        case 'N':
          // Sequence number используется для диагностики на стороне HAL.
          // Здесь не сохраняем, чтобы не держать лишнее состояние.
          break;
        case 'TS':
          timestampMs = value.toInt();
          break;
      }
    }

    return SensorPacket(
      timestampMs: timestampMs,
      voltageV: voltage,
      currentA: current,
      temperatureC: temperature,
      pressurePa: pressure,
      humidityPct: humidity,
      distanceMm: distance,
      accelX: acceleration, // Simplified: single axis
      magneticFieldMt: magneticField,
      forceN: force,
      luxLx: lux,
      radiationCpm: radiation,
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  ПАРСИНГ: FTDI датчик расстояния
  // ═══════════════════════════════════════════════════════════

  static SensorPacket? _parseDistanceLine(
    String line,
    SignalProcessor? processor,
    bool enableFiltering,
  ) {
    // Формат: "173 cm" или "1234 mm"
    final match = RegExp(r'(\d+)\s*(cm|mm)').firstMatch(line);
    if (match == null) return null;

    final valueStr = match.group(1);
    final unit = match.group(2);
    if (valueStr == null || unit == null) return null;

    var value = double.tryParse(valueStr);
    if (value == null) return null;

    // Конвертация в мм
    if (unit == 'cm') value *= 10;

    // Фильтрация
    if (enableFiltering && processor != null) {
      value = processor.process(value);
    }

    return SensorPacket(
      timestampMs: 0,
      distanceMm: value,
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  ПАРСИНГ: BLE мультидатчик
  // ═══════════════════════════════════════════════════════════

  static const int _legacyPacketSize = 80;
  static const int _frameHeaderSize = 4;
  static const int _framedPacketSize = _frameHeaderSize + _legacyPacketSize;
  static const int _frameMagic = 0x4C50; // 'PL' little-endian
  static const int _frameProtocolVersion = 1;

  static SensorPacket? _tryExtractBlePacket(List<int> buffer) {
    if (buffer.isEmpty) return null;

    int magicIndex = -1;
    for (int i = 0; i + 1 < buffer.length; i++) {
      final candidate = buffer[i] | (buffer[i + 1] << 8);
      if (candidate == _frameMagic) {
        magicIndex = i;
        break;
      }
    }

    if (magicIndex > 0) {
      buffer.removeRange(0, magicIndex);
    }

    if (magicIndex == -1) {
      if (buffer.length > 1) {
        buffer.removeRange(0, buffer.length - 1);
      }
      return null;
    }

    if (buffer.length < _frameHeaderSize) return null;

    final protocolVersion = buffer[2];
    final payloadSize = buffer[3];
    if (protocolVersion != _frameProtocolVersion ||
        payloadSize != _legacyPacketSize) {
      buffer.removeAt(0);
      return null;
    }

    if (buffer.length < _framedPacketSize) {
      return null;
    }

    final payload = Uint8List.fromList(
      buffer.sublist(_frameHeaderSize, _framedPacketSize),
    );
    final packet = _parseBleSensorPacket(payload);

    if (packet != null) {
      buffer.removeRange(0, _framedPacketSize);
      return packet;
    }

    buffer.removeAt(0);
    return null;
  }

  static SensorPacket? _parseBleSensorPacket(Uint8List data) {
    if (data.length < _legacyPacketSize) return null;

    final byteData = ByteData.sublistView(data);

    final timestamp = byteData.getUint32(0, Endian.little);
    final distance = byteData.getFloat32(4, Endian.little);
    final voltage = byteData.getFloat32(8, Endian.little);
    final current = byteData.getFloat32(12, Endian.little);
    final temperature = byteData.getFloat32(20, Endian.little);
    final pressure = byteData.getFloat32(24, Endian.little);
    final humidity = byteData.getFloat32(28, Endian.little);
    final accelX = byteData.getFloat32(32, Endian.little);
    final accelY = byteData.getFloat32(36, Endian.little);
    final accelZ = byteData.getFloat32(40, Endian.little);
    final magneticField = byteData.getFloat32(60, Endian.little);
    final force = byteData.getFloat32(64, Endian.little);
    final lux = byteData.getFloat32(68, Endian.little);
    final radiation = byteData.getFloat32(72, Endian.little);
    final validFlags = byteData.getUint32(76, Endian.little);

    if (validFlags == 0) return null;

    if (!_isLikelyValidPacket(
      timestamp: timestamp,
      validFlags: validFlags,
      distance: distance,
      voltage: voltage,
      current: current,
      temperature: temperature,
      pressure: pressure,
      humidity: humidity,
      accelX: accelX,
      accelY: accelY,
      accelZ: accelZ,
      magneticField: magneticField,
      force: force,
      lux: lux,
      radiation: radiation,
    )) {
      return null;
    }

    return SensorPacket(
      timestampMs: timestamp,
      voltageV: _ifValid(validFlags, 1 << 1, voltage),
      currentA: _ifValid(validFlags, 1 << 2, current),
      pressurePa: _ifValid(validFlags, 1 << 5, pressure),
      temperatureC: _ifValid(validFlags, 1 << 4, temperature),
      humidityPct: _ifValid(validFlags, 1 << 6, humidity),
      accelX: _ifValid(validFlags, 1 << 7, accelX),
      accelY: _ifValid(validFlags, 1 << 8, accelY),
      accelZ: _ifValid(validFlags, 1 << 9, accelZ),
      magneticFieldMt: _ifValid(validFlags, 1 << 14, magneticField),
      distanceMm: _ifValid(validFlags, 1 << 0, distance),
      forceN: _ifValid(validFlags, 1 << 15, force),
      luxLx: _ifValid(validFlags, 1 << 16, lux),
      radiationCpm: _ifValid(validFlags, 1 << 17, radiation),
    );
  }

  static double? _ifValid(int flags, int bit, double value) {
    if (flags & bit != 0) return value;
    return null;
  }

  static bool _isLikelyValidPacket({
    required int timestamp,
    required int validFlags,
    required double distance,
    required double voltage,
    required double current,
    required double temperature,
    required double pressure,
    required double humidity,
    required double accelX,
    required double accelY,
    required double accelZ,
    required double magneticField,
    required double force,
    required double lux,
    required double radiation,
  }) {
    if (validFlags == 0) return false;

    bool inRange(double v, double min, double max) => v.isFinite && v >= min && v <= max;

    if ((validFlags & (1 << 0)) != 0 && !inRange(distance, 0, 100000)) return false;
    if ((validFlags & (1 << 1)) != 0 && !inRange(voltage, -500, 500)) return false;
    if ((validFlags & (1 << 2)) != 0 && !inRange(current, -100, 100)) return false;
    if ((validFlags & (1 << 4)) != 0 && !inRange(temperature, -100, 300)) return false;
    if ((validFlags & (1 << 5)) != 0 && !inRange(pressure, 1000, 500000)) return false;
    if ((validFlags & (1 << 6)) != 0 && !inRange(humidity, 0, 100)) return false;
    if ((validFlags & (1 << 7)) != 0 && !inRange(accelX, -500, 500)) return false;
    if ((validFlags & (1 << 8)) != 0 && !inRange(accelY, -500, 500)) return false;
    if ((validFlags & (1 << 9)) != 0 && !inRange(accelZ, -500, 500)) return false;
    if ((validFlags & (1 << 14)) != 0 && !inRange(magneticField, -10000, 10000)) return false;
    if ((validFlags & (1 << 15)) != 0 && !inRange(force, -100000, 100000)) return false;
    if ((validFlags & (1 << 16)) != 0 && !inRange(lux, 0, 200000)) return false;
    if ((validFlags & (1 << 17)) != 0 && !inRange(radiation, 0, 1000000)) return false;

    return true;
  }

  // ═══════════════════════════════════════════════════════════
  //  CRC8 (Dallas/Maxim)
  // ═══════════════════════════════════════════════════════════

  static int _crc8(String data) {
    int crc = 0x00;
    for (int i = 0; i < data.length; i++) {
      int b = data.codeUnitAt(i) & 0xFF;
      for (int bit = 0; bit < 8; bit++) {
        if ((crc ^ b) & 0x01 != 0) {
          crc = (crc >> 1) ^ 0x8C;
        } else {
          crc >>= 1;
        }
        b >>= 1;
      }
    }
    return crc & 0xFF;
  }
}

/// Ошибка обработки в Isolate
class _IsolateError {
  final Object error;
  final StackTrace? stackTrace;
  const _IsolateError(this.error, [this.stackTrace]);
}

/// Лог-сообщение из Isolate в основной поток
class _IsolateLog {
  final String message;
  const _IsolateLog(this.message);
}
