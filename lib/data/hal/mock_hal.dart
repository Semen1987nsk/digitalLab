import 'dart:async';
import 'dart:math';
import '../../domain/entities/sensor_data.dart';
import '../../domain/repositories/hal_interface.dart';
import '../../presentation/pages/test_lab/test_scenarios_page.dart';

/// Mock-реализация HAL для разработки без реального оборудования
/// Генерирует реалистичные данные датчика расстояния с шумом
/// Поддерживает различные сценарии для тестирования
class MockHAL implements HALInterface {
  final _connectionStatusController = StreamController<ConnectionStatus>.broadcast();
  final _sensorDataController = StreamController<SensorPacket>.broadcast();
  
  Timer? _measurementTimer;
  Timer? _disconnectTimer;
  final _random = Random();
  int _timestampMs = 0;
  int _sampleRateHz = 10;
  bool _isMeasuring = false;
  
  // Параметры симуляции
  double _baseDistance = 500.0; // мм
  double _distanceOffset = 0.0; // калибровка
  double _motionPhase = 0.0;
  
  // Текущий сценарий тестирования
  TestScenario _scenario = TestScenario.normalConnection;
  String _lastErrorMessage = '';
  
  DeviceInfo? _deviceInfo;
  
  /// Последнее сообщение об ошибке (для тестирования)
  String get lastErrorMessage => _lastErrorMessage;
  
  /// Установить сценарий тестирования
  void setScenario(TestScenario scenario) {
    _scenario = scenario;
    print('MockHAL: Сценарий установлен: ${scenario.title}');
  }
  
  @override
  Stream<ConnectionStatus> get connectionStatus => _connectionStatusController.stream;
  
  @override
  Stream<SensorPacket> get sensorData => _sensorDataController.stream;
  
  @override
  DeviceInfo? get deviceInfo => _deviceInfo;
  
  @override
  bool get isCalibrated => _distanceOffset != 0.0;
  
  @override
  Future<bool> connect() async {
    _connectionStatusController.add(ConnectionStatus.connecting);
    _lastErrorMessage = '';
    
    // Обработка сценариев подключения
    switch (_scenario) {
      case TestScenario.accessDenied:
        await Future.delayed(const Duration(milliseconds: 300));
        _lastErrorMessage = 'Доступ запрещён (errno=5). Запустите от Администратора или закройте другие программы.';
        _connectionStatusController.add(ConnectionStatus.error);
        return false;
        
      case TestScenario.portBusy:
        await Future.delayed(const Duration(milliseconds: 500));
        _lastErrorMessage = 'Порт занят другой программой (errno=16). Закройте Arduino IDE или PuTTY.';
        _connectionStatusController.add(ConnectionStatus.error);
        return false;
        
      case TestScenario.noPortsFound:
        await Future.delayed(const Duration(milliseconds: 200));
        _lastErrorMessage = 'COM-порты не найдены. Проверьте подключение USB.';
        _connectionStatusController.add(ConnectionStatus.error);
        return false;
        
      case TestScenario.slowConnection:
        // Медленное подключение - 5 секунд
        await Future.delayed(const Duration(seconds: 5));
        break;
        
      case TestScenario.disconnectMidSession:
        // Подключаемся нормально, но запланируем отключение
        await Future.delayed(const Duration(milliseconds: 500));
        _disconnectTimer = Timer(const Duration(seconds: 5), () {
          _lastErrorMessage = 'Соединение потеряно. Датчик отключён.';
          _connectionStatusController.add(ConnectionStatus.error);
          stopMeasurement();
        });
        break;
        
      default:
        // Обычная задержка подключения
        await Future.delayed(const Duration(milliseconds: 500));
    }
    
    _deviceInfo = DeviceInfo(
      name: 'Mock-датчик (${_scenario.title})',
      firmwareVersion: 'Mock 1.0',
      batteryPercent: 85,
      enabledSensors: ['distance', 'temperature'],
      connectionType: ConnectionType.usb,
    );
    _timestampMs = 0;
    
    _connectionStatusController.add(ConnectionStatus.connected);
    return true;
  }
  
  @override
  Future<void> disconnect() async {
    _disconnectTimer?.cancel();
    _disconnectTimer = null;
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
    // Toggle: если калибровка активна - сбрасываем
    if (_distanceOffset != 0.0) {
      _distanceOffset = 0.0;
    } else {
      if (sensorId == 'distance') {
        _distanceOffset = -_baseDistance;
      }
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
    _disconnectTimer?.cancel();
    await disconnect();
    await _connectionStatusController.close();
    await _sensorDataController.close();
  }
  
  /// Счётчик пакетов для сценария прерывистых данных
  int _packetCounter = 0;

  /// Генерация реалистичных данных с шумом
  void _generateSensorData() {
    _timestampMs += (1000 / _sampleRateHz).round();
    _motionPhase += 0.05;
    _packetCounter++;
    
    // Обработка сценариев данных
    switch (_scenario) {
      case TestScenario.intermittentData:
        // Пропускаем каждый 3-й пакет
        if (_packetCounter % 3 == 0) return;
        break;
        
      case TestScenario.wrongBaudRate:
        // Генерируем мусор
        final garbage = SensorPacket(
          timestampMs: _timestampMs,
          distanceMm: _random.nextDouble() * 99999 - 50000,
          temperatureC: _random.nextDouble() * 1000 - 500,
        );
        _sensorDataController.add(garbage);
        return;
        
      default:
        break;
    }
    
    // Базовые параметры шума
    double noiseMultiplier = 1.0;
    if (_scenario == TestScenario.noisyData) {
      noiseMultiplier = 10.0; // В 10 раз больше шума
    }
    
    // Симуляция: объект приближается и удаляется (синусоида)
    // + белый шум ±5мм (реалистично для VL53L1X)
    final motion = sin(_motionPhase) * 200; // ±200мм
    final noise = (_random.nextDouble() - 0.5) * 10 * noiseMultiplier;
    
    final distance = _baseDistance + motion + noise + _distanceOffset;
    
    // Симуляция температуры (медленные изменения)
    final tempNoise = (_random.nextDouble() - 0.5) * 0.2 * noiseMultiplier;
    final temperature = 22.0 + sin(_motionPhase * 0.1) * 2 + tempNoise;
    
    // Симуляция ускорения (вибрации)
    final accelX = (_random.nextDouble() - 0.5) * 0.1 * noiseMultiplier;
    final accelY = (_random.nextDouble() - 0.5) * 0.1 * noiseMultiplier;
    final accelZ = 9.81 + (_random.nextDouble() - 0.5) * 0.05 * noiseMultiplier;
    
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
