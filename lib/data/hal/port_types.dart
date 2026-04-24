/// Shared port type definitions used by PortScanner, PortConnectionManager,
/// SensorHub, and UsbHALWindows.
///
/// Extracted to break circular import between port_scanner.dart and
/// port_connection_manager.dart.
library;

/// Тип COM-порта
enum PortType {
  ftdi,        // FTDI чип (датчик расстояния V802)
  arduino,     // Arduino UNO/Mega (мультидатчик Labosfera)
  bluetooth,   // Bluetooth Serial
  builtin,     // Встроенный порт (COM1 и т.д.)
  virtual,     // Виртуальный порт
  unknown,     // Неизвестный тип
}

/// Статус доступности порта
enum PortAvailability {
  available,      // Можно открыть
  accessDenied,   // errno=5 - нет прав или занят
  busy,           // Порт занят другой программой
  error,          // Другая ошибка
  untested,       // Ещё не проверяли
}

/// Полная информация о COM-порте
class PortInfo {
  final String name;              // "COM3"
  final String description;       // "USB Serial Port"
  final String manufacturer;      // "FTDI"
  final PortType type;            // ftdi
  final PortAvailability availability;
  final String? errorMessage;     // Сообщение об ошибке если есть
  final int? vendorId;
  final int? productId;
  
  const PortInfo({
    required this.name,
    required this.description,
    required this.manufacturer,
    required this.type,
    required this.availability,
    this.errorMessage,
    this.vendorId,
    this.productId,
  });
  
  /// Это вероятно наш датчик?
  bool get isLikelyOurSensor => type == PortType.ftdi || type == PortType.arduino;
  
  /// Это Arduino-мультидатчик?
  bool get isArduinoMultisensor => type == PortType.arduino;
  
  /// Это FTDI-датчик расстояния?
  bool get isFtdiDistanceSensor => type == PortType.ftdi;
  
  /// Можно ли подключиться?
  bool get canConnect => availability == PortAvailability.available;
  
  /// Человекочитаемое описание типа
  String get typeDescription {
    switch (type) {
      case PortType.ftdi: return 'FTDI (расстояние)';
      case PortType.arduino: return 'Arduino (мультидатчик)';
      case PortType.bluetooth: return 'Bluetooth';
      case PortType.builtin: return 'Встроенный';
      case PortType.virtual: return 'Виртуальный';
      case PortType.unknown: return 'Неизвестный';
    }
  }
  
  /// Человекочитаемый статус
  String get availabilityDescription {
    switch (availability) {
      case PortAvailability.available: return '✓ Доступен';
      case PortAvailability.accessDenied: return '✗ Нет доступа';
      case PortAvailability.busy: return '✗ Занят';
      case PortAvailability.error: return '✗ Ошибка';
      case PortAvailability.untested: return '? Не проверен';
    }
  }
  
  @override
  String toString() => '$name: $description ($typeDescription) - $availabilityDescription';
}
