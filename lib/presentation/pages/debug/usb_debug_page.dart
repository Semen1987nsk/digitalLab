import 'package:flutter/material.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'dart:typed_data';
import 'dart:async';

/// Страница отладки USB для тестирования подключения к датчику
class UsbDebugPage extends StatefulWidget {
  const UsbDebugPage({super.key});

  @override
  State<UsbDebugPage> createState() => _UsbDebugPageState();
}

class _UsbDebugPageState extends State<UsbDebugPage> {
  List<String> _ports = [];
  String? _selectedPort;
  SerialPort? _port;
  SerialPortReader? _reader;
  StreamSubscription? _subscription;
  
  bool _isConnected = false;
  final List<String> _logs = [];
  final List<String> _data = [];
  String _buffer = '';
  
  // Защита от краша при горячем подключении
  bool _isScanning = false;
  Timer? _scanTimer;
  
  @override
  void initState() {
    super.initState();
    _scanPorts();
    // Периодическое сканирование портов
    _scanTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_isConnected && !_isScanning) {
        _scanPortsSilent();
      }
    });
  }
  
  @override
  void dispose() {
    _scanTimer?.cancel();
    _disconnect();
    super.dispose();
  }
  
  void _log(String message) {
    if (!mounted) return;
    setState(() {
      _logs.insert(0, '[${DateTime.now().toString().substring(11, 19)}] $message');
      if (_logs.length > 100) _logs.removeLast();
    });
  }
  
  void _scanPortsSilent() {
    if (_isScanning) return;
    _isScanning = true;
    
    try {
      final ports = SerialPort.availablePorts;
      if (mounted && ports.length != _ports.length) {
        setState(() {
          _ports = ports;
          if (ports.isNotEmpty && _selectedPort == null) {
            _selectedPort = ports.first;
          }
        });
        _log('Порты обновлены: ${ports.length}');
      }
    } catch (e) {
      // Игнорируем ошибки при фоновом сканировании
    } finally {
      _isScanning = false;
    }
  }
  
  void _scanPorts() {
    if (_isScanning) return;
    _isScanning = true;
    _log('Сканирование портов...');
    
    try {
      final ports = SerialPort.availablePorts;
      _log('Найдено портов: ${ports.length}');
      
      for (final portName in ports) {
        try {
          final port = SerialPort(portName);
          final desc = port.description ?? 'Нет описания';
          final mfr = port.manufacturer ?? 'Неизвестно';
          _log('  $portName: $desc ($mfr)');
          port.dispose();
        } catch (e) {
          _log('  $portName: Ошибка - $e');
        }
      }
      
      if (mounted) {
        setState(() {
          _ports = ports;
          if (ports.isNotEmpty && _selectedPort == null) {
            _selectedPort = ports.first;
          }
        });
      }
    } catch (e) {
      _log('Ошибка сканирования: $e');
    } finally {
      _isScanning = false;
    }
  }
  
  Future<void> _connect() async {
    if (_selectedPort == null) {
      _log('Порт не выбран');
      return;
    }
    
    _log('Подключение к $_selectedPort...');
    
    try {
      // Создаём объект порта
      _log('Создание SerialPort объекта...');
      _port = SerialPort(_selectedPort!);
      
      // Проверяем, существует ли порт
      if (_port == null) {
        _log('Не удалось создать объект порта');
        return;
      }
      
      // Пробуем несколько методов открытия порта
      bool opened = false;
      
      // Метод 1: Только чтение (наименее агрессивный)
      _log('Попытка 1: openRead()...');
      opened = _port!.openRead();
      
      if (!opened) {
        final error1 = SerialPort.lastError;
        _log('openRead() неудача: $error1');
        
        // Метод 2: Чтение и запись
        _log('Попытка 2: openReadWrite()...');
        _port?.dispose();
        _port = SerialPort(_selectedPort!);
        opened = _port!.openReadWrite();
        
        if (!opened) {
          final error2 = SerialPort.lastError;
          _log('openReadWrite() неудача: $error2');
          
          // Метод 3: Эксклюзивный режим
          _log('Попытка 3: open(mode: 3)...');
          _port?.dispose();
          _port = SerialPort(_selectedPort!);
          opened = _port!.open(mode: SerialPortMode.readWrite);
          
          if (!opened) {
            final error3 = SerialPort.lastError;
            _log('Все попытки неудачны!');
            _log('errno=5 = Доступ запрещён');
            _log('Решения:');
            _log('1) Запустить от Администратора');
            _log('2) Закрыть другие программы (Arduino IDE и т.д.)');
            _log('3) Переподключить USB кабель');
            _port?.dispose();
            _port = null;
            return;
          }
        }
      }
      
      _log('Порт открыт успешно!');
      
      // Настройка конфигурации порта
      _log('Настройка параметров: 9600 8N1...');
      try {
        final config = SerialPortConfig();
        config.baudRate = 9600;
        config.bits = 8;
        config.stopBits = 1;
        config.parity = SerialPortParity.none;
        _port!.config = config;
        _log('Конфигурация применена');
      } catch (e) {
        _log('Ошибка настройки (продолжаем): $e');
      }
      
      setState(() => _isConnected = true);
      
      // Небольшая пауза перед началом чтения
      await Future.delayed(const Duration(milliseconds: 500));
      
      if (!mounted) return;
      
      // Начинаем чтение данных
      _log('Запуск чтения данных...');
      _startReading();
      
    } catch (e, stack) {
      _log('ОШИБКА ПОДКЛЮЧЕНИЯ: $e');
      _log('Stack: ${stack.toString().split('\n').take(3).join(' | ')}');
      _port?.dispose();
      _port = null;
    }
  }
  
  void _startReading() {
    if (_port == null || !_port!.isOpen) {
      _log('Порт не открыт для чтения');
      return;
    }
    
    try {
      _reader = SerialPortReader(_port!, timeout: 1000);
      
      _subscription = _reader!.stream.listen(
        (data) {
          if (mounted) {
            _processData(data);
          }
        },
        onError: (e) {
          _log('Ошибка чтения: $e');
        },
        onDone: () {
          _log('Поток данных закрыт');
        },
        cancelOnError: false,
      );
      
      _log('Чтение запущено, ожидание данных...');
      
    } catch (e, stack) {
      _log('ОШИБКА ЗАПУСКА ЧТЕНИЯ: $e');
      _log('Stack: ${stack.toString().split('\n').take(3).join(' | ')}');
    }
  }
  
  void _processData(Uint8List data) {
    if (!mounted) return;
    
    _buffer += String.fromCharCodes(data);
    
    while (_buffer.contains('\n')) {
      final idx = _buffer.indexOf('\n');
      final line = _buffer.substring(0, idx).trim();
      _buffer = _buffer.substring(idx + 1);
      
      if (line.isNotEmpty && mounted) {
        setState(() {
          _data.insert(0, line);
          if (_data.length > 50) _data.removeLast();
        });
      }
    }
  }
  
  void _disconnect() {
    _log('Отключение...');
    
    try {
      _subscription?.cancel();
      _subscription = null;
    } catch (e) {
      _log('Ошибка отмены подписки: $e');
    }
    
    try {
      _reader?.close();
      _reader = null;
    } catch (e) {
      _log('Ошибка закрытия reader: $e');
    }
    
    try {
      if (_port != null && _port!.isOpen) {
        _port!.close();
      }
    } catch (e) {
      _log('Ошибка закрытия порта: $e');
    }
    
    try {
      _port?.dispose();
      _port = null;
    } catch (e) {
      _log('Ошибка dispose порта: $e');
    }
    
    if (mounted) {
      setState(() => _isConnected = false);
    }
    _log('Отключено');
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('USB Отладка'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _scanPorts,
            tooltip: 'Обновить порты',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Панель управления
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: DropdownButton<String>(
                        value: _selectedPort,
                        hint: const Text('Выберите порт'),
                        isExpanded: true,
                        items: _ports.map((p) => DropdownMenuItem(
                          value: p,
                          child: Text(p),
                        )).toList(),
                        onChanged: _isConnected ? null : (v) {
                          setState(() => _selectedPort = v);
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: _isConnected ? _disconnect : _connect,
                      icon: Icon(_isConnected ? Icons.stop : Icons.play_arrow),
                      label: Text(_isConnected ? 'Отключить' : 'Подключить'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isConnected ? Colors.red : Colors.green,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Данные и логи
            Expanded(
              child: Row(
                children: [
                  // Данные с датчика
                  Expanded(
                    child: Card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            color: Colors.green.withOpacity(0.2),
                            child: const Text('📊 Данные с датчика', 
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          Expanded(
                            child: ListView.builder(
                              itemCount: _data.length,
                              itemBuilder: (ctx, i) => Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                                child: Text(_data[i],
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(width: 16),
                  
                  // Логи
                  Expanded(
                    child: Card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            color: Colors.blue.withOpacity(0.2),
                            child: const Text('📋 Логи', 
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          Expanded(
                            child: ListView.builder(
                              itemCount: _logs.length,
                              itemBuilder: (ctx, i) => Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 1),
                                child: Text(_logs[i],
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                    color: _logs[i].contains('Ошибка') 
                                      ? Colors.red 
                                      : null,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
