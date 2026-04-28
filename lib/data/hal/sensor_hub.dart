import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../domain/entities/sensor_data.dart';
import '../../domain/repositories/hal_interface.dart';
import '../../core/logging.dart';
import '../../core/cancellation_token.dart';
import 'port_connection_manager.dart';
import 'port_scanner.dart'; // PortType enum
import 'usb_hal_windows.dart';
import 'data_isolate.dart';

/// Описание подключённого устройства в хабе
class HubDevice {
  /// Уникальный ID (например, "COM3", "COM4")
  final String id;

  /// Человекочитаемое имя ("Мультидатчик (COM3)")
  final String name;

  /// HAL-экземпляр
  final HALInterface hal;

  /// Текущий статус
  ConnectionStatus status;

  /// Последняя ошибка (для UI)
  String? lastError;

  /// Счётчик принятых пакетов
  int packetsReceived = 0;

  /// Время последнего пакета (для расчёта pkt/s)
  DateTime? lastPacketTime;

  /// Скользящее окно timestamps для расчёта pkt/s
  final List<DateTime> _packetTimestamps = [];

  /// Пакетов в секунду (скользящее среднее за 3 сек)
  double get packetsPerSecond {
    final now = DateTime.now();
    _packetTimestamps.removeWhere(
      (t) => now.difference(t).inMilliseconds > 3000,
    );
    if (_packetTimestamps.isEmpty) return 0;
    return _packetTimestamps.length / 3.0;
  }

  /// Зафиксировать приход пакета
  void recordPacket() {
    packetsReceived++;
    final now = DateTime.now();
    lastPacketTime = now;
    _packetTimestamps.add(now);
    // Обрезаем окно (макс 300 записей за 3 сек при 100 Гц)
    if (_packetTimestamps.length > 300) {
      _packetTimestamps.removeRange(0, _packetTimestamps.length - 300);
    }
  }

  HubDevice({
    required this.id,
    required this.name,
    required this.hal,
    this.status = ConnectionStatus.disconnected,
  });
}

// ═══════════════════════════════════════════════════════════════════
//  SensorHub — Composite HAL для одновременной работы с N устройствами
//
//  Архитектурный паттерн: как Vernier LabQuest / PASCO Capstone.
//
//  • Управляет несколькими HALInterface одновременно
//  • Мержит SensorPacket потоки → единый выходной Stream
//  • Сам реализует HALInterface → весь UI работает без изменений
//  • connect() подключает ВСЕ зарегистрированные устройства
//  • Каждое устройство заполняет СВОИ поля в SensorPacket
// ═══════════════════════════════════════════════════════════════════

class SensorHub implements HALInterface {
  final _statusController = StreamController<ConnectionStatus>.broadcast();
  final _dataController = StreamController<SensorPacket>.broadcast();

  /// Auto-detect mode: сканирует USB-порты при первом connect().
  /// false = устройства добавлены вручную через addDevice().
  /// true = SensorHub найдёт устройства через Isolate-based scan.
  final bool autoDetect;

  /// Последняя ошибка сканирования (для UI через SensorConnectionController)
  String? lastScanError;

  SensorHub({this.autoDetect = false});

  /// Зарегистрированные устройства
  final List<HubDevice> _devices = [];

  /// Подписки на данные каждого устройства
  final Map<String, StreamSubscription<SensorPacket>> _dataSubs = {};

  /// Подписки на статус каждого устройства
  final Map<String, StreamSubscription<ConnectionStatus>> _statusSubs = {};

  /// Счётчик пропусков порта в scan (защита от transient-glitch)
  final Map<String, int> _missingPortCounters = {};

  /// Cooldown для авто-reconnect (ms since epoch)
  final Map<String, int> _reconnectAfterMs = {};

  /// Consecutive reconnect failures per device → exponential backoff.
  /// Prevents blocking UI thread: COM3 with errno=31 retries can freeze
  /// the main isolate for 5-10s per attempt (FFI openReadWrite is sync).
  final Map<String, int> _consecutiveDeviceFailures = {};

  /// Consecutive scan failure counter.
  /// When scan times out (FFI hung), do NOT remove devices — they may
  /// still be streaming data. Only reset on successful scan.
  int _consecutiveScanFailures = 0;

  /// Таймер hot-plug мониторинга (Plug & Play) — фоновый
  Timer? _hotplugTimer;

  /// Авто-восстановление: true если quick-rescan запланирован
  /// или есть устройства в очереди на reconnect (exponential backoff).
  /// UI показывает "Восстановление связи..." вместо "Отключён" — менее
  /// пугающе для учителя.
  bool get isRecovering {
    if (_disposed) return false;
    if (_quickRescanTimer?.isActive == true) return true;
    // Есть устройства с запланированным reconnect (cooldown не истёк)
    if (_reconnectAfterMs.isNotEmpty) return true;
    return false;
  }

  /// Quick-rescan таймер: срабатывает через 1.5с после отключения.
  /// Обеспечивает быстрое переподключение (~3с вместо ~9с).
  Timer? _quickRescanTimer;

  /// Scan/Connect guard flags (исключаем гонки)
  bool _scanInProgress = false;
  bool _connectInProgress = false;

  /// Cancellation tokens для безопасного прерывания операций
  CancellationToken? _currentConnectToken;
  CancellationToken? _currentScanToken;

  bool _disposed = false;

  /// Список подключённых устройств (для UI)
  List<HubDevice> get devices => List.unmodifiable(_devices);

  /// Количество подключённых устройств
  int get connectedCount =>
      _devices.where((d) => d.status == ConnectionStatus.connected).length;

  /// Общий статус хаба
  ConnectionStatus get currentStatus {
    if (_devices.isEmpty) return ConnectionStatus.disconnected;
    if (_devices.any((d) => d.status == ConnectionStatus.connected)) {
      return ConnectionStatus.connected;
    }
    if (_devices.any((d) => d.status == ConnectionStatus.connecting)) {
      return ConnectionStatus.connecting;
    }
    if (_devices.any((d) => d.status == ConnectionStatus.error)) {
      return ConnectionStatus.error;
    }
    return ConnectionStatus.disconnected;
  }

  /// Создаёт HubDevice из результата PortConnectionManager.scanPorts().
  HubDevice _buildDeviceFromDetectedPort(DetectedPort d) {
    final usbHal = UsbHALWindows()
      ..selectedPort = d.name
      // Передаём тип устройства → UsbHALWindows пропустит _findBestPortAsync()
      // и не будет делать FFI-вызовы VID/PID на main thread.
      ..selectedDeviceType =
          (d.type == PortType.arduino || d.type == PortType.unknown)
              ? IsolateDeviceType.arduinoMultisensor
              : IsolateDeviceType.ftdiDistance;

    return HubDevice(
      id: d.name,
      name: '${d.typeName} (${d.name})',
      hal: usbHal,
    );
  }

  /// Подключает одно устройство с timeout и человекочитаемой ошибкой.
  Future<bool> _connectSingleDevice(HubDevice device) async {
    if (_disposed) return false;

    try {
      debugPrint('SensorHub: подключение ${device.name}...');
      device.lastError = null;

      // Per-device timeout — не ждём бесконечно на зависшем порту.
      // 12с = до 5с retry при errno=31 + 3с Arduino bootloader + 4с запас.
      // errno=31 (ERROR_GEN_FAILURE) — Windows USB driver needs 1-2s per retry.
      final ok = await device.hal.connect().timeout(
        const Duration(seconds: 12),
        onTimeout: () {
          debugPrint('SensorHub: ⏱ таймаут ${device.name} (12 сек)');
          return false;
        },
      );

      if (ok) {
        debugPrint('SensorHub: ✓ ${device.name} подключён');
        return true;
      }

      // Получаем конкретную ошибку из HAL
      String error = 'Не удалось подключить';
      if (device.hal is UsbHALWindows) {
        error = (device.hal as UsbHALWindows).lastError ?? error;
      }
      device.lastError = autoDetect
          ? '$error Идёт автоматическое восстановление подключения.'
          : error;
      debugPrint('SensorHub: ✗ ${device.name}: $error');
      return false;
    } catch (e) {
      const msg = 'Подключение временно недоступно.';
      device.lastError = autoDetect
          ? '$msg Идёт автоматическое восстановление подключения.'
          : msg;
      debugPrint('SensorHub: ✗ ${device.name} ошибка: $e');
      return false;
    } finally {
      // Обновляем UI после каждого устройства (per-device progress)
      _statusController.add(currentStatus);
    }
  }

  /// Сканирует USB-порты и синхронизирует topology хаба:
  /// - добавляет новые устройства,
  /// - удаляет отсутствующие (после 2 пропусков),
  /// - опционально авто-подключает новые.
  Future<void> _refreshTopology({required bool connectNew}) async {
    if (_disposed || _scanInProgress) return;
    if (_connectInProgress && connectNew) return;

    // ── NOTE: No early-return optimization here ──
    // Previously we skipped scans when all devices were connected to avoid
    // SetupDi deadlock (sp_list_ports → SetupDiGetClassDevs mutex hang).
    //
    // This was REMOVED because:
    //   1. Scanning now uses Registry ("reg query"), NOT SetupDi/FFI.
    //      Registry reads are <10ms, never deadlock, run in Isolate.
    //   2. The optimization BLOCKED hot-plug detection of re-plugged devices.
    //      Scenario: COM4 unplugged→removed, COM3 still connected →
    //      "all connected" → scan skipped → COM4 never rediscovered.
    //   3. Cost of scanning: ~10ms every 3s in background Isolate = negligible.

    // Отменяем предыдущую операцию сканирования
    _currentScanToken?.cancel();
    _currentScanToken = CancellationToken();
    final token = _currentScanToken!;

    _scanInProgress = true;
    try {
      final detected = await PortConnectionManager.scanPorts();
      if (_disposed) return;

      // ── Scan FAILED (timeout/error) — do NOT touch topology ──
      // If FFI hung (Windows SetupDi* APIs), scanPorts returns null.
      // Critical: do NOT increment miss counters or remove devices.
      // Streaming devices are still alive — only the scan is broken.
      if (detected == null) {
        _consecutiveScanFailures++;
        if (_consecutiveScanFailures % 5 == 0) {
          debugPrint(
            'SensorHub: ⚠ $_consecutiveScanFailures consecutive scan failures',
          );
        }
        if (_devices.isEmpty) {
          lastScanError = 'Не удалось просканировать USB-порты. '
              'Попробуйте ещё раз.';
        }
        return;
      }
      _consecutiveScanFailures = 0;

      final detectedByName = <String, DetectedPort>{
        for (final d in detected) d.name: d,
      };

      // ── Add newly detected ports ──
      final newDevices = <HubDevice>[];
      for (final d in detected) {
        if (_devices.any((dev) => dev.id == d.name)) {
          _missingPortCounters[d.name] = 0;
          continue;
        }

        final hubDevice = _buildDeviceFromDetectedPort(d);
        addDevice(hubDevice);
        _missingPortCounters[d.name] = 0;
        newDevices.add(hubDevice);
      }

      // ── Remove missing ports (smart debounce) ──
      // Устройство уже отключено + порт пропал → удаляем сразу.
      // Устройство подключено + порт пропал → debounce (2 scan miss)
      // защита от transient-глитчей Windows SetupDi.
      for (final dev in List<HubDevice>.from(_devices)) {
        if (detectedByName.containsKey(dev.id)) {
          _missingPortCounters[dev.id] = 0;
          continue;
        }

        // Device already disconnected/error and port is gone → remove now.
        // No debounce needed — the HAL already confirmed disconnect.
        if (dev.status != ConnectionStatus.connected) {
          debugPrint(
              'SensorHub: порт ${dev.id} отсутствует (уже отключён) → remove');
          await removeDevice(dev.id);
          _missingPortCounters.remove(dev.id);
          continue;
        }

        // Connected device missing from scan → transient glitch protection
        final misses = (_missingPortCounters[dev.id] ?? 0) + 1;
        _missingPortCounters[dev.id] = misses;
        if (misses >= 2) {
          debugPrint('SensorHub: порт ${dev.id} исчез (2 scan miss) → remove');
          await removeDevice(dev.id);
          _missingPortCounters.remove(dev.id);
        }
      }

      // ── Auto-connect newly attached devices ──
      if (connectNew && newDevices.isNotEmpty) {
        for (final dev in newDevices) {
          if (token.isCancelled || _disposed) break;
          await _connectSingleDevice(dev);
          await Future.delayed(const Duration(milliseconds: 150));
        }
      }

      // ── Auto-reconnect existing failed/disconnected devices ──
      // Fixes transient Windows open errors (e.g. errno=0 right after hotplug).
      if (connectNew) {
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        for (final dev in List<HubDevice>.from(_devices)) {
          if (token.isCancelled || _disposed) break;
          if (dev.status == ConnectionStatus.connected ||
              dev.status == ConnectionStatus.connecting) {
            continue;
          }

          final allowAt = _reconnectAfterMs[dev.id] ?? 0;
          if (nowMs < allowAt) continue;

          final ok = await _connectSingleDevice(dev);
          // ── EXPONENTIAL BACKOFF ──
          // COM3 with errno=31 blocks UI thread for 5-10s per attempt
          // (FFI openReadWrite is synchronous). Exponential backoff prevents
          // hammering a broken port every 3s and freezing the chart.
          //
          // Schedule: 3s → 6s → 15s → 30s → 60s (cap)
          // On success: reset immediately.
          if (!ok) {
            final fails = (_consecutiveDeviceFailures[dev.id] ?? 0) + 1;
            _consecutiveDeviceFailures[dev.id] = fails;
            final cooldownMs = switch (fails) {
              1 => 3000,
              2 => 6000,
              3 => 15000,
              4 => 30000,
              _ => 60000,
            };
            _reconnectAfterMs[dev.id] =
                DateTime.now().millisecondsSinceEpoch + cooldownMs;
            if (fails >= 3) {
              debugPrint('SensorHub: ${dev.id} — $fails consecutive failures, '
                  'backoff ${cooldownMs ~/ 1000}s');
            }
          } else {
            _reconnectAfterMs.remove(dev.id);
            _consecutiveDeviceFailures.remove(dev.id);
          }

          if (ok) {
            dev.lastError = null;
          }

          await Future.delayed(const Duration(milliseconds: 120));
        }
      }

      if (detected.isEmpty && _devices.isEmpty) {
        lastScanError = 'USB-датчики не найдены. '
            'Подключите устройство — оно определится автоматически.';
      }

      _statusController.add(currentStatus);
    } catch (e) {
      debugPrint('SensorHub: ошибка scan topology: $e');
    } finally {
      _scanInProgress = false;
    }
  }

  /// Запускает hot-plug мониторинг USB (Plug & Play).
  ///
  /// Поведение:
  /// - подключили новый датчик → добавится и подключится автоматически;
  /// - вытащили датчик → аккуратно удалится из topology.
  void _startHotplugMonitor() {
    if (!autoDetect || _disposed || _hotplugTimer != null) return;

    _hotplugTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_disposed) return;
      unawaited(_refreshTopology(connectNew: true));
    });

    debugPrint('SensorHub: Plug & Play monitor started (3s)');
  }

  /// Запланировать быстрое повторное сканирование после отключения датчика.
  ///
  /// Вызывается когда UsbHALWindows обнаруживает потерю связи (физическое
  /// отключение USB). Вместо ожидания 3с hot-plug таймера,
  /// немедленно планирует рескан через 1.5с.
  ///
  /// Таймлайн Plug-and-Play:
  ///   0мс:     Пользователь вытаскивает USB
  ///   ~10мс:   _pollSerialPort детектит bytesAvailable<0
  ///   ~310мс:  _cleanupSerialResources(300мс) завершена
  ///   ~310мс:  status=disconnected → SensorHub запускает quick rescan
  ///   ~1810мс: Quick rescan срабатывает (1.5с после disconnect)
  ///   ~1820мс: Registry scan (<10мс)
  ///   ~1820мс: Устройство найдено → connect()
  ///   ~3000мс: Подключено! (~1.2с probe + open + Arduino boot)
  ///
  /// Итого: ~3сек от втыкания до работы. (v1 было ~9сек)
  void _scheduleQuickRescan() {
    if (_disposed || !autoDetect) return;

    // Debounce: если несколько устройств отключились одновременно,
    // делаем один рескан, не N.
    _quickRescanTimer?.cancel();
    _quickRescanTimer = Timer(const Duration(milliseconds: 1500), () {
      if (_disposed) return;
      debugPrint('SensorHub: ⚡ Quick rescan (post-disconnect Plug & Play)');
      unawaited(_refreshTopology(connectNew: true));
    });
  }

  // ═════════════════════════════════════════════════════════════
  //  УПРАВЛЕНИЕ УСТРОЙСТВАМИ
  // ═════════════════════════════════════════════════════════════

  /// Добавить устройство в хаб
  void addDevice(HubDevice device) {
    if (_disposed) return;
    if (_devices.any((d) => d.id == device.id)) {
      debugPrint('SensorHub: устройство ${device.id} уже зарегистрировано');
      return;
    }
    _devices.add(device);
    debugPrint('SensorHub: + ${device.name} (${device.id})');

    // Подписываемся на статус
    _statusSubs[device.id] = device.hal.connectionStatus.listen((status) {
      device.status = status;
      debugPrint('SensorHub: ${device.id} → $status');
      _statusController.add(currentStatus);

      // ── Plug & Play: мгновенная реакция на отключение ──
      // Когда устройство отключается, сбрасываем cooldown
      // и запускаем быстрое сканирование через 1.5с.
      // 1.5с = 300мс cleanup + запас на Windows USB драйвер.
      if (status == ConnectionStatus.disconnected && autoDetect && !_disposed) {
        _reconnectAfterMs.remove(device.id);
        _scheduleQuickRescan();
      }
    });

    // Подписываемся на данные — каждый пакет проходит напрямую
    _dataSubs[device.id] = device.hal.sensorData.listen((packet) {
      if (!_disposed) {
        device.recordPacket();
        _dataController.add(packet);
      }
    });
  }

  /// Удалить устройство из хаба
  Future<void> removeDevice(String deviceId) async {
    final idx = _devices.indexWhere((d) => d.id == deviceId);
    if (idx == -1) return;

    final device = _devices[idx];
    debugPrint('SensorHub: - ${device.name}');

    await _dataSubs[deviceId]?.cancel();
    await _statusSubs[deviceId]?.cancel();
    _dataSubs.remove(deviceId);
    _statusSubs.remove(deviceId);

    try {
      await device.hal.disconnect();
      await device.hal.dispose();
    } catch (e) {
      debugPrint('SensorHub: ошибка при удалении ${device.id}: $e');
    }

    _devices.removeAt(idx);
    _reconnectAfterMs.remove(deviceId);
    _consecutiveDeviceFailures.remove(deviceId);
    _statusController.add(currentStatus);
  }

  // ═════════════════════════════════════════════════════════════
  //  HALInterface IMPLEMENTATION
  // ═════════════════════════════════════════════════════════════

  @override
  Stream<ConnectionStatus> get connectionStatus => _statusController.stream;

  @override
  Stream<SensorPacket> get sensorData => _dataController.stream;

  @override
  DeviceInfo? get deviceInfo {
    // Собираем общую информацию из всех подключённых устройств
    final connected = _devices.where(
      (d) => d.status == ConnectionStatus.connected,
    );

    if (connected.isEmpty) return null;

    // Мержим списки сенсоров от всех устройств
    final allSensors = <String>{};
    final names = <String>[];
    String fwVersion = '';

    for (final device in connected) {
      final info = device.hal.deviceInfo;
      if (info != null) {
        allSensors.addAll(info.enabledSensors);
        names.add(info.name);
        if (fwVersion.isEmpty) fwVersion = info.firmwareVersion;
      }
    }

    return DeviceInfo(
      name: connected.length == 1
          ? names.firstOrNull ?? 'Датчик'
          : '${connected.length} устройства',
      firmwareVersion: fwVersion,
      batteryPercent: 100,
      enabledSensors: allSensors.toList(),
      connectionType: ConnectionType.usb,
    );
  }

  @override
  bool get isCalibrated => _devices.any((d) => d.hal.isCalibrated);

  @override
  Future<bool> connect() async {
    if (_disposed) return false;

    // Hot-plug monitor запускается ПОСЛЕ первого скана,
    // чтобы не блокировать UI при запуске приложения.

    // ── AUTO-DETECT: Scan USB ports in background Isolate ────
    // Pattern: NI MAX / Vernier Auto-ID / PASCO Hardware Manager
    // ALL FFI calls run in Isolate — UI thread NEVER blocks.
    //
    // Scan triggers:
    //   (a) First connect — _devices is empty
    //   (b) Reconnect after disconnect — _devices was cleared by disconnect()
    //   (c) Belt-and-suspenders: all devices in dead state (error/disconnected)
    //       This handles edge cases where _devices wasn't properly cleared.
    final allDevicesDead = _devices.isNotEmpty &&
        _devices.every((d) =>
            d.status == ConnectionStatus.disconnected ||
            d.status == ConnectionStatus.error);

    if (autoDetect && (_devices.isEmpty || allDevicesDead)) {
      // If devices are stale (all dead), clear them for a fresh start
      if (allDevicesDead) {
        debugPrint('SensorHub: 🔄 Все устройства мертвы — пересканирование');
        for (final sub in _dataSubs.values) {
          try {
            await sub.cancel();
          } catch (_) {}
        }
        for (final sub in _statusSubs.values) {
          try {
            await sub.cancel();
          } catch (_) {}
        }
        _dataSubs.clear();
        _statusSubs.clear();
        _devices.clear();
        _missingPortCounters.clear();
        _reconnectAfterMs.clear();
      }

      _statusController.add(ConnectionStatus.connecting);
      debugPrint('SensorHub: 🔍 Сканирование USB-портов (Isolate)...');
      lastScanError = null;

      await _refreshTopology(connectNew: false);
      if (_disposed) return false; // User switched mode during scan

      if (_devices.isEmpty) {
        lastScanError ??= 'USB-датчики не найдены. '
            'Подключите устройство — оно определится автоматически.';
        debugPrint('SensorHub: ✗ $lastScanError');
        // Plug & Play: не возвращаем error сразу.
        // Запускаем hot-plug монитор — когда пользователь
        // воткнёт датчик, _refreshTopology найдёт его
        // и подключит автоматически (в течение 3сек).
        _statusController.add(ConnectionStatus.disconnected);
        _startHotplugMonitor();
        return false;
      }

      // Notify UI: devices discovered, per-device cards will appear
      _statusController.add(ConnectionStatus.connecting);
    }

    if (_devices.isEmpty) return false;

    debugPrint('SensorHub: подключение ${_devices.length} устройств...');
    _statusController.add(ConnectionStatus.connecting);

    _connectInProgress = true;

    bool anyConnected = false;

    // ┌─────────────────────────────────────────────────────────┐
    // │  SEQUENTIAL connect — НЕ параллельный!                  │
    // │                                                         │
    // │  Причина: flutter_libserialport использует синхронный    │
    // │  FFI вызов sp_open(). Два одновременных sp_open() на    │
    // │  Windows могут конфликтовать в usbser.sys / ftser2k.sys, │
    // │  вызывая errno=121 (semaphore timeout) или errno=5.     │
    // │                                                         │
    // │  Vernier/PASCO тоже подключают устройства последовательно│
    // │  — это единственный надёжный подход на Windows.          │
    // └─────────────────────────────────────────────────────────┘
    try {
      final snapshot = List<HubDevice>.from(_devices);
      for (int i = 0; i < snapshot.length; i++) {
        if (_disposed) break;
        final ok = await _connectSingleDevice(snapshot[i]);
        anyConnected = anyConnected || ok;

        // Пауза между устройствами — даём Windows освободить USB bus
        if (i < snapshot.length - 1 && !_disposed) {
          await Future.delayed(const Duration(milliseconds: 150));
        }
      }
    } catch (e) {
      debugPrint('SensorHub: ошибка в цикле подключения: $e');
    } finally {
      _connectInProgress = false;
    }

    final status =
        anyConnected ? ConnectionStatus.connected : ConnectionStatus.error;
    _statusController.add(status);

    debugPrint('SensorHub: подключено $connectedCount/${_devices.length}');

    // Start hot-plug monitor AFTER first connect attempt.
    // If already running (started in empty-scan path above) — _startHotplugMonitor()
    // has a guard (_hotplugTimer != null) and will skip.
    if (autoDetect) {
      _startHotplugMonitor();
    }

    return anyConnected;
  }

  @override
  Future<void> disconnect() async {
    debugPrint('SensorHub: отключение всех устройств');

    // ── CRITICAL: Stop hot-plug FIRST ─────────────────────
    // Hot-plug timer spawns Isolate.run() → FFI calls to
    // sp_get_port_usb_vid_pid() (Windows SetupDi API).
    // If these run CONCURRENT with sp_close()/sp_free_port()
    // on the main thread → CRT heap corruption →
    // _CrtIsValidHeapPointer crash.
    _hotplugTimer?.cancel();
    _hotplugTimer = null;
    _quickRescanTimer?.cancel();
    _quickRescanTimer = null;
    _currentScanToken?.cancel();
    _currentConnectToken?.cancel();

    // Wait for any in-progress scan Isolate to finish (max 6s).
    // scanPorts() has its own 5s timeout, so 6s is sufficient.
    if (_scanInProgress) {
      debugPrint('SensorHub: ожидание завершения сканирования...');
      for (int i = 0; i < 60 && _scanInProgress; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }

    // ── Now safe to disconnect devices ────────────────────
    // Parallel disconnect: each device closes its own port independently.
    // Total time = max(device1, device2), not sum.
    await Future.wait(
      _devices.map((device) async {
        try {
          await device.hal.disconnect();
        } catch (e) {
          debugPrint('SensorHub: ошибка отключения ${device.id}: $e');
        }
      }),
    );

    // ── CRITICAL FIX: Clear ALL stale state ───────────────
    // Previously, _devices was NOT cleared after disconnect.
    // This caused connect() to skip scan (because _devices.isEmpty was false)
    // and reuse stale UsbHALWindows instances with potentially dead ports.
    //
    // Root cause of "disconnect → never reconnects" bug:
    // 1. disconnect() kept stale HubDevices in _devices
    // 2. connect() saw _devices.isNotEmpty → skipped fresh scan
    // 3. Tried to reconnect same UsbHALWindows to same port name
    // 4. Windows often reassigns COM ports → stale port fails forever
    //
    // Fix: Clear everything so next connect() does a fresh scan
    // and creates brand-new UsbHALWindows instances.
    // Child UsbHALWindows are NOT disposed (intentional micro-leak ~200B each)
    // — their sp_port structs will be GC'd by OS at process exit.

    // Cancel all subscriptions (prevents stale callbacks from dead HALs)
    for (final sub in _dataSubs.values) {
      try {
        await sub.cancel();
      } catch (_) {}
    }
    for (final sub in _statusSubs.values) {
      try {
        await sub.cancel();
      } catch (_) {}
    }
    _dataSubs.clear();
    _statusSubs.clear();

    // Clear devices — forces fresh scan on next connect()
    _devices.clear();

    // Reset all tracking state
    _missingPortCounters.clear();
    _reconnectAfterMs.clear();
    _consecutiveScanFailures = 0;
    _connectInProgress = false;
    lastScanError = null;

    debugPrint('SensorHub: все устройства отключены, состояние сброшено');
    _statusController.add(ConnectionStatus.disconnected);
  }

  @override
  Future<void> startMeasurement() async {
    // SH-1 fix: snapshot to avoid ConcurrentModificationError
    // if hot-plug timer modifies _devices during await.
    final snapshot = List<HubDevice>.of(_devices);
    for (final device in snapshot) {
      if (_disposed) break;
      if (device.status == ConnectionStatus.connected) {
        try {
          await device.hal.startMeasurement();
        } catch (e) {
          debugPrint('SensorHub: ошибка startMeasurement ${device.id}: $e');
        }
      }
    }
  }

  @override
  Future<void> stopMeasurement() async {
    final snapshot = List<HubDevice>.of(_devices);
    for (final device in snapshot) {
      try {
        await device.hal.stopMeasurement();
      } catch (e) {
        debugPrint('SensorHub: ошибка stopMeasurement ${device.id}: $e');
      }
    }
  }

  @override
  Future<void> calibrate(String sensorId) async {
    // Калибруем на ВСЕХ устройствах (каждое проигнорирует чужой sensorId)
    final snapshot = List<HubDevice>.of(_devices);
    for (final device in snapshot) {
      if (_disposed) break;
      if (device.status == ConnectionStatus.connected) {
        try {
          await device.hal.calibrate(sensorId);
        } catch (e) {
          debugPrint('SensorHub: ошибка calibrate ${device.id}: $e');
        }
      }
    }
  }

  @override
  Future<void> setSampleRate(int hz) async {
    final snapshot = List<HubDevice>.of(_devices);
    for (final device in snapshot) {
      try {
        await device.hal.setSampleRate(hz);
      } catch (e) {
        debugPrint('SensorHub: ошибка setSampleRate ${device.id}: $e');
      }
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    // Отменяем все операции
    _currentConnectToken?.cancel();
    _currentScanToken?.cancel();

    _hotplugTimer?.cancel();
    _hotplugTimer = null;
    _quickRescanTimer?.cancel();
    _quickRescanTimer = null;

    // SH-2 fix: Wait for any in-progress scan Isolate to finish
    // before closing stream controllers. Without this wait,
    // _refreshTopology() can resume after controllers are closed
    // → StateError: Cannot add event after closing.
    if (_scanInProgress) {
      debugPrint('SensorHub: dispose — ожидание завершения сканирования...');
      for (int i = 0; i < 60 && _scanInProgress; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }

    Logger.info('SensorHub: dispose (${_devices.length} устройств)');

    // Отписываемся от всех
    for (final sub in _dataSubs.values) {
      await sub.cancel();
    }
    for (final sub in _statusSubs.values) {
      await sub.cancel();
    }
    _dataSubs.clear();
    _statusSubs.clear();
    _reconnectAfterMs.clear();

    // Отключаем и освобождаем все устройства
    for (final device in _devices) {
      try {
        await device.hal.disconnect();
        await device.hal.dispose();
      } catch (e) {
        debugPrint('SensorHub: ошибка dispose ${device.id}: $e');
      }
    }
    _devices.clear();

    await _statusController.close();
    await _dataController.close();
  }
}
