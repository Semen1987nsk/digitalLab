import 'dart:async';
import 'dart:typed_data';
import 'package:usb_serial/usb_serial.dart';
import '../../domain/entities/sensor_data.dart';
import '../../domain/repositories/hal_interface.dart';

/// USB HAL для датчика расстояния V802 (HC-SR04 + FT232RL)
/// 
/// Формат данных: "173 cm\n" (число + пробел + "cm" + перевод строки)
/// Скорость порта: 9600 бод
class UsbHAL implements HALInterface {
  static const int _baudRate = 9600;
  static const int _vendorId = 0x0403;   // FTDI
  static const int _productId = 0x6001;  // FT232RL
  
  final _connectionStatusController = StreamController<ConnectionStatus>.broadcast();
  final _sensorDataController = StreamController<SensorPacket>.broadcast();
  
  UsbPort? _port;
  StreamSubscription? _subscription;
  String _buffer = '';
  int _timestampMs = 0;
  int _startTimeMs = 0;
  bool _isMeasuring = false;
  double _calibrationOffset = 0.0;
  
  DeviceInfo? _deviceInfo;
  
  @override
  Stream<ConnectionStatus> get connectionStatus => _connectionStatusController.stream;
  
  @override
  Stream<SensorPacket> get sensorData => _sensorDataController.stream;
  
  @override
  DeviceInfo? get deviceInfo => _deviceInfo;
  
  /// Поиск устройства V802
  static Future<UsbDevice?> findDevice() async {
    final devices = await UsbSerial.listDevices();
    
    for (final device in devices) {
      // Ищем FT232RL
      if (device.vid == _vendorId && device.pid == _productId) {
        return device;
      }
    }
    
    // Если не нашли по VID/PID, возвращаем первое устройство
    if (devices.isNotEmpty) {
      return devices.first;
    }
    
    return null;
  }
  
  @override
  Future<bool> connect() async {
    _connectionStatusController.add(ConnectionStatus.connecting);
    
    try {
      final device = await findDevice();
      
      if (device == null) {
        _connectionStatusController.add(ConnectionStatus.error);
        return false;
      }
      
      _port = await device.create();
      
      if (_port == null) {
        _connectionStatusController.add(ConnectionStatus.error);
        return false;
      }
      
      final opened = await _port!.open();
      if (!opened) {
        _connectionStatusController.add(ConnectionStatus.error);
        return false;
      }
      
      // Настройка порта: 9600 бод, 8N1
      await _port!.setDTR(true);
      await _port!.setRTS(true);
      await _port!.setPortParameters(
        _baudRate,
        UsbPort.DATABITS_8,
        UsbPort.STOPBITS_1,
        UsbPort.PARITY_NONE,
      );
      
      _deviceInfo = DeviceInfo(
        name: 'V802 (${device.productName ?? "HC-SR04"})',
        firmwareVersion: 'USB-Serial',
        batteryPercent: 100, // USB-питание
        enabledSensors: ['distance'],
        connectionType: ConnectionType.usb,
      );
      
      // Подписка на входящие данные
      _subscription = _port!.inputStream?.listen(_onDataReceived);
      
      _connectionStatusController.add(ConnectionStatus.connected);
      return true;
      
    } catch (e) {
      print('[USB HAL] Connection error: $e');
      _connectionStatusController.add(ConnectionStatus.error);
      return false;
    }
  }
  
  @override
  Future<void> disconnect() async {
    await stopMeasurement();
    await _subscription?.cancel();
    _subscription = null;
    await _port?.close();
    _port = null;
    _deviceInfo = null;
    _connectionStatusController.add(ConnectionStatus.disconnected);
  }
  
  @override
  Future<void> startMeasurement() async {
    _isMeasuring = true;
    _startTimeMs = DateTime.now().millisecondsSinceEpoch;
    _buffer = '';
  }
  
  @override
  Future<void> stopMeasurement() async {
    _isMeasuring = false;
  }
  
  @override
  Future<void> calibrate(String sensorId) async {
    // Запоминаем текущее значение как ноль
    // Будет применено к следующим измерениям
    // Нужно получить последнее значение и сохранить как offset
    print('[USB HAL] Calibration requested for $sensorId');
  }
  
  /// Установить калибровочное смещение (см)
  void setCalibrationOffset(double offsetCm) {
    _calibrationOffset = offsetCm;
  }
  
  @override
  Future<void> setSampleRate(int hz) async {
    // Датчик V802 отправляет данные с фиксированной частотой
    // Игнорируем запрос (частота определяется прошивкой датчика)
    print('[USB HAL] Sample rate change not supported by V802');
  }
  
  @override
  Future<void> dispose() async {
    await disconnect();
    await _connectionStatusController.close();
    await _sensorDataController.close();
  }
  
  /// Обработка входящих данных
  void _onDataReceived(Uint8List data) {
    if (!_isMeasuring) return;
    
    // Добавляем в буфер
    _buffer += String.fromCharCodes(data);
    
    // Ищем полные строки (разделитель \n или \r\n)
    while (_buffer.contains('\n')) {
      final newlineIndex = _buffer.indexOf('\n');
      final line = _buffer.substring(0, newlineIndex).trim();
      _buffer = _buffer.substring(newlineIndex + 1);
      
      if (line.isNotEmpty) {
        _parseLine(line);
      }
    }
  }
  
  /// Парсинг строки формата "173 cm"
  void _parseLine(String line) {
    try {
      // Формат: "173 cm" или "173.5 cm"
      final regex = RegExp(r'(\d+\.?\d*)\s*(?:cm|см)?', caseSensitive: false);
      final match = regex.firstMatch(line);
      
      if (match != null) {
        final distanceCm = double.parse(match.group(1)!);
        final distanceMm = (distanceCm * 10) - (_calibrationOffset * 10);
        
        _timestampMs = DateTime.now().millisecondsSinceEpoch - _startTimeMs;
        
        final packet = SensorPacket(
          timestampMs: _timestampMs,
          distanceMm: distanceMm,
        );
        
        _sensorDataController.add(packet);
      }
    } catch (e) {
      print('[USB HAL] Parse error for line "$line": $e');
    }
  }
}
