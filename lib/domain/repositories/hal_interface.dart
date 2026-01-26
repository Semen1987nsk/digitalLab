import '../entities/sensor_data.dart';

/// Абстрактный интерфейс Hardware Abstraction Layer
/// Все реализации (BLE, USB, Mock) должны реализовать этот интерфейс
abstract class HALInterface {
  /// Статус подключения
  Stream<ConnectionStatus> get connectionStatus;
  
  /// Поток данных от датчика
  Stream<SensorPacket> get sensorData;
  
  /// Информация об устройстве (null если не подключено)
  DeviceInfo? get deviceInfo;
  
  /// Подключиться к устройству
  Future<bool> connect();
  
  /// Отключиться
  Future<void> disconnect();
  
  /// Начать измерения
  Future<void> startMeasurement();
  
  /// Остановить измерения
  Future<void> stopMeasurement();
  
  /// Калибровать датчик (обнулить)
  Future<void> calibrate(String sensorId);
  
  /// Установить частоту опроса (Гц)
  Future<void> setSampleRate(int hz);
  
  /// Освободить ресурсы
  Future<void> dispose();
}
