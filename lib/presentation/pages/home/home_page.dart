import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../domain/entities/sensor_data.dart';
import '../../../domain/entities/sensor_type.dart';
import '../../../domain/utils/sensor_utils.dart';
import '../../blocs/calibration/voltage_calibration_provider.dart';
import '../../blocs/experiment/experiment_provider.dart';
import '../../themes/app_theme.dart';
import '../../themes/design_tokens.dart';
import '../../widgets/device_panel.dart';
import '../../widgets/hover_lift.dart';
import '../../widgets/labosfera_app_bar.dart';
import '../../widgets/pulse_clock.dart';
import '../../widgets/sensor_icon.dart';
import '../../widgets/sensor_sparkline.dart';
import '../experiment/experiment_page.dart';
import '../oscilloscope/oscilloscope_page.dart';
import '../ble/ble_device_page.dart';
import '../debug/usb_debug_page.dart';
import '../port_selection/port_selection_page.dart';

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
    final connectionState = ref.watch(sensorConnectionProvider);
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _buildAppBar(context, ref, connectionState),
          const SliverToBoxAdapter(
            child: DevicePanel(),
          ),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(DS.sp4, DS.sp3, DS.sp4, 0),
              child: _ConnectionModeSelector(),
            ),
          ),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(DS.sp4, DS.sp4, DS.sp4, DS.sp1),
              child: _SectionHeader(
                title: 'Датчики',
                subtitle:
                    'Каждый датчик откликается на физическое воздействие — '
                    'нажмите, чтобы начать эксперимент.',
                accentColor: AppColors.primary,
              ),
            ),
          ),
          const SliverPadding(
            padding: EdgeInsets.fromLTRB(DS.sp4, DS.sp2, DS.sp4, DS.sp6),
            sliver: _SensorGrid(),
          ),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(DS.sp4, 0, DS.sp4, DS.sp2),
              child: _SectionHeader(
                title: 'Инструменты',
                subtitle:
                    'Дополнительные режимы для углублённой работы с сигналом.',
                accentColor: AppColors.warning,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(DS.sp4, 0, DS.sp4, DS.sp8),
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
  ) {
    return LabosferaSliverAppBar(
      actions: [
        IconButton(
          icon: const Icon(Icons.settings_ethernet),
          tooltip: 'Выбор COM-порта',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PortSelectionPage(
                onPortSelected: (portName) {
                  final ok = ref
                      .read(halSettingsProvider.notifier)
                      .setSelectedPort(portName);
                  Navigator.pop(context);
                  if (ok) {
                    ref.read(sensorConnectionProvider.notifier).connect();
                  } else if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Сначала остановите запись эксперимента',
                        ),
                      ),
                    );
                  }
                },
              ),
            ),
          ),
        ),
        if (!Platform.isWindows && !Platform.isLinux)
          IconButton(
            icon: const Icon(Icons.bluetooth_searching),
            tooltip: 'Поиск Bluetooth устройств',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BleDevicePage()),
            ),
          ),
        IconButton(
          icon: const Icon(Icons.bug_report_outlined),
          tooltip: 'USB-отладка',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const UsbDebugPage()),
          ),
        ),
        _ConnectionDot(status: connectionState.status),
        const SizedBox(width: DS.sp3),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  ВЫБОР РЕЖИМА ПОДКЛЮЧЕНИЯ — видимый сегментный переключатель
//  USB / Симуляция (BLE — только на мобильных платформах).
//
//  Раньше был спрятан в popup-меню `more_horiz`, что не позволяло
//  учителю быстро переключиться в симуляцию для демонстрации без
//  железа. Теперь — на главном экране, в одно нажатие.
// ═══════════════════════════════════════════════════════════════

class _ConnectionModeSelector extends ConsumerWidget {
  const _ConnectionModeSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(halModeProvider);
    final hasBle = !Platform.isWindows && !Platform.isLinux;

    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: DS.sp3, vertical: DS.sp2),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(DS.rLg),
        border: Border.all(color: palette.cardBorder),
      ),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: DS.sp2),
            child: Icon(
              Icons.settings_input_component_outlined,
              size: 18,
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(width: DS.sp2),
          Text(
            'Режим подключения',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: palette.textSecondary,
            ),
          ),
          const Spacer(),
          SegmentedButton<HalMode>(
            segments: [
              const ButtonSegment(
                value: HalMode.usb,
                label: Text('USB'),
                icon: Icon(Icons.usb, size: 16),
              ),
              if (hasBle)
                const ButtonSegment(
                  value: HalMode.ble,
                  label: Text('BLE'),
                  icon: Icon(Icons.bluetooth, size: 16),
                ),
              const ButtonSegment(
                value: HalMode.mock,
                label: Text('Симуляция'),
                icon: Icon(Icons.developer_mode, size: 16),
              ),
            ],
            selected: {mode},
            onSelectionChanged: (s) {
              final ok =
                  ref.read(halSettingsProvider.notifier).setMode(s.first);
              if (!ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Сначала остановите запись эксперимента',
                    ),
                  ),
                );
              }
            },
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
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

// ═══════════════════════════════════════════════════════════════
//  СЕТКА ДАТЧИКОВ (Consumer — подписка на connection + live data)
//
//  Вынесена в отдельный ConsumerWidget чтобы rebuild при новом
//  SensorPacket не затрагивал AppBar и DevicePanel.
// ═══════════════════════════════════════════════════════════════

class _SensorGrid extends ConsumerWidget {
  const _SensorGrid();

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
              isDeviceConnected: isDeviceConnected,
              isHardwareConnected: isHardwareConnected,
              liveValue: liveValue,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ExperimentPage(sensorType: sensor),
                ),
              ),
            ),
          );
        },
        childCount: SensorType.values.length,
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
// ═══════════════════════════════════════════════════════════════

class _SensorCard extends StatefulWidget {
  final SensorType sensor;
  final bool isDeviceConnected;
  final bool isHardwareConnected;
  final double? liveValue;
  final VoidCallback onTap;

  const _SensorCard({
    required this.sensor,
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

  /// Буфер последних значений для sparkline. Маленький — 60 точек.
  /// Накапливается в State, чтобы переключение между датчиками или
  /// rebuild не сбрасывали историю.
  static const int _sparkBufferSize = 60;
  final List<double> _sparkBuffer = [];

  @override
  void didUpdateWidget(covariant _SensorCard old) {
    super.didUpdateWidget(old);
    final v = widget.liveValue;
    if (v != null && v.isFinite) {
      _sparkBuffer.add(v);
      if (_sparkBuffer.length > _sparkBufferSize) {
        _sparkBuffer.removeAt(0);
      }
    }
    if (!widget.isHardwareConnected && _sparkBuffer.isNotEmpty) {
      _sparkBuffer.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final sensor = widget.sensor;
    final isDeviceConnected = widget.isDeviceConnected;
    final isHardwareConnected = widget.isHardwareConnected;
    final liveValue = widget.liveValue;
    final color = sensor.color;

    final border = isHardwareConnected
        ? sensor.color.withValues(alpha: 0.45)
        : sensor.color.withValues(alpha: 0.15);
    final hoverBorder = sensor.color.withValues(alpha: 0.75);

    final semanticValue = liveValue == null
        ? (isHardwareConnected ? 'нет данных' : 'датчик не подключён')
        : '${SensorUtils.formatValue(liveValue, sensor)} ${sensor.unit}';

    return Semantics(
      button: true,
      label:
          '${sensor.title}, $semanticValue. Нажмите, чтобы открыть эксперимент',
      child: HoverLift(
        onHoverChanged: (h) => setState(() => _hover = h),
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
                              alpha: isHardwareConnected ? 0.12 : 0.06),
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
                          // Иконка датчика — кастомный SVG (символ физической
                          // величины в стилизованной рамке).
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: color.withValues(
                                  alpha: isHardwareConnected ? 0.18 : 0.10),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.all(6),
                            child: SensorIcon(sensor: sensor, color: color),
                          ),
                          const Spacer(),
                          if (isDeviceConnected)
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
                        const SizedBox(height: 4),
                      ],

                      // Mini-sparkline (PASCO SPARKvue pattern): живой trend
                      // последних 60 точек. Хорошо читается на проекторе.
                      if (_sparkBuffer.length >= 2) ...[
                        SensorSparkline(
                          values: _sparkBuffer,
                          color: sensor.color,
                          height: 22,
                        ),
                        const SizedBox(height: 4),
                      ],

                      // Название датчика
                      Text(
                        sensor.title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 1),

                      // Подзаголовок
                      Text(
                        sensor.subtitle,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
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
}

// ═══════════════════════════════════════════════════════════════
//  БЕЙДЖ ПОДКЛЮЧЕНИЯ — Animated status chip
//
//  Inspired by Vernier's channel status dots and PASCO's
//  sensor detection indicators. Pulsing green dot when active,
//  muted grey when sensor not detected.
// ═══════════════════════════════════════════════════════════════

class _ConnectionBadge extends StatelessWidget {
  final bool isConnected;
  const _ConnectionBadge({required this.isConnected});

  @override
  Widget build(BuildContext context) {
    final color = isConnected ? AppColors.success : AppColors.textHint;
    final label = isConnected ? 'Подключён' : 'Не подкл.';

    return Semantics(
      liveRegion: true,
      label: isConnected ? 'Датчик подключён' : 'Датчик не подключён',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isConnected ? 0.12 : 0.06),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: color.withValues(alpha: isConnected ? 0.3 : 0.15),
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Pulse-dot подписан на shared PulseClock — один Ticker на всё
            // приложение. Раньше каждый Badge заводил свой AnimationController
            // (12 на сетке датчиков), теперь источник один.
            isConnected
                ? PulseClock.instance.listen(
                    builder: (_, value, __) =>
                        _PulseDot(color: color, alpha: value),
                  )
                : _PulseDot(color: color, alpha: 0.5),
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
      ),
    );
  }
}

class _PulseDot extends StatelessWidget {
  final Color color;
  final double alpha;
  const _PulseDot({required this.color, required this.alpha});

  @override
  Widget build(BuildContext context) {
    final glowing = alpha > 0.5 + 1e-3;
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: alpha),
        boxShadow: glowing
            ? [
                BoxShadow(
                  color: color.withValues(alpha: alpha * 0.4),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ]
            : null,
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

    return Semantics(
      liveRegion: true,
      label: '$formatted ${sensor.unit}',
      excludeSemantics: true,
      child: Container(
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
    final label = switch (status) {
      ConnectionStatus.disconnected => 'Не подключено',
      ConnectionStatus.connecting => 'Подключение',
      ConnectionStatus.connected => 'Подключено',
      ConnectionStatus.error => 'Ошибка подключения',
    };

    return Tooltip(
      message: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: status == ConnectionStatus.connected
                ? [
                    BoxShadow(
                        color: color.withValues(alpha: 0.5), blurRadius: 6)
                  ]
                : null,
          ),
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
    return Semantics(
      button: true,
      label: 'Осциллограф. 2 канала, триггер, автоизмерения',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border:
                  Border.all(color: AppColors.warning.withValues(alpha: 0.25)),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.surface,
                  AppColors.warning.withValues(alpha: 0.04),
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
                    color: AppColors.warning.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.monitor_heart_outlined,
                    color: AppColors.warning,
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
      ),
    );
  }
}
