import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/hal/ble_hal.dart';
import '../../../data/hal/mock_hal.dart';
import '../../../data/hal/sensor_hub.dart';
import '../../../data/hal/usb_hal_windows.dart';
import '../../../domain/entities/sensor_data.dart';
import '../../../domain/entities/sensor_type.dart';
import '../../../domain/repositories/hal_interface.dart';
import '../../../domain/utils/circular_sample_buffer.dart';
import '../../../data/datasources/local/experiment_autosave_service.dart';
import '../../../core/di/providers.dart';
import '../ble/ble_scan_provider.dart';

// ═══════════════════════════════════════════════════════════════
//  ГЛОБАЛЬНЫЕ НАСТРОЙКИ
// ═══════════════════════════════════════════════════════════════

/// Режим подключения
enum HalMode { mock, usb, ble }

/// Текущий режим HAL
/// По умолчанию USB на десктопе (школьный ПК), Mock на мобилке.
/// Переключается через UI: USB (COM), Bluetooth, Симуляция.
final halModeProvider = StateProvider<HalMode>((ref) {
  // Desktop = USB (основной сценарий — школа + датчик по USB)
  // Mobile = Mock (для демонстрации без железа)
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    return HalMode.usb;
  }
  return HalMode.mock;
});

/// Выбранный COM-порт (null = автовыбор)
final selectedPortProvider = StateProvider<String?>((ref) => null);

/// Все датчики приложения — одна унифицированная версия продукта.
final availableSensorsProvider = Provider<List<SensorType>>((ref) {
  return SensorType.values;
});

// ═══════════════════════════════════════════════════════════════
//  HAL (Hardware Abstraction Layer)
//
//  USB Mode: SensorHub автоматически находит ВСЕ USB-датчики
//  и подключает их одновременно (Vernier/PASCO-style).
//
//  Если selectedPort задан вручную — подключается только к нему.
// ═══════════════════════════════════════════════════════════════

/// Провайдер HAL — пересоздаётся при смене режима или порта
final halProvider = Provider<HALInterface>((ref) {
  final mode = ref.watch(halModeProvider);
  final selectedPort = ref.watch(selectedPortProvider);

  final HALInterface hal;

  switch (mode) {
    case HalMode.usb:
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        hal = _createUsbHal(selectedPort);
      } else {
        // USB OTG на мобилке: пока не реализовано, fallback → симуляция
        debugPrint(
            'HAL: USB не реализован на ${Platform.operatingSystem}, fallback → Mock');
        hal = MockHAL();
      }
    case HalMode.ble:
      // BLE не поддерживается на Windows desktop
      if (Platform.isWindows || Platform.isLinux) {
        debugPrint(
            'HAL: BLE не поддерживается на ${Platform.operatingSystem}, fallback → USB');
        // Fallback to USB instead of crashing
        hal = SensorHub(autoDetect: true);
        break;
      }
      final bleDevice = ref.watch(selectedBleDeviceProvider);
      hal = BleHAL(targetDevice: bleDevice);
      debugPrint('HAL: BleHAL (device: ${bleDevice?.platformName})');
    case HalMode.mock:
      hal = MockHAL();
  }

  ref.onDispose(() {
    debugPrint('HAL: disposing ($mode)');
    hal.dispose();
  });

  return hal;
});

/// Создаёт USB HAL.
///
/// Ручной выбор порта → UsbHALWindows (прямое подключение).
/// Автоопределение → SensorHub с lazy Isolate-based сканированием.
///
/// ┌────────────────────────────────────────────────────────────┐
/// │  ZERO FFI IN PROVIDER BODY                                 │
/// │                                                            │
/// │  Раньше: FFI-сканирование портов при создании провайдера   │
/// │  → блокировка UI на 1-10 секунд при переключении на USB.   │
/// │                                                            │
/// │  Сейчас (NI MAX / Vernier Auto-ID / PASCO Capstone):       │
/// │  1. Провайдер создаёт ПУСТОЙ SensorHub (0ms, без FFI)      │
/// │  2. connect() → сканирование в background Isolate           │
/// │  3. UI показывает "Сканирование..." (адаптивный прогресс)   │
/// │  4. Обнаруженные устройства → подключение каждого            │
/// └────────────────────────────────────────────────────────────┘
HALInterface _createUsbHal(String? selectedPort) {
  // Ручной выбор → один порт, без сканирования
  if (selectedPort != null) {
    debugPrint('HAL: UsbHALWindows (manual: $selectedPort)');
    final usbHal = UsbHALWindows();
    usbHal.selectedPort = selectedPort;
    return usbHal;
  }

  // Auto-detect → SensorHub с lazy port scanning.
  // Сканирование запустится в background Isolate при connect().
  // Провайдер возвращается МГНОВЕННО — UI НЕ блокируется.
  debugPrint('HAL: SensorHub (auto-detect, lazy scan)');
  return SensorHub(autoDetect: true);
}

// ═══════════════════════════════════════════════════════════════
//  ПОДКЛЮЧЕНИЕ
// ═══════════════════════════════════════════════════════════════

/// Состояние одного устройства (для per-device UI, как Vernier/PASCO)
class DeviceStatusInfo {
  final String id;
  final String name;
  final ConnectionStatus status;
  final String? error;
  final double packetsPerSecond;
  final int totalPackets;

  const DeviceStatusInfo({
    required this.id,
    required this.name,
    required this.status,
    this.error,
    this.packetsPerSecond = 0,
    this.totalPackets = 0,
  });
}

class SensorConnectionState {
  final ConnectionStatus status;
  final String? errorMessage;
  final DeviceInfo? deviceInfo;

  /// Per-device statuses (empty for single-device mode)
  final List<DeviceStatusInfo> deviceStatuses;

  /// Whether we're using SensorHub (multi-device)
  final bool isMultiDevice;

  /// Auto-recovery in progress (quick-rescan or exponential backoff).
  /// UI показывает "Восстановление связи..." вместо "Отключён"
  /// — менее пугающе для учителя при коротком обрыве.
  final bool isRecovering;

  const SensorConnectionState({
    this.status = ConnectionStatus.disconnected,
    this.errorMessage,
    this.deviceInfo,
    this.deviceStatuses = const [],
    this.isMultiDevice = false,
    this.isRecovering = false,
  });

  SensorConnectionState copyWith({
    ConnectionStatus? status,
    String? errorMessage,
    bool clearErrorMessage = false,
    DeviceInfo? deviceInfo,
    List<DeviceStatusInfo>? deviceStatuses,
    bool? isMultiDevice,
    bool? isRecovering,
  }) =>
      SensorConnectionState(
        status: status ?? this.status,
        errorMessage:
            clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
        deviceInfo: deviceInfo ?? this.deviceInfo,
        deviceStatuses: deviceStatuses ?? this.deviceStatuses,
        isMultiDevice: isMultiDevice ?? this.isMultiDevice,
        isRecovering: isRecovering ?? this.isRecovering,
      );
}

class SensorConnectionController extends StateNotifier<SensorConnectionState> {
  final HALInterface _hal;
  StreamSubscription<ConnectionStatus>? _statusSub;
  Timer? _deviceStatusTimer;

  /// Number of connect retries before giving up.
  /// 0 = single attempt, fail fast. User presses button again if needed.
  /// (Vernier/PASCO pattern — no silent retries that amplify timeout)
  static const int _maxConnectRetries = 0;

  SensorConnectionController(this._hal, {bool autoConnect = false})
      : super(SensorConnectionState(
          isMultiDevice: _hal is SensorHub,
        )) {
    _statusSub = _hal.connectionStatus.listen((status) {
      state = state.copyWith(
        status: status,
        deviceInfo: _hal.deviceInfo,
        deviceStatuses: _buildDeviceStatuses(),
        isRecovering:
            _hal is SensorHub ? (_hal as SensorHub).isRecovering : false,
      );
    });

    // Per-device status refresh timer (for live packet rate, like Saleae Logic)
    // 2 seconds is enough for pkt/s display — avoids excessive UI rebuilds
    if (_hal is SensorHub) {
      _deviceStatusTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) {
          if (mounted && state.status == ConnectionStatus.connected) {
            final newStatuses = _buildDeviceStatuses();
            final newDeviceInfo = _hal.deviceInfo;
            // Only rebuild if packet rates or device info actually changed
            final statusesChanged =
                _statusesChanged(state.deviceStatuses, newStatuses);
            final sensorsChanged = newDeviceInfo?.enabledSensors.length !=
                state.deviceInfo?.enabledSensors.length;
            if (statusesChanged || sensorsChanged) {
              state = state.copyWith(
                deviceStatuses: newStatuses,
                deviceInfo: newDeviceInfo,
              );
            }
          }
        },
      );
    }

    // Plug & Play: авто-подключение через 1.5с после запуска.
    // 1.5с = splash screen (закончился) + UI рендеринг + Windows USB drivers ready.
    // Mock = 500мс (мгновенный, нет FFI).
    if (autoConnect) {
      final delay = _hal is SensorHub
          ? const Duration(milliseconds: 1500)
          : const Duration(milliseconds: 500);
      Future.delayed(delay, () {
        if (mounted) connect();
      });
    }
  }

  /// Build per-device status list from SensorHub
  List<DeviceStatusInfo> _buildDeviceStatuses() {
    if (_hal is! SensorHub) return const [];
    final hub = _hal as SensorHub;
    return hub.devices
        .map((d) => DeviceStatusInfo(
              id: d.id,
              name: d.name,
              status: d.status,
              error: d.lastError,
              packetsPerSecond: d.packetsPerSecond,
              totalPackets: d.packetsReceived,
            ))
        .toList();
  }

  /// Checks if device statuses actually changed (avoids unnecessary rebuilds)
  bool _statusesChanged(
      List<DeviceStatusInfo> old, List<DeviceStatusInfo> next) {
    if (old.length != next.length) return true;
    for (int i = 0; i < old.length; i++) {
      if (old[i].status != next[i].status) return true;
      if (old[i].error != next[i].error) return true;
      // Only trigger rebuild if packet rate changed by ≥0.5 Hz
      if ((old[i].packetsPerSecond - next[i].packetsPerSecond).abs() >= 0.5) {
        return true;
      }
    }
    return false;
  }

  Future<bool> connect() async {
    if (state.status == ConnectionStatus.connecting) {
      debugPrint('SensorConnection: подключение уже в процессе');
      return false;
    }
    state = state.copyWith(
        status: ConnectionStatus.connecting, clearErrorMessage: true);

    // Retry loop — school USB ports can be flaky on first attempt
    for (int attempt = 0; attempt <= _maxConnectRetries; attempt++) {
      try {
        if (attempt > 0) {
          debugPrint(
              'SensorConnection: повтор подключения ($attempt/$_maxConnectRetries)');
          await Future.delayed(Duration(milliseconds: 500 * attempt));
          if (!mounted) return false;
        }

        final ok = await _hal.connect();
        if (ok) {
          state = state.copyWith(
            deviceStatuses: _buildDeviceStatuses(),
          );
          return true;
        }

        // Last attempt failed — get specific error from HAL
        if (attempt == _maxConnectRetries && mounted) {
          String errorMsg = 'Подключение датчика временно недоступно. '
              'Проверьте USB-подключение и попробуйте снова.';

          if (_hal is UsbHALWindows) {
            final halError = (_hal as UsbHALWindows).lastError;
            if (halError != null && halError.isNotEmpty) {
              errorMsg = halError;
            }
          } else if (_hal is SensorHub) {
            final hub = _hal as SensorHub;
            // Hub-level error (e.g., no devices found during scan)
            if (hub.lastScanError != null) {
              errorMsg = hub.lastScanError!;
            } else {
              // Collect per-device errors
              final errors = hub.devices
                  .where((d) => d.lastError != null)
                  .map((d) => '${d.name}: ${d.lastError}')
                  .toList();
              if (errors.isNotEmpty) {
                errorMsg = errors.join('\n');
              }
            }
          }

          state = state.copyWith(
            status: ConnectionStatus.error,
            errorMessage: errorMsg,
            deviceStatuses: _buildDeviceStatuses(),
          );
        }
      } catch (e) {
        debugPrint(
            'SensorConnection: ошибка подключения (попытка $attempt): $e');
        if (attempt == _maxConnectRetries && mounted) {
          state = state.copyWith(
            status: ConnectionStatus.error,
            errorMessage: 'Не удалось завершить подключение. '
                'Попробуйте ещё раз.',
          );
          return false;
        }
      }
    }
    return false;
  }

  Future<void> disconnect() async {
    await _hal.disconnect();
    state = state.copyWith(
      status: ConnectionStatus.disconnected,
      clearErrorMessage: true,
      deviceStatuses: _buildDeviceStatuses(),
    );
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _deviceStatusTimer?.cancel();
    super.dispose();
  }
}

final sensorConnectionProvider =
    StateNotifierProvider<SensorConnectionController, SensorConnectionState>(
  (ref) {
    final hal = ref.watch(halProvider);
    final mode = ref.watch(halModeProvider);
    // Plug & Play: авто-подключение для USB и Mock.
    //
    // Безопасно после редизайна v3:
    //   - Сканирование через Windows Registry (<10ms, никогда не зависает)
    //   - Все FFI в Isolate.run() (UI thread никогда не блокируется)
    //   - Timer-based чтение (нет Isolate heap corruption)
    //   - Hot-plug монитор с quick rescan (1.5с)
    //
    // Лучшие практики (Vernier LabQuest / PASCO Capstone / NI MAX):
    // Пользователь не нажимает кнопки — датчик подключается сам.
    //
    // BLE: пользователь выбирает устройство вручную (ограничение ОС).
    final shouldAutoConnect = mode == HalMode.mock || mode == HalMode.usb;
    return SensorConnectionController(hal, autoConnect: shouldAutoConnect);
  },
);

// ═══════════════════════════════════════════════════════════════
//  ПОТОК ДАННЫХ
// ═══════════════════════════════════════════════════════════════

final sensorDataStreamProvider = StreamProvider<SensorPacket>((ref) {
  final hal = ref.watch(halProvider);
  return hal.sensorData;
});

// ═══════════════════════════════════════════════════════════════
//  ЭКСПЕРИМЕНТ
// ═══════════════════════════════════════════════════════════════

class ExperimentState {
  final bool isRunning;
  final List<SensorPacket> data;

  /// Полное число измерений (data может быть оконным подмножеством во время live).
  final int totalMeasurements;
  final int sampleRateHz;
  final DateTime? startTime;
  final DateTime? endTime;
  final bool isCalibrated;
  final bool isBufferWarning;
  final bool isRecoveredSession;

  /// Wall-clock elapsed seconds since start — обновляется каждый тик (30 FPS).
  /// Используется графиком для плавной прокрутки оси X, независимо от частоты данных.
  final double elapsedSeconds;

  /// ID эксперимента в SQLite (от autosave). Позволяет экспортировать
  /// полную историю из БД, когда in-memory буфер уже перезаписался.
  /// null = эксперимент не был сохранён в БД (autosave отключён).
  final int? dbExperimentId;

  const ExperimentState({
    this.isRunning = false,
    this.data = const [],
    this.totalMeasurements = 0,
    this.sampleRateHz = 10,
    this.startTime,
    this.endTime,
    this.isCalibrated = false,
    this.isBufferWarning = false,
    this.isRecoveredSession = false,
    this.elapsedSeconds = 0.0,
    this.dbExperimentId,
  });

  ExperimentState copyWith({
    bool? isRunning,
    List<SensorPacket>? data,
    int? totalMeasurements,
    int? sampleRateHz,
    DateTime? startTime,
    bool clearStartTime = false,
    DateTime? endTime,
    bool clearEndTime = false,
    bool? isCalibrated,
    bool? isBufferWarning,
    bool? isRecoveredSession,
    double? elapsedSeconds,
    int? dbExperimentId,
    bool clearDbExperimentId = false,
  }) =>
      ExperimentState(
        isRunning: isRunning ?? this.isRunning,
        data: data ?? this.data,
        totalMeasurements: totalMeasurements ?? this.totalMeasurements,
        sampleRateHz: sampleRateHz ?? this.sampleRateHz,
        startTime: clearStartTime ? null : (startTime ?? this.startTime),
        endTime: clearEndTime ? null : (endTime ?? this.endTime),
        isCalibrated: isCalibrated ?? this.isCalibrated,
        isBufferWarning: isBufferWarning ?? this.isBufferWarning,
        isRecoveredSession: isRecoveredSession ?? this.isRecoveredSession,
        elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
        dbExperimentId: clearDbExperimentId
            ? null
            : (dbExperimentId ?? this.dbExperimentId),
      );

  Duration get duration {
    if (startTime == null) return Duration.zero;
    final end = endTime ?? DateTime.now();
    return end.difference(startTime!);
  }

  int get measurementCount => totalMeasurements;
}

class ExperimentController extends StateNotifier<ExperimentState> {
  final HALInterface _hal;
  final ExperimentAutosaveService? _autosave;
  StreamSubscription<SensorPacket>? _dataSub;
  Timer? _uiTimer;
  bool _shutdownStarted = false;
  bool _isStarting = false;

  ExperimentController(this._hal, [this._autosave])
      : super(const ExperimentState());

  /// Circular buffer — O(1) add, O(1) eviction on overflow.
  /// Replaces List + removeRange which was O(N) and caused UI jank
  /// on Celeron N4000 (shifting 450K elements = ~200ms freeze).
  late final CircularSampleBuffer<SensorPacket> _buffer =
      CircularSampleBuffer<SensorPacket>(
    maxCapacity: _maxBufferSize,
    warningThreshold: 0.8,
    onWarningThreshold: () {
      debugPrint('⚠️ ExperimentController: буфер заполнен на 80% '
          '(${_buffer.length}/$_maxBufferSize). '
          'Старые данные начнут перезаписываться.');
      if (mounted) {
        state = state.copyWith(isBufferWarning: true);
      }
    },
  );

  int _dataVersion = 0;
  int _lastEmittedVersion = -1;

  /// Last accepted timestamp (for monotonicity validation)
  int _lastAcceptedTimestamp = -1;

  // Adaptive UI publish rate — с оконным снэпшотом стоимость тика O(window),
  // не O(buffer), поэтому можно держать высокий FPS.
  int _uiIntervalMs = 33; // default ~30 FPS
  int _packetsSinceAdaptiveCheck = 0;
  DateTime _lastAdaptiveCheckAt = DateTime.now();

  /// Максимальный размер буфера.
  ///
  /// 150K × ~150 байт/пакет ≈ 22 МБ (vs 75 МБ при 500K).
  /// На Celeron N4000/4GB RAM это критично:
  /// - Queue<T> (linked list) имеет ~48B overhead на узел
  /// - toList() на stop() создаёт копию → пиковый spike = 2× буфер
  ///
  /// Для длинных экспериментов (>25 мин при 100Hz) данные
  /// безопасно хранятся в SQLite через autosave (30с интервал).
  /// При stop() отдаём только буфер для немедленного экспорта;
  /// полную историю можно загрузить из БД потоково.
  static const int _maxBufferSize = 150000;

  // ── FPS debug counter ──
  int _fpsFrameCount = 0;
  DateTime _fpsLastReport = DateTime.now();

  void _startUiTimer() {
    _uiTimer?.cancel();
    _uiTimer = Timer.periodic(Duration(milliseconds: _uiIntervalMs), (_) {
      if (!state.isRunning) return;

      // Wall-clock elapsed — основа плавной прокрутки
      final elapsed = state.startTime != null
          ? DateTime.now().difference(state.startTime!).inMicroseconds / 1e6
          : 0.0;

      // FPS measurement (debug only — avoid string formatting in release)
      if (kDebugMode) {
        _fpsFrameCount++;
        final now = DateTime.now();
        final fpsElapsed = now.difference(_fpsLastReport).inMilliseconds;
        if (fpsElapsed >= 2000) {
          final fps = _fpsFrameCount * 1000.0 / fpsElapsed;
          debugPrint('📊 CHART FPS: ${fps.toStringAsFixed(1)} '
              '($_fpsFrameCount frames / ${(fpsElapsed / 1000).toStringAsFixed(1)}s, '
              'timer=${_uiIntervalMs}ms, window=${_buffer.length > state.sampleRateHz * 35 ? state.sampleRateHz * 35 : _buffer.length})');
          _fpsFrameCount = 0;
          _fpsLastReport = now;
        }
      }

      if (_dataVersion != _lastEmittedVersion) {
        // ── НОВЫЕ ДАННЫЕ: обновляем data + elapsedSeconds ──
        _lastEmittedVersion = _dataVersion;
        final windowSize = math.max(state.sampleRateHz * 35, 1000);
        state = state.copyWith(
          data: _buffer.takeLast(windowSize),
          totalMeasurements: _buffer.length,
          elapsedSeconds: elapsed,
        );
      } else {
        // ── НЕТ НОВЫХ ДАННЫХ: обновляем ТОЛЬКО elapsedSeconds ──
        // Это дёшево (нет копирования списка), но позволяет
        // графику прокручиваться плавно по wall-clock.
        state = state.copyWith(elapsedSeconds: elapsed);
      }
    });
  }

  void _maybeAdaptUiRate() {
    final now = DateTime.now();
    final elapsedMs = now.difference(_lastAdaptiveCheckAt).inMilliseconds;
    if (elapsedMs < 1000) return;

    final pps = _packetsSinceAdaptiveCheck * 1000.0 / elapsedMs;
    _packetsSinceAdaptiveCheck = 0;
    _lastAdaptiveCheckAt = now;

    int targetMs;
    // С оконным снэпшотом (~3500 элементов) стоимость обновления
    // постоянна при любом размере буфера → держим ≥30 FPS.
    // 30 FPS = золотой стандарт для real-time графиков
    // (Vernier LabQuest: 20 FPS, PASCO Capstone: 30 FPS, осциллографы: 60 FPS).
    if (pps > 500) {
      targetMs = 40; // ~25 FPS — экстремальная частота (500+ Гц)
    } else {
      targetMs = 33; // ~30 FPS — норма (все остальные диапазоны)
    }

    if (targetMs != _uiIntervalMs && state.isRunning) {
      _uiIntervalMs = targetMs;
      _startUiTimer();
      debugPrint(
        'ExperimentController: адаптивный UI tick = ${_uiIntervalMs}ms '
        '(pps=${pps.toStringAsFixed(1)}, n=${_buffer.length})',
      );
    }
  }

  Future<void> start() async {
    // EP-1 fix: Re-entrancy guard — prevents orphan data subscriptions
    // if start() is called twice before the first completes (across await gaps).
    if (_isStarting) return;
    _isStarting = true;

    try {
      // Если эксперимент уже запущен — останавливаем предыдущий чисто
      if (state.isRunning) {
        debugPrint(
            'ExperimentController: принудительная остановка предыдущего');
        _uiTimer?.cancel();
        _uiTimer = null;
        await _dataSub?.cancel();
        _dataSub = null;
        await _hal.stopMeasurement();
      }

      debugPrint('ExperimentController: start() вызван');
      _buffer.clear();
      _dataVersion = 0;
      _lastEmittedVersion = -1;
      _lastAcceptedTimestamp = -1;
      _uiIntervalMs = 33;
      _packetsSinceAdaptiveCheck = 0;
      _lastAdaptiveCheckAt = DateTime.now();

      final now = DateTime.now();
      state = state.copyWith(
        isRunning: true,
        data: const [],
        totalMeasurements: 0,
        startTime: now,
        clearEndTime: true,
        elapsedSeconds: 0.0,
        isBufferWarning: false,
        isRecoveredSession: false,
      );

      // ── Autosave: создаём сессию в SQLite ───────────────────
      try {
        await _autosave?.beginSession(
          startTime: now,
          sampleRateHz: state.sampleRateHz,
        );
        // Прокидываем ID эксперимента в state — позволяет UI
        // экспортировать полную историю из БД для длинных экспериментов.
        final dbId = _autosave?.experimentId;
        if (dbId != null) {
          state = state.copyWith(dbExperimentId: dbId);
        }
      } catch (e) {
        debugPrint('Autosave: не удалось создать сессию: $e');
      }

      _dataSub?.cancel();
      _uiTimer?.cancel();

      await _hal.setSampleRate(state.sampleRateHz);

      // Подписываемся на поток данных ПЕРЕД startMeasurement()
      debugPrint('ExperimentController: подписываемся на sensorData...');
      _dataSub = _hal.sensorData.listen(
        (packet) {
          if (state.isRunning) {
            // 3.4: Отбрасываем пакеты с невалидным временем
            // (прошивка не инициализирована или повреждённый пакет)
            if (packet.timestampMs <= 0 || !packet.timeSeconds.isFinite) return;

            // 3.5: Monotonicity check — отбрасываем пакеты с временем
            // меньше предыдущего (clock rollback, corrupt packet, stale data)
            if (_lastAcceptedTimestamp >= 0 &&
                packet.timestampMs < _lastAcceptedTimestamp) {
              return; // skip non-monotonic
            }
            _lastAcceptedTimestamp = packet.timestampMs;

            // CircularSampleBuffer: O(1) add + O(1) eviction on overflow.
            // No removeRange jank (previously O(N) shift of 450K elements).
            _buffer.add(packet);
            _autosave?.addPacket(packet);
            _packetsSinceAdaptiveCheck++;
            _dataVersion++;
            _maybeAdaptUiRate();
            // Отладка: каждый 50-й пакет (debug only)
            if (kDebugMode && _buffer.length % 50 == 1) {
              debugPrint(
                  'Experiment RX: буфер=${_buffer.length}/$_maxBufferSize '
                  '(evicted=${_buffer.totalEvicted}) t=${packet.timestampMs}ms');
            }
          }
        },
        onError: (e) {
          debugPrint('Experiment: Ошибка потока данных: $e');
        },
        onDone: () {
          debugPrint('Experiment: Поток данных закрыт');
        },
      );

      // Стартуем с ~20 FPS, далее адаптация по реальной нагрузке.
      _startUiTimer();

      // 3.3: Таймаут 5с — если датчик не ответил, UI не зависает
      try {
        await _hal.startMeasurement().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            debugPrint('Сенсор не ответил на startMeasurement за 5с');
            _uiTimer?.cancel();
            _dataSub?.cancel();
            state = state.copyWith(isRunning: false);
          },
        );
      } catch (e) {
        debugPrint('ExperimentController: ошибка запуска: $e');
        _uiTimer?.cancel();
        _dataSub?.cancel();
        state = state.copyWith(isRunning: false);
      }
    } finally {
      _isStarting = false;
    }
  }

  Future<void> stop() async {
    _shutdownStarted = true;
    _uiTimer?.cancel();
    _uiTimer = null;
    await _dataSub?.cancel();
    _dataSub = null;
    await _hal.stopMeasurement();

    // ── Autosave: финальный flush + status=completed ────────
    try {
      await _autosave?.endSession();
    } catch (e) {
      debugPrint('Autosave: ошибка при завершении: $e');
    }

    // При остановке — снэпшот буфера для немедленного экспорта/анализа.
    // Ограничиваем 50K точками чтобы избежать memory spike (×2 на копию).
    // Полная история доступна в SQLite через autosave.
    const exportCap = 50000;
    final exportData = _buffer.length > exportCap
        ? _buffer.takeLast(exportCap)
        : _buffer.toList();
    state = state.copyWith(
      isRunning: false,
      endTime: DateTime.now(),
      data: exportData,
      totalMeasurements: _buffer.length,
      isBufferWarning: false,
      isRecoveredSession: false,
    );
  }

  Future<void> shutdown() async {
    if (_shutdownStarted) return;
    _shutdownStarted = true;

    _uiTimer?.cancel();
    _uiTimer = null;

    await _dataSub?.cancel();
    _dataSub = null;

    if (state.isRunning) {
      try {
        await _hal.stopMeasurement();
      } catch (e) {
        debugPrint('ExperimentController: ошибка shutdown stopMeasurement: $e');
      }
    }

    if (_autosave?.isActive ?? false) {
      try {
        await _autosave?.endSession();
      } catch (e) {
        debugPrint('ExperimentController: ошибка shutdown autosave: $e');
      }
    }
  }

  void restoreRecoveredSession(RecoveredExperimentSession session) {
    _uiTimer?.cancel();
    _uiTimer = null;
    _dataSub?.cancel();
    _dataSub = null;

    _buffer.clear();
    for (final packet in session.packets) {
      _buffer.add(packet);
    }

    _dataVersion = 0;
    _lastEmittedVersion = 0;
    _lastAcceptedTimestamp =
        session.packets.isNotEmpty ? session.packets.last.timestampMs : -1;

    final effectiveEnd = session.effectiveEndTime;
    final elapsedSeconds =
        effectiveEnd.difference(session.startTime).inMicroseconds / 1e6;

    state = state.copyWith(
      isRunning: false,
      data: _buffer.toList(),
      totalMeasurements: _buffer.length,
      sampleRateHz: session.sampleRateHz,
      startTime: session.startTime,
      endTime: effectiveEnd,
      isBufferWarning: false,
      isRecoveredSession: true,
      elapsedSeconds: elapsedSeconds,
    );
  }

  void clear() {
    _buffer.clear();
    _dataVersion = 0;
    _lastEmittedVersion = -1;
    _lastAcceptedTimestamp = -1;
    state = state.copyWith(
      data: const [],
      totalMeasurements: 0,
      clearStartTime: true,
      clearEndTime: true,
      elapsedSeconds: 0.0,
      isCalibrated: false,
      isBufferWarning: false,
      isRecoveredSession: false,
      clearDbExperimentId: true,
    );
  }

  /// Called when user navigates to a different sensor page.
  /// If no experiment is running, clears stale data from the previous sensor
  /// so the new page starts clean. If running — does nothing (user must stop first).
  void resetForSensor() {
    if (state.isRunning || state.isRecoveredSession) {
      return; // don't interrupt active or recovered experiment
    }
    clear();
  }

  Future<void> setSampleRate(int hz) async {
    state = state.copyWith(sampleRateHz: hz);
    if (state.isRunning) await _hal.setSampleRate(hz);
  }

  Future<void> calibrate(String sensorId) async {
    await _hal.calibrate(sensorId);
    state = state.copyWith(isCalibrated: _hal.isCalibrated);
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    _dataSub?.cancel();
    // 3.5: Останавливаем датчик при закрытии экрана без нажатия «Стоп»
    if (state.isRunning && !_shutdownStarted) {
      _hal.stopMeasurement(); // fire-and-forget: dispose синхронный
    }
    super.dispose();
  }
}

final experimentControllerProvider =
    StateNotifierProvider<ExperimentController, ExperimentState>((ref) {
  final hal = ref.watch(halProvider);
  final autosave = ref.watch(autosaveServiceProvider);
  final controller = ExperimentController(hal, autosave);
  ref.onDispose(() {
    unawaited(controller.shutdown());
  });
  return controller;
});
