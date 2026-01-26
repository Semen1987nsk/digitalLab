import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import '../../domain/entities/sensor_data.dart';
import '../../domain/repositories/hal_interface.dart';

/// USB HAL для датчика расстояния V802 (HC-SR04 + FT232RL)
/// Использует flutter_libserialport для Windows/Linux/macOS
/// 
/// Формат данных: "173 cm\n" (число + пробел + "cm" + перевод строки)
/// Скорость порта: 9600 бод
class UsbHALWindows implements HALInterface {
  static const int _baudRate = 9600;
  
  final _connectionStatusController = StreamController<ConnectionStatus>.broadcast();
  final _sensorDataController = StreamController<SensorPacket>.broadcast();
  
  SerialPort? _port;
  SerialPortReader? _reader;
  StreamSubscription? _subscription;
  String _buffer = '';
  int _timestampMs = 0;
  int _startTimeMs = 0;
  bool _isMeasuring = false;
  double _calibrationOffset = 0.0;
  Timer? _readTimer;
  
  DeviceInfo? _deviceInfo;
  
  @override
  Stream<ConnectionStatus> get connectionStatus => _connectionStatusController.stream;
  
  @override
  Stream<SensorPacket> get sensorData => _sensorDataController.stream;
  
  @override
  DeviceInfo? get deviceInfo => _deviceInfo;
  
  /// Получить список доступных COM-портов
  static List<String> getAvailablePorts() {
    return SerialPort.availablePorts;
  }
  
  /// Найти порт FT232RL (V802)
  static String? findV802Port() {
    final ports = SerialPort.availablePorts;
    
    for (final portName in ports) {
      try {
        final port = SerialPort(portName);
        final description = port.description ?? '';
        final manufacturer = port.manufacturer ?? '';
        
        // Ищем FT232R или FTDI
        if (description.toLowerCase().contains('ft232') ||
            description.toLowerCase().contains('ftdi') ||
            manufacturer.toLowerCase().contains('ftdi')) {
          port.dispose();
          return portName;
        }
        port.dispose();
      } catch (e) {
        // Порт может быть занят
        continue;
      }
    }
    
    // Если не нашли FT232, возвращаем первый доступный COM-порт
    if (ports.isNotEmpty) {
      return ports.first;
    }
    
    return null;
  }
  
  @override
  Future<bool> connect() async {
    _connectionStatusController.add(ConnectionStatus.connecting);
    
    try {
      final portName = findV802Port();
      
      if (portName == null) {
        print('USB HAL: Порты не найдены');
        _connectionStatusController.add(ConnectionStatus.error);
        return false;
      }
      
      print('USB HAL: Подключение к $portName');
      
      _port = SerialPort(portName);
      
      // Настройка порта
      final config = SerialPortConfig();
      config.baudRate = _baudRate;
      config.bits = 8;
      config.stopBits = 1;
      config.parity = SerialPortParity.none;
      config.setFlowControl(SerialPortFlowControl.none);
      
      if (!_port!.openReadWrite()) {
        print('USB HAL: Не удалось открыть порт: ${SerialPort.lastError}');
        _connectionStatusController.add(ConnectionStatus.error);
        return false;
      }
      
      _port!.config = config;
      
      _deviceInfo = DeviceInfo(
        name: 'V802 ($portName)',
        firmwareVersion: 'USB-Serial',
        batteryPercent: 100,
        enabledSensors: ['distance'],
        connectionType: ConnectionType.usb,
      );
      
      // Начать чтение данных
      _startReading();
      
      _connectionStatusController.add(ConnectionStatus.connected);
      print('USB HAL: Подключено к $portName');
      return true;
      
    } catch (e) {
      print('USB HAL: Ошибка подключения: $e');
      _connectionStatusController.add(ConnectionStatus.error);
      return false;
    }
  }
  
  void _startReading() {
    _reader = SerialPortReader(_port!);
    
    _subscription = _reader!.stream.listen(
      (data) {
        _processIncomingData(data);
      },
      onError: (error) {
        print('USB HAL: Ошибка чтения: $error');
        _connectionStatusController.add(ConnectionStatus.error);
      },
      onDone: () {
        print('USB HAL: Поток закрыт');
        _connectionStatusController.add(ConnectionStatus.disconnected);
      },
    );
  }
  
  void _processIncomingData(Uint8List data) {
    // Добавляем данные в буфер
    _buffer += String.fromCharCodes(data);
    
    // Ищем полные строки (оканчивающиеся на \n или \r\n)
    while (true) {
      final newlineIndex = _buffer.indexOf('\n');
      if (newlineIndex == -1) break;
      
      final line = _buffer.substring(0, newlineIndex).trim();
      _buffer = _buffer.substring(newlineIndex + 1);
      
      if (line.isNotEmpty) {
        _parseLine(line);
      }
    }
    
    // Защита от переполнения буфера
    if (_buffer.length > 1024) {
      _buffer = _buffer.substring(_buffer.length - 256);
    }
  }
  
  /// Парсинг строки вида "173 cm" или "45.2 см"
  void _parseLine(String line) {
    // Регулярка для извлечения числа
    final regex = RegExp(r'(\d+\.?\d*)\s*(?:cm|см|mm|мм)?', caseSensitive: false);
    final match = regex.firstMatch(line);
    
    if (match != null) {
      final valueStr = match.group(1);
      if (valueStr != null) {
        var value = double.tryParse(valueStr);
        
        if (value != null) {
          // Конвертируем cm в mm если нужно
          if (line.toLowerCase().contains('cm') || line.toLowerCase().contains('см')) {
            value *= 10; // cm -> mm
          }
          
          // Применяем калибровку
          value += _calibrationOffset;
          
          // Вычисляем timestamp
          if (_startTimeMs == 0) {
            _startTimeMs = DateTime.now().millisecondsSinceEpoch;
          }
          _timestampMs = DateTime.now().millisecondsSinceEpoch - _startTimeMs;
          
          // Создаём пакет данных
          final packet = SensorPacket(
            timestampMs: _timestampMs,
            distanceMm: value,
          );
          
          _sensorDataController.add(packet);
          
          print('USB HAL: Расстояние = ${value.toStringAsFixed(1)} мм');
        }
      }
    }
  }
  
  @override
  Future<void> disconnect() async {
    _subscription?.cancel();
    _subscription = null;
    
    _reader?.close();
    _reader = null;
    
    _port?.close();
    _port?.dispose();
    _port = null;
    
    _readTimer?.cancel();
    _readTimer = null;
    
    _buffer = '';
    _timestampMs = 0;
    _startTimeMs = 0;
    _isMeasuring = false;
    
    _connectionStatusController.add(ConnectionStatus.disconnected);
  }
  
  @override
  Future<void> startMeasurement() async {
    _isMeasuring = true;
    _startTimeMs = DateTime.now().millisecondsSinceEpoch;
    _timestampMs = 0;
  }
  
  @override
  Future<void> stopMeasurement() async {
    _isMeasuring = false;
  }
  
  @override
  Future<void> calibrate() async {
    // Для калибровки нужно измерить известное расстояние
    // Пока просто сбрасываем offset
    _calibrationOffset = 0.0;
  }
  
  @override
  Future<void> setCalibrationOffset(double offset) async {
    _calibrationOffset = offset;
  }
  
  @override
  Future<void> sendCommand(String command) async {
    if (_port == null || !_port!.isOpen) return;
    
    try {
      _port!.write(Uint8List.fromList('$command\n'.codeUnits));
    } catch (e) {
      print('USB HAL: Ошибка отправки команды: $e');
    }
  }
  
  @override
  void dispose() {
    disconnect();
    _connectionStatusController.close();
    _sensorDataController.close();
  }
}
