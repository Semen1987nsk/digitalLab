import 'dart:async';
import 'package:flutter_libserialport/flutter_libserialport.dart';

/// Результат попытки подключения
class ConnectionResult {
  final bool success;
  final SerialPort? port;
  final String? errorMessage;
  final String methodUsed;
  
  const ConnectionResult({
    required this.success,
    this.port,
    this.errorMessage,
    this.methodUsed = '',
  });
  
  factory ConnectionResult.success(SerialPort port, String method) => 
    ConnectionResult(success: true, port: port, methodUsed: method);
  
  factory ConnectionResult.failure(String error) => 
    ConnectionResult(success: false, errorMessage: error);
}

/// Конфигурация порта
class PortConfig {
  final int baudRate;
  final int dataBits;
  final int stopBits;
  final int parity;
  
  const PortConfig({
    this.baudRate = 9600,
    this.dataBits = 8,
    this.stopBits = 1,
    this.parity = 0,
  });
  
  /// Стандартная конфигурация для нашего датчика
  static const sensorDefault = PortConfig(
    baudRate: 9600,
    dataBits: 8,
    stopBits: 1,
    parity: 0,
  );
}

/// Менеджер подключения к COM-порту
/// Пробует разные методы открытия и конфигурации
class PortConnectionManager {
  /// Callback для логирования
  final void Function(String message)? onLog;
  
  /// Максимальное количество попыток
  final int maxRetries;
  
  /// Задержка между попытками (мс)
  final int retryDelayMs;
  
  PortConnectionManager({
    this.onLog,
    this.maxRetries = 3,
    this.retryDelayMs = 500,
  });
  
  void _log(String message) {
    onLog?.call(message);
    print('PortConnection: $message');
  }
  
  /// Подключается к порту с множественными попытками
  Future<ConnectionResult> connect(
    String portName, {
    PortConfig config = PortConfig.sensorDefault,
  }) async {
    _log('Подключение к $portName...');
    
    // Методы открытия порта в порядке приоритета
    final openMethods = <String, bool Function(SerialPort)>{
      'openRead': (p) => p.openRead(),
      'openReadWrite': (p) => p.openReadWrite(),
      'open(readWrite)': (p) => p.open(mode: SerialPortMode.readWrite),
    };
    
    String lastError = '';
    
    // Пробуем каждый метод
    for (final entry in openMethods.entries) {
      final methodName = entry.key;
      final openFunc = entry.value;
      
      // Несколько попыток для каждого метода
      for (int attempt = 1; attempt <= maxRetries; attempt++) {
        _log('  $methodName попытка $attempt/$maxRetries...');
        
        SerialPort? port;
        try {
          port = SerialPort(portName);
          
          final opened = openFunc(port);
          
          if (opened) {
            _log('  ✓ Порт открыт методом $methodName');
            
            // Применяем конфигурацию
            final configResult = await _applyConfig(port, config);
            if (!configResult) {
              _log('  ⚠ Конфигурация не применена, но продолжаем');
            }
            
            // Небольшая пауза для стабилизации
            await Future.delayed(const Duration(milliseconds: 200));
            
            return ConnectionResult.success(port, methodName);
          }
          
          // Анализируем ошибку
          final error = SerialPort.lastError;
          lastError = _formatError(error);
          _log('  ✗ $lastError');
          
          port.dispose();
          
        } catch (e) {
          lastError = e.toString();
          _log('  ✗ Исключение: $lastError');
          try { port?.dispose(); } catch (_) {}
        }
        
        // Пауза перед следующей попыткой
        if (attempt < maxRetries) {
          await Future.delayed(Duration(milliseconds: retryDelayMs));
        }
      }
    }
    
    // Все попытки неудачны
    _log('Все методы открытия неудачны');
    return ConnectionResult.failure(_getSolutionMessage(lastError));
  }
  
  /// Применяет конфигурацию к порту
  Future<bool> _applyConfig(SerialPort port, PortConfig config) async {
    try {
      final portConfig = SerialPortConfig();
      portConfig.baudRate = config.baudRate;
      portConfig.bits = config.dataBits;
      portConfig.stopBits = config.stopBits;
      portConfig.parity = config.parity;
      port.config = portConfig;
      _log('  Конфигурация: ${config.baudRate} ${config.dataBits}N${config.stopBits}');
      return true;
    } catch (e) {
      _log('  Ошибка конфигурации: $e');
      return false;
    }
  }
  
  /// Форматирует ошибку SerialPort
  String _formatError(SerialPortError? error) {
    if (error == null) return 'Неизвестная ошибка';
    
    final errno = error.errorCode;
    final message = error.message;
    
    // Известные коды ошибок
    switch (errno) {
      case 2:
        return 'Порт не найден (errno=2)';
      case 5:
        return 'Доступ запрещён (errno=5)';
      case 13:
        return 'Нет прав доступа (errno=13)';
      case 16:
        return 'Порт занят (errno=16)';
      default:
        return '$message (errno=$errno)';
    }
  }
  
  /// Возвращает рекомендации по решению проблемы
  String _getSolutionMessage(String lastError) {
    if (lastError.contains('errno=5') || lastError.contains('Доступ')) {
      return '''Доступ запрещён (errno=5)

Решения:
1. Запустите программу от Администратора
2. Закройте другие программы (Arduino IDE, PuTTY)
3. Переподключите USB-кабель датчика
4. Перезагрузите компьютер''';
    }
    
    if (lastError.contains('errno=2') || lastError.contains('не найден')) {
      return '''Порт не найден

Решения:
1. Проверьте подключение USB-кабеля
2. Установите драйвер FTDI
3. Проверьте Диспетчер устройств''';
    }
    
    if (lastError.contains('errno=16') || lastError.contains('занят')) {
      return '''Порт занят другой программой

Решения:
1. Закройте Arduino IDE, PuTTY, терминалы
2. Перезапустите программу''';
    }
    
    return 'Не удалось подключиться: $lastError';
  }
  
  /// Безопасно закрывает порт
  void closePort(SerialPort? port) {
    if (port == null) return;
    
    try {
      if (port.isOpen) {
        port.close();
        _log('Порт закрыт');
      }
    } catch (e) {
      _log('Ошибка закрытия: $e');
    }
    
    try {
      port.dispose();
    } catch (_) {}
  }
}
