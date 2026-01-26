/// Пакет данных от датчика
class SensorPacket {
  final int timestampMs;
  
  // Расстояние (мм)
  final double? distanceMm;
  
  // Электричество
  final double? voltageV;
  final double? currentA;
  final double? powerW;
  
  // Окружающая среда
  final double? temperatureC;
  final double? pressurePa;
  final double? humidityPct;
  
  // Движение (м/с²)
  final double? accelX;
  final double? accelY;
  final double? accelZ;
  
  // Гироскоп (°/с)
  final double? gyroX;
  final double? gyroY;
  final double? gyroZ;
  
  // Термопара
  final double? thermocoupleC;

  const SensorPacket({
    required this.timestampMs,
    this.distanceMm,
    this.voltageV,
    this.currentA,
    this.powerW,
    this.temperatureC,
    this.pressurePa,
    this.humidityPct,
    this.accelX,
    this.accelY,
    this.accelZ,
    this.gyroX,
    this.gyroY,
    this.gyroZ,
    this.thermocoupleC,
  });

  /// Время в секундах (для графиков)
  double get timeSeconds => timestampMs / 1000.0;

  @override
  String toString() {
    final parts = <String>[];
    parts.add('t=${timestampMs}ms');
    if (distanceMm != null) parts.add('d=${distanceMm!.toStringAsFixed(1)}mm');
    if (voltageV != null) parts.add('V=${voltageV!.toStringAsFixed(3)}V');
    if (currentA != null) parts.add('I=${currentA!.toStringAsFixed(4)}A');
    if (temperatureC != null) parts.add('T=${temperatureC!.toStringAsFixed(1)}°C');
    return 'SensorPacket(${parts.join(', ')})';
  }
}

/// Информация о подключённом устройстве
class DeviceInfo {
  final String name;
  final String firmwareVersion;
  final int batteryPercent;
  final List<String> enabledSensors;
  final ConnectionType connectionType;

  const DeviceInfo({
    required this.name,
    required this.firmwareVersion,
    required this.batteryPercent,
    required this.enabledSensors,
    required this.connectionType,
  });

  factory DeviceInfo.mock() => const DeviceInfo(
    name: 'PhysicsLab Mock',
    firmwareVersion: '1.0.0-mock',
    batteryPercent: 100,
    enabledSensors: ['distance', 'temperature', 'acceleration'],
    connectionType: ConnectionType.mock,
  );
}

enum ConnectionType {
  ble,
  usb,
  mock,
}

enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,
}
