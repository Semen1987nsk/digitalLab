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
final halModeProvider = StateProvider<HalMode>((ref) => HalMode.mock);

/// Провайдер HAL (Hardware Abstraction Layer)
/// Автоматически выбирает реализацию в зависимости от режима
final halProvider = Provider<HALInterface>((ref) {
  final mode = ref.watch(halModeProvider);
  
  final HALInterface hal;
  switch (mode) {
    case HalMode.usb:
      // На Windows/Linux/macOS используем flutter_libserialport
      // На Android используем usb_serial
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        hal = UsbHALWindows();
      } else {
        hal = UsbHAL();
      }
      break;
    case HalMode.ble:
      // TODO: BleHAL
      hal = MockHAL();
      break;
    case HalMode.mock:
    default:
      hal = MockHAL();
  }
  
  ref.onDispose(() => hal.dispose());
  return hal;
});

/// Провайдер статуса подключения
final connectionStatusProvider = StreamProvider<ConnectionStatus>((ref) {
  final hal = ref.watch(halProvider);
  return hal.connectionStatus;
});

/// Провайдер потока данных
final sensorDataProvider = StreamProvider<SensorPacket>((ref) {
  final hal = ref.watch(halProvider);
  return hal.sensorData;
});

/// Провайдер информации об устройстве
final deviceInfoProvider = Provider<DeviceInfo?>((ref) {
  final hal = ref.watch(halProvider);
  return hal.deviceInfo;
});

/// Состояние эксперимента
class ExperimentState {
  final bool isRunning;
  final List<SensorPacket> data;
  final int sampleRateHz;
  final DateTime? startTime;
  
  const ExperimentState({
    this.isRunning = false,
    this.data = const [],
    this.sampleRateHz = 10,
    this.startTime,
  });
  
  ExperimentState copyWith({
    bool? isRunning,
    List<SensorPacket>? data,
    int? sampleRateHz,
    DateTime? startTime,
  }) {
    return ExperimentState(
      isRunning: isRunning ?? this.isRunning,
      data: data ?? this.data,
      sampleRateHz: sampleRateHz ?? this.sampleRateHz,
      startTime: startTime ?? this.startTime,
    );
  }
  
  /// Длительность эксперимента
  Duration get duration {
    if (startTime == null) return Duration.zero;
    return DateTime.now().difference(startTime!);
  }
  
  /// Количество измерений
  int get measurementCount => data.length;
}

/// Контроллер эксперимента
class ExperimentController extends StateNotifier<ExperimentState> {
  final HALInterface _hal;
  
  ExperimentController(this._hal) : super(const ExperimentState());
  
  /// Подключиться к датчику
  Future<bool> connect() async {
    return await _hal.connect();
  }
  
  /// Начать эксперимент
  Future<void> start() async {
    state = state.copyWith(
      isRunning: true,
      data: [],
      startTime: DateTime.now(),
    );
    
    await _hal.setSampleRate(state.sampleRateHz);
    await _hal.startMeasurement();
    
    // Подписка на данные
    _hal.sensorData.listen((packet) {
      if (state.isRunning) {
        state = state.copyWith(data: [...state.data, packet]);
      }
    });
  }
  
  /// Остановить эксперимент
  Future<void> stop() async {
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
  
  /// Калибровать датчик
  Future<void> calibrate(String sensorId) async {
    await _hal.calibrate(sensorId);
  }
}

/// Провайдер контроллера эксперимента
final experimentControllerProvider = 
    StateNotifierProvider<ExperimentController, ExperimentState>((ref) {
  final hal = ref.watch(halProvider);
  return ExperimentController(hal);
});
