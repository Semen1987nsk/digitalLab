import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../domain/entities/sensor_data.dart';
import '../../domain/repositories/hal_interface.dart';

/// Mock-реализация HAL для разработки без реального оборудования.
///
/// Генерирует реалистичные данные для всех 9 датчиков:
/// Базовые: V, A, P, T, Acc(xyz), Mag
/// 360: Distance, Force, Lux
class MockHAL implements HALInterface {
  final _connectionStatusController = StreamController<ConnectionStatus>.broadcast();
  final _sensorDataController = StreamController<SensorPacket>.broadcast();

  Timer? _measurementTimer;
  final _rng = Random();
  int _timestampMs = 0;
  int _sampleRateHz = 10;
  /// Флаг: идёт ли формальное измерение (эксперимент).
  /// Данные генерируются всегда (для превью), но timestamps
  /// обнуляются при start/stop.
  // ignore: unused_field
  bool _isMeasuring = false;

  // Фазы симуляции (разные частоты — реалистичнее)
  double _phase = 0.0;

  // Калибровка
  double _distanceOffset = 0.0;

  DeviceInfo? _deviceInfo;

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
    debugPrint('Mock HAL: connect() вызван');
    _connectionStatusController.add(ConnectionStatus.connecting);
    await Future.delayed(const Duration(milliseconds: 500));

    _deviceInfo = const DeviceInfo(
      name: 'Labosfera Mock',
      firmwareVersion: '2.0.0-dev',
      batteryPercent: 87,
      enabledSensors: [
        'voltage', 'current', 'pressure', 'temperature',
        'acceleration', 'magnetic_field',
        'distance', 'force', 'lux', 'radiation',
      ],
      connectionType: ConnectionType.mock,
    );
    _timestampMs = 0;
    _phase = 0;

    // Запускаем генерацию данных СРАЗУ при подключении
    // Это обеспечивает живой превью на главном экране
    _startDataGeneration();

    _connectionStatusController.add(ConnectionStatus.connected);
    debugPrint('Mock HAL: подключено, таймер запущен ($_sampleRateHz Гц)');
    return true;
  }

  /// Запуск таймера генерации данных
  void _startDataGeneration() {
    _measurementTimer?.cancel();
    final intervalMs = (1000 / _sampleRateHz).round();
    _measurementTimer = Timer.periodic(
      Duration(milliseconds: intervalMs),
      (_) => _generateSensorData(),
    );
  }

  @override
  Future<void> disconnect() async {
    _isMeasuring = false;
    _measurementTimer?.cancel();
    _measurementTimer = null;
    _deviceInfo = null;
    _distanceOffset = 0.0;
    _timestampMs = 0;
    _phase = 0;
    _connectionStatusController.add(ConnectionStatus.disconnected);
  }

  @override
  Future<void> startMeasurement() async {
    _isMeasuring = true;
    // Сбрасываем timestamps для эксперимента (таймер уже работает)
    _timestampMs = 0;
    _phase = 0;
    debugPrint('Mock HAL: Измерение начато (timestamps обнулены)');
  }

  @override
  Future<void> stopMeasurement() async {
    _isMeasuring = false;
    // Таймер НЕ останавливаем — данные продолжают течь для превью
    debugPrint('Mock HAL: Измерение остановлено (превью активен)');
  }

  @override
  Future<void> calibrate(String sensorId) async {
    if (sensorId == 'distance') {
      // Toggle: если калибровка активна — сбрасываем, иначе устанавливаем
      _distanceOffset = _distanceOffset != 0.0 ? 0.0 : -500.0;
    }
    // Для других датчиков — пока не реализовано в Mock
  }

  @override
  Future<void> setSampleRate(int hz) async {
    _sampleRateHz = hz.clamp(1, 100);
    // Перезапускаем таймер с новой частотой если активен
    if (_measurementTimer != null) {
      _startDataGeneration();
    }
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    await _connectionStatusController.close();
    await _sensorDataController.close();
  }

  double _noise(double amplitude) => (_rng.nextDouble() - 0.5) * amplitude;

  void _generateSensorData() {
    _timestampMs += (1000 / _sampleRateHz).round();
    _phase += 0.05;

    // Отладочный вывод каждые 5 секунд
    if (_timestampMs % 5000 < (1000 / _sampleRateHz).round() + 1) {
      debugPrint('Mock HAL: генерация данных, t=${_timestampMs}ms, phase=${_phase.toStringAsFixed(2)}');
    }

    // ── Базовые датчики ──────────────────────────────────────

    // Напряжение: батарейка 3-5В с медленной разрядкой
    final voltage = 4.0 + sin(_phase * 0.2) * 1.0 + _noise(0.05);

    // Ток: V/R, R≈100Ω + шум
    final current = voltage / 100.0 + _noise(0.003);

    // Давление: атмосферное ~101.3 кПа + медленный дрейф
    final pressure = 101325.0 + sin(_phase * 0.05) * 500 + _noise(50);

    // Температура: комнатная ~22°C с медленным дрейфом
    final temperature = 22.0 + sin(_phase * 0.1) * 2 + _noise(0.1);

    // Ускорение: покоится (g по Z) + лёгкие вибрации
    final accelX = _noise(0.08);
    final accelY = _noise(0.08);
    final accelZ = 9.81 + _noise(0.04);

    // Влажность: ~45% с медленным дрейфом (BME280)
    final humidity = 45.0 + sin(_phase * 0.07) * 10 + _noise(0.5);

    // Магнитное поле: ~50 мТл (магнит рядом) + синусоида при удалении
    final magnetic = 50.0 + sin(_phase * 0.3) * 30 + _noise(2);

    // ── Датчики 360 ──────────────────────────────────────────

    // Расстояние: объект ~50 см, качается ±20 см
    final distance = 500.0 + sin(_phase) * 200 + _noise(5) + _distanceOffset;

    // Сила: пружина — осциллирующий сигнал ~5 Н
    final force = 5.0 + sin(_phase * 1.5) * 3 + _noise(0.15);

    // Освещённость: лампа ~500 лк, мерцание 50 Гц (симуляция)
    final lux = 500.0 + sin(_phase * 2.0) * 100 + _noise(10);

    // ── Модуль "Атом" ────────────────────────────────────────

    // Радиация: фоновый уровень ~20–60 имп/мин с пуассоновским шумом
    final radiation = 35.0 + sin(_phase * 0.08) * 15 + _noise(8);

    _sensorDataController.add(SensorPacket(
      timestampMs: _timestampMs,
      voltageV: voltage,
      currentA: current,
      pressurePa: pressure,
      temperatureC: temperature,
      accelX: accelX,
      accelY: accelY,
      accelZ: accelZ,
      magneticFieldMt: magnetic,
      humidityPct: humidity.clamp(0, 100),
      distanceMm: distance.clamp(150, 4000),
      forceN: force,
      luxLx: lux.clamp(0, 100000),
      radiationCpm: radiation.clamp(0, 20000),
    ));
  }
}
