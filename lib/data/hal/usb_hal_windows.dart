import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import '../../domain/entities/sensor_data.dart';
import '../../domain/entities/sensor_type.dart';
import '../../domain/repositories/hal_interface.dart';
import '../../domain/math/signal_processor.dart';
import '../../core/logging.dart';
import 'port_scanner.dart';
import 'port_connection_manager.dart';
import 'data_isolate.dart';

/// USB HAL для мультидатчика Labosfera и датчика расстояния V802.
/// Использует flutter_libserialport для Windows/Linux/macOS.
///
/// v0.4 Reliability features:
/// - CRC8 validation on every data line (matches firmware v0.4)
/// - Auto-reconnect with exponential backoff on disconnect
/// - Packet sequence monitoring for loss detection
/// - Per-channel SignalProcessors for all multisensor data
/// - Thread-safe disconnect handling
/// - Robust port selection with fallback
class UsbHALWindows implements HALInterface {
  final _connectionStatusController =
      StreamController<ConnectionStatus>.broadcast();
  final _sensorDataController = StreamController<SensorPacket>.broadcast();

  /// Per-channel signal processors for multisensor (optional filtering)
  // ignore: unused_field
  final Map<SensorType, SignalProcessor> _processors = {};

  /// Менеджер подключений
  final _connectionManager = PortConnectionManager();

  /// Выбранный порт вручную (null = автовыбор)
  String? selectedPort;

  /// Тип устройства, определённый SensorHub при сканировании.
  /// Когда задан вместе с selectedPort → пропускаем _findBestPortAsync().
  IsolateDeviceType? selectedDeviceType;

  SerialPort? _port;

  /// Timer для polling-чтения из COM-порта (10мс интервал).
  /// Заменяет SerialPortReader (который спавнил фоновый Isolate
  /// с sp_wait → WaitForMultipleObjects → heap corruption при закрытии).
  Timer? _readTimer;

  /// Data-flow watchdog: если порт открыт и идёт измерение, но данные
  /// не приходят дольше порога, значит:
  /// - Arduino зависло на I2C (дешёвый BME280 заблокировал шину)
  /// - Кабель имеет частичный контакт (D+/D- не пропускает данные)
  /// - USB-драйвер OS в stall-состоянии
  /// Watchdog принудительно дёргает _handleDisconnect() →
  /// SensorHub сделает quick rescan через 1.5с.
  Timer? _dataWatchdogTimer;
  DateTime? _lastDataReceivedAt;

  /// Arduino мультидатчик: 2с (100 Гц → 200 пропущенных пакетов = серьёзно)
  /// FTDI дальномер: 5с (10 Гц, лазер может тормозить на отражающих поверхностях)
  static const int _watchdogThresholdArduinoMs = 2000;
  static const int _watchdogThresholdFtdiMs = 5000;
  int get _dataWatchdogThresholdMs =>
      _deviceType == IsolateDeviceType.ftdiDistance
          ? _watchdogThresholdFtdiMs
          : _watchdogThresholdArduinoMs;

  String _buffer = '';
  int _timestampMs = 0;
  int _startTimeMs = 0;
  bool _isMeasuring = false;
  double _calibrationOffset = 0.0;
  double _lastRawValue = 0.0;
  int _connectTimeMs = 0;
  Timer? _healthCheckTimer;
  String? _connectedPortName;
  bool _isConnected = false;

  /// Флаг: ресурсы освобождены, операции запрещены
  bool _disposed = false;

  /// Последняя ошибка подключения (человекочитаемая, на русском)
  String? _lastError;

  /// Получить последнюю ошибку (для UI)
  String? get lastError => _lastError;

  /// Флаг: подключение в процессе (защита от двойного вызова)
  bool _isConnecting = false;

  /// Флаг: отключение в процессе (защита от двойного вызова)
  bool _isDisconnecting = false;

  /// Таймер ожидания DATA_START (отменяется при disconnect/dispose)
  Timer? _dataStartTimer;

  /// Тип подключённого устройства
  IsolateDeviceType _deviceType = IsolateDeviceType.ftdiDistance;

  /// Получен ли маркер DATA_START (для мультидатчика)
  bool _dataStartReceived = false;

  /// Версия прошивки из заголовка
  String _firmwareVersion = '';

  /// Базовый timestamp Arduino при старте измерения
  int _arduinoBaseTimestamp = 0;

  DeviceInfo? _deviceInfo;

  // ═══════════════════════════════════════════════════════════
  //  PACKET INTEGRITY
  // ═══════════════════════════════════════════════════════════

  /// Last seen packet sequence number (from N: field)
  int _lastPacketN = 0;

  /// Total packets received
  int _totalPacketsReceived = 0;

  /// Total CRC errors
  int _crcErrors = 0;

  /// Total packets with sequence gaps (lost)
  int _lostPackets = 0;

  /// Whether firmware supports CRC (auto-detected)
  bool _firmwareHasCrc = false;

  /// Безопасное освобождение ресурсов последовательного порта (v3).
  ///
  /// v3: Без SerialPortReader / фонового Isolate.
  /// Чтение через Timer.periodic(10мс) + sp_nonblocking_read на main thread.
  /// Отсутствие Isolate означает:
  /// - Нет zombie native thread с копией Pointer<sp_port>
  /// - Нет гонки sp_wait/WaitForMultipleObjects vs CloseHandle
  /// - Нет _CrtIsValidHeapPointer crash от cross-thread free()
  /// - Cleanup мгновенный — не нужно ждать 700мс+1200мс
  ///
  /// Порядок очистки:
  /// 1. Отменить Timer (мгновенно, ~0мс)
  /// 2. Закрыть порт (sp_close → CloseHandle, ~1мс)
  /// 3. Подождать 300мс — Windows USB-драйвер завершает IRP_MJ_CLOSE
  ///
  /// НЕ вызываем port.dispose() (sp_free_port):
  /// Timer callback мог уже начать выполнение _pollSerialPort() и
  /// захватить port в локальную переменную до обнуления _port.

  /// Safely closes and disposes a SerialPort in a background Isolate
  /// to prevent blocking the Flutter UI thread on Windows.
  static void _closePortSafe(SerialPort? port) {
    if (port == null) return;
    final address = port.address;
    unawaited(Isolate.run(() {
      try {
        final isolatePort = SerialPort.fromAddress(address);
        if (isolatePort.isOpen) {
          isolatePort.close();
        }
        isolatePort.dispose();
      } catch (_) {}
    }));
  }

  /// Micro-leak ~200 байт — ничтожно. ОС освобождает при выходе.
  Future<void> _cleanupSerialResources({
    required Timer? readTimer,
    required SerialPort? port,
  }) async {
    debugPrint('USB HAL cleanup v3: начало '
        '(timer=${readTimer != null ? "да" : "нет"}, '
        'port=${port != null ? "да" : "нет"})');

    // ── Step 1: Stop polling timer (instant) ──────────────────
    // Timer.cancel() prevents future _pollSerialPort() callbacks.
    // Any already-executing callback will see _isDisconnecting=true
    // and return early (Dart is single-threaded, no true concurrency).
    readTimer?.cancel();

    // ── Step 2: Close native OS handle in Isolate ─────────────
    // sp_close() → CloseHandle(port->hdl) + overlapped events.
    // On Windows, CloseHandle() on a physically unplugged CDC ACM device
    // can block the calling thread for 10-20 seconds waiting for IRP_MJ_CLOSE.
    // We offload this to an Isolate to prevent freezing the Flutter UI.
    _closePortSafe(port);

    // ── Step 3: Brief yield for Windows USB driver ────────────
    // After CloseHandle(), USB serial driver processes IRP_MJ_CLOSE
    // asynchronously. 300ms covers CH340/FTDI/usbser.sys.
    // (v2 needed 1900ms total due to Isolate — no longer needed.)
    if (port != null) {
      await Future.delayed(const Duration(milliseconds: 300));
    }

    // NO port.dispose() — intentional micro-leak (~200 bytes).
    // See doc comment above.

    debugPrint('USB HAL cleanup v3: завершено');
  }

  @override
  Stream<ConnectionStatus> get connectionStatus =>
      _connectionStatusController.stream;

  @override
  Stream<SensorPacket> get sensorData => _sensorDataController.stream;

  @override
  DeviceInfo? get deviceInfo => _deviceInfo;

  /// Получить список доступных COM-портов
  static List<String> getAvailablePorts() {
    return SerialPort.availablePorts;
  }

  /// Diagnostic stats
  String get diagnostics =>
      'pkts=$_totalPacketsReceived crc_err=$_crcErrors lost=$_lostPackets';

  // Known USB Vendor IDs
  static const int _vidArduino = 0x2341; // Arduino LLC (UNO, Mega)
  static const int _vidFtdi = 0x0403; // FTDI (FT232R — distance sensor)
  static const int _vidCH340 = 0x1A86; // WCH CH340 (Arduino clones)
  static const int _vidCP210x = 0x10C4; // Silicon Labs CP210x (Arduino clones)

  /// Найти лучший порт с проверкой VID/PID.
  ///
  /// Приоритет:
  /// 1. Ручной выбор (`selectedPort`)
  /// 2. Arduino по VID (0x2341, 0x1A86, 0x10C4)
  /// 3. FTDI по VID (0x0403)
  /// 4. Любой USB-порт (не COM1/COM2) — fallback
  Future<PortInfo?> _findBestPortAsync() async {
    debugPrint('USB HAL: Поиск датчика...');

    // ── 1. Ручной выбор ──────────────────────────────────
    if (selectedPort != null) {
      debugPrint('USB HAL: Используем вручную выбранный порт: $selectedPort');
      // Попытаемся определить тип даже для ручного порта
      final type = _probePortType(selectedPort!);
      return PortInfo(
        name: selectedPort!,
        description: 'Ручной выбор',
        manufacturer: '',
        type: type,
        availability: PortAvailability.untested,
      );
    }

    // ── 2. Получаем список реально активных USB-портов ───────
    // НЕ используем SerialPort.availablePorts для автовыбора:
    // на Windows он видит ghost/disabled COM-устройства через SetupDi,
    // из-за чего приложение пытается подключаться к отключённым Arduino.
    final List<(String, int, int)> detectedPorts;
    try {
      detectedPorts = await PortConnectionManager.enumeratePortsAsync();
      debugPrint(
        'USB HAL: Активные USB-порты: '
        '${detectedPorts.map((p) => '${p.$1}(vid=0x${p.$2.toRadixString(16)},pid=0x${p.$3.toRadixString(16)})').toList()}',
      );
    } catch (e) {
      debugPrint('USB HAL: Ошибка получения списка портов: $e');
      return null;
    }

    if (detectedPorts.isEmpty) {
      debugPrint('USB HAL: Нет активных USB COM-портов');
      return null;
    }

    // ── 3. Проверяем VID/PID каждого порта ───────────────
    PortInfo? bestArduino;
    PortInfo? bestFtdi;
    PortInfo? bestUnknownUsb;

    for (final (name, rawVid, rawPid) in detectedPorts) {
      final int? vid = rawVid == 0 ? null : rawVid;
      final int? pid = rawPid == 0 ? null : rawPid;
      String description = '';
      const String manufacturer = '';
      PortType type = PortType.unknown;

      // Классифицируем по VID
      if (vid == _vidArduino || vid == _vidCH340 || vid == _vidCP210x) {
        type = PortType.arduino;
        description = vid == _vidArduino
            ? 'Arduino'
            : (vid == _vidCH340 ? 'CH340' : 'CP210x');
      } else if (vid == _vidFtdi) {
        type = PortType.ftdi;
        description = 'FTDI';
      } else if (vid != null && vid > 0) {
        // Неизвестный USB — возможно наш
        description = 'USB VID:0x${vid.toRadixString(16)}';
      }

      debugPrint('USB HAL:   $name → VID=0x${(vid ?? 0).toRadixString(16)} '
          'PID=0x${(pid ?? 0).toRadixString(16)} type=$type');

      final info = PortInfo(
        name: name,
        description: description,
        manufacturer: manufacturer,
        type: type,
        availability: PortAvailability.untested,
        vendorId: vid,
        productId: pid,
      );

      // Распределяем по категориям
      if (type == PortType.arduino) {
        bestArduino ??= info;
      } else if (type == PortType.ftdi) {
        bestFtdi ??= info;
      } else if (vid != null && vid > 0) {
        bestUnknownUsb ??= info;
      }
    }

    // ── 4. Возвращаем лучший вариант ─────────────────────
    if (bestArduino != null) {
      debugPrint('USB HAL: ✓ Найден Arduino мультидатчик: ${bestArduino.name}');
      return bestArduino;
    }

    if (bestFtdi != null) {
      debugPrint('USB HAL: ✓ Найден FTDI датчик расстояния: ${bestFtdi.name}');
      return bestFtdi;
    }

    if (bestUnknownUsb != null) {
      debugPrint(
          'USB HAL: ⚠ Неизвестный USB: ${bestUnknownUsb.name} — пробуем как мультидатчик');
      return PortInfo(
        name: bestUnknownUsb.name,
        description: bestUnknownUsb.description,
        manufacturer: '',
        type: PortType.arduino, // assume Arduino as fallback
        availability: PortAvailability.untested,
        vendorId: bestUnknownUsb.vendorId,
        productId: bestUnknownUsb.productId,
      );
    }

    debugPrint('USB HAL: ✗ USB-датчики не найдены');
    return null;
  }

  /// Быстрая проверка типа порта по VID (для ручного выбора)
  PortType _probePortType(String portName) {
    PortType result = PortType.unknown;
    try {
      final port = SerialPort(portName);
      try {
        final vid = port.vendorId;
        if (vid == _vidArduino || vid == _vidCH340 || vid == _vidCP210x) {
          result = PortType.arduino;
        } else if (vid == _vidFtdi) {
          result = PortType.ftdi;
        }
      } catch (_) {}
      // ALWAYS dispose — previous code leaked handle on early return
      _closePortSafe(port);
    } catch (_) {}
    return result;
  }

  @override
  Future<bool> connect() async {
    if (_disposed) {
      Logger.warning('USB HAL: connect() после dispose — игнорируем');
      return false;
    }
    if (_isConnecting) {
      debugPrint('USB HAL: connect() уже выполняется — игнорируем');
      return false;
    }
    if (_isConnected) {
      debugPrint('USB HAL: уже подключены к $_connectedPortName');
      return true;
    }

    // ── CRITICAL FIX: Set flag BEFORE any await ──────────────
    // Without this, two concurrent connect() calls can both pass
    // the _isConnecting check, await the disconnect wait, and then
    // both try to open the same COM port → errno=5 (Access Denied).
    // Dart's event loop is single-threaded but yields at every await,
    // allowing interleaving of async calls.
    _isConnecting = true;
    _lastError = null; // Clear previous error for fresh attempt
    _connectionStatusController.add(ConnectionStatus.connecting);

    // Wait for in-progress disconnect to finish (max 3s).
    // _cleanupSerialResources v3 is fast (~300ms), but disconnect()
    // may be running other teardown logic. 3s is generous.
    if (_isDisconnecting) {
      debugPrint('USB HAL: connect() во время отключения — ждём...');
      for (int i = 0; i < 30 && _isDisconnecting && !_disposed; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      if (_disposed) {
        _isConnecting = false;
        return false;
      }
      if (_isDisconnecting) {
        debugPrint('USB HAL: disconnect() зависло — принудительный сброс');
        _isDisconnecting = false;
      }
    }

    // No artificial delay before connect.
    // _cleanupSerialResources v3 handles driver IRP_MJ_CLOSE internally.
    // PortConnectionManager.connect() has its own yield + probe cycle.

    try {
      return await _connectInternal().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('USB HAL: Таймаут подключения (10 сек)');
          _lastError = 'Подключение заняло больше времени, чем ожидалось. '
              'Проверьте USB-подключение датчика и повторите попытку.';

          // Signal _connectInternal to stop (it checks _isConnecting)
          _isConnecting = false;

          // ── ATOMIC OWNERSHIP cleanup ──
          _dataStartTimer?.cancel();
          _dataStartTimer = null;
          _healthCheckTimer?.cancel();
          _healthCheckTimer = null;

          final timer = _readTimer;
          final port = _port;
          _readTimer = null;
          _port = null;

          unawaited(
            _cleanupSerialResources(
              readTimer: timer,
              port: port,
            ),
          );

          _isConnected = false;
          _connectedPortName = null;
          _connectionStatusController.add(ConnectionStatus.error);
          return false;
        },
      );
    } catch (e, stack) {
      debugPrint('USB HAL: Критическая ошибка: $e');
      debugPrint('Stack: $stack');
      _connectionStatusController.add(ConnectionStatus.error);
      return false;
    } finally {
      _isConnecting = false;
    }
  }

  Future<bool> _connectInternal() async {
    try {
      await Future.delayed(const Duration(milliseconds: 50));
      if (!_isConnecting || _disposed) return false; // cancelled by timeout

      // ── Определяем порт и тип устройства ────────────────
      String portName;
      bool isArduino;

      if (selectedPort != null && selectedDeviceType != null) {
        // Fast path: SensorHub уже определил порт + тип через Isolate-scan.
        // ZERO FFI на main thread.
        portName = selectedPort!;
        _deviceType = selectedDeviceType!;
        isArduino = _deviceType == IsolateDeviceType.arduinoMultisensor;
        debugPrint(
            'USB HAL: $portName [${isArduino ? "мультидатчик" : "расстояние"}] (SensorHub)');
      } else if (selectedPort != null) {
        // selectedPort задан вручную, но тип неизвестен → быстрый VID-probe
        portName = selectedPort!;
        final type = _probePortType(portName);
        isArduino = type == PortType.arduino || type == PortType.unknown;
        _deviceType = isArduino
            ? IsolateDeviceType.arduinoMultisensor
            : IsolateDeviceType.ftdiDistance;
        debugPrint(
            'USB HAL: $portName [${isArduino ? "мультидатчик" : "расстояние"}] (ручной)');
      } else {
        // Полный auto-detect (legacy single-device mode)
        final portInfo = await _findBestPortAsync();
        if (portInfo == null) {
          debugPrint('USB HAL: Датчик не найден');
          _connectionStatusController.add(ConnectionStatus.error);
          return false;
        }
        portName = portInfo.name;
        isArduino = portInfo.type == PortType.arduino ||
            portInfo.type == PortType.unknown;
        _deviceType = isArduino
            ? IsolateDeviceType.arduinoMultisensor
            : IsolateDeviceType.ftdiDistance;
      }

      if (!_isConnecting || _disposed) return false; // cancelled by timeout

      final config =
          isArduino ? PortConfig.multisensorDefault : PortConfig.sensorDefault;

      Logger.info('USB HAL: Подключение к $portName '
          '[${isArduino ? "мультидатчик 115200" : "расстояние 9600"}]');

      final result = await _connectionManager.connect(portName, config: config);

      if (!_isConnecting || _disposed) {
        // Timeout fired while we were connecting.
        //
        // CRITICAL: Do NOT call result.port.close() / .dispose() here!
        // port.close() → sp_close() → CloseHandle() is SYNCHRONOUS FFI.
        // On Arduino CDC ACM (usbser.sys), CloseHandle() can block the
        // main event loop for 10-20 seconds waiting for IRP_MJ_CLOSE.
        // This blocks ALL subsequent connect attempts (SensorHub serial).
        //
        // Intentional micro-leak (~200 bytes per timeout):
        // OS reclaims the handle at process exit. Timeouts are rare
        // (cold start only), so leak is negligible.
        debugPrint('USB HAL: timeout — порт leaked (avoid blocking close)');
        return false;
      }

      if (!result.success) {
        final errMsg = result.errorMessage ?? '';
        debugPrint('USB HAL: Подключение неудачно: $errMsg');

        // errno=121 = "Semaphore timeout" — USB driver is frozen
        // This happens when port was improperly closed (crash, power glitch).
        // The ONLY fix is physical USB replug. Expose clear message to user.
        if (errMsg.contains('код 31') || errMsg.contains('не готово')) {
          _lastError = 'Устройство $portName инициализируется. '
              'Подключение повторится автоматически через несколько секунд.';
        } else if (errMsg.contains('121') ||
            errMsg.contains('семафор') ||
            errMsg.contains('semaphore') ||
            errMsg.contains('timeout')) {
          _lastError = 'Драйвер порта $portName завис. '
              'Переподключите USB-кабель датчика (вытащите и вставьте обратно).';
        } else if (errMsg.contains('errno=5') || errMsg.contains('Доступ')) {
          _lastError = 'Порт $portName занят. '
              'Закройте Arduino IDE / другие программы и повторите.';
        } else {
          _lastError = errMsg;
        }

        _connectionStatusController.add(ConnectionStatus.error);
        return false;
      }

      _port = result.port;
      Logger.info('USB HAL: Порт открыт методом: ${result.methodUsed}');

      _firmwareVersion = isArduino ? 'Labosfera v0.4' : 'FT232R';
      _dataStartReceived = !isArduino;
      _firmwareHasCrc = false; // Will be auto-detected

      // Reset packet stats
      _lastPacketN = 0;
      _totalPacketsReceived = 0;
      _crcErrors = 0;
      _lostPackets = 0;

      // DATA_START timeout for Arduino
      if (isArduino) {
        _dataStartTimer?.cancel();
        _dataStartTimer = Timer(const Duration(seconds: 5), () {
          if (!_dataStartReceived && _isConnected && !_disposed) {
            debugPrint(
                'USB HAL: DATA_START не получен за 5с — начинаем парсинг');
            _dataStartReceived = true;
          }
        });
      }

      _deviceInfo = DeviceInfo(
        name: isArduino
            ? 'Мультидатчик ($portName)'
            : 'Датчик расстояния ($portName)',
        firmwareVersion: _firmwareVersion,
        batteryPercent: 100,
        enabledSensors: isArduino
            // Do not assume sensors before '# SENSORS:' arrives from firmware.
            // This avoids false positives in UI and keeps source-of-truth in firmware.
            ? <String>[]
            : ['distance'],
        connectionType: ConnectionType.usb,
      );

      // No extra delay here — PortConnectionManager.connect() already waits
      // 300ms for Arduino DTR/bootloader stabilization.

      if (!_isConnecting || _disposed) {
        // Cancelled during stabilization — clean up
        _closePortSafe(_port);
        _port = null;
        return false;
      }

      _connectedPortName = portName;
      _isConnected = true;
      _connectTimeMs = DateTime.now().millisecondsSinceEpoch;
      _buffer = '';

      // Парсинг данных выполняется на main thread через _processIncomingData().
      // DataIsolate НЕ используется: при 100 Гц парсинг CSV тривиален (~0.1мс),
      // а протокол Arduino (DATA_START, # SENSORS, CRC авто-детект) требует
      // состояния, которое корректно обрабатывается только в UsbHALWindows.

      _startReading();
      _startHealthCheck();

      _connectionStatusController.add(ConnectionStatus.connected);
      Logger.info('USB HAL: Подключено к $portName');
      return true;
    } catch (e, stack) {
      debugPrint('USB HAL: Ошибка подключения: $e');
      debugPrint('Stack: $stack');
      _connectionStatusController.add(ConnectionStatus.error);
      // Atomic cleanup
      final port = _port;
      _port = null;
      _closePortSafe(port);
      return false;
    }
  }

  /// Запускает Timer-based polling для чтения данных из COM-порта.
  ///
  /// Использует Timer.periodic(10мс) + sp_nonblocking_read вместо
  /// SerialPortReader (который спавнил фоновый Isolate с sp_wait).
  ///
  /// Преимущества:
  /// - Нет Isolate → нет zombie native thread → нет heap corruption
  /// - port.close() работает мгновенно → reconnect без задержек 1.9с
  /// - Нет WaitForMultipleObjects race condition
  /// - CPU overhead: ~200 FFI вызовов/сек × <10мкс = <0.2% CPU
  void _startReading() {
    if (_disposed) return;
    if (_port == null || !_port!.isOpen) {
      Logger.warning('USB HAL: Порт не открыт для чтения');
      return;
    }

    _readTimer?.cancel();
    _readTimer = Timer.periodic(const Duration(milliseconds: 10), (_) {
      _pollSerialPort();
    });

    // ── Data-Flow Watchdog ──────────────────────────────────
    // Проверяем каждые 500мс: если данные не приходили > 2с,
    // значит датчик молчит (зависший I2C, плохой кабель).
    // Тригерим disconnect → SensorHub quick-rescan → auto-reconnect.
    _lastDataReceivedAt = DateTime.now();
    _dataWatchdogTimer?.cancel();
    _dataWatchdogTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _checkDataFlowWatchdog();
    });

    debugPrint('USB HAL: Чтение запущено (Timer-polling, 10мс, watchdog=2с)');
  }

  /// Читает данные из COM-порта (вызывается Timer каждые ~10мс).
  ///
  /// sp_input_waiting() + sp_nonblocking_read() — оба non-blocking FFI
  /// на main thread. При 115200 бод: ~115 байт за 10мс — легко
  /// помещается в Windows kernel buffer (4096 байт по умолчанию).
  ///
  /// При физическом отключении USB:
  /// - sp_input_waiting → ClearCommError → FALSE → возвращает -1
  /// - Детектим available < 0 → вызываем _handleDisconnect()
  void _pollSerialPort() {
    if (_disposed || !_isConnected || _isDisconnecting) return;
    final port = _port;
    if (port == null) return;

    try {
      final available = port.bytesAvailable;
      if (available > 0) {
        final data = port.read(available);
        if (data.isNotEmpty) {
          _processIncomingData(data);
        }
      } else if (available < 0) {
        // sp_input_waiting returned error — device disconnected
        debugPrint('USB HAL: bytesAvailable=$available — устройство отключено');
        _handleDisconnect();
      }
      // available == 0 → no data this tick, skip
    } catch (e) {
      // Unexpected error (port closed externally, driver crash, etc.)
      if (_isConnected && !_isDisconnecting) {
        debugPrint('USB HAL: Ошибка чтения: $e');
        _handleDisconnect();
      }
    }
  }

  void _startHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _checkConnection();
    });
  }

  void _checkConnection() {
    if (_disposed ||
        !_isConnected ||
        _isDisconnecting ||
        _connectedPortName == null) {
      return;
    }

    try {
      final port = _port;
      if (port == null || !port.isOpen) {
        debugPrint('USB HAL: Порт $_connectedPortName закрыт!');
        _handleDisconnect();
      }
    } catch (e) {
      debugPrint('USB HAL: Ошибка проверки порта: $e');
      _handleDisconnect();
    }
  }

  /// Data-Flow Watchdog: обнаружение "живого" но молчащего устройства.
  ///
  /// Сценарии:
  /// 1. Arduino I2C зависло (BME280 заблокировал шину) → Serial.print
  ///    перестаёт работать → порт открыт, bytesAvailable=0 бесконечно.
  /// 2. Кабель с плохим контактом: D+/D- искажаются → данные мусор
  ///    или пустота, но ClearCommError всё равно возвращает 0.
  /// 3. Windows usbser.sys в stall: порт "открыт" но IRP_MJ_READ
  ///    не завершается.
  ///
  /// Все 3 случая: порт открыт, healthCheck видит isOpen=true,
  /// но пакеты не приходят. Без watchdog — бесконечное молчание.
  void _checkDataFlowWatchdog() {
    if (_disposed || !_isConnected || _isDisconnecting) return;

    final lastData = _lastDataReceivedAt;
    if (lastData == null) return;

    final silenceMs = DateTime.now().difference(lastData).inMilliseconds;

    // Только если данные УЖЕ приходили (dataStartReceived) и
    // молчание превысило порог. До DATA_START не трогаем —
    // Arduino может долго грузиться (bootloader 1-3с).
    if (_dataStartReceived && silenceMs > _dataWatchdogThresholdMs) {
      debugPrint('USB HAL: ⚠️ Data-flow watchdog: нет данных $silenceMs мс '
          '(порог: $_dataWatchdogThresholdMs мс). '
          'Принудительное переподключение.');
      _handleDisconnect();
    }
  }

  /// Обработка отключения датчика — THREAD-SAFE (atomic port ownership)
  ///
  /// Может быть вызван из: stream onError, stream onDone, health check.
  /// Все пути гарантированно безопасны даже при одновременном вызове.
  ///
  /// Pattern: "take ownership" — копируем ссылки в локальные переменные
  /// и ОБНУЛЯЕМ поля ДО cleanup. Второй вызов видит null → skip.
  void _handleDisconnect() {
    // Guard against double-call from stream error + health check
    if (!_isConnected || _isDisconnecting) return;
    _isDisconnecting = true;

    Logger.info('USB HAL: Датчик отключён ($_connectedPortName)');
    _isConnected = false;
    _connectedPortName = null;

    // Stop all timers
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;
    _dataStartTimer?.cancel();
    _dataStartTimer = null;
    _dataWatchdogTimer?.cancel();
    _dataWatchdogTimer = null;

    // ── ATOMIC OWNERSHIP: take refs → null fields ──
    // This prevents double-free if disconnect() races with us.
    final timer = _readTimer;
    final port = _port;
    _readTimer = null;
    _port = null;

    _deviceInfo = null;

    // ── Emit disconnected IMMEDIATELY (before cleanup delay) ──────
    // v4.0 FIX: Previously status was emitted in whenComplete() AFTER
    // 300ms cleanup delay. This slowed SensorHub's quick rescan trigger.
    // Now: emit instantly → SensorHub schedules rescan immediately.
    // connect() has _isDisconnecting guard → waits for cleanup to finish.
    if (!_disposed) {
      _connectionStatusController.add(ConnectionStatus.disconnected);
    }

    unawaited(
      _cleanupSerialResources(
        readTimer: timer,
        port: port,
      ).whenComplete(() {
        _isDisconnecting = false;

        // ── Reset session state (same as manual disconnect) ──
        // Without this, reconnected sessions inherit stale state:
        //   _isMeasuring=true → packet timestamps wrong
        //   _dataStartReceived=true → header parsing skipped
        //   _buffer not empty → corrupt first parse
        _buffer = '';
        _timestampMs = 0;
        _startTimeMs = 0;
        _connectTimeMs = 0;
        _isMeasuring = false;
        _dataStartReceived = false;
        _arduinoBaseTimestamp = 0;
        _lastDataReceivedAt = null;
        _lastError = null;
        // Status already emitted above — no duplicate.
      }),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  CRC8 (Dallas/Maxim, polynomial 0x31 reflected)
  //  Must match firmware crc8() exactly!
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

  // ═══════════════════════════════════════════════════════════
  //  DATA PROCESSING
  // ═══════════════════════════════════════════════════════════

  void _processIncomingData(Uint8List data) {
    if (_disposed || !_isConnected || _isDisconnecting) return;
    // Feed data-flow watchdog: данные приходят → датчик жив
    _lastDataReceivedAt = DateTime.now();
    _buffer += utf8.decode(data, allowMalformed: true);

    while (true) {
      final newlineIndex = _buffer.indexOf('\n');
      if (newlineIndex == -1) break;

      final line = _buffer.substring(0, newlineIndex).trim();
      _buffer = _buffer.substring(newlineIndex + 1);

      if (line.isNotEmpty) {
        switch (_deviceType) {
          case IsolateDeviceType.arduinoMultisensor:
            _parseMultisensorLine(line);
            break;
          case IsolateDeviceType.ftdiDistance:
            _parseDistanceLine(line);
            break;
          case IsolateDeviceType.bleMultisensor:
            break; // Not handled by USB
        }
      }
    }

    // Protect against buffer overflow — preserve line boundary
    // Previous code: substring(len-512) could cut a line in half
    // → corrupt parse → CRC error or bad value → dropped packet.
    if (_buffer.length > 2048) {
      final keepFrom = _buffer.lastIndexOf('\n', _buffer.length - 512);
      _buffer = keepFrom != -1
          ? _buffer.substring(keepFrom + 1)
          : _buffer.substring(_buffer.length - 512);
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  ПАРСИНГ: Arduino мультидатчик (with CRC8 validation)
  // ═══════════════════════════════════════════════════════════

  static const _sensorCodeMap = {
    'V': 'voltage',
    'A': 'current',
    'T': 'temperature',
    'P': 'pressure',
    'H': 'humidity',
    'ACC': 'acceleration',
    'AX': 'acceleration',
    'AY': 'acceleration',
    'AZ': 'acceleration',
    'MAG': 'magnetic_field',
    'M': 'magnetic_field',
    'DIST': 'distance',
    'F': 'force',
    'LUX': 'lux',
    'RAD': 'radiation',
  };

  /// Data field keys that are NOT sensors (metadata fields).
  static const _nonSensorKeys = {'N', 'T_MS', 'BAT', 'ERR'};

  void _parseSensorCapabilities(String sensorList) {
    final codes = sensorList.split(',').map((s) => s.trim()).toList();
    final enabled =
        codes.map((code) => _sensorCodeMap[code]).whereType<String>().toList();

    if (enabled.isNotEmpty) {
      debugPrint('USB HAL: Датчики прошивки: $enabled');
      _deviceInfo = DeviceInfo(
        name: _deviceInfo?.name ?? 'Мультидатчик',
        firmwareVersion: _firmwareVersion,
        batteryPercent: _deviceInfo?.batteryPercent ?? 100,
        enabledSensors: enabled,
        connectionType: ConnectionType.usb,
      );
    }
  }

  /// Auto-detect enabled sensors from actual data field keys.
  ///
  /// When Arduino firmware doesn't send `# SENSORS:` header, we infer
  /// which sensors are present from the keys in each data packet
  /// (e.g. V:2.51 → 'voltage', T:28.0 → 'temperature').
  /// Updates [_deviceInfo.enabledSensors] when new sensors appear.
  void _autoDetectSensors(Map<String, double> fields) {
    final info = _deviceInfo;
    if (info == null) return;

    final currentSensors = info.enabledSensors.toSet();
    var changed = false;

    for (final key in fields.keys) {
      if (_nonSensorKeys.contains(key)) continue;
      final sensorId = _sensorCodeMap[key];
      if (sensorId != null && !currentSensors.contains(sensorId)) {
        currentSensors.add(sensorId);
        changed = true;
      }
    }

    if (changed) {
      _deviceInfo = DeviceInfo(
        name: info.name,
        firmwareVersion: info.firmwareVersion,
        batteryPercent: info.batteryPercent,
        enabledSensors: currentSensors.toList(),
        connectionType: info.connectionType,
      );
      debugPrint(
          'USB HAL: Автоопределение датчиков: ${currentSensors.toList()}');
    }
  }

  /// Парсинг строки мультидатчика.
  ///
  /// Формат v0.4: `V:7.537,A:0.839,...,N:42,T_MS:514*A3`
  /// Где *A3 = CRC8 hex checksum (optional, auto-detected)
  void _parseMultisensorLine(String line) {
    // Skip header until DATA_START
    if (!_dataStartReceived) {
      if (line.contains('LABOSFERA') || line.contains('Labosfera')) {
        final versionMatch = RegExp(r'v[\d.]+').firstMatch(line);
        if (versionMatch != null) {
          _firmwareVersion = 'Labosfera ${versionMatch.group(0)}';
          _deviceInfo = DeviceInfo(
            name: _deviceInfo?.name ?? 'Мультидатчик',
            firmwareVersion: _firmwareVersion,
            batteryPercent: _deviceInfo?.batteryPercent ?? 100,
            enabledSensors: _deviceInfo?.enabledSensors ?? [],
            connectionType: ConnectionType.usb,
          );
        }
      }

      if (line.startsWith('# SENSORS:')) {
        _parseSensorCapabilities(
          line.substring('# SENSORS:'.length).trim(),
        );
      }

      // Auto-detect CRC support from header
      if (line.contains('CRC: CRC8')) {
        _firmwareHasCrc = true;
        debugPrint('USB HAL: Прошивка поддерживает CRC8');
      }

      if (line == 'DATA_START') {
        _dataStartReceived = true;
        debugPrint(
            'USB HAL: DATA_START получен (CRC=${_firmwareHasCrc ? "ON" : "OFF"})');
        _connectionStatusController.add(ConnectionStatus.connected);
      }
      return;
    }

    // Skip comments
    if (line.startsWith('#')) return;

    try {
      String dataLine = line;

      // === CRC8 Validation ===
      // Format: "V:1.234,...,T_MS:500*A3"
      final crcIndex = line.lastIndexOf('*');
      if (crcIndex != -1 && crcIndex < line.length - 1) {
        final crcHex = line.substring(crcIndex + 1);
        dataLine = line.substring(0, crcIndex);

        // Validate CRC
        final expectedCrc = int.tryParse(crcHex, radix: 16);
        if (expectedCrc != null) {
          _firmwareHasCrc = true;
          final actualCrc = _crc8(dataLine);
          if (actualCrc != expectedCrc) {
            _crcErrors++;
            if (_crcErrors % 10 == 1) {
              debugPrint(
                  'USB HAL: CRC ошибка! expected=0x${crcHex.toUpperCase()} '
                  'actual=0x${actualCrc.toRadixString(16).toUpperCase()} '
                  'total=$_crcErrors');
            }
            return; // DISCARD corrupted packet
          }
        }
      } else if (_firmwareHasCrc) {
        // Firmware should have CRC but this line doesn't — corrupted
        _crcErrors++;
        return;
      }

      // Parse key:value pairs
      final fields = <String, double>{};

      for (final pair in dataLine.split(',')) {
        final colonIdx = pair.indexOf(':');
        if (colonIdx == -1) continue;

        final key = pair.substring(0, colonIdx).trim();
        final valueStr = pair.substring(colonIdx + 1).trim();
        final value = double.tryParse(valueStr);
        if (value != null) {
          fields[key] = value;
        }
      }

      if (fields.isEmpty) return;

      // ── Runtime capability discovery ──
      // Arduino firmware may not send '# SENSORS:' header, so we infer
      // enabled sensors from actual data field keys in each packet.
      // This runs on every packet but the Set comparison is O(n) with n≤12.
      _autoDetectSensors(fields);

      _totalPacketsReceived++;

      // === Packet sequence monitoring ===
      if (fields.containsKey('N')) {
        final packetN = fields['N']!.toInt();
        if (_lastPacketN > 0 && packetN > _lastPacketN + 1) {
          final gap = packetN - _lastPacketN - 1;
          _lostPackets += gap;
          if (gap > 5) {
            debugPrint(
                'USB HAL: Потеряно $gap пакетов! (N: $_lastPacketN → $packetN)');
          }
        }
        _lastPacketN = packetN;
      }

      // Timestamp: use T_MS from Arduino
      final int timestamp;
      if (fields.containsKey('T_MS')) {
        final rawMs = fields['T_MS']!.toInt();
        if (_isMeasuring) {
          if (_arduinoBaseTimestamp == 0) {
            _arduinoBaseTimestamp = rawMs;
            timestamp = 0;
          } else {
            timestamp = rawMs - _arduinoBaseTimestamp;
          }
        } else {
          if (_connectTimeMs > 0) {
            timestamp = DateTime.now().millisecondsSinceEpoch - _connectTimeMs;
          } else {
            timestamp = rawMs;
          }
        }
      } else {
        final baseMs = _isMeasuring && _startTimeMs > 0
            ? _startTimeMs
            : (_connectTimeMs > 0
                ? _connectTimeMs
                : DateTime.now().millisecondsSinceEpoch);
        timestamp = DateTime.now().millisecondsSinceEpoch - baseMs;
      }

      final packet = SensorPacket(
        timestampMs: timestamp,
        voltageV: fields['V'],
        currentA: fields['A'],
        temperatureC: fields['T'],
        pressurePa: fields['P'],
        humidityPct: fields['H'],
        accelX: fields['AX'] != null ? fields['AX']! * 9.80665 : null,
        accelY: fields['AY'] != null ? fields['AY']! * 9.80665 : null,
        accelZ: fields['AZ'] != null ? fields['AZ']! * 9.80665 : null,
        magneticFieldMt: fields['M'],
        distanceMm: fields['DIST'],
        forceN: fields['F'],
        luxLx: fields['LUX'],
        radiationCpm: fields['RAD'],
      );

      _sensorDataController.add(packet);

      // Debug: every 10th packet
      if (_totalPacketsReceived % 10 == 1) {
        debugPrint('USB HAL TX: pkt#${fields['N']?.toInt()} t=${timestamp}ms '
            'V=${fields['V']?.toStringAsFixed(2)} '
            'T=${fields['T']?.toStringAsFixed(1)} '
            'P=${fields['P']?.toStringAsFixed(0)}');
      }

      // Debug: packet loss stats every 100 packets
      if (_totalPacketsReceived % 100 == 0 && _lostPackets > 0) {
        debugPrint('USB HAL: Stats: rx=$_totalPacketsReceived '
            'lost=$_lostPackets crc_err=$_crcErrors');
      }
    } catch (e) {
      debugPrint('USB HAL: Ошибка парсинга: "$line" → $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  ПАРСИНГ: FTDI датчик расстояния V802
  // ═══════════════════════════════════════════════════════════

  void _parseDistanceLine(String line) {
    final regex =
        RegExp(r'(\d+\.?\d*)\s*(?:cm|см|mm|мм)?', caseSensitive: false);
    final match = regex.firstMatch(line);

    if (match != null) {
      final valueStr = match.group(1);
      if (valueStr != null) {
        var rawValue = double.tryParse(valueStr);

        if (rawValue != null) {
          if (line.toLowerCase().contains('cm') ||
              line.toLowerCase().contains('см')) {
            rawValue *= 10;
          }

          _lastRawValue = rawValue;

          final calibratedValue = rawValue + _calibrationOffset;
          final baseMs = _startTimeMs > 0
              ? _startTimeMs
              : (_connectTimeMs > 0
                  ? _connectTimeMs
                  : DateTime.now().millisecondsSinceEpoch);
          _timestampMs = DateTime.now().millisecondsSinceEpoch - baseMs;

          final packet = SensorPacket(
            timestampMs: _timestampMs,
            distanceMm: calibratedValue,
          );

          _totalPacketsReceived++;

          _sensorDataController.add(packet);
        }
      }
    }
  }

  @override
  Future<void> disconnect() async {
    if (!_isConnected && _port == null) {
      debugPrint('USB HAL: disconnect() — уже отключены');
      return;
    }

    // Prevent _handleDisconnect from running in parallel
    if (_isDisconnecting) {
      debugPrint('USB HAL: disconnect() — отключение уже в процессе');
      return;
    }
    _isDisconnecting = true;
    debugPrint('USB HAL: disconnect() вызван');

    _isConnected = false;
    _connectedPortName = null;

    // Stop all timers
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;
    _dataStartTimer?.cancel();
    _dataStartTimer = null;
    _dataWatchdogTimer?.cancel();
    _dataWatchdogTimer = null;

    // ── ATOMIC OWNERSHIP: take refs → null fields → THEN cleanup ──
    // Same pattern as _handleDisconnect(). If _handleDisconnect() fires
    // concurrently (e.g., from stream error during our cleanup), it will
    // see _isDisconnecting=true and skip.
    final timer = _readTimer;
    final port = _port;
    _readTimer = null;
    _port = null;

    await _cleanupSerialResources(
      readTimer: timer,
      port: port,
    );

    _buffer = '';
    _timestampMs = 0;
    _startTimeMs = 0;
    _connectTimeMs = 0;
    _isMeasuring = false;
    _dataStartReceived = false;
    _arduinoBaseTimestamp = 0;
    _lastDataReceivedAt = null;
    _deviceInfo = null;

    _isDisconnecting = false;

    if (!_disposed) {
      _connectionStatusController.add(ConnectionStatus.disconnected);
    }
  }

  @override
  Future<void> startMeasurement() async {
    _buffer = '';
    _timestampMs = 0;
    _arduinoBaseTimestamp = 0;
    _isMeasuring = true;

    if (_deviceType == IsolateDeviceType.ftdiDistance) {
      _startTimeMs = DateTime.now().millisecondsSinceEpoch;
    } else {
      _startTimeMs = 0;
    }

    debugPrint('USB HAL: Измерение начато (${_deviceType.name})');
  }

  @override
  Future<void> stopMeasurement() async {
    _isMeasuring = false;
    debugPrint('USB HAL: Измерение остановлено');
  }

  @override
  Future<void> calibrate(String sensorId) async {
    if (_calibrationOffset != 0.0) {
      _calibrationOffset = 0.0;
      debugPrint('USB HAL: Калибровка СБРОШЕНА.');
    } else {
      if (_lastRawValue > 0) {
        _calibrationOffset = -_lastRawValue;
        debugPrint(
            'USB HAL: Калибровка нуля. Offset = ${_calibrationOffset.toStringAsFixed(1)} мм');
      } else {
        debugPrint('USB HAL: Нет данных для калибровки.');
      }
    }
  }

  @override
  bool get isCalibrated => _calibrationOffset != 0.0;

  @override
  Future<void> setSampleRate(int hz) async {
    // Sample rate is controlled by firmware
  }

  /// Тип подключённого устройства (для UI)
  IsolateDeviceType get deviceType => _deviceType;

  Future<void> sendCommand(String command) async {
    if (_port == null || !_port!.isOpen) return;

    try {
      _port!.write(Uint8List.fromList('$command\n'.codeUnits));
    } catch (e) {
      debugPrint('USB HAL: Ошибка отправки команды: $e');
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    debugPrint('USB HAL: dispose()');

    await disconnect();

    try {
      await _connectionStatusController.close();
    } catch (_) {}
    try {
      await _sensorDataController.close();
    } catch (_) {}
  }
}
