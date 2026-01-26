import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../domain/entities/sensor_data.dart';
import '../../blocs/experiment/experiment_provider.dart';
import '../../themes/app_theme.dart';
import '../experiment/experiment_page.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionStatus = ref.watch(connectionStatusProvider);
    final experimentState = ref.watch(experimentControllerProvider);
    final halMode = ref.watch(halModeProvider);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Цифровая Лаборатория'),
        actions: [
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
            child: connectionStatus.when(
              data: (status) => _ConnectionIndicator(status: status),
              loading: () => const _ConnectionIndicator(status: ConnectionStatus.connecting),
              error: (_, __) => const _ConnectionIndicator(status: ConnectionStatus.error),
            ),
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
            connectionStatus.when(
              data: (status) => _buildConnectButton(context, ref, status),
              loading: () => _buildConnectButton(context, ref, ConnectionStatus.connecting),
              error: (_, __) => _buildConnectButton(context, ref, ConnectionStatus.error),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildConnectButton(BuildContext context, WidgetRef ref, ConnectionStatus status) {
    final controller = ref.read(experimentControllerProvider.notifier);
    
    switch (status) {
      case ConnectionStatus.disconnected:
        return ElevatedButton.icon(
          onPressed: () => controller.connect(),
          icon: const Icon(Icons.bluetooth),
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
          onPressed: null,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.success,
          ),
          icon: const Icon(Icons.check_circle),
          label: const Text('Датчик подключён'),
        );
      case ConnectionStatus.error:
        return ElevatedButton.icon(
          onPressed: () => controller.connect(),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.error,
          ),
          icon: const Icon(Icons.error),
          label: const Text('Ошибка. Повторить'),
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
