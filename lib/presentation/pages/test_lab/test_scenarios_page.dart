import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/hal/mock_hal.dart';
import '../../blocs/experiment/experiment_provider.dart';

/// Сценарии для тестирования
enum TestScenario {
  normalConnection,      // Всё работает
  accessDenied,          // errno=5
  portBusy,              // Порт занят
  noPortsFound,          // Нет портов
  intermittentData,      // Прерывистые данные
  noisyData,             // Шумные данные
  disconnectMidSession,  // Отключение во время работы
  slowConnection,        // Медленное подключение
  wrongBaudRate,         // Неверная скорость (мусор)
}

extension TestScenarioExt on TestScenario {
  String get title {
    switch (this) {
      case TestScenario.normalConnection: return '✅ Нормальное подключение';
      case TestScenario.accessDenied: return '🔒 Доступ запрещён (errno=5)';
      case TestScenario.portBusy: return '⏳ Порт занят';
      case TestScenario.noPortsFound: return '❌ Порты не найдены';
      case TestScenario.intermittentData: return '📶 Прерывистые данные';
      case TestScenario.noisyData: return '📊 Шумные данные';
      case TestScenario.disconnectMidSession: return '🔌 Отключение во время работы';
      case TestScenario.slowConnection: return '🐌 Медленное подключение';
      case TestScenario.wrongBaudRate: return '🔢 Неверная скорость (мусор)';
    }
  }
  
  String get description {
    switch (this) {
      case TestScenario.normalConnection: 
        return 'Датчик подключается и передаёт стабильные данные';
      case TestScenario.accessDenied: 
        return 'Симуляция ошибки "Доступ запрещён" при открытии порта';
      case TestScenario.portBusy: 
        return 'Порт занят другой программой';
      case TestScenario.noPortsFound: 
        return 'В системе нет COM-портов';
      case TestScenario.intermittentData: 
        return 'Данные приходят с пропусками (плохой контакт)';
      case TestScenario.noisyData: 
        return 'Данные с большим шумом (помехи)';
      case TestScenario.disconnectMidSession: 
        return 'Датчик отключается через 5 секунд после старта';
      case TestScenario.slowConnection: 
        return 'Подключение занимает 5 секунд';
      case TestScenario.wrongBaudRate: 
        return 'Приходит мусор вместо нормальных данных';
    }
  }
  
  IconData get icon {
    switch (this) {
      case TestScenario.normalConnection: return Icons.check_circle;
      case TestScenario.accessDenied: return Icons.lock;
      case TestScenario.portBusy: return Icons.hourglass_top;
      case TestScenario.noPortsFound: return Icons.usb_off;
      case TestScenario.intermittentData: return Icons.signal_cellular_alt;
      case TestScenario.noisyData: return Icons.show_chart;
      case TestScenario.disconnectMidSession: return Icons.power_off;
      case TestScenario.slowConnection: return Icons.slow_motion_video;
      case TestScenario.wrongBaudRate: return Icons.error_outline;
    }
  }
  
  Color get color {
    switch (this) {
      case TestScenario.normalConnection: return Colors.green;
      case TestScenario.accessDenied: return Colors.red;
      case TestScenario.portBusy: return Colors.orange;
      case TestScenario.noPortsFound: return Colors.grey;
      case TestScenario.intermittentData: return Colors.amber;
      case TestScenario.noisyData: return Colors.purple;
      case TestScenario.disconnectMidSession: return Colors.red;
      case TestScenario.slowConnection: return Colors.blue;
      case TestScenario.wrongBaudRate: return Colors.brown;
    }
  }
}

/// Провайдер текущего тестового сценария
final testScenarioProvider = StateProvider<TestScenario>(
  (ref) => TestScenario.normalConnection,
);

/// Страница тестирования сценариев
class TestScenariosPage extends ConsumerStatefulWidget {
  const TestScenariosPage({super.key});

  @override
  ConsumerState<TestScenariosPage> createState() => _TestScenariosPageState();
}

class _TestScenariosPageState extends ConsumerState<TestScenariosPage> {
  String _log = '';
  bool _isRunning = false;
  
  void _addLog(String message) {
    setState(() {
      final time = DateTime.now().toString().substring(11, 19);
      _log = '$_log[$time] $message\n';
    });
  }
  
  Future<void> _runScenario(TestScenario scenario) async {
    setState(() {
      _isRunning = true;
      _log = '';
    });
    
    _addLog('Запуск сценария: ${scenario.title}');
    
    // Переключаемся на Mock режим
    ref.read(halModeProvider.notifier).state = HalMode.mock;
    ref.read(testScenarioProvider.notifier).state = scenario;
    
    _addLog('Режим: Mock HAL');
    _addLog('Сценарий установлен');
    
    // Получаем HAL и настраиваем его
    final hal = ref.read(halProvider);
    if (hal is MockHAL) {
      hal.setScenario(scenario);
      _addLog('MockHAL настроен');
    }
    
    // Пробуем подключиться
    _addLog('Попытка подключения...');
    
    try {
      final connected = await hal.connect();
      
      if (connected) {
        _addLog('✅ Подключение успешно!');
        
        // Слушаем данные 5 секунд
        _addLog('Ожидание данных (5 сек)...');
        
        int dataCount = 0;
        final subscription = hal.sensorData.listen((packet) {
          dataCount++;
          if (dataCount <= 5 || dataCount % 10 == 0) {
            _addLog('Данные: ${packet.distanceMm?.toStringAsFixed(1)} мм');
          }
        });
        
        await Future.delayed(const Duration(seconds: 5));
        await subscription.cancel();
        
        _addLog('Получено $dataCount пакетов данных');
        
        // Отключаемся
        await hal.disconnect();
        _addLog('Отключено');
        
      } else {
        _addLog('❌ Подключение не удалось');
        
        // Проверяем сообщение об ошибке
        if (hal is MockHAL) {
          _addLog('Причина: ${hal.lastErrorMessage}');
        }
      }
    } catch (e) {
      _addLog('❌ Исключение: $e');
    }
    
    _addLog('\n--- Сценарий завершён ---');
    
    setState(() => _isRunning = false);
  }
  
  @override
  Widget build(BuildContext context) {
    final currentScenario = ref.watch(testScenarioProvider);
    
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('🧪 Тестовая лаборатория'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => setState(() => _log = ''),
            tooltip: 'Очистить лог',
          ),
        ],
      ),
      body: Row(
        children: [
          // Список сценариев
          SizedBox(
            width: 350,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Выберите сценарий:',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: TestScenario.values.length,
                    itemBuilder: (ctx, index) {
                      final scenario = TestScenario.values[index];
                      final isSelected = scenario == currentScenario;
                      
                      return Card(
                        color: isSelected 
                          ? scenario.color.withOpacity(0.2)
                          : const Color(0xFF1E1E1E),
                        margin: const EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          onTap: () => ref.read(testScenarioProvider.notifier).state = scenario,
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Icon(scenario.icon, color: scenario.color, size: 28),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        scenario.title,
                                        style: TextStyle(
                                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        scenario.description,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey[500],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isSelected)
                                  const Icon(Icons.check, color: Colors.green),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                
                // Кнопка запуска
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: _isRunning ? null : () => _runScenario(currentScenario),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: currentScenario.color,
                      ),
                      icon: _isRunning
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.play_arrow),
                      label: Text(_isRunning ? 'Выполняется...' : 'Запустить тест'),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Разделитель
          const VerticalDivider(width: 1),
          
          // Лог
          Expanded(
            child: Container(
              color: const Color(0xFF0D0D0D),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    color: const Color(0xFF1A1A1A),
                    child: Row(
                      children: [
                        const Icon(Icons.terminal, size: 18),
                        const SizedBox(width: 8),
                        const Text(
                          'Лог выполнения',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        Text(
                          'Сценарий: ${currentScenario.title}',
                          style: TextStyle(color: currentScenario.color, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(
                        _log.isEmpty ? 'Выберите сценарий и нажмите "Запустить тест"' : _log,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: Colors.white70,
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
    );
  }
}
