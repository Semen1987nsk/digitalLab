import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../domain/entities/sensor_data.dart';
import '../../domain/math/crc8.dart';
import '../../domain/repositories/hal_interface.dart';
import 'data_isolate.dart';

// ═══════════════════════════════════════════════════════════════
//  BLE HAL — подключение к мультидатчику по Bluetooth Low Energy
//
//  Протокол (из firmware/src/core/config.h):
//  Service:     e4c8a4e0-1234-5678-9abc-def012345678
//  Data:        e4c8a4e1-...  (Notify — бинарный поток SensorPacket)
//  Command:     e4c8a4e2-...  (Write — команды START/STOP/CALIBRATE)
//  Config:      e4c8a4e3-...  (Read/Write — частота, включённые датчики)
//  Firmware:    e4c8a4e4-...  (Read — версия, батарея)
//
//  Формат данных: бинарный пакет фиксированной структуры (не Protobuf,
//  чтобы минимизировать overhead на ESP32). Порядок полей соответствует
//  proto/sensor_data.proto, но это flat-struct с valid_flags.
// ═══════════════════════════════════════════════════════════════

/// UUIDs сервисов и характеристик (должны совпадать с прошивкой)
class BleUuids {
  static final Guid service = Guid('e4c8a4e0-1234-5678-9abc-def012345678');
  static final Guid charData = Guid('e4c8a4e1-1234-5678-9abc-def012345678');
  static final Guid charCommand = Guid('e4c8a4e2-1234-5678-9abc-def012345678');
  static final Guid charConfig = Guid('e4c8a4e3-1234-5678-9abc-def012345678');
  static final Guid charFirmware = Guid('e4c8a4e4-1234-5678-9abc-def012345678');

  BleUuids._();
}

/// Имя устройства для фильтрации при сканировании
const String kBleDeviceName = 'PhysicsLab';

/// Команды, отправляемые на датчик через Write-характеристику
class BleCommand {
  static const int start = 0x01;
  static const int stop = 0x02;
  static const int calibrate = 0x03;
  static const int setSampleRate = 0x04;
  static const int getInfo = 0x05;
  static const int clearBuffer = 0x06;

  BleCommand._();
}

/// Битовые флаги валидных полей в пакете (соответствуют valid_flags)
// ignore_for_file: unused_field
/// Битовые флаги валидных полей в пакете от ESP32.
/// Соответствуют SensorField в firmware/src/core/ring_buffer.h.
/// Все поля используются в _parseSensorPacket / _parseEnabledSensors.
class _ValidField {
  static const int distance = 1 << 0;
  static const int voltage = 1 << 1;
  static const int current = 1 << 2;
  // power (bit 3) — вычисляемое поле, в SensorPacket не передаётся
  static const int temperature = 1 << 4;
  static const int pressure = 1 << 5;
  static const int humidity = 1 << 6;
  static const int accelX = 1 << 7;
  static const int accelY = 1 << 8;
  static const int accelZ = 1 << 9;
  // gyro (bits 10-12) — зарезервированы для будущих версий
  // thermocouple (bit 13) — зарезервирован
  static const int magneticField = 1 << 14;
  static const int force = 1 << 15;
  static const int lux = 1 << 16;
  static const int radiation = 1 << 17;

  static const int allKnownBits = distance |
      voltage |
      current |
      temperature |
      pressure |
      humidity |
      accelX |
      accelY |
      accelZ |
      magneticField |
      force |
      lux |
      radiation;

  _ValidField._();
}

/// BLE реализация Hardware Abstraction Layer.
///
/// Подключается к ESP32-S3 мультидатчику по BLE 4.1+.
/// Поддерживает:
/// - Сканирование и автоподключение по имени "PhysicsLab"
/// - Подключение к конкретному [targetDevice]
/// - Получение данных через BLE Notify
/// - Отправку команд (старт/стоп/калибровка/частота)
/// - Автопереподключение при разрыве связи
class BleHAL implements HALInterface {
  /// Если задан — подключаемся к конкретному устройству.
  /// Если null — сканируем и подключаемся к первому "PhysicsLab".
  BluetoothDevice? targetDevice;

  BleHAL({this.targetDevice});

  // ── Streams ──────────────────────────────────────────────────

  final _connectionStatusController =
      StreamController<ConnectionStatus>.broadcast();
  final _sensorDataController = StreamController<SensorPacket>.broadcast();

  final DataProcessingIsolate _dataIsolate = DataProcessingIsolate();
  StreamSubscription<SensorPacket>? _isolateSub;

  // ── BLE state ────────────────────────────────────────────────

  BluetoothDevice? _device;
  BluetoothCharacteristic? _dataChar;
  BluetoothCharacteristic? _commandChar;
  BluetoothCharacteristic? _configChar;
  BluetoothCharacteristic? _firmwareChar;

  StreamSubscription<BluetoothConnectionState>? _connectionSub;
  StreamSubscription<List<int>>? _dataSub;
  StreamSubscription<List<ScanResult>>? _scanSub;

  DeviceInfo? _deviceInfo;
  bool _isMeasuring = false;
  bool _disposed = false;
  bool _isCalibrated = false;
  int _sampleRateHz = 10;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 10;
  bool _isConnecting = false;
  bool _isRecoveringDataStall = false;
  DateTime? _lastDataAt;
  Timer? _dataWatchdogTimer;
  Timer? _reconnectTimer; // отменяемый таймер переподключения
  bool _requireFramedPackets = false;

  /// Буфер реконструкции BLE-потока.
  ///
  /// На разных адаптерах/драйверах один SensorPacket может приехать:
  /// - фрагментами (несколько notify),
  /// - пачкой (несколько пакетов в одном notify).
  final List<int> _notifyBuffer = <int>[];

  /// Защита от неограниченного роста буфера при повреждённом потоке.
  static const int _maxNotifyBufferBytes = 1280;

  /// Минимальная версия firmware для текущего BLE пакета.
  static const int _minFwMajor = 1;
  static const int _minFwMinor = 0;
  static const int _minFwPatch = 0;

  // Зарезервировано для фильтрации отдельных каналов BLE.
  // final _signalProcessors = <SensorType, SignalProcessor>{};

  // ── HALInterface getters ─────────────────────────────────────

  @override
  Stream<ConnectionStatus> get connectionStatus =>
      _connectionStatusController.stream;

  @override
  Stream<SensorPacket> get sensorData => _sensorDataController.stream;

  @override
  DeviceInfo? get deviceInfo => _deviceInfo;

  @override
  bool get isCalibrated => _isCalibrated;

  // ── Connect ──────────────────────────────────────────────────

  @override
  Future<bool> connect() async {
    if (_disposed) return false;
    if (_isConnecting) {
      debugPrint('BLE HAL: connect() уже выполняется');
      return false;
    }

    _reconnectTimer
        ?.cancel(); // отменяем отложенный reconnect при ручном подключении
    _reconnectAttempts = 0; // Сброс счётчика при ручном вызове connect()
    _isConnecting = true;

    _connectionStatusController.add(ConnectionStatus.connecting);
    debugPrint('BLE HAL: Начинаю подключение...');

    try {
      // 1) Проверяем поддержку BLE
      if (!await FlutterBluePlus.isSupported) {
        debugPrint('BLE HAL: Bluetooth не поддерживается на этом устройстве');
        _connectionStatusController.add(ConnectionStatus.error);
        return false;
      }

      // 2) Ждём включения адаптера (до 5 секунд)
      final adapterState = await FlutterBluePlus.adapterState
          .where((s) => s == BluetoothAdapterState.on)
          .first
          .timeout(const Duration(seconds: 5), onTimeout: () {
        throw TimeoutException('Bluetooth адаптер не включён');
      });

      if (adapterState != BluetoothAdapterState.on) {
        debugPrint('BLE HAL: Bluetooth выключен');
        _connectionStatusController.add(ConnectionStatus.error);
        return false;
      }

      // 3) Находим устройство
      final device = await _findDevice();
      if (device == null) {
        debugPrint('BLE HAL: Устройство PhysicsLab не найдено');
        _connectionStatusController.add(ConnectionStatus.error);
        return false;
      }

      _device = device;
      debugPrint('BLE HAL: Найдено устройство: ${device.platformName} '
          '(${device.remoteId})');

      // 4) Подключаемся
      await device.connect(
        timeout: const Duration(seconds: 10),
        autoConnect: false,
      );
      debugPrint('BLE HAL: Подключено к ${device.platformName}');

      // 4.5) Запускаем Isolate для парсинга
      if (!_dataIsolate.isRunning) {
        await _dataIsolate.start(deviceType: IsolateDeviceType.bleMultisensor);
        _isolateSub = _dataIsolate.dataStream.listen((packet) {
          _sensorDataController.add(packet);
        });
      }

      // 5) Слушаем разрывы соединения
      _connectionSub?.cancel();
      _connectionSub = device.connectionState.listen((state) {
        if (_disposed) return;
        if (state == BluetoothConnectionState.disconnected) {
          debugPrint('BLE HAL: Соединение потеряно');
          _connectionStatusController.add(ConnectionStatus.disconnected);
          _cleanup();
          // Автопереподключение с экспоненциальным backoff (cap 30s)
          if (!_disposed && _reconnectAttempts < _maxReconnectAttempts) {
            _reconnectAttempts++;
            // Exponential backoff: 2s, 4s, 8s, 16s, 30s, 30s, ...
            final delaySec = (1 << _reconnectAttempts).clamp(2, 30); // 2^n
            final delay = Duration(seconds: delaySec);
            debugPrint(
                'BLE HAL: Автопереподключение #$_reconnectAttempts/$_maxReconnectAttempts через ${delay.inSeconds}с...');
            _reconnectTimer?.cancel();
            _reconnectTimer = Timer(delay, () {
              if (!_disposed) connect();
            });
          } else if (_reconnectAttempts >= _maxReconnectAttempts) {
            debugPrint(
                'BLE HAL: Исчерпаны попытки переподключения ($_maxReconnectAttempts). '
                'Пользователь может нажать "Переподключить" для сброса.');
            _connectionStatusController.add(ConnectionStatus.error);
          }
        }
      });

      // 5.5) MTU negotiation (из исследования Nordic + flutter_blue_plus)
      // Default MTU=23 (payload=20B). Наш пакет ~80B → 5 фрагментов.
      // requestMtu(256) уменьшает до 1 фрагмента → -80% BLE overhead.
      // 350мс predelay (Nordic best practice) — ждём стабилизации L2CAP.
      // На Windows requestMtu() не поддерживается — MTU auto-negotiated.
      try {
        await Future.delayed(const Duration(milliseconds: 350));
        if (_disposed) return false;
        final mtu = await device.requestMtu(256);
        debugPrint('BLE HAL: MTU negotiated: $mtu');
      } catch (e) {
        // requestMtu() не поддерживается на текущей платформе (Windows)
        // или устройство не отвечает — продолжаем с default MTU.
        // _notifyBuffer + фрагментная сборка обработает любой MTU.
        debugPrint('BLE HAL: MTU negotiation unavailable: $e');
      }

      // 6) Обнаруживаем сервисы и характеристики
      final success = await _discoverServices(device);
      if (!success) {
        debugPrint('BLE HAL: Не удалось найти сервис PhysicsLab');
        await device.disconnect();
        _connectionStatusController.add(ConnectionStatus.error);
        return false;
      }

      // 7) Читаем информацию об устройстве
      await _readDeviceInfo();

      // 7.1) Проверка совместимости протокола
      if (_deviceInfo != null &&
          !_isFirmwareCompatible(_deviceInfo!.firmwareVersion)) {
        const requiredVersion = '$_minFwMajor.$_minFwMinor.$_minFwPatch';
        final currentVersion = _deviceInfo!.firmwareVersion;
        debugPrint('BLE HAL: Несовместимая прошивка: $currentVersion '
            '(требуется >= $requiredVersion)');
        await device.disconnect();
        _connectionStatusController.add(ConnectionStatus.error);
        return false;
      }

      // 8) Подписываемся на данные
      await _subscribeToData();

      _reconnectAttempts = 0; // Сброс счётчика при успешном подключении
      _startDataWatchdog();
      _connectionStatusController.add(ConnectionStatus.connected);
      debugPrint('BLE HAL: Готов к работе');
      return true;
    } on TimeoutException catch (e) {
      debugPrint('BLE HAL: Таймаут: $e');
      _connectionStatusController.add(ConnectionStatus.error);
      return false;
    } catch (e, stack) {
      debugPrint('BLE HAL: Ошибка подключения: $e');
      debugPrint('Stack: $stack');
      _connectionStatusController.add(ConnectionStatus.error);
      return false;
    } finally {
      _isConnecting = false;
    }
  }

  /// Сканирование BLE и поиск устройства "PhysicsLab"
  Future<BluetoothDevice?> _findDevice() async {
    // Если целевое устройство задано — используем его напрямую
    if (targetDevice != null) {
      debugPrint('BLE HAL: Используем заданное устройство: '
          '${targetDevice!.platformName}');
      return targetDevice;
    }

    // Проверяем уже привязанные устройства
    final bonded = await FlutterBluePlus.bondedDevices;
    for (final device in bonded) {
      if (device.platformName.contains(kBleDeviceName)) {
        debugPrint('BLE HAL: Найден привязанный PhysicsLab: '
            '${device.remoteId}');
        return device;
      }
    }

    // Сканируем
    debugPrint('BLE HAL: Начинаю сканирование (10 сек)...');
    BluetoothDevice? found;

    final completer = Completer<BluetoothDevice?>();

    _scanSub = FlutterBluePlus.onScanResults.listen(
      (results) {
        for (final result in results) {
          final name = result.device.platformName;
          final advName = result.advertisementData.advName;

          if (name.contains(kBleDeviceName) ||
              advName.contains(kBleDeviceName)) {
            debugPrint('BLE HAL: Найден $name (RSSI: ${result.rssi})');
            found = result.device;
            FlutterBluePlus.stopScan();
            if (!completer.isCompleted) completer.complete(found);
          }
        }
      },
      onError: (e) {
        debugPrint('BLE HAL: Ошибка сканирования: $e');
        if (!completer.isCompleted) completer.complete(null);
      },
    );

    // Запускаем сканирование с фильтром по сервису
    await FlutterBluePlus.startScan(
      withServices: [BleUuids.service],
      timeout: const Duration(seconds: 10),
    );

    // Если сканирование завершилось по таймауту
    if (!completer.isCompleted) {
      completer.complete(found);
    }

    _scanSub?.cancel();
    _scanSub = null;

    return completer.future;
  }

  /// Поиск сервиса и характеристик PhysicsLab
  Future<bool> _discoverServices(BluetoothDevice device) async {
    debugPrint('BLE HAL: Обнаружение сервисов...');
    final services = await device.discoverServices();

    for (final service in services) {
      if (service.uuid == BleUuids.service) {
        debugPrint('BLE HAL: Найден сервис PhysicsLab');

        for (final char in service.characteristics) {
          if (char.uuid == BleUuids.charData) {
            _dataChar = char;
            debugPrint('BLE HAL:   → Data characteristic (Notify)');
          } else if (char.uuid == BleUuids.charCommand) {
            _commandChar = char;
            debugPrint('BLE HAL:   → Command characteristic (Write)');
          } else if (char.uuid == BleUuids.charConfig) {
            _configChar = char;
            debugPrint('BLE HAL:   → Config characteristic (R/W)');
          } else if (char.uuid == BleUuids.charFirmware) {
            _firmwareChar = char;
            debugPrint('BLE HAL:   → Firmware characteristic (Read)');
          }
        }

        // Минимум — нужна Data + Command
        if (_dataChar != null && _commandChar != null) {
          return true;
        }
      }
    }

    debugPrint('BLE HAL: Сервис PhysicsLab не найден среди '
        '${services.length} сервисов');
    return false;
  }

  /// Подписка на Notify-характеристику данных
  Future<void> _subscribeToData() async {
    if (_dataChar == null) return;

    debugPrint('BLE HAL: Подписка на Notify...');
    await _dataChar!.setNotifyValue(true);

    _notifyBuffer.clear();

    _dataSub?.cancel();
    _dataSub = _dataChar!.onValueReceived.listen(
      (value) {
        try {
          if (value.isEmpty) return;
          _lastDataAt = DateTime.now();

          // Отправляем сырые байты в фоновый Isolate для парсинга
          _dataIsolate.processRawData(Uint8List.fromList(value));
        } catch (e) {
          debugPrint('BLE HAL: Ошибка отправки в Isolate: $e');
        }
      },
      onError: (e) {
        debugPrint('BLE HAL: Ошибка потока данных: $e');
      },
    );
  }

  /// Чтение информации об устройстве из Firmware-характеристики
  Future<void> _readDeviceInfo() async {
    String fwVersion = 'unknown';
    int battery = 0;
    List<String> sensors = [];

    // Читаем firmware info
    if (_firmwareChar != null) {
      try {
        final data = await _firmwareChar!.read();
        if (data.length >= 2) {
          // Формат: [major, minor, patch, batteryPercent, ...]
          fwVersion = '${data[0]}.${data[1]}.${data.length > 2 ? data[2] : 0}';
          battery = data.length > 3 ? data[3] : 0;
        }
      } catch (e) {
        debugPrint('BLE HAL: Не удалось прочитать firmware info: $e');
      }
    }

    _requireFramedPackets = _isVersionAtLeast(fwVersion, 1, 1, 0);

    // Читаем конфигурацию (какие датчики включены)
    if (_configChar != null) {
      try {
        final data = await _configChar!.read();
        sensors = _parseEnabledSensors(data);
      } catch (e) {
        debugPrint('BLE HAL: Не удалось прочитать config: $e');
        sensors = [
          'distance',
          'voltage',
          'current',
          'temperature',
          'pressure',
          'acceleration',
          'magnetic_field'
        ];
      }
    }

    if (sensors.isEmpty) {
      // Дефолтный набор Классики
      sensors = [
        'voltage',
        'current',
        'pressure',
        'temperature',
        'acceleration',
        'magnetic_field'
      ];
    }

    _deviceInfo = DeviceInfo(
      name: _device?.platformName ?? 'PhysicsLab',
      firmwareVersion: fwVersion,
      batteryPercent: battery,
      enabledSensors: sensors,
      connectionType: ConnectionType.ble,
    );

    debugPrint('BLE HAL: Device info: $fwVersion, battery=$battery%, '
        'sensors=${sensors.length}, framed=$_requireFramedPackets');
  }

  // ── Disconnect ───────────────────────────────────────────────

  @override
  Future<void> disconnect() async {
    debugPrint('BLE HAL: Отключение...');
    // BLE-1 fix: Cancel reconnect timer BEFORE cleanup to prevent
    // unwanted reconnection after user-initiated disconnect.
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await stopMeasurement();
    _stopDataWatchdog();
    _cleanup();

    try {
      await _device?.disconnect();
    } catch (e) {
      debugPrint('BLE HAL: Ошибка при отключении: $e');
    }
    _device = null;
    _deviceInfo = null;
    _connectionStatusController.add(ConnectionStatus.disconnected);
  }

  void _cleanup() {
    _dataSub?.cancel();
    _dataSub = null;
    _notifyBuffer.clear();
    _requireFramedPackets = false;
    _lastDataAt = null;
    _connectionSub?.cancel();
    _connectionSub = null;
    _scanSub?.cancel();
    _scanSub = null;
    _dataChar = null;
    _commandChar = null;
    _configChar = null;
    _firmwareChar = null;
  }

  void _startDataWatchdog() {
    _stopDataWatchdog();
    _lastDataAt = DateTime.now();
    _dataWatchdogTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_disposed || _isRecoveringDataStall || _device == null) return;
      if (!_isMeasuring) return;

      final last = _lastDataAt;
      if (last == null) return;
      final idleMs = DateTime.now().difference(last).inMilliseconds;

      // Если в режиме измерения нет данных >7с — восстанавливаем соединение.
      if (idleMs > 7000) {
        debugPrint('BLE HAL: Watchdog: нет данных ${idleMs}ms, '
            'выполняю soft-reconnect');
        _recoverFromDataStall();
      }
    });
  }

  void _stopDataWatchdog() {
    _dataWatchdogTimer?.cancel();
    _dataWatchdogTimer = null;
  }

  void _recoverFromDataStall() {
    if (_isRecoveringDataStall || _disposed) return;
    _isRecoveringDataStall = true;

    unawaited(() async {
      try {
        _connectionStatusController.add(ConnectionStatus.connecting);
        await disconnect();
        if (!_disposed) {
          await connect();
        }
      } catch (e) {
        debugPrint('BLE HAL: Watchdog recover error: $e');
      } finally {
        _isRecoveringDataStall = false;
      }
    }());
  }

  // ── Measurement control ──────────────────────────────────────

  @override
  Future<void> startMeasurement() async {
    if (_commandChar == null || _isMeasuring) return;
    _isMeasuring = true;

    await _sendCommand(BleCommand.start);
    debugPrint('BLE HAL: Измерение запущено');
  }

  @override
  Future<void> stopMeasurement() async {
    if (_commandChar == null) return;
    _isMeasuring = false;

    await _sendCommand(BleCommand.stop);
    debugPrint('BLE HAL: Измерение остановлено');
  }

  @override
  Future<void> calibrate(String sensorId) async {
    if (_commandChar == null) return;

    final payload = Uint8List(2 + sensorId.length + 1); // +1 for CRC
    payload[0] = BleCommand.calibrate;
    payload[1] = sensorId.length;
    for (int i = 0; i < sensorId.length; i++) {
      payload[2 + i] = sensorId.codeUnitAt(i);
    }
    payload[payload.length - 1] = crc8(payload.sublist(0, payload.length - 1));

    await _commandChar!.write(payload, withoutResponse: false);
    _isCalibrated = !_isCalibrated;
    debugPrint('BLE HAL: Калибровка $sensorId (calibrated=$_isCalibrated)');
  }

  @override
  Future<void> setSampleRate(int hz) async {
    _sampleRateHz = hz.clamp(1, 1000);

    if (_commandChar == null) return;

    final payload = Uint8List(4); // +1 for CRC
    payload[0] = BleCommand.setSampleRate;
    // Little-endian (ESP32-S3 native byte order)
    payload[1] = _sampleRateHz & 0xFF;
    payload[2] = (_sampleRateHz >> 8) & 0xFF;
    payload[3] = crc8(payload.sublist(0, 3));

    await _commandChar!.write(payload, withoutResponse: false);
    debugPrint('BLE HAL: Частота установлена: $_sampleRateHz Гц');
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _reconnectTimer?.cancel(); // отменяем отложенный reconnect
    _stopDataWatchdog();
    await disconnect();
    await _isolateSub?.cancel();
    await _dataIsolate.dispose();
    await _connectionStatusController.close();
    await _sensorDataController.close();
  }

  // ── Send BLE command ─────────────────────────────────────────

  Future<void> _sendCommand(int cmd) async {
    if (_commandChar == null) return;

    try {
      final payload = Uint8List(2);
      payload[0] = cmd;
      payload[1] = crc8([cmd]);
      await _commandChar!.write(payload, withoutResponse: false);
    } catch (e) {
      debugPrint('BLE HAL: Ошибка отправки команды $cmd: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  Парсинг бинарного пакета от ESP32
  //
  //  Формат flat-struct (little-endian):
  //  Offset  Size  Field
  //  0       4     timestamp_ms      (uint32)
  //  4       4     distance_mm       (float32)
  //  8       4     voltage_v         (float32)
  //  12      4     current_a         (float32)
  //  16      4     power_w           (float32)
  //  20      4     temperature_c     (float32)
  //  24      4     pressure_pa       (float32)
  //  28      4     humidity_pct      (float32)
  //  32      4     accel_x           (float32)
  //  36      4     accel_y           (float32)
  //  40      4     accel_z           (float32)
  //  44      4     gyro_x            (float32)
  //  48      4     gyro_y            (float32)
  //  52      4     gyro_z            (float32)
  //  56      4     thermocouple_c    (float32)
  //  60      4     magnetic_field_mt (float32)  // расширение
  //  64      4     force_n           (float32)  // расширение
  //  68      4     lux_lx            (float32)  // расширение
  //  72      4     radiation_cpm     (float32)  // расширение
  //  76      4     valid_flags       (uint32)
  //  ────────────────────────────────────────────
  //  Total:  80 bytes
  // ═══════════════════════════════════════════════════════════════

  bool _isFirmwareCompatible(String firmwareVersion) {
    final match = RegExp(r'(\d+)\.(\d+)\.(\d+)').firstMatch(firmwareVersion);
    if (match == null) {
      // Если версия не распознана — не блокируем, но логируем.
      debugPrint('BLE HAL: Не удалось распарсить версию: "$firmwareVersion"');
      return true;
    }

    final major = int.tryParse(match.group(1) ?? '') ?? 0;
    final minor = int.tryParse(match.group(2) ?? '') ?? 0;
    final patch = int.tryParse(match.group(3) ?? '') ?? 0;

    if (major != _minFwMajor) {
      return major > _minFwMajor;
    }
    if (minor != _minFwMinor) {
      return minor > _minFwMinor;
    }
    return patch >= _minFwPatch;
  }

  bool _isVersionAtLeast(String version, int major, int minor, int patch) {
    final match = RegExp(r'(\d+)\.(\d+)\.(\d+)').firstMatch(version);
    if (match == null) return false;

    final vMajor = int.tryParse(match.group(1) ?? '') ?? 0;
    final vMinor = int.tryParse(match.group(2) ?? '') ?? 0;
    final vPatch = int.tryParse(match.group(3) ?? '') ?? 0;

    if (vMajor != major) return vMajor > major;
    if (vMinor != minor) return vMinor > minor;
    return vPatch >= patch;
  }

  /// Парсинг списка включённых датчиков из Config-характеристики
  List<String> _parseEnabledSensors(List<int> data) {
    // Формат: bitfield в первых 4 байтах
    if (data.length < 4) return [];

    final bd = ByteData.sublistView(Uint8List.fromList(data));
    final flags = bd.getUint32(0, Endian.little);
    final sensors = <String>[];

    if (flags & _ValidField.voltage != 0) sensors.add('voltage');
    if (flags & _ValidField.current != 0) sensors.add('current');
    if (flags & _ValidField.pressure != 0) sensors.add('pressure');
    if (flags & _ValidField.temperature != 0) sensors.add('temperature');
    if (flags & _ValidField.accelX != 0) sensors.add('acceleration');
    if (flags & _ValidField.magneticField != 0) {
      sensors.add('magnetic_field');
    }
    if (flags & _ValidField.distance != 0) sensors.add('distance');
    if (flags & _ValidField.force != 0) sensors.add('force');
    if (flags & _ValidField.lux != 0) sensors.add('lux');
    if (flags & _ValidField.radiation != 0) sensors.add('radiation');

    return sensors;
  }
}

// ═══════════════════════════════════════════════════════════════
//  Утилиты BLE
// ═══════════════════════════════════════════════════════════════

/// Результат сканирования BLE-устройств
class BleDeviceResult {
  final BluetoothDevice device;
  final String name;
  final int rssi;

  const BleDeviceResult({
    required this.device,
    required this.name,
    required this.rssi,
  });

  @override
  String toString() => '$name ($rssi dBm)';
}
