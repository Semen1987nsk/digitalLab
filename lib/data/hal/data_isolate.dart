import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../../domain/entities/sensor_data.dart';
import '../../domain/entities/sensor_type.dart';
import '../../domain/math/signal_processor.dart';
import '../../core/logging.dart';
import 'packet_parsers.dart';

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
                final packet = PacketParsers.tryExtractBlePacket(bleBuffer);
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
                    packet = PacketParsers.parseMultisensorLine(
                      line,
                      processors,
                      params.enableFiltering,
                    );
                    if (packet == null) {
                      crcErrors++;
                    }
                    break;
                  case IsolateDeviceType.ftdiDistance:
                    // Standalone V802 distance device — фильтрация без UI-маппинга.
                    packet = PacketParsers.parseDistanceLine(line, null, false);
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
                        ? (crcErrors / packetsProcessed * 100)
                            .toStringAsFixed(1)
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
                final lastNewline =
                    stringBuffer.lastIndexOf('\n', stringBuffer.length - 512);
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

  // Парсинг пакетов выделен в `packet_parsers.dart` (PacketParsers) —
  // там же тесты в `test/unit/hal/packet_parsers_test.dart`.
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
