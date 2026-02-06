import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/hal/mock_hal.dart';
import '../../../data/hal/usb_hal.dart';
import '../../../data/hal/usb_hal_windows.dart';
import '../../../domain/entities/sensor_data.dart';
import '../../../domain/repositories/hal_interface.dart';

/// Режим подключения
enum HalMode { mock, usb, ble }

/// Текущий режим HAL (переключается в настройках)
final halModeProvider = StateProvider<HalMode>((ref) => HalMode.usb);

/// Выбранный COM-порт (null = автовыбор)
final selectedPortProvider = StateProvider<String?>((ref) => null);

/// Провайдер HAL (Hardware Abstraction Layer)
/// SINGLETON - один экземпляр на всё приложение
final halProvider = Provider<HALInterface>((ref) {
  final mode = ref.read(halModeProvider);  // read, не watch!
  final selectedPort = ref.watch(selectedPortProvider);  // watch для реагирования на изменения
  
  final HALInterface hal;
  switch (mode) {
    case HalMode.usb:
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        final usbHal = UsbHALWindows();
        // Передаём выбранный порт если есть
        usbHal.selectedPort = selectedPort;
        print('HAL Provider: Создан UsbHALWindows (selectedPort: $selectedPort)');
        hal = usbHal;
      } else {
        hal = UsbHAL();
      }
      break;
    case HalMode.ble:
      hal = MockHAL(); // TODO: BleHAL
      break;
    case HalMode.mock:
    default:
      hal = MockHAL();
  }
  
  // Закрываем HAL при завершении приложения
  ref.onDispose(() {
    print('HAL Provider: Disposing HAL');
    hal.dispose();
  });
  
  return hal;
});

/// Состояние подключения к датчику
class SensorConnectionState {
  final ConnectionStatus status;
  final String? errorMessage;
  final DeviceInfo? deviceInfo;
  
  const SensorConnectionState({
    this.status = ConnectionStatus.disconnected,
    this.errorMessage,
    this.deviceInfo,
  });
  
  SensorConnectionState copyWith({
    ConnectionStatus? status,
    String? errorMessage,
    DeviceInfo? deviceInfo,
  }) {
    return SensorConnectionState(
      status: status ?? this.status,
      errorMessage: errorMessage,
      deviceInfo: deviceInfo ?? this.deviceInfo,
    );
  }
}

/// Контроллер подключения к датчику
class SensorConnectionController extends StateNotifier<SensorConnectionState> {
  final HALInterface _hal;
  StreamSubscription<ConnectionStatus>? _statusSubscription;
  
  SensorConnectionController(this._hal) : super(const SensorConnectionState()) {
    // Подписываемся на изменения статуса подключения
    _statusSubscription = _hal.connectionStatus.listen((status) {
      state = state.copyWith(
        status: status,
        deviceInfo: _hal.deviceInfo,
      );
    });
  }
  
  /// Подключиться к датчику
  Future<bool> connect() async {
    state = state.copyWith(status: ConnectionStatus.connecting);
    
    try {
      final success = await _hal.connect();
      if (!success) {
        state = state.copyWith(
          status: ConnectionStatus.error,
          errorMessage: 'Не удалось подключиться к датчику',
        );
      }
      return success;
    } catch (e) {
      state = state.copyWith(
        status: ConnectionStatus.error,
        errorMessage: e.toString(),
      );
      return false;
    }
  }
  
  /// Отключиться от датчика
  Future<void> disconnect() async {
    await _hal.disconnect();
    state = state.copyWith(status: ConnectionStatus.disconnected);
  }
  
  @override
  void dispose() {
    _statusSubscription?.cancel();
    super.dispose();
  }
}

/// Провайдер контроллера подключения
final sensorConnectionProvider = 
    StateNotifierProvider.autoDispose<SensorConnectionController, SensorConnectionState>((ref) {
  final hal = ref.watch(halProvider);
  final controller = SensorConnectionController(hal);
  
  ref.onDispose(() {
    controller.dispose();
  });
  
  ref.keepAlive();
  
  return controller;
});

/// Провайдер потока данных от датчика
final sensorDataStreamProvider = StreamProvider.autoDispose<SensorPacket>((ref) {
  final hal = ref.watch(halProvider);
  ref.keepAlive();
  return hal.sensorData;
});

/// Состояние эксперимента
class ExperimentState {
  final bool isRunning;
  final List<SensorPacket> data;
  final int sampleRateHz;
  final DateTime? startTime;
  final bool isCalibrated;
  
  const ExperimentState({
    this.isRunning = false,
    this.data = const [],
    this.sampleRateHz = 10,
    this.startTime,
    this.isCalibrated = false,
  });
  
  ExperimentState copyWith({
    bool? isRunning,
    List<SensorPacket>? data,
    int? sampleRateHz,
    DateTime? startTime,
    bool? isCalibrated,
  }) {
    return ExperimentState(
      isRunning: isRunning ?? this.isRunning,
      data: data ?? this.data,
      sampleRateHz: sampleRateHz ?? this.sampleRateHz,
      startTime: startTime ?? this.startTime,
      isCalibrated: isCalibrated ?? this.isCalibrated,
    );
  }
  
  Duration get duration {
    if (startTime == null) return Duration.zero;
    return DateTime.now().difference(startTime!);
  }
  
  int get measurementCount => data.length;
}

/// Контроллер эксперимента
class ExperimentController extends StateNotifier<ExperimentState> {
  final HALInterface _hal;
  StreamSubscription<SensorPacket>? _dataSubscription;
  
  ExperimentController(this._hal) : super(const ExperimentState());
  
  /// Начать эксперимент
  Future<void> start() async {
    print('ExperimentController: Начинаем эксперимент...');
    
    // Сначала очищаем состояние
    state = state.copyWith(
      isRunning: true,
      data: [],
      startTime: DateTime.now(),
    );
    
    // Отменяем старую подписку если есть
    _dataSubscription?.cancel();
    
    await _hal.setSampleRate(state.sampleRateHz);
    
    // ВАЖНО: сначала подписка, потом старт измерений
    // чтобы не пропустить первые данные
    _dataSubscription = _hal.sensorData.listen((packet) {
      if (state.isRunning) {
        print('ExperimentController: Получен пакет t=${packet.timestampMs}ms');
        state = state.copyWith(data: [...state.data, packet]);
      }
    });
    
    // Теперь стартуем измерения
    await _hal.startMeasurement();
    print('ExperimentController: Измерение запущено');
  }
  
  /// Остановить эксперимент
  Future<void> stop() async {
    _dataSubscription?.cancel();
    _dataSubscription = null;
    await _hal.stopMeasurement();
    state = state.copyWith(isRunning: false);
  }
  
  /// Очистить данные
  void clear() {
    state = state.copyWith(data: [], startTime: null);
  }
  
  /// Установить частоту опроса
  Future<void> setSampleRate(int hz) async {
    state = state.copyWith(sampleRateHz: hz);
    if (state.isRunning) {
      await _hal.setSampleRate(hz);
    }
  }
  
  /// Калибровать датчик (toggle: установить/сбросить ноль)
  Future<void> calibrate(String sensorId) async {
    await _hal.calibrate(sensorId);
    // Обновляем состояние калибровки в state
    state = state.copyWith(isCalibrated: _hal.isCalibrated);
  }
  
  @override
  void dispose() {
    _dataSubscription?.cancel();
    super.dispose();
  }
}

/// Провайдер контроллера эксперимента
final experimentControllerProvider = 
    StateNotifierProvider.autoDispose<ExperimentController, ExperimentState>((ref) {
  final hal = ref.watch(halProvider);
  final controller = ExperimentController(hal);
  
  ref.onDispose(() {
    controller.dispose();
  });
  
  ref.keepAlive();
  
  return controller;
});
