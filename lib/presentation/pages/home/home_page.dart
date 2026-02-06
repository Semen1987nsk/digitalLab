import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../domain/entities/sensor_data.dart';
import '../../blocs/experiment/experiment_provider.dart';
import '../../themes/app_theme.dart';
import '../experiment/experiment_page.dart';
import '../debug/usb_debug_page.dart';
import '../port_selection/port_selection_page.dart';
import '../test_lab/test_scenarios_page.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Используем новый провайдер подключения
    final connectionState = ref.watch(sensorConnectionProvider);
    final experimentState = ref.watch(experimentControllerProvider);
    final halMode = ref.watch(halModeProvider);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Цифровая Лаборатория'),
        actions: [
          // Кнопка выбора порта
          IconButton(
            icon: const Icon(Icons.settings_ethernet),
            tooltip: 'Выбор COM-порта',
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => PortSelectionPage(
                  onPortSelected: (portName) {
                    ref.read(selectedPortProvider.notifier).state = portName;
                    Navigator.pop(context);
                    // Переподключаемся к выбранному порту
                    ref.read(sensorConnectionProvider.notifier).connect();
                  },
                ),
              ));
            },
          ),
          // Кнопка тестовой лаборатории
          IconButton(
            icon: const Icon(Icons.science),
            tooltip: '🧪 Тестовая лаборатория',
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => const TestScenariosPage(),
              ));
            },
          ),
          // Кнопка отладки USB
          IconButton(
            icon: const Icon(Icons.bug_report),
            tooltip: 'USB Отладка',
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => const UsbDebugPage(),
              ));
            },
          ),
          // Переключатель режима HAL
          PopupMenuButton<HalMode>(
            icon: Icon(_getHalModeIcon(halMode)),
            tooltip: 'Режим подключения',
            onSelected: (mode) {
              ref.read(halModeProvider.notifier).state = mode;
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: HalMode.mock,
                child: Row(
                  children: [
                    Icon(Icons.developer_mode, 
                      color: halMode == HalMode.mock ? AppColors.primary : null),
                    const SizedBox(width: 12),
                    const Text('Симуляция'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: HalMode.usb,
                child: Row(
                  children: [
                    Icon(Icons.usb, 
                      color: halMode == HalMode.usb ? AppColors.primary : null),
                    const SizedBox(width: 12),
                    const Text('USB (V802)'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: HalMode.ble,
                child: Row(
                  children: [
                    Icon(Icons.bluetooth, 
                      color: halMode == HalMode.ble ? AppColors.primary : null),
                    const SizedBox(width: 12),
                    const Text('Bluetooth'),
                  ],
                ),
              ),
            ],
          ),
          // Индикатор статуса подключения
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _ConnectionIndicator(status: connectionState.status),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Заголовок
            Text(
              'Физика',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Выберите тип эксперимента',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 32),
            
            // Сетка экспериментов
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 1.5,
                children: [
                  _ExperimentCard(
                    title: 'Расстояние',
                    subtitle: 'Датчик расстояния',
                    icon: Icons.straighten,
                    color: AppColors.distance,
                    onTap: () => _openExperiment(context, 'distance'),
                  ),
                  _ExperimentCard(
                    title: 'Температура',
                    subtitle: 'Термометр',
                    icon: Icons.thermostat,
                    color: AppColors.temperature,
                    onTap: () => _openExperiment(context, 'temperature'),
                  ),
                  _ExperimentCard(
                    title: 'Напряжение',
                    subtitle: 'Вольтметр',
                    icon: Icons.electrical_services,
                    color: AppColors.voltage,
                    onTap: () => _openExperiment(context, 'voltage'),
                  ),
                  _ExperimentCard(
                    title: 'Ускорение',
                    subtitle: 'Акселерометр',
                    icon: Icons.speed,
                    color: AppColors.acceleration,
                    onTap: () => _openExperiment(context, 'acceleration'),
                  ),
                ],
              ),
            ),
            
            // Кнопка подключения
            const SizedBox(height: 24),
            _buildConnectButton(context, ref, connectionState.status),
          ],
        ),
      ),
    );
  }
  
  Widget _buildConnectButton(BuildContext context, WidgetRef ref, ConnectionStatus status) {
    final connectionController = ref.read(sensorConnectionProvider.notifier);
    
    switch (status) {
      case ConnectionStatus.disconnected:
        return ElevatedButton.icon(
          onPressed: () => connectionController.connect(),
          icon: const Icon(Icons.usb),
          label: const Text('Подключить датчик'),
        );
      case ConnectionStatus.connecting:
        return ElevatedButton.icon(
          onPressed: null,
          icon: const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          label: const Text('Подключение...'),
        );
      case ConnectionStatus.connected:
        return ElevatedButton.icon(
          onPressed: () => connectionController.disconnect(),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.success,
          ),
          icon: const Icon(Icons.check_circle),
          label: const Text('Датчик подключён'),
        );
      case ConnectionStatus.error:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.error.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.usb_off, color: AppColors.error, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Датчик не обнаружен',
                    style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () => connectionController.connect(),
              icon: const Icon(Icons.refresh),
              label: const Text('Повторить поиск'),
            ),
          ],
        );
    }
  }
  
  void _openExperiment(BuildContext context, String sensorType) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ExperimentPage(sensorType: sensorType),
      ),
    );
  }
  
  IconData _getHalModeIcon(HalMode mode) {
    switch (mode) {
      case HalMode.usb:
        return Icons.usb;
      case HalMode.ble:
        return Icons.bluetooth;
      case HalMode.mock:
      default:
        return Icons.developer_mode;
    }
  }
}

class _ConnectionIndicator extends StatelessWidget {
  final ConnectionStatus status;
  
  const _ConnectionIndicator({required this.status});
  
  @override
  Widget build(BuildContext context) {
    Color color;
    IconData icon;
    
    switch (status) {
      case ConnectionStatus.disconnected:
        color = AppColors.disconnected;
        icon = Icons.bluetooth_disabled;
        break;
      case ConnectionStatus.connecting:
        color = AppColors.warning;
        icon = Icons.bluetooth_searching;
        break;
      case ConnectionStatus.connected:
        color = AppColors.success;
        icon = Icons.bluetooth_connected;
        break;
      case ConnectionStatus.error:
        color = AppColors.error;
        icon = Icons.error_outline;
        break;
    }
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Icon(icon, color: color, size: 24),
      ],
    );
  }
}

class _ExperimentCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  
  const _ExperimentCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });
  
  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withOpacity(0.2),
                color.withOpacity(0.05),
              ],
            ),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, size: 40, color: color),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: color,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
