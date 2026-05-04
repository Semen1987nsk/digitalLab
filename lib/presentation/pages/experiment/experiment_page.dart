import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../data/utils/export_utils.dart';
import '../../../domain/entities/calibration_data.dart';
import '../../../domain/entities/sensor_data.dart';
import '../../../domain/entities/sensor_type.dart';
import '../../../domain/utils/sensor_utils.dart';
import '../../blocs/calibration/voltage_calibration_provider.dart';
import '../../blocs/experiment/experiment_provider.dart';
import '../../themes/app_theme.dart';
import '../../widgets/sensor_icon.dart';
import 'experiment_big_display.dart';
import 'experiment_chart_view.dart';
import 'experiment_control_bar.dart';
import 'experiment_data_table_view.dart';
import 'view_mode_selector.dart';

// ═══════════════════════════════════════════════════════════════
//  ЭКРАН ЭКСПЕРИМЕНТА
//
//  Связующий виджет: подписки на провайдеры, шорткаты, диалоги,
//  баннеры состояния. Сами визуальные компоненты — в соседних
//  файлах: ControlBar, ChartView, BigDisplay, DataTableView,
//  ViewModeSelector.
//
//  Три режима отображения (как у Vernier/PASCO):
//  • Табло — одно крупное число для проектора
//  • График — Y(t) в реальном времени с LTTB
//  • Таблица — числовые данные для записи
// ═══════════════════════════════════════════════════════════════

// ── Keyboard intents ──────────────────────────────────────────

class _ToggleRecordingIntent extends Intent {
  const _ToggleRecordingIntent();
}

class _CloseIntent extends Intent {
  const _CloseIntent();
}

class _ExportIntent extends Intent {
  const _ExportIntent();
}

class _SetViewModeIntent extends Intent {
  // ignore: prefer_const_constructors_in_immutables
  _SetViewModeIntent(this.mode);
  final ViewMode mode;
}

// ── Page ──────────────────────────────────────────────────────

class ExperimentPage extends ConsumerStatefulWidget {
  final SensorType sensorType;

  const ExperimentPage({super.key, required this.sensorType});

  @override
  ConsumerState<ExperimentPage> createState() => _ExperimentPageState();
}

class _ExperimentPageState extends ConsumerState<ExperimentPage> {
  ViewMode _viewMode = ViewMode.chart;

  @override
  void initState() {
    super.initState();
    // При переходе на экран другого датчика — очищаем данные предыдущего.
    // resetForSensor() безопасен: если эксперимент запущен — ничего не делает,
    // т.к. все датчики пишутся одновременно (как Vernier/PASCO).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(experimentControllerProvider.notifier).resetForSensor();
    });
  }

  // ── Confirm dialogs ───────────────────────────────────────

  Future<bool> _confirmStopOnBack() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                color: AppColors.warning, size: 24),
            SizedBox(width: 10),
            Text('Запись активна'),
          ],
        ),
        content: const Text(
          'Идёт запись данных со всех датчиков.\n'
          'Остановить запись и вернуться?',
          style: TextStyle(fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Продолжить запись'),
          ),
          FilledButton(
            onPressed: () {
              ref.read(experimentControllerProvider.notifier).stop();
              Navigator.pop(ctx, true);
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Остановить и выйти'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<bool> _confirmStartNewRecording() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.playlist_add_rounded,
                color: AppColors.primary, size: 24),
            SizedBox(width: 10),
            Text('Начать новую запись?'),
          ],
        ),
        content: const Text(
          'Текущий график останется доступен только до начала новой записи. '
          'Продолжить и начать новый эксперимент?',
          style: TextStyle(fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Оставить текущую запись'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Новая запись'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // ── Actions ───────────────────────────────────────────────

  Future<void> _handlePrimaryAction(
    ExperimentController controller,
    ExperimentState experiment,
    bool isConnected,
  ) async {
    if (experiment.isRunning) {
      await controller.stop();
      return;
    }

    if (!isConnected) return;

    if (experiment.measurementCount > 0) {
      final shouldStartNew = await _confirmStartNewRecording();
      if (!shouldStartNew) return;
    }

    await controller.start();
  }

  /// Единый путь экспорта (используется и кнопкой, и шорткатом Ctrl+S).
  ///
  /// Для длинных экспериментов (> in-memory буфера) читает из SQLite
  /// постранично — не держит весь датасет в RAM.
  Future<void> _exportExperiment(
    ExperimentState experiment,
    SensorType sensor,
    VoltageCalibration? voltageCalibration,
  ) async {
    try {
      String path;
      final dbExpId = experiment.dbExperimentId;
      if (dbExpId != null &&
          experiment.totalMeasurements > experiment.data.length) {
        final db = ref.read(appDatabaseProvider);
        path = await ExportUtils.exportFullExperimentFromDb(
          db,
          dbExpId,
          sensor,
          voltageCalibration: voltageCalibration,
        );
      } else {
        path = await ExportUtils.exportToCsv(
          experiment.data,
          sensor,
          voltageCalibration: voltageCalibration,
        );
      }
      if (path.isEmpty || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Данные сохранены: $path'),
          backgroundColor: AppColors.accent,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка экспорта: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  double? _latestValueForSensor({
    required SensorType sensor,
    required SensorPacket? livePacket,
    required List<SensorPacket> history,
  }) {
    final live = SensorUtils.getValue(livePacket, sensor);
    if (live != null) return live;

    for (int i = history.length - 1; i >= 0; i--) {
      final v = SensorUtils.getValue(history[i], sensor);
      if (v != null) return v;
    }
    return null;
  }

  // ── Build ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final experiment = ref.watch(experimentControllerProvider);
    final controller = ref.read(experimentControllerProvider.notifier);
    final connectionState = ref.watch(sensorConnectionProvider);
    final sensorStream = ref.watch(sensorDataStreamProvider);
    final isConnected = connectionState.status == ConnectionStatus.connected;

    SensorPacket? lastPacket;
    sensorStream.whenData((p) => lastPacket = p);
    lastPacket ??= experiment.data.isNotEmpty ? experiment.data.last : null;

    final sensor = widget.sensorType;

    // ── Программная калибровка (Vernier/PASCO/Keithley pattern) ──
    // RAW данные хранятся в буфере. Калибровка применяется при отображении.
    // Это позволяет ретроактивно перекалибровать ВСЕ данные.
    final calState = ref.watch(voltageCalibrationProvider);
    final VoltageCalibration? voltageCalibration =
        sensor == SensorType.voltage && calState.calibration.isModified
            ? calState.calibration
            : null;

    final rawCurrentValue = _latestValueForSensor(
      sensor: sensor,
      livePacket: lastPacket,
      history: experiment.data,
    );

    final currentValue = voltageCalibration != null && rawCurrentValue != null
        ? voltageCalibration.apply(rawCurrentValue)
        : rawCurrentValue;
    final visibleValue = currentValue;

    // ── Клавиатурные шорткаты ─────────────────────────────────
    // Space  — старт/стоп
    // Esc    — выход (с подтверждением во время записи)
    // Ctrl+S — экспорт
    // 1/2/3  — табло/график/таблица
    final shortcuts = <ShortcutActivator, Intent>{
      const SingleActivator(LogicalKeyboardKey.space):
          const _ToggleRecordingIntent(),
      const SingleActivator(LogicalKeyboardKey.escape): const _CloseIntent(),
      const SingleActivator(LogicalKeyboardKey.keyS, control: true):
          const _ExportIntent(),
      const SingleActivator(LogicalKeyboardKey.digit1):
          _SetViewModeIntent(ViewMode.display),
      const SingleActivator(LogicalKeyboardKey.digit2):
          _SetViewModeIntent(ViewMode.chart),
      const SingleActivator(LogicalKeyboardKey.digit3):
          _SetViewModeIntent(ViewMode.table),
    };
    final actions = <Type, Action<Intent>>{
      _ToggleRecordingIntent: CallbackAction<_ToggleRecordingIntent>(
        onInvoke: (_) {
          _handlePrimaryAction(controller, experiment, isConnected);
          return null;
        },
      ),
      _CloseIntent: CallbackAction<_CloseIntent>(
        onInvoke: (_) async {
          if (experiment.isRunning) {
            final ok = await _confirmStopOnBack();
            if (ok && context.mounted) Navigator.of(context).pop();
          } else if (context.mounted) {
            Navigator.of(context).pop();
          }
          return null;
        },
      ),
      _ExportIntent: CallbackAction<_ExportIntent>(
        onInvoke: (_) {
          if (experiment.data.isNotEmpty) {
            _exportExperiment(experiment, sensor, voltageCalibration);
          }
          return null;
        },
      ),
      _SetViewModeIntent: CallbackAction<_SetViewModeIntent>(
        onInvoke: (intent) {
          setState(() => _viewMode = intent.mode);
          return null;
        },
      ),
    };

    return PopScope(
      canPop: !experiment.isRunning,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return; // Already popped (not recording)
        final shouldPop = await _confirmStopOnBack();
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Shortcuts(
        shortcuts: shortcuts,
        child: Actions(
          actions: actions,
          child: Focus(
            autofocus: true,
            child: Scaffold(
              appBar: AppBar(
                title: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SensorIcon(sensor: sensor, size: 22),
                    const SizedBox(width: 10),
                    Text(sensor.title),
                  ],
                ),
                actions: [
                  ViewModeSelector(
                    mode: _viewMode,
                    color: sensor.color,
                    onChanged: (m) => setState(() => _viewMode = m),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
              body: Column(
                children: [
                  _StatusBanners(
                    experiment: experiment,
                    connectionState: connectionState,
                    isConnected: isConnected,
                    onReconnect: () =>
                        ref.read(sensorConnectionProvider.notifier).connect(),
                  ),
                  ControlBar(
                    sensor: sensor,
                    isRunning: experiment.isRunning,
                    isConnected: isConnected,
                    measurementCount: experiment.measurementCount,
                    isCalibrated: sensor == SensorType.voltage
                        ? calState.calibration.isModified
                        : experiment.isCalibrated,
                    sampleRateHz: experiment.sampleRateHz,
                    currentValue: visibleValue,
                    elapsedSeconds: experiment.elapsedSeconds,
                    onStart: () => _handlePrimaryAction(
                        controller, experiment, isConnected),
                    onStop: () => _handlePrimaryAction(
                        controller, experiment, isConnected),
                    onClear: () => controller.clear(),
                    onCalibrate: rawCurrentValue != null
                        ? () {
                            if (sensor == SensorType.voltage) {
                              ref
                                  .read(voltageCalibrationProvider.notifier)
                                  .quickZero(rawCurrentValue);
                            } else {
                              controller.calibrate(sensor.id);
                            }
                          }
                        : null,
                    onExport: () => _exportExperiment(
                        experiment, sensor, voltageCalibration),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: _buildContent(
                          experiment, visibleValue, voltageCalibration),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(ExperimentState state, double? currentValue,
      VoltageCalibration? voltageCalibration) {
    final sensor = widget.sensorType;
    switch (_viewMode) {
      case ViewMode.display:
        return BigDisplay(value: currentValue, sensor: sensor);
      case ViewMode.table:
        return DataTableView(
          data: state.data,
          sensor: sensor,
          voltageCalibration: voltageCalibration,
        );
      case ViewMode.chart:
        return RepaintBoundary(
          child: ChartView(
            data: state.data,
            sensor: sensor,
            isRunning: state.isRunning,
            elapsedSeconds: state.elapsedSeconds,
            voltageCalibration: voltageCalibration,
          ),
        );
    }
  }
}

// ═══════════════════════════════════════════════════════════════
//  Баннеры статуса над ControlBar.
//
//  Приоритет (показываем максимум один баннер):
//   1. Переполнение буфера (warning)
//   2. Запись завершена (info — после успешного эксперимента)
//   3. Ошибка подключения (error)
//   4. «Подключите датчик» (warning — только при пустом эксперименте)
// ═══════════════════════════════════════════════════════════════

class _StatusBanners extends StatelessWidget {
  final ExperimentState experiment;
  final SensorConnectionState connectionState;
  final bool isConnected;
  final VoidCallback onReconnect;

  const _StatusBanners({
    required this.experiment,
    required this.connectionState,
    required this.isConnected,
    required this.onReconnect,
  });

  @override
  Widget build(BuildContext context) {
    if (experiment.isBufferWarning) {
      return const _Banner(
        icon: Icons.warning_amber_rounded,
        color: AppColors.warning,
        text:
            'Буфер заполнен на 80%. Старые данные будут перезаписаны, но сохранены в базу.',
      );
    }

    if (!experiment.isRunning && experiment.measurementCount > 0) {
      return const _Banner(
        icon: Icons.check_circle_outline,
        color: AppColors.primary,
        text:
            'Запись завершена. Можно просматривать график, экспортировать данные или начать новую запись.',
      );
    }

    if (connectionState.status == ConnectionStatus.error &&
        !experiment.isRunning) {
      return _Banner(
        icon: Icons.error_outline,
        color: AppColors.error,
        text: connectionState.errorMessage ?? 'Ошибка подключения к датчику',
        actionLabel: 'Переподключить',
        onAction: onReconnect,
      );
    }

    if (!isConnected &&
        !experiment.isRunning &&
        experiment.measurementCount == 0 &&
        connectionState.status != ConnectionStatus.connecting) {
      return _Banner(
        icon: Icons.info_outline,
        color: AppColors.warning,
        text: 'Подключите датчик для получения данных',
        actionLabel: 'Подключить',
        onAction: onReconnect,
      );
    }

    return const SizedBox.shrink();
  }
}

class _Banner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _Banner({
    required this.icon,
    required this.color,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: color.withValues(alpha: 0.1),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color, fontSize: 13),
            ),
          ),
          if (actionLabel != null && onAction != null)
            FilledButton.tonal(
              onPressed: onAction,
              style: FilledButton.styleFrom(
                backgroundColor: color.withValues(alpha: 0.15),
                foregroundColor: color,
                minimumSize: const Size(0, 34),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              child: Text(actionLabel!, style: const TextStyle(fontSize: 13)),
            ),
        ],
      ),
    );
  }
}
