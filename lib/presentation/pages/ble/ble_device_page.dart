import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/hal/ble_hal.dart';
import '../../blocs/ble/ble_scan_provider.dart';
import '../../blocs/experiment/experiment_provider.dart';
import '../../themes/app_theme.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/labosfera_app_bar.dart';

// ═══════════════════════════════════════════════════════════════
//  BLE Device Selection Page
//
//  Сканирует BLE-устройства, показывает список найденных,
//  позволяет выбрать мультидатчик "PhysicsLab" и подключиться.
//
//  Вдохновлено: nRF Connect, PASCO device picker
// ═══════════════════════════════════════════════════════════════

class BleDevicePage extends ConsumerStatefulWidget {
  const BleDevicePage({super.key});

  @override
  ConsumerState<BleDevicePage> createState() => _BleDevicePageState();
}

class _BleDevicePageState extends ConsumerState<BleDevicePage> {
  @override
  void initState() {
    super.initState();
    // Автоматически начинаем сканирование при открытии
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(bleScanProvider.notifier).startScan();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scanState = ref.watch(bleScanProvider);

    return Scaffold(
      appBar: LabosferaAppBar(
        title: 'Bluetooth устройства',
        subtitle: scanState.isScanning
            ? 'Идёт поиск поблизости...'
            : 'Беспроводное подключение мультидатчика',
        actions: [
          if (scanState.isScanning)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Повторить сканирование',
              onPressed: () => ref.read(bleScanProvider.notifier).startScan(),
            ),
        ],
      ),
      body: Column(
        children: [
          // ── Баннер состояния адаптера ─────────────────────
          if (!scanState.isBluetoothOn)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: AppColors.error.withValues(alpha: 0.15),
              child: const Row(
                children: [
                  Icon(Icons.bluetooth_disabled,
                      color: AppColors.error, size: 24),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Bluetooth выключен. Включите Bluetooth '
                      'в настройках системы.',
                      style: TextStyle(color: AppColors.error),
                    ),
                  ),
                ],
              ),
            ),

          // ── Баннер ошибки ─────────────────────────────────
          if (scanState.error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: AppColors.warning.withValues(alpha: 0.1),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber,
                      color: AppColors.warning, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      scanState.error!,
                      style: const TextStyle(
                          color: AppColors.warning, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),

          // ── Подсказка ─────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    scanState.isScanning ? 'Сканирование...' : 'Готово',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Найдено: ${scanState.devices.length}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),

          // ── Анимация сканирования ─────────────────────────
          if (scanState.isScanning)
            const LinearProgressIndicator(
              backgroundColor: AppColors.surfaceLight,
              color: AppColors.primary,
              minHeight: 2,
            ),

          // ── Список устройств ──────────────────────────────
          Expanded(
            child: scanState.devices.isEmpty
                ? _buildEmptyState(scanState)
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: scanState.devices.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final device = scanState.devices[index];
                      return _DeviceCard(
                        result: device,
                        onTap: () => _connectToDevice(device),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BleScanState scanState) {
    if (scanState.isScanning) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bluetooth_searching,
                size: 64, color: AppColors.primary.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            const Text(
              'Поиск устройств...',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
            ),
            const SizedBox(height: 8),
            const Text(
              'Убедитесь, что мультидатчик включён',
              style: TextStyle(color: AppColors.textHint, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return EmptyState(
      illustration: EmptyStateIllustration.sensorWaves,
      title: 'Устройства не найдены',
      message:
          'Убедитесь, что мультидатчик включён и находится в зоне действия '
          'Bluetooth. Если поиск не помогает, проверьте разрешения приложения.',
      action: ElevatedButton.icon(
        onPressed: () => ref.read(bleScanProvider.notifier).startScan(),
        icon: const Icon(Icons.refresh),
        label: const Text('Повторить поиск'),
      ),
    );
  }

  Future<void> _connectToDevice(BleDeviceResult result) async {
    // Останавливаем сканирование
    await ref.read(bleScanProvider.notifier).stopScan();

    // Сохраняем выбранное устройство
    ref.read(selectedBleDeviceProvider.notifier).state = result.device;

    // Переключаемся на BLE режим
    ref.read(halModeProvider.notifier).state = HalMode.ble;

    if (!mounted) return;
    Navigator.pop(context);

    // Подключаемся через провайдер подключения
    // (halProvider пересоздастся при смене halModeProvider)
    await Future.delayed(const Duration(milliseconds: 100));
    ref.read(sensorConnectionProvider.notifier).connect();
  }
}

// ═══════════════════════════════════════════════════════════════
//  Карточка BLE-устройства
// ═══════════════════════════════════════════════════════════════

class _DeviceCard extends StatelessWidget {
  final BleDeviceResult result;
  final VoidCallback onTap;

  const _DeviceCard({required this.result, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isPhysicsLab = result.name.contains(kBleDeviceName);
    final signalStrength = _rssiToStrength(result.rssi);

    return Material(
      color: isPhysicsLab
          ? AppColors.primary.withValues(alpha: 0.08)
          : AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isPhysicsLab
                  ? AppColors.primary.withValues(alpha: 0.3)
                  : AppColors.surfaceLight,
            ),
          ),
          child: Row(
            children: [
              // Иконка
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isPhysicsLab
                      ? AppColors.primary.withValues(alpha: 0.15)
                      : AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isPhysicsLab ? Icons.science : Icons.bluetooth,
                  color: isPhysicsLab
                      ? AppColors.primary
                      : AppColors.textSecondary,
                  size: 24,
                ),
              ),

              const SizedBox(width: 16),

              // Название и ID
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          result.name,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: isPhysicsLab
                                ? FontWeight.w600
                                : FontWeight.normal,
                            color: isPhysicsLab
                                ? AppColors.primary
                                : AppColors.textPrimary,
                          ),
                        ),
                        if (isPhysicsLab) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'ЛАБОСФЕРА',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: AppColors.accent,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      result.device.remoteId.str,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textHint,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),

              // Сила сигнала
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SignalBars(strength: signalStrength),
                  const SizedBox(height: 4),
                  Text(
                    '${result.rssi} dBm',
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textHint,
                    ),
                  ),
                ],
              ),

              const SizedBox(width: 8),

              // Стрелка
              Icon(
                Icons.chevron_right,
                color: isPhysicsLab ? AppColors.primary : AppColors.textHint,
              ),
            ],
          ),
        ),
      ),
    );
  }

  int _rssiToStrength(int rssi) {
    if (rssi >= -50) return 4;
    if (rssi >= -60) return 3;
    if (rssi >= -70) return 2;
    if (rssi >= -80) return 1;
    return 0;
  }
}

/// Виджет "палочки" силы сигнала (как Wi-Fi)
class _SignalBars extends StatelessWidget {
  final int strength; // 0..4

  const _SignalBars({required this.strength});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(4, (i) {
        final isActive = i < strength;
        return Container(
          width: 4,
          height: 6.0 + i * 4.0,
          margin: const EdgeInsets.only(right: 2),
          decoration: BoxDecoration(
            color: isActive
                ? _barColor(strength)
                : AppColors.textHint.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(1),
          ),
        );
      }),
    );
  }

  Color _barColor(int strength) {
    if (strength >= 3) return AppColors.accent;
    if (strength >= 2) return AppColors.warning;
    return AppColors.error;
  }
}
