import 'package:flutter/material.dart';
import '../../../data/hal/port_scanner.dart';
import '../../../data/hal/port_connection_manager.dart';

/// Страница выбора COM-порта с диагностикой
class PortSelectionPage extends StatefulWidget {
  /// Callback при успешном выборе порта
  final void Function(String portName)? onPortSelected;
  
  const PortSelectionPage({super.key, this.onPortSelected});
  
  @override
  State<PortSelectionPage> createState() => _PortSelectionPageState();
}

class _PortSelectionPageState extends State<PortSelectionPage> {
  final PortScanner _scanner = PortScanner();
  List<PortInfo> _ports = [];
  bool _isScanning = false;
  bool _isConnecting = false;
  String? _selectedPort;
  String _log = '';
  
  @override
  void initState() {
    super.initState();
    _scanPorts();
  }
  
  void _addLog(String message) {
    setState(() {
      _log = '$_log\n$message';
    });
  }
  
  Future<void> _scanPorts() async {
    setState(() {
      _isScanning = true;
      _selectedPort = null; // Сбрасываем выбор
      _log = 'Сканирование портов...\n';
    });
    
    final ports = await _scanner.scanPorts(
      testAvailability: true,
      onProgress: _addLog,
    );
    
    setState(() {
      _ports = ports;
      _isScanning = false;
    });
    
    _addLog('\nНайдено ${ports.length} портов');
    
    // Автоматически выбираем ТОЛЬКО если это наш датчик (FTDI)
    final best = _scanner.findBestSensorPort(ports);
    if (best != null && best.isLikelyOurSensor) {
      setState(() => _selectedPort = best.name);
      _addLog('✓ Датчик найден: ${best.name}');
    } else {
      _addLog('⚠ Датчик НЕ найден! Подключите USB-датчик.');
    }
  }
  
  Future<void> _connectToPort(PortInfo port) async {
    setState(() {
      _isConnecting = true;
      _log = '$_log\n\n--- Подключение к ${port.name} ---\n';
    });
    
    final manager = PortConnectionManager(
      onLog: _addLog,
      maxRetries: 2,
      retryDelayMs: 300,
    );
    
    final result = await manager.connect(port.name);
    
    if (result.success) {
      _addLog('\n✅ УСПЕШНО подключено!');
      _addLog('Метод: ${result.methodUsed}');
      
      // Закрываем тестовое подключение
      manager.closePort(result.port);
      
      // Вызываем callback
      widget.onPortSelected?.call(port.name);
      
      // Показываем сообщение об успехе
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Порт ${port.name} готов к работе'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else {
      _addLog('\n❌ ОШИБКА подключения');
      _addLog(result.errorMessage ?? 'Неизвестная ошибка');
      
      // Показываем диалог с ошибкой
      if (mounted) {
        _showErrorDialog(result.errorMessage ?? 'Не удалось подключиться');
      }
    }
    
    setState(() => _isConnecting = false);
  }
  
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red),
            SizedBox(width: 8),
            Text('Ошибка подключения'),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Выбор COM-порта'),
        actions: [
          IconButton(
            icon: _isScanning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: _isScanning ? null : _scanPorts,
            tooltip: 'Обновить список',
          ),
        ],
      ),
      body: Column(
        children: [
          // Список портов
          Expanded(
            flex: 2,
            child: _buildPortList(),
          ),
          
          // Лог
          Expanded(
            flex: 1,
            child: _buildLogPanel(),
          ),
        ],
      ),
    );
  }
  
  /// Проверяет, есть ли среди портов наш датчик (FTDI)
  bool get _hasSensorPort => _ports.any((p) => p.isLikelyOurSensor);
  
  Widget _buildPortList() {
    if (_isScanning && _ports.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Сканирование портов...'),
          ],
        ),
      );
    }
    
    if (_ports.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.usb_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'COM-порты не найдены',
              style: TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 8),
            const Text(
              'Подключите датчик и нажмите "Обновить"',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _scanPorts,
              icon: const Icon(Icons.refresh),
              label: const Text('Обновить'),
            ),
          ],
        ),
      );
    }
    
    return Column(
      children: [
        // Предупреждение если датчик не найден
        if (!_hasSensorPort)
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withOpacity(0.5)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber, color: Colors.orange, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Датчик не обнаружен!',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.orange,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Подключите USB-датчик и нажмите "Обновить" (↻)',
                        style: TextStyle(color: Colors.grey[400], fontSize: 13),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _scanPorts,
                  icon: const Icon(Icons.refresh, color: Colors.orange),
                  tooltip: 'Обновить список портов',
                ),
              ],
            ),
          ),
        
        // Список портов
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _ports.length,
            itemBuilder: (ctx, index) => _buildPortCard(_ports[index]),
          ),
        ),
      ],
    );
  }
  
  Widget _buildPortCard(PortInfo port) {
    final isSelected = port.name == _selectedPort;
    final isOurSensor = port.isLikelyOurSensor;
    
    return Card(
      color: isSelected
          ? const Color(0xFF2E4A2E)
          : const Color(0xFF1E1E1E),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isOurSensor
              ? Colors.green.withOpacity(0.5)
              : Colors.transparent,
          width: 2,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _selectedPort = port.name),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Иконка типа порта
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _getTypeColor(port.type).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _getTypeIcon(port.type),
                  color: _getTypeColor(port.type),
                ),
              ),
              const SizedBox(width: 16),
              
              // Информация о порте
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          port.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (isOurSensor) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'ДАТЧИК',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      // Показываем описание только если оно не пустое, иначе тип порта
                      (port.description != null && port.description!.isNotEmpty)
                          ? port.description!
                          : port.typeDescription,
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _buildStatusBadge(port),
                        const SizedBox(width: 8),
                        Text(
                          port.typeDescription,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              // Кнопка подключения
              if (isSelected)
                ElevatedButton(
                  onPressed: _isConnecting
                      ? null
                      : () => _connectToPort(port),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                  child: _isConnecting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Подключить'),
                ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildStatusBadge(PortInfo port) {
    Color color;
    String text;
    
    switch (port.availability) {
      case PortAvailability.available:
        color = Colors.green;
        text = 'Доступен';
        break;
      case PortAvailability.accessDenied:
        color = Colors.orange;
        text = 'Запрещён';
        break;
      case PortAvailability.busy:
        color = Colors.red;
        text = 'Занят';
        break;
      case PortAvailability.error:
        color = Colors.red;
        text = 'Ошибка';
        break;
      case PortAvailability.untested:
        color = Colors.grey;
        text = '???';
        break;
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
  
  IconData _getTypeIcon(PortType type) {
    switch (type) {
      case PortType.ftdi:
        return Icons.sensors;
      case PortType.arduino:
        return Icons.developer_board;
      case PortType.bluetooth:
        return Icons.bluetooth;
      case PortType.builtin:
        return Icons.computer;
      case PortType.virtual:
        return Icons.cloud;
      case PortType.unknown:
        return Icons.usb;
    }
  }
  
  Color _getTypeColor(PortType type) {
    switch (type) {
      case PortType.ftdi:
        return Colors.green;
      case PortType.arduino:
        return Colors.blue;
      case PortType.bluetooth:
        return Colors.indigo;
      case PortType.builtin:
        return Colors.grey;
      case PortType.virtual:
        return Colors.purple;
      case PortType.unknown:
        return Colors.orange;
    }
  }
  
  Widget _buildLogPanel() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D0D),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Лог диагностики',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: () => setState(() => _log = ''),
                tooltip: 'Очистить лог',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              reverse: true,
              child: Text(
                _log,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: Colors.white70,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
