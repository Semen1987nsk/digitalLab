import 'dart:async';
import 'dart:math';
import '../../domain/entities/sensor_data.dart';
import '../../domain/repositories/hal_interface.dart';

/// Mock-реализация HAL для разработки без реального оборудования
/// Генерирует реалистичные данные датчика расстояния с шумом
class MockHAL implements HALInterface {
  final _connectionStatusController = StreamController<ConnectionStatus>.broadcast();
  final _sensorDataController = StreamController<SensorPacket>.broadcast();
  
  Timer? _measurementTimer;
  final _random = Random();
  int _timestampMs = 0;
  int _sampleRateHz = 10;
  bool _isMeasuring = false;
  
  // Параметры симуляции
  double _baseDistance = 500.0; // мм
  double _distanceOffset = 0.0; // калибровка
  double _motionPhase = 0.0;
  
  DeviceInfo? _deviceInfo;
  
  @override
  Stream<ConnectionStatus> get connectionStatus => _connectionStatusController.stream;
  
  @override
  Stream<SensorPacket> get sensorData => _sensorDataController.stream;
  
  @override
  DeviceInfo? get deviceInfo => _deviceInfo;
  
  @override
  Future<bool> connect() async {
    _connectionStatusController.add(ConnectionStatus.connecting);
    
    // Имитация задержки подключения
    await Future.delayed(const Duration(milliseconds: 500));
    
    _deviceInfo = DeviceInfo.mock();
    _timestampMs = 0;
    
    _connectionStatusController.add(ConnectionStatus.connected);
    return true;
  }
  
  @override
  Future<void> disconnect() async {
    await stopMeasurement();
    _deviceInfo = null;
    _connectionStatusController.add(ConnectionStatus.disconnected);
  }
  
  @override
  Future<void> startMeasurement() async {
    if (_isMeasuring) return;
    _isMeasuring = true;
    
    final intervalMs = (1000 / _sampleRateHz).round();
    
    _measurementTimer = Timer.periodic(
      Duration(milliseconds: intervalMs),
      (_) => _generateSensorData(),
    );
  }
  
  @override
  Future<void> stopMeasurement() async {
    _isMeasuring = false;
    _measurementTimer?.cancel();
    _measurementTimer = null;
  }
  
  @override
  Future<void> calibrate(String sensorId) async {
    if (sensorId == 'distance') {
      _distanceOffset = -_baseDistance;
    }
  }
  
  @override
  Future<void> setSampleRate(int hz) async {
    _sampleRateHz = hz.clamp(1, 100);
    if (_isMeasuring) {
      await stopMeasurement();
      await startMeasurement();
    }
  }
  
  @override
  Future<void> dispose() async {
    await disconnect();
    await _connectionStatusController.close();
    await _sensorDataController.close();
  }
  
  /// Генерация реалистичных данных с шумом
  void _generateSensorData() {
    _timestampMs += (1000 / _sampleRateHz).round();
    _motionPhase += 0.05;
    
    // Симуляция: объект приближается и удаляется (синусоида)
    // + белый шум ±5мм (реалистично для VL53L1X)
    final motion = sin(_motionPhase) * 200; // ±200мм
    final noise = (_random.nextDouble() - 0.5) * 10; // ±5мм
    
    final distance = _baseDistance + motion + noise + _distanceOffset;
    
    // Симуляция температуры (медленные изменения)
    final temperature = 22.0 + sin(_motionPhase * 0.1) * 2 + 
                        (_random.nextDouble() - 0.5) * 0.2;
    
    // Симуляция ускорения (вибрации)
    final accelX = (_random.nextDouble() - 0.5) * 0.1;
    final accelY = (_random.nextDouble() - 0.5) * 0.1;
    final accelZ = 9.81 + (_random.nextDouble() - 0.5) * 0.05;
    
    final packet = SensorPacket(
      timestampMs: _timestampMs,
      distanceMm: distance.clamp(0, 4000), // VL53L1X max range
      temperatureC: temperature,
      accelX: accelX,
      accelY: accelY,
      accelZ: accelZ,
    );
    
    _sensorDataController.add(packet);
  }
}
