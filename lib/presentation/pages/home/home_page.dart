import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../domain/entities/sensor_data.dart';
import '../../../domain/entities/sensor_type.dart';
import '../../../domain/utils/sensor_utils.dart';
import '../../blocs/calibration/voltage_calibration_provider.dart';
import '../../blocs/experiment/experiment_provider.dart';
import '../../themes/app_theme.dart';
import '../../widgets/device_panel.dart';
import '../../widgets/labosfera_app_bar.dart';
import '../experiment/experiment_page.dart';
import '../oscilloscope/oscilloscope_page.dart';
import '../ble/ble_device_page.dart';
import '../debug/usb_debug_page.dart';
import '../port_selection/port_selection_page.dart';

enum _HomeMenuAction {
  useUsb,
  useBle,
  useMock,
  openUsbDebug,
}

// ═══════════════════════════════════════════════════════════════
//  ГЛАВНЫЙ ЭКРАН — Панель датчиков
//
//  Вдохновлено: Vernier Graphical Analysis, PASCO SPARKvue, Phyphox
//  Принципы:
//  • Все датчики видны сразу — живые значения обновляются в реальном времени
//  • Цветовое кодирование по типу датчика
//  • Бейджи версий (Базовая / 360) на заблокированных сенсорах
//  • Один тап → открывает эксперимент с графиком
//  • Крупные элементы (48dp+) для тач-экранов и проекторов
// ═══════════════════════════════════════════════════════════════

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // select() — слушаем только изменение статуса, а не каждое обновление
    // state object. Уменьшает количество rebuild на слабых ПК.
    final connectionState = ref.watch(sensorConnectionProvider);
    final version = ref.watch(productVersionProvider);
    final halMode = ref.watch(halModeProvider);
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _buildAppBar(context, ref, connectionState, halMode, version),
          const SliverToBoxAdapter(
            child: DevicePanel(),
          ),
          SliverToBoxAdapter(
            child: _HomeOverviewCard(
              connectionState: connectionState,
              halMode: halMode,
              version: version,
            ),
          ),
          SliverToBoxAdapter(
            child: _VersionHeader(version: version),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            sliver: _SensorGrid(version: version),
          ),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: _SectionHeader(
                title: 'Инструменты',
                subtitle: 'Дополнительные режимы для углублённой работы с сигналом.',
                accentColor: AppColors.warning,
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            sliver: SliverToBoxAdapter(
              child: _OscilloscopeCard(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const OscilloscopePage()),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(
    BuildContext context,
    WidgetRef ref,
    SensorConnectionState connectionState,
    HalMode halMode,
    ProductVersion version,
  ) {
    return LabosferaSliverAppBar(
      actions: [
        // Порт
        IconButton(
          icon: const Icon(Icons.settings_ethernet, size: 22),
          tooltip: 'Выбор COM-порта',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PortSelectionPage(
                onPortSelected: (portName) {
                  ref.read(selectedPortProvider.notifier).state = portName;
                  Navigator.pop(context);
                  ref.read(sensorConnectionProvider.notifier).connect();
                },
              ),
            ),
          ),
        ),
        if (!Platform.isWindows && !Platform.isLinux)
          IconButton(
            icon: const Icon(Icons.bluetooth_searching, size: 22),
            tooltip: 'Поиск Bluetooth устройств',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BleDevicePage()),
            ),
          ),
        PopupMenuButton<_HomeMenuAction>(
          icon: const Icon(Icons.more_horiz_rounded, size: 22),
          tooltip: 'Дополнительно',
          onSelected: (action) {
            switch (action) {
              case _HomeMenuAction.useUsb:
                ref.read(halModeProvider.notifier).state = HalMode.usb;
              case _HomeMenuAction.useBle:
                ref.read(halModeProvider.notifier).state = HalMode.ble;
              case _HomeMenuAction.useMock:
                ref.read(halModeProvider.notifier).state = HalMode.mock;
              case _HomeMenuAction.openUsbDebug:
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const UsbDebugPage()),
                );
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem<_HomeMenuAction>(
              enabled: false,
              child: Text(
                'Режим подключения',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary.withValues(alpha: 0.9),
                ),
              ),
            ),
            _homeMenuItem(
              action: _HomeMenuAction.useUsb,
              icon: Icons.usb,
              label: 'USB (COM)',
              selected: halMode == HalMode.usb,
            ),
            if (!Platform.isWindows && !Platform.isLinux)
              _homeMenuItem(
                action: _HomeMenuAction.useBle,
                icon: Icons.bluetooth,
                label: 'Bluetooth',
                selected: halMode == HalMode.ble,
              ),
            _homeMenuItem(
              action: _HomeMenuAction.useMock,
              icon: Icons.developer_mode,
              label: 'Симуляция',
              selected: halMode == HalMode.mock,
            ),
            const PopupMenuDivider(),
            _homeMenuItem(
              action: _HomeMenuAction.openUsbDebug,
              icon: Icons.bug_report_outlined,
              label: 'USB отладка',
              selected: false,
            ),
          ],
        ),
        _ConnectionDot(status: connectionState.status),
        const SizedBox(width: 12),
      ],
    );
  }

  PopupMenuItem<_HomeMenuAction> _homeMenuItem({
    required _HomeMenuAction action,
    required IconData icon,
    required String label,
    required bool selected,
  }) {
    return PopupMenuItem<_HomeMenuAction>(
      value: action,
      child: Row(
        children: [
          Icon(icon, color: selected ? AppColors.primary : null, size: 20),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  ЗАГОЛОВОК ВЕРСИИ
// ═══════════════════════════════════════════════════════════════

class _VersionHeader extends ConsumerWidget {
  final ProductVersion version;
  const _VersionHeader({required this.version});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            title: 'Датчики',
            subtitle: 'Выберите нужный датчик для запуска эксперимента или просмотра текущих значений.',
            accentColor: AppColors.primary,
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: SegmentedButton<ProductVersion>(
              segments: const [
                ButtonSegment(
                  value: ProductVersion.base,
                  label: Text('Базовая', style: TextStyle(fontSize: 13)),
                  icon: Icon(Icons.science_outlined, size: 18),
                ),
                ButtonSegment(
                  value: ProductVersion.pro360,
                  label: Text('360', style: TextStyle(fontSize: 13)),
                  icon: Icon(Icons.rocket_launch_outlined, size: 18),
                ),
              ],
              selected: {version},
              onSelectionChanged: (v) =>
                  ref.read(productVersionProvider.notifier).state = v.first,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeOverviewCard extends StatelessWidget {
  final SensorConnectionState connectionState;
  final HalMode halMode;
  final ProductVersion version;

  const _HomeOverviewCard({
    required this.connectionState,
    required this.halMode,
    required this.version,
  });

  @override
  Widget build(BuildContext context) {
    final (statusText, statusColor, guidance) = switch (connectionState.status) {
      ConnectionStatus.connected => (
          'Лаборатория готова',
          AppColors.success,
          'Данные поступают. Выберите датчик, чтобы открыть эксперимент или посмотреть живые значения.',
        ),
      ConnectionStatus.connecting => (
          'Подключение выполняется',
          AppColors.warning,
          'Подождите завершения подключения. После этого карточки датчиков начнут обновляться автоматически.',
        ),
      ConnectionStatus.error => (
          'Есть проблема с подключением',
          AppColors.error,
          'Проверьте кабель, питание датчика и выбранный режим подключения. Затем повторите попытку.',
        ),
      ConnectionStatus.disconnected => (
          'Подключите датчик или включите симуляцию',
          AppColors.primary,
          'Для начала работы выберите COM-порт сверху или переключитесь в режим симуляции через меню.',
        ),
    };

    final modeLabel = switch (halMode) {
      HalMode.usb => 'USB (COM)',
      HalMode.ble => 'Bluetooth',
      HalMode.mock => 'Симуляция',
    };

    final versionLabel = switch (version) {
      ProductVersion.base => 'Базовая версия',
      ProductVersion.pro360 => 'Версия 360',
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.hub_outlined, color: statusColor),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          statusText,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          guidance,
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.textSecondary,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _InfoPill(
                    icon: Icons.settings_input_component_outlined,
                    label: modeLabel,
                    color: AppColors.primary,
                  ),
                  _InfoPill(
                    icon: version == ProductVersion.base
                        ? Icons.science_outlined
                        : Icons.rocket_launch_outlined,
                    label: versionLabel,
                    color: version == ProductVersion.base
                        ? AppColors.primary
                        : AppColors.version360,
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

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color accentColor;

  const _SectionHeader({
    required this.title,
    required this.subtitle,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 3,
          height: 36,
          decoration: BoxDecoration(
            color: accentColor,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _InfoPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  СЕТКА ДАТЧИКОВ (Consumer — подписка на connection + live data)
//
//  Вынесена в отдельный ConsumerWidget чтобы rebuild при новом
//  SensorPacket не затрагивал AppBar и DevicePanel.
// ═══════════════════════════════════════════════════════════════

class _SensorGrid extends ConsumerWidget {
  final ProductVersion version;
  const _SensorGrid({required this.version});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionState = ref.watch(sensorConnectionProvider);
    final isDeviceConnected =
        connectionState.status == ConnectionStatus.connected;
    final enabledSensors =
        connectionState.deviceInfo?.enabledSensors ?? <String>[];

    // Live packet — only subscribe when device is connected.
    // Null when disconnected → no unnecessary rebuilds.
    SensorPacket? livePacket;
    if (isDeviceConnected) {
      ref.watch(sensorDataStreamProvider).whenData((p) => livePacket = p);
    }

    // Программная калибровка напряжения (Vernier/PASCO pattern):
    // Результат калибровки с CalibrationPage должен быть виден везде.
    final calState = ref.watch(voltageCalibrationProvider);

    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 280,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.2,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          const allSensors = SensorType.values;
          if (index >= allSensors.length) return null;
          final sensor = allSensors[index];
          final isAvailable = sensor.isAvailableIn(version);

          // Hardware presence: sensor.id must be in enabledSensors list
          final isHardwareConnected =
              isDeviceConnected && enabledSensors.contains(sensor.id);

          // Live value — с учётом программной калибровки для напряжения
          final rawValue = isHardwareConnected
              ? SensorUtils.getValue(livePacket, sensor)
              : null;
          final liveValue = rawValue != null &&
                  sensor == SensorType.voltage &&
                  calState.calibration.isModified
              ? calState.calibration.apply(rawValue)
              : rawValue;

          return RepaintBoundary(
            child: _SensorCard(
              sensor: sensor,
              isAvailable: isAvailable,
              isDeviceConnected: isDeviceConnected,
              isHardwareConnected: isHardwareConnected,
              liveValue: liveValue,
              onTap: isAvailable
                  ? () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              ExperimentPage(sensorType: sensor),
                        ),
                      )
                  : () => _showUpgradeDialog(context, sensor),
            ),
          );
        },
        childCount: SensorType.values.length,
      ),
    );
  }

  void _showUpgradeDialog(BuildContext context, SensorType sensor) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(sensor.icon, color: sensor.color),
            const SizedBox(width: 12),
            Text(sensor.title),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Датчик «${sensor.title}» доступен в версии 360.',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.version360Badge.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppColors.version360Badge.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.rocket_launch,
                      color: AppColors.version360, size: 20),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Версия 360 включает датчик силы, расстояния и люксметр',
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Понятно'),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  КАРТОЧКА ДАТЧИКА (Vernier / PASCO / Phyphox inspired)
//
//  • Градиентный фон + glow-border когда датчик подключён
//  • Анимированный бейдж «Подключён» / «Не подключён»
//  • Живое значение прямо на карточке (как в SPARKvue)
//  • Бейдж «360» для недоступных в базовой версии
// ═══════════════════════════════════════════════════════════════

class _SensorCard extends StatefulWidget {
  final SensorType sensor;
  final bool isAvailable;
  final bool isDeviceConnected;
  final bool isHardwareConnected;
  final double? liveValue;
  final VoidCallback onTap;

  const _SensorCard({
    required this.sensor,
    required this.isAvailable,
    required this.isDeviceConnected,
    required this.isHardwareConnected,
    required this.liveValue,
    required this.onTap,
  });

  @override
  State<_SensorCard> createState() => _SensorCardState();
}

class _SensorCardState extends State<_SensorCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final sensor = widget.sensor;
    final isAvailable = widget.isAvailable;
    final isDeviceConnected = widget.isDeviceConnected;
    final isHardwareConnected = widget.isHardwareConnected;
    final liveValue = widget.liveValue;
    final color = isAvailable ? sensor.color : AppColors.textHint;

    final border = isHardwareConnected
        ? sensor.color.withValues(alpha: 0.45)
        : isAvailable
            ? sensor.color.withValues(alpha: 0.15)
            : AppColors.cardBorder;
    final hoverBorder = isAvailable
        ? sensor.color.withValues(alpha: 0.75)
        : AppColors.cardBorder;

    return MouseRegion(
      cursor: isAvailable
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        transform: _hover
            ? (Matrix4.identity()..translateByDouble(0.0, -2.0, 0.0, 1.0))
            : Matrix4.identity(),
        child: Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: _hover ? hoverBorder : border,
          width: (isHardwareConnected || _hover) ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: widget.onTap,
        splashColor: color.withValues(alpha: 0.1),
        hoverColor: Colors.transparent,
        child: Stack(
          children: [
            // ── Градиент фона ──
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      color.withValues(
                          alpha: isHardwareConnected
                              ? 0.12
                              : isAvailable
                                  ? 0.06
                                  : 0.02),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // ── Glow-эффект при подключённом датчике ──
            if (isHardwareConnected)
              Positioned(
                top: -20,
                left: -20,
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: sensor.color.withValues(alpha: 0.15),
                        blurRadius: 40,
                        spreadRadius: 10,
                      ),
                    ],
                  ),
                ),
              ),

            // ── Контент ──
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Иконка + бейджи (верхняя строка)
                  Row(
                    children: [
                      // Иконка датчика
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: color.withValues(
                              alpha: isHardwareConnected ? 0.18 : 0.10),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(sensor.icon, color: color, size: 20),
                      ),
                      const Spacer(),
                      // Бейдж 360 или бейдж подключения
                      if (!isAvailable)
                        _pro360Badge()
                      else if (isDeviceConnected)
                        _ConnectionBadge(isConnected: isHardwareConnected),
                    ],
                  ),

                  const Spacer(),

                  // Живое значение (когда подключён и данные идут)
                  if (liveValue != null) ...[
                    _LiveValueChip(
                      value: liveValue,
                      sensor: sensor,
                    ),
                    const SizedBox(height: 6),
                  ],

                  // Название датчика
                  Text(
                    sensor.title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isAvailable
                          ? AppColors.textPrimary
                          : AppColors.textHint,
                    ),
                  ),
                  const SizedBox(height: 1),

                  // Подзаголовок
                  Text(
                    sensor.subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: isAvailable
                          ? AppColors.textSecondary
                          : AppColors.textHint,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
        ),
      ),
    );
  }

  Widget _pro360Badge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.version360Badge.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
            color: AppColors.version360Badge.withValues(alpha: 0.3)),
      ),
      child: const Text(
        '360',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.version360,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  БЕЙДЖ ПОДКЛЮЧЕНИЯ — Animated status chip
//
//  Inspired by Vernier's channel status dots and PASCO's
//  sensor detection indicators. Pulsing green dot when active,
//  muted grey when sensor not detected.
// ═══════════════════════════════════════════════════════════════

class _ConnectionBadge extends StatefulWidget {
  final bool isConnected;
  const _ConnectionBadge({required this.isConnected});

  @override
  State<_ConnectionBadge> createState() => _ConnectionBadgeState();
}

class _ConnectionBadgeState extends State<_ConnectionBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _pulseAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    if (widget.isConnected) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(_ConnectionBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isConnected && !oldWidget.isConnected) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.isConnected && oldWidget.isConnected) {
      _pulseController.stop();
      _pulseController.value = 0;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isConnected ? AppColors.success : AppColors.textHint;
    final label = widget.isConnected ? 'Подключён' : 'Не подкл.';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: widget.isConnected ? 0.12 : 0.06),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: color.withValues(alpha: widget.isConnected ? 0.3 : 0.15),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Animated pulse dot
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (_, __) => Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(
                  alpha: widget.isConnected ? _pulseAnimation.value : 0.5,
                ),
                boxShadow: widget.isConnected
                    ? [
                        BoxShadow(
                          color: color.withValues(
                              alpha: _pulseAnimation.value * 0.4),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color.withValues(alpha: 0.9),
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  ЖИВОЕ ЗНАЧЕНИЕ — Compact value chip on the sensor card
//
//  Shows the current sensor reading directly on the card.
//  Inspired by PASCO SPARKvue sensor tiles that show live values
//  without opening the experiment screen.
//  Font uses tabular figures for stable width during updates.
// ═══════════════════════════════════════════════════════════════

class _LiveValueChip extends StatelessWidget {
  final double value;
  final SensorType sensor;

  const _LiveValueChip({
    required this.value,
    required this.sensor,
  });

  @override
  Widget build(BuildContext context) {
    final formatted = SensorUtils.formatValue(value, sensor);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: sensor.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: formatted,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: sensor.color,
                fontFeatures: const [FontFeature.tabularFigures()],
                letterSpacing: -0.5,
              ),
            ),
            TextSpan(
              text: ' ${sensor.unit}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: sensor.color.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  ИНДИКАТОР ПОДКЛЮЧЕНИЯ (точка в AppBar)
// ═══════════════════════════════════════════════════════════════

class _ConnectionDot extends StatelessWidget {
  final ConnectionStatus status;
  const _ConnectionDot({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      ConnectionStatus.disconnected => AppColors.disconnected,
      ConnectionStatus.connecting => AppColors.warning,
      ConnectionStatus.connected => AppColors.success,
      ConnectionStatus.error => AppColors.error,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: status == ConnectionStatus.connected
              ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 6)]
              : null,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  КАРТОЧКА ОСЦИЛЛОГРАФА
// ═══════════════════════════════════════════════════════════════

class _OscilloscopeCard extends StatelessWidget {
  final VoidCallback onTap;
  const _OscilloscopeCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFD29922).withValues(alpha: 0.25)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.surface,
                const Color(0xFFD29922).withValues(alpha: 0.04),
              ],
            ),
          ),
          child: Row(
            children: [
              // Иконка осциллографа
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFFD29922).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.monitor_heart_outlined,
                  color: Color(0xFFD29922),
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              // Текст
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Осциллограф',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '2 канала • Триггер • Автоизмерения',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textHint,
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
