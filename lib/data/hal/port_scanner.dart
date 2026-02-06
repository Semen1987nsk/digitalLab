import 'package:flutter_libserialport/flutter_libserialport.dart';

/// Тип COM-порта
enum PortType {
  ftdi,        // FTDI чип (наш датчик!)
  arduino,     // Arduino (CH340, CP210x)
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
  bool get isLikelyOurSensor => type == PortType.ftdi;
  
  /// Можно ли подключиться?
  bool get canConnect => availability == PortAvailability.available;
  
  /// Человекочитаемое описание типа
  String get typeDescription {
    switch (type) {
      case PortType.ftdi: return 'FTDI (датчик)';
      case PortType.arduino: return 'Arduino';
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

/// Сканер COM-портов с проверкой доступности
class PortScanner {
  /// Callback для логирования
  final void Function(String message)? onLog;
  
  PortScanner({this.onLog});
  
  void _log(String message) {
    onLog?.call(message);
    print('PortScanner: $message');
  }
  
  /// Очищает строку от невалидных UTF-8 символов (проблема кодировки Windows)
  String _sanitizeString(String input) {
    if (input.isEmpty) return input;
    
    // Проверяем на типичные признаки неправильной кодировки
    // CP1251 "Последовательный порт" читается как "Ïîñëåäîâàòåëüíûé ïîðò"
    // Символы Ï, î, ñ и т.д. - это 0xCF, 0xEE, 0xF1 в UTF-8
    
    // Если есть символы из диапазона кириллицы CP1251, 
    // но они не образуют валидную UTF-8 последовательность
    bool hasEncodingIssue = false;
    
    for (int i = 0; i < input.length; i++) {
      final c = input.codeUnitAt(i);
      // Эти символы часто появляются при неправильной кодировке
      // Ï = 0xCF (207), î = 0xEE (238), ñ = 0xF1 (241), etc.
      if ((c >= 0xC0 && c <= 0xFF) && i + 1 < input.length) {
        final next = input.codeUnitAt(i + 1);
        // В правильной UTF-8 за байтом 0xC0-0xDF должен идти 0x80-0xBF
        // Но в испорченной кодировке идут другие символы
        if (c >= 0xC0 && c <= 0xDF && (next < 0x80 || next > 0xBF)) {
          hasEncodingIssue = true;
          break;
        }
      }
      // Простая проверка: если много символов > 127 подряд - скорее всего проблема
      if (c > 127 && c < 256) {
        hasEncodingIssue = true;
        break;
      }
    }
    
    if (hasEncodingIssue) {
      return ''; // Не показываем мусор
    }
    
    // Удаляем непечатаемые символы
    return input.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '').trim();
  }
  
  /// Сканирует все порты и возвращает полную информацию
  Future<List<PortInfo>> scanPorts({
    bool testAvailability = true,
    void Function(String message)? onProgress,
  }) async {
    void log(String message) {
      _log(message);
      onProgress?.call(message);
    }
    
    log('Начало сканирования портов...');
    
    final List<PortInfo> result = [];
    
    try {
      final portNames = SerialPort.availablePorts;
      log('Найдено ${portNames.length} портов');
      
      for (final portName in portNames) {
        final portInfo = await _analyzePort(portName, testAvailability);
        result.add(portInfo);
        log('  $portInfo');
      }
      
      // Сортируем: FTDI порты первые, затем доступные
      result.sort((a, b) {
        // FTDI порты первые
        if (a.isLikelyOurSensor && !b.isLikelyOurSensor) return -1;
        if (!a.isLikelyOurSensor && b.isLikelyOurSensor) return 1;
        // Затем по доступности
        if (a.canConnect && !b.canConnect) return -1;
        if (!a.canConnect && b.canConnect) return 1;
        // Затем по имени
        return a.name.compareTo(b.name);
      });
      
    } catch (e) {
      log('Ошибка сканирования: $e');
    }
    
    log('Сканирование завершено: ${result.length} портов');
    return result;
  }
  
  /// Анализирует один порт
  Future<PortInfo> _analyzePort(String portName, bool testAvailability) async {
    String description = '';
    String manufacturer = '';
    PortType type = PortType.unknown;
    PortAvailability availability = PortAvailability.untested;
    String? errorMessage;
    int? vendorId;
    int? productId;
    
    SerialPort? port;
    
    try {
      port = SerialPort(portName);
      
      // Получаем информацию о порте
      description = _sanitizeString(port.description ?? '');
      manufacturer = _sanitizeString(port.manufacturer ?? '');
      vendorId = port.vendorId;
      productId = port.productId;
      
      // Определяем тип порта
      type = _detectPortType(portName, description, manufacturer, vendorId);
      
      // Тестируем доступность если нужно
      if (testAvailability) {
        availability = await _testPortAvailability(port);
        if (availability != PortAvailability.available) {
          errorMessage = SerialPort.lastError?.message;
        }
      }
      
    } catch (e) {
      errorMessage = e.toString();
      availability = PortAvailability.error;
    } finally {
      try { port?.dispose(); } catch (_) {}
    }
    
    return PortInfo(
      name: portName,
      description: description,
      manufacturer: manufacturer,
      type: type,
      availability: availability,
      errorMessage: errorMessage,
      vendorId: vendorId,
      productId: productId,
    );
  }
  
  /// Определяет тип порта по его характеристикам
  PortType _detectPortType(String name, String description, String manufacturer, int? vendorId) {
    final descLower = description.toLowerCase();
    final mfrLower = manufacturer.toLowerCase();
    
    // FTDI (VID: 0x0403)
    if (vendorId == 0x0403 ||
        descLower.contains('ftdi') ||
        descLower.contains('ft232') ||
        mfrLower.contains('ftdi')) {
      return PortType.ftdi;
    }
    
    // Arduino / CH340 / CP210x
    if (descLower.contains('ch340') ||
        descLower.contains('cp210') ||
        descLower.contains('arduino') ||
        mfrLower.contains('wch') ||
        mfrLower.contains('silicon labs')) {
      return PortType.arduino;
    }
    
    // Bluetooth
    if (descLower.contains('bluetooth') ||
        descLower.contains('bth') ||
        descLower.contains('rfcomm')) {
      return PortType.bluetooth;
    }
    
    // USB Serial - НЕ считаем автоматически датчиком!
    // SUNIX и другие PCI-E карты тоже показываются как USB Serial
    // Только FTDI VID 0x0403 гарантированно наш датчик
    // if (descLower.contains('usb') && descLower.contains('serial')) {
    //   return PortType.ftdi; // УДАЛЕНО - это неправильно
    // }
    
    // Встроенные порты (COM1, COM2 часто)
    if (name == 'COM1' || name == 'COM2') {
      // Но проверяем - может быть USB
      if (descLower.contains('usb')) {
        return PortType.unknown;
      }
      return PortType.builtin;
    }
    
    // Виртуальные порты
    if (descLower.contains('virtual') ||
        descLower.contains('emulated')) {
      return PortType.virtual;
    }
    
    return PortType.unknown;
  }
  
  /// Тестирует доступность порта (пытается открыть)
  Future<PortAvailability> _testPortAvailability(SerialPort port) async {
    try {
      // Пробуем открыть на чтение
      final opened = port.openRead();
      
      if (opened) {
        port.close();
        return PortAvailability.available;
      }
      
      // Анализируем ошибку
      final error = SerialPort.lastError;
      if (error != null) {
        final errno = error.errorCode;
        // errno 5 = Access Denied (Windows)
        // errno 13 = Permission denied (Linux)
        if (errno == 5 || errno == 13) {
          return PortAvailability.accessDenied;
        }
        // errno 16 = Device busy (Linux)
        if (errno == 16) {
          return PortAvailability.busy;
        }
      }
      
      return PortAvailability.error;
      
    } catch (e) {
      return PortAvailability.error;
    }
  }
  
  /// Находит лучший порт для датчика (автовыбор)
  /// ВАЖНО: Возвращает только FTDI порты! Не возвращает случайные порты.
  PortInfo? findBestSensorPort(List<PortInfo> ports) {
    // 1. Ищем FTDI порт который доступен
    for (final port in ports) {
      if (port.isLikelyOurSensor && port.canConnect) {
        _log('Лучший порт (FTDI доступен): ${port.name}');
        return port;
      }
    }
    
    // 2. Ищем любой FTDI порт (даже недоступный - для диагностики)
    for (final port in ports) {
      if (port.isLikelyOurSensor) {
        _log('FTDI порт найден но недоступен: ${port.name} - ${port.availabilityDescription}');
        return port;
      }
    }
    
    // ВАЖНО: НЕ возвращаем случайные порты!
    // Если FTDI не найден - значит датчик не подключён
    _log('Датчик FTDI не найден. Подключите датчик к USB.');
    return null;
  }
}
