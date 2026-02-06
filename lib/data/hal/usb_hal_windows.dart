import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import '../../domain/entities/sensor_data.dart';
import '../../domain/repositories/hal_interface.dart';
import '../../domain/math/signal_processor.dart';
import 'port_scanner.dart';
import 'port_connection_manager.dart';

/// USB HAL для датчика расстояния V802 (HC-SR04 + FT232RL)
/// Использует flutter_libserialport для Windows/Linux/macOS
/// 
/// Формат данных: "173 cm\n" (число + пробел + "cm" + перевод строки)
/// Скорость порта: 9600 бод
class UsbHALWindows implements HALInterface {
  static const int _baudRate = 9600;  // Проверено: датчик работает на 9600
  
  final _connectionStatusController = StreamController<ConnectionStatus>.broadcast();
  final _sensorDataController = StreamController<SensorPacket>.broadcast();
  
  /// Процессор сигнала для фильтрации шума
  final _signalProcessor = SignalProcessor(sensorType: SensorType.distance);
  
  /// Сканер портов
  final _portScanner = PortScanner();
  
  /// Менеджер подключений
  final _connectionManager = PortConnectionManager();
  
  /// Выбранный порт вручную (null = автовыбор)
  String? selectedPort;
  
  SerialPort? _port;
  SerialPortReader? _reader;
  StreamSubscription? _subscription;
  String _buffer = '';
  int _timestampMs = 0;
  int _startTimeMs = 0;
  bool _isMeasuring = false;
  double _calibrationOffset = 0.0;
  double _lastRawValue = 0.0;  // Для калибровки нуля
  Timer? _readTimer;
  Timer? _healthCheckTimer;
  String? _connectedPortName;  // Запоминаем порт к которому подключились
  bool _isConnected = false;
  
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
  
  /// Найти порт FT232RL (V802) - НОВАЯ версия через PortScanner
  Future<String?> findV802PortAsync() async {
    print('USB HAL: Поиск датчика через PortScanner...');
    
    // Если порт выбран вручную - используем его
    if (selectedPort != null) {
      print('USB HAL: Используем вручную выбранный порт: $selectedPort');
      return selectedPort;
    }
    
    // Сканируем порты с проверкой доступности
    final ports = await _portScanner.scanPorts(
      testAvailability: true,
      onProgress: (msg) => print('USB HAL: $msg'),
    );
    
    // Ищем лучший порт для датчика
    final best = _portScanner.findBestSensorPort(ports);
    
    if (best != null) {
      print('USB HAL: НАЙДЕН датчик на ${best.name} (${best.typeDescription})');
      return best.name;
    }
    
    print('USB HAL: Датчик FT232R не найден');
    return null;
  }
  
  /// Найти порт FT232RL (V802) - синхронная версия для совместимости
  static String? findV802Port() {
    final ports = SerialPort.availablePorts;
    
    print('USB HAL: Поиск датчика среди ${ports.length} портов...');
    
    for (final portName in ports) {
      try {
        final port = SerialPort(portName);
        final description = port.description ?? '';
        final manufacturer = port.manufacturer ?? '';
        
        print('USB HAL: Проверка $portName: "$description" ($manufacturer)');
        
        // Ищем FT232R, FTDI или USB Serial (это наш датчик!)
        if (description.toLowerCase().contains('ft232') ||
            description.toLowerCase().contains('ftdi') ||
            description.toLowerCase().contains('usb serial') ||
            description.toLowerCase().contains('usb-serial') ||
            manufacturer.toLowerCase().contains('ftdi')) {
          port.dispose();
          print('USB HAL: НАЙДЕН датчик на $portName');
          return portName;
        }
        port.dispose();
      } catch (e) {
        print('USB HAL: Ошибка проверки $portName: $e');
        continue;
      }
    }
    
    // НЕ возвращаем первый попавшийся порт - только реальный датчик!
    print('USB HAL: Датчик FT232R не найден');
    return null;
  }
  
  @override
  Future<bool> connect() async {
    _connectionStatusController.add(ConnectionStatus.connecting);
    
    try {
      // НОВЫЙ ПОДХОД: Используем асинхронный поиск через PortScanner
      final portName = await findV802PortAsync();
      
      if (portName == null) {
        print('USB HAL: Датчик FTDI не найден');
        _connectionStatusController.add(ConnectionStatus.error);
        return false;
      }
      
      print('USB HAL: Подключение к $portName через PortConnectionManager');
      
      // НОВЫЙ ПОДХОД: Используем PortConnectionManager для надёжного подключения
      final result = await _connectionManager.connect(
        portName,
        config: PortConfig.sensorDefault,
      );
      
      if (!result.success) {
        print('USB HAL: Подключение неудачно: ${result.errorMessage}');
        _connectionStatusController.add(ConnectionStatus.error);
        return false;
      }
      
      // Используем успешно открытый порт
      _port = result.port;
      print('USB HAL: Порт открыт методом: ${result.methodUsed}');
      
      _deviceInfo = DeviceInfo(
        name: 'Датчик расстояния ($portName)',
        firmwareVersion: 'FT232R',
        batteryPercent: 100,
        enabledSensors: ['distance'],
        connectionType: ConnectionType.usb,
      );
      
      // Небольшая пауза перед началом чтения
      await Future.delayed(const Duration(milliseconds: 300));
      
      // Запоминаем порт
      _connectedPortName = portName;
      _isConnected = true;
      
      // Начать чтение данных
      _startReading();
      
      // Запускаем проверку здоровья соединения
      _startHealthCheck();
      
      _connectionStatusController.add(ConnectionStatus.connected);
      print('USB HAL: Подключено к $portName');
      return true;
      
    } catch (e, stack) {
      print('USB HAL: Ошибка подключения: $e');
      print('Stack: $stack');
      _connectionStatusController.add(ConnectionStatus.error);
      _port?.dispose();
      _port = null;
      return false;
    }
  }
  
  void _startReading() {
    if (_port == null || !_port!.isOpen) {
      print('USB HAL: Порт не открыт для чтения');
      return;
    }
    
    try {
      _reader = SerialPortReader(_port!, timeout: 1000);
      
      _subscription = _reader!.stream.listen(
        (data) {
          _processIncomingData(data);
        },
        onError: (error) {
          print('USB HAL: Ошибка чтения: $error');
          _handleDisconnect();
        },
        onDone: () {
          print('USB HAL: Поток закрыт');
          _handleDisconnect();
        },
        cancelOnError: false,
      );
      
      print('USB HAL: Чтение запущено');
    } catch (e) {
      print('USB HAL: Ошибка запуска чтения: $e');
      _connectionStatusController.add(ConnectionStatus.error);
    }
  }
  
  /// Периодическая проверка подключения
  void _startHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _checkConnection();
    });
  }
  
  /// Проверяет что порт всё ещё доступен
  void _checkConnection() {
    if (!_isConnected || _connectedPortName == null) return;
    
    // Проверяем что порт всё ещё в списке доступных
    final availablePorts = SerialPort.availablePorts;
    if (!availablePorts.contains(_connectedPortName)) {
      print('USB HAL: Порт $_connectedPortName больше не доступен!');
      _handleDisconnect();
      return;
    }
    
    // Проверяем что порт открыт
    if (_port == null || !_port!.isOpen) {
      print('USB HAL: Порт закрыт!');
      _handleDisconnect();
    }
  }
  
  /// Обработка отключения датчика
  void _handleDisconnect() {
    if (!_isConnected) return;  // Уже отключены
    
    print('USB HAL: Датчик отключён');
    _isConnected = false;
    
    // Останавливаем проверку
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;
    
    // Закрываем ресурсы
    try { _subscription?.cancel(); } catch (_) {}
    try { _reader?.close(); } catch (_) {}
    try { _port?.close(); } catch (_) {}
    try { _port?.dispose(); } catch (_) {}
    
    _subscription = null;
    _reader = null;
    _port = null;
    _connectedPortName = null;
    
    // Уведомляем UI
    _connectionStatusController.add(ConnectionStatus.disconnected);
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
        var rawValue = double.tryParse(valueStr);
        
        if (rawValue != null) {
          // Конвертируем cm в mm если нужно
          if (line.toLowerCase().contains('cm') || line.toLowerCase().contains('см')) {
            rawValue *= 10; // cm -> mm
          }
          
          // ВАЖНО: Сохраняем сырое значение ВСЕГДА (для функции "Ноль")
          // Это позволяет калибровать даже когда измерение остановлено
          _lastRawValue = rawValue;
          
          // НЕ отправляем данные в UI пока измерение не начато
          if (!_isMeasuring) {
            return;
          }
          
          // Применяем калибровку (смещение нуля)
          final calibratedValue = rawValue + _calibrationOffset;
          
          // 🔥 ФИЛЬТРАЦИЯ: Медианный фильтр + Калман
          // Убирает шум и выбросы, делает график плавным
          final filteredValue = _signalProcessor.process(calibratedValue);
          
          // Вычисляем timestamp от момента старта измерений
          _timestampMs = DateTime.now().millisecondsSinceEpoch - _startTimeMs;
          
          // Создаём пакет данных с ОТФИЛЬТРОВАННЫМ значением
          final packet = SensorPacket(
            timestampMs: _timestampMs,
            distanceMm: filteredValue,
          );
          
          _sensorDataController.add(packet);
          
          print('USB HAL: t=${_timestampMs}ms, raw=${calibratedValue.toStringAsFixed(1)}, filtered=${filteredValue.toStringAsFixed(1)} мм');
        }
      }
    }
  }
  
  @override
  Future<void> disconnect() async {
    _isConnected = false;
    _connectedPortName = null;
    
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;
    
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
    // Очищаем буфер от старых данных
    _buffer = '';
    // Сбрасываем время - отсчёт с нуля
    _startTimeMs = DateTime.now().millisecondsSinceEpoch;
    _timestampMs = 0;
    // Сбрасываем фильтры для нового измерения
    _signalProcessor.reset();
    _isMeasuring = true;
    print('USB HAL: Измерение начато, время и фильтры сброшены');
  }
  
  @override
  Future<void> stopMeasurement() async {
    _isMeasuring = false;
    print('USB HAL: Измерение остановлено');
  }
  
  @override
  Future<void> calibrate(String sensorId) async {
    // Toggle: если калибровка активна - сбрасываем, иначе устанавливаем
    if (_calibrationOffset != 0.0) {
      // Сбрасываем калибровку
      _calibrationOffset = 0.0;
      _signalProcessor.reset();  // Сбрасываем фильтр для быстрой реакции
      print('USB HAL: Калибровка СБРОШЕНА. Показываем абсолютные значения.');
    } else {
      // Устанавливаем ноль
      if (_lastRawValue > 0) {
        _calibrationOffset = -_lastRawValue;
        _signalProcessor.reset();  // Сбрасываем фильтр для быстрой реакции
        print('USB HAL: Калибровка нуля. Offset = ${_calibrationOffset.toStringAsFixed(1)} мм');
        print('USB HAL: Текущее значение ${_lastRawValue.toStringAsFixed(1)} мм теперь = 0');
      } else {
        print('USB HAL: Нет данных для калибровки. Подождите измерения.');
      }
    }
  }
  
  /// Проверить активна ли калибровка
  @override
  bool get isCalibrated => _calibrationOffset != 0.0;
  
  /// Сбросить калибровку (вернуть абсолютные значения)
  Future<void> resetCalibration() async {
    _calibrationOffset = 0.0;
    print('USB HAL: Калибровка сброшена');
  }
  
  @override
  Future<void> setSampleRate(int hz) async {
    // USB датчик передаёт данные с фиксированной частотой
    // Игнорируем настройку (данные приходят как есть)
  }
  
  Future<void> setCalibrationOffset(double offset) async {
    _calibrationOffset = offset;
  }
  
  Future<void> sendCommand(String command) async {
    if (_port == null || !_port!.isOpen) return;
    
    try {
      _port!.write(Uint8List.fromList('$command\n'.codeUnits));
    } catch (e) {
      print('USB HAL: Ошибка отправки команды: $e');
    }
  }
  
  @override
  Future<void> dispose() async {
    await disconnect();
    await _connectionStatusController.close();
    await _sensorDataController.close();
  }
}
