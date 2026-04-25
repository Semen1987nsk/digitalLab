import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/services.dart';
import '../../../core/di/providers.dart';
import '../../../domain/entities/calibration_data.dart';
import '../../../domain/entities/sensor_data.dart';
import '../../../domain/entities/sensor_type.dart';
import '../../../domain/math/lttb.dart';
import '../../../domain/utils/sensor_utils.dart';
import '../../../domain/utils/export_utils.dart';
import '../../blocs/calibration/voltage_calibration_provider.dart';
import '../../blocs/experiment/experiment_provider.dart';
import 'stopped_review_widgets.dart';
import '../../themes/app_theme.dart';

// ═══════════════════════════════════════════════════════════════
//  ЭКРАН ЭКСПЕРИМЕНТА
//
//  Три режима отображения (как у Vernier/PASCO):
//  • Табло — одно крупное число для проектора
//  • График — Y(t) в реальном времени с LTTB
//  • Таблица — числовые данные для записи
// ═══════════════════════════════════════════════════════════════

enum ViewMode { display, chart, table }

// ═══════════════════════════════════════════════════════════════
//  KEYBOARD INTENTS — объявлены один раз на файл, чтобы
//  использовать в Shortcuts/Actions карте.
// ═══════════════════════════════════════════════════════════════

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

  /// Диалог подтверждения при выходе во время записи.
  /// Vernier/PASCO pattern: предупреждаем о потере данных.
  Future<bool> _confirmStopOnBack() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 24),
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
            Icon(Icons.playlist_add_rounded, color: AppColors.primary, size: 24),
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

    // Откалиброванное значение (для отображения в control bar и табло)
    final currentValue = voltageCalibration != null && rawCurrentValue != null
        ? voltageCalibration.apply(rawCurrentValue)
        : rawCurrentValue;
    final visibleValue = currentValue;

    // ── Клавиатурные шорткаты ─────────────────────────────────
    // Space       — старт/стоп записи (но только когда можно)
    // Escape      — выход (с подтверждением, если идёт запись)
    // Ctrl+S      — экспорт CSV
    // 1/2/3       — переключение режимов табло/график/таблица
    final shortcuts = <ShortcutActivator, Intent>{
      const SingleActivator(LogicalKeyboardKey.space):
          const _ToggleRecordingIntent(),
      const SingleActivator(LogicalKeyboardKey.escape):
          const _CloseIntent(),
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
            _runExportFromShortcut(ref, experiment, sensor, voltageCalibration);
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
            Icon(sensor.icon, color: sensor.color, size: 22),
            const SizedBox(width: 10),
            Text(sensor.title),
          ],
        ),
        actions: [
          // Переключатель режимов
          _ViewModeSelector(
            mode: _viewMode,
            color: sensor.color,
            onChanged: (m) => setState(() => _viewMode = m),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Баннер: запись продолжается (при входе на страницу во время записи)
          // Баннер: предупреждение о переполнении буфера
          if (experiment.isBufferWarning)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: AppColors.warning.withValues(alpha: 0.1),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Буфер заполнен на 80%. Старые данные будут перезаписаны, но сохранены в базу.',
                      style: TextStyle(color: AppColors.warning, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),

          // Баннер: ошибка подключения
          if (!experiment.isRunning &&
              experiment.measurementCount > 0)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: AppColors.primary.withValues(alpha: 0.1),
              child: const Row(
                children: [
                  Icon(Icons.check_circle_outline, color: AppColors.primary, size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Запись завершена. Можно просматривать график, экспортировать данные или начать новую запись.',
                      style: TextStyle(color: AppColors.primary, fontSize: 13),
                    ),
                  ),
                ],
              ),
            )

          // Баннер: ошибка подключения
          else if (connectionState.status == ConnectionStatus.error && !experiment.isRunning)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: AppColors.error.withValues(alpha: 0.1),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: AppColors.error, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      connectionState.errorMessage ?? 'Ошибка подключения к датчику',
                      style: const TextStyle(color: AppColors.error, fontSize: 13),
                    ),
                  ),
                  FilledButton.tonal(
                    onPressed: () => ref.read(sensorConnectionProvider.notifier).connect(),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.error.withValues(alpha: 0.15),
                      foregroundColor: AppColors.error,
                      minimumSize: const Size(0, 34),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    child: const Text('Переподключить', style: TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            )
          // Баннер: подключите датчик (если не подключён и нет ошибки)
          else if (!isConnected &&
              !experiment.isRunning &&
              experiment.measurementCount == 0 &&
              connectionState.status != ConnectionStatus.connecting)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: AppColors.warning.withValues(alpha: 0.1),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: AppColors.warning, size: 18),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Подключите датчик для получения данных',
                      style: TextStyle(color: AppColors.warning, fontSize: 13),
                    ),
                  ),
                  FilledButton.tonal(
                    onPressed: () => ref.read(sensorConnectionProvider.notifier).connect(),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.warning.withValues(alpha: 0.15),
                      foregroundColor: AppColors.warning,
                      minimumSize: const Size(0, 34),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    child: const Text('Подключить', style: TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ),

          // Панель управления
          _ControlBar(
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
            onStart: () => _handlePrimaryAction(controller, experiment, isConnected),
            onStop: () => _handlePrimaryAction(controller, experiment, isConnected),
            onClear: () => controller.clear(),
            onCalibrate: rawCurrentValue != null
                ? () {
                    if (sensor == SensorType.voltage) {
                      // Программная калибровка: quickZero через Riverpod
                      ref.read(voltageCalibrationProvider.notifier)
                          .quickZero(rawCurrentValue);
                    } else {
                      controller.calibrate(sensor.id);
                    }
                  }
                : null,
            onExport: () async {
              try {
                String path;
                final dbExpId = experiment.dbExperimentId;
                // Если данных больше чем вместилось в in-memory буфер
                // (эксперимент > 25 мин при 100Hz), экспортируем из SQLite
                // постранично — не держим всё в RAM.
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
                if (path.isEmpty) return;
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Данные сохранены: $path'),
                      backgroundColor: AppColors.accent,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Ошибка экспорта: $e'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              }
            },
          ),

          // Контент
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: _buildContent(experiment, visibleValue, voltageCalibration),
            ),
          ),
        ],
      ),
            ), // child: Scaffold
          ), // Focus
        ), // Actions
      ), // Shortcuts
    ); // PopScope
  }

  Future<void> _runExportFromShortcut(
    WidgetRef ref,
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

  Widget _buildContent(ExperimentState state, double? currentValue, VoltageCalibration? voltageCalibration) {
    final sensor = widget.sensorType;
    switch (_viewMode) {
      case ViewMode.display:
        return _BigDisplay(value: currentValue, sensor: sensor);
      case ViewMode.table:
        return _DataTableView(data: state.data, sensor: sensor, voltageCalibration: voltageCalibration);
      case ViewMode.chart:
        return RepaintBoundary(
          child: _ChartView(
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
//  ПЕРЕКЛЮЧАТЕЛЬ РЕЖИМОВ
// ═══════════════════════════════════════════════════════════════

class _ViewModeSelector extends StatelessWidget {
  final ViewMode mode;
  final Color color;
  final ValueChanged<ViewMode> onChanged;

  const _ViewModeSelector({
    required this.mode,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _modeButton(ViewMode.display, Icons.monitor, 'Табло'),
          _modeButton(ViewMode.chart, Icons.show_chart, 'График'),
          _modeButton(ViewMode.table, Icons.table_rows_outlined, 'Таблица'),
        ],
      ),
    );
  }

  Widget _modeButton(ViewMode m, IconData icon, String tooltip) {
    final isSelected = mode == m;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onChanged(m),
        borderRadius: BorderRadius.circular(11),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.16) : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected ? color : AppColors.textHint,
              ),
              const SizedBox(width: 6),
              Text(
                tooltip,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  color: isSelected ? color : AppColors.textSecondary,
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
//  ПАНЕЛЬ УПРАВЛЕНИЯ
// ═══════════════════════════════════════════════════════════════

class _ControlBar extends StatelessWidget {
  final SensorType sensor;
  final bool isRunning;
  final bool isConnected;
  final int measurementCount;
  final bool isCalibrated;
  final int sampleRateHz;
  final double? currentValue;
  final double elapsedSeconds;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onClear;
  final VoidCallback? onCalibrate;
  final VoidCallback onExport;

  const _ControlBar({
    required this.sensor,
    required this.isRunning,
    required this.isConnected,
    required this.measurementCount,
    required this.isCalibrated,
    required this.sampleRateHz,
    required this.currentValue,
    required this.elapsedSeconds,
    required this.onStart,
    required this.onStop,
    required this.onClear,
    required this.onCalibrate,
    required this.onExport,
  });

  double _valueBoxWidth(SensorType sensor) {
    switch (sensor) {
      case SensorType.acceleration:
        return 170;
      case SensorType.pressure:
        return 150;
      case SensorType.radiation:
        return 160;
      default:
        return 130;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasRecordedData = measurementCount > 0;
    final isReviewMode = !isRunning && hasRecordedData;
    final primaryLabel = isRunning
        ? 'Стоп'
        : hasRecordedData
            ? 'Новая запись'
            : 'Старт';
    final primaryIcon = isRunning
        ? Icons.stop_rounded
        : hasRecordedData
            ? Icons.playlist_add_rounded
            : Icons.play_arrow_rounded;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SessionStatusPill(
                  isRunning: isRunning,
                  isReviewMode: isReviewMode,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _ActionButton(
                      onPressed: isRunning ? onStop : (isConnected ? onStart : null),
                      icon: primaryIcon,
                      label: primaryLabel,
                      color: isRunning ? AppColors.error : AppColors.accent,
                      filled: true,
                    ),
                    if (isReviewMode)
                      _ActionButton(
                        onPressed: onExport,
                        icon: Icons.download_rounded,
                        label: 'Экспорт',
                        color: AppColors.primary,
                      )
                    else
                      _ActionButton(
                        onPressed: onCalibrate,
                        icon: Icons.tune_rounded,
                        label: isCalibrated ? 'Ноль ✓' : 'Ноль',
                        color: isCalibrated ? AppColors.accent : null,
                      ),
                    _ActionButton(
                      onPressed: isRunning || !hasRecordedData ? null : onClear,
                      icon: Icons.delete_outline_rounded,
                      label: isReviewMode ? 'Удалить запись' : 'Очистить',
                    ),
                    if (!isReviewMode)
                      _ActionButton(
                        onPressed: isRunning || !hasRecordedData ? null : onExport,
                        icon: Icons.download_rounded,
                        label: 'Экспорт',
                      ),
                    if (isReviewMode)
                      _ActionButton(
                        onPressed: onCalibrate,
                        icon: Icons.tune_rounded,
                        label: isCalibrated ? 'Ноль ✓' : 'Ноль',
                        color: isCalibrated ? AppColors.accent : null,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          _ExperimentSummary(
            sensor: sensor,
            currentValue: currentValue,
            measurementCount: measurementCount,
            elapsedSeconds: elapsedSeconds,
            isRunning: isRunning,
            valueBoxWidth: _valueBoxWidth(sensor),
          ),
        ],
      ),
    );
  }
}

class _SessionStatusPill extends StatelessWidget {
  final bool isRunning;
  final bool isReviewMode;

  const _SessionStatusPill({
    required this.isRunning,
    required this.isReviewMode,
  });

  @override
  Widget build(BuildContext context) {
    final (icon, label, color) = isRunning
        ? (Icons.fiber_manual_record_rounded, 'Идёт запись', AppColors.error)
        : isReviewMode
            ? (Icons.analytics_outlined, 'Режим анализа', AppColors.primary)
            : (Icons.play_circle_outline_rounded, 'Готов к записи', AppColors.textSecondary);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExperimentSummary extends StatelessWidget {
  final SensorType sensor;
  final double? currentValue;
  final int measurementCount;
  final double elapsedSeconds;
  final bool isRunning;
  final double valueBoxWidth;

  const _ExperimentSummary({
    required this.sensor,
    required this.currentValue,
    required this.measurementCount,
    required this.elapsedSeconds,
    required this.isRunning,
    required this.valueBoxWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ExperimentTimer(
          elapsedSeconds: elapsedSeconds,
          isRunning: isRunning,
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: sensor.color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: sensor.color.withValues(alpha: 0.2)),
          ),
          child: SizedBox(
            width: valueBoxWidth,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                currentValue != null
                    ? '${SensorUtils.formatValue(currentValue!, sensor)} ${sensor.unit}'
                    : '— ${sensor.unit}',
                maxLines: 1,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: currentValue != null
                      ? sensor.color
                      : sensor.color.withValues(alpha: 0.4),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.data_usage, size: 14, color: AppColors.textHint),
              const SizedBox(width: 5),
              Text(
                '$measurementCount',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final String label;
  final Color? color;
  final bool filled;

  const _ActionButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    this.color,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    if (filled) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: color ?? AppColors.accent,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18, color: color),
      label: Text(label, style: TextStyle(color: color)),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide(color: color?.withValues(alpha: 0.3) ?? AppColors.surfaceBright),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  ТАЙМЕР ЭКСПЕРИМЕНТА
//
//  Показывает время с начала измерений в формате MM:SS.d
//  Пульсирующая красная точка при записи (как в профессиональных DAQ)
//  SingleTickerProviderStateMixin → единственный AnimationController
//  для пульсации точки. Само время elapsedSeconds приходит из провайдера
//  (обновляется 30fps), а не из собственного таймера → zero drift.
// ═══════════════════════════════════════════════════════════════

class _ExperimentTimer extends StatefulWidget {
  final double elapsedSeconds;
  final bool isRunning;

  const _ExperimentTimer({
    required this.elapsedSeconds,
    required this.isRunning,
  });

  @override
  State<_ExperimentTimer> createState() => _ExperimentTimerState();
}

class _ExperimentTimerState extends State<_ExperimentTimer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _pulseAnim = Tween<double>(begin: 1.0, end: 0.25).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    if (widget.isRunning) _pulseCtrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _ExperimentTimer old) {
    super.didUpdateWidget(old);
    if (widget.isRunning && !old.isRunning) {
      _pulseCtrl.repeat(reverse: true);
    } else if (!widget.isRunning && old.isRunning) {
      _pulseCtrl.stop();
      _pulseCtrl.value = 0.0; // reset to full opacity
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  /// Formats seconds into MM:SS.d (tenths of a second)
  static String _formatTime(double totalSeconds) {
    if (totalSeconds <= 0) return '00:00.0';
    final mins = totalSeconds ~/ 60;
    final secs = (totalSeconds % 60).toInt();
    final tenths = ((totalSeconds % 1) * 10).toInt();
    return '${mins.toString().padLeft(2, '0')}:'
        '${secs.toString().padLeft(2, '0')}.$tenths';
  }

  @override
  Widget build(BuildContext context) {
    final isRunning = widget.isRunning;
    final elapsed = widget.elapsedSeconds;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isRunning
            ? AppColors.error.withValues(alpha: 0.08)
            : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isRunning
              ? AppColors.error.withValues(alpha: 0.3)
              : AppColors.cardBorder,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Пульсирующая точка записи / статичная иконка таймера
          if (isRunning)
            AnimatedBuilder(
              animation: _pulseAnim,
              builder: (_, __) => Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.error.withValues(alpha: _pulseAnim.value),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.error.withValues(alpha: _pulseAnim.value * 0.5),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            )
          else
            Icon(
              Icons.timer_outlined,
              size: 16,
              color: elapsed > 0
                  ? AppColors.textSecondary
                  : AppColors.textHint,
            ),
          const SizedBox(width: 8),

          // Время MM:SS.d
          Text(
            _formatTime(elapsed),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: isRunning
                  ? AppColors.error
                  : (elapsed > 0 ? AppColors.textPrimary : AppColors.textHint),
              fontFeatures: const [FontFeature.tabularFigures()],
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  ТАБЛО — крупное число для проектора
// ═══════════════════════════════════════════════════════════════

class _BigDisplay extends StatelessWidget {
  final double? value;
  final SensorType sensor;

  const _BigDisplay({required this.value, required this.sensor});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(sensor.icon, size: 48, color: sensor.color.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text(
            sensor.title,
            style: const TextStyle(fontSize: 20, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value != null
                      ? SensorUtils.formatValue(value!, sensor)
                      : '—',
                  style: TextStyle(
                    fontSize: 120,
                    fontWeight: FontWeight.w700,
                    color: sensor.color,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    letterSpacing: -3,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  sensor.unit,
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w500,
                    color: sensor.color.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Режим «Табло» — для проектора',
              style: TextStyle(color: AppColors.textHint, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  ГРАФИК — Y(t) с LTTB
// ═══════════════════════════════════════════════════════════════

/// Результат сбора точек: spots + precomputed Y-bounds (один проход).
class _ChartData {
  final List<FlSpot> spots;
  final double minY;
  final double maxY;
  const _ChartData(this.spots, this.minY, this.maxY);
}

enum _ChartInteractionMode { pan, selectZoom }

class _ChartView extends StatefulWidget {
  final List<SensorPacket> data;
  final SensorType sensor;
  final bool isRunning;

  /// Wall-clock elapsed seconds (30 FPS) for smooth X-axis scrolling.
  final double elapsedSeconds;

  /// Программная калибровка напряжения (null = без калибровки)
  final VoltageCalibration? voltageCalibration;

  const _ChartView({
    required this.data,
    required this.sensor,
    required this.isRunning,
    required this.elapsedSeconds,
    this.voltageCalibration,
  });

  @override
  State<_ChartView> createState() => _ChartViewState();
}

class _ChartViewState extends State<_ChartView> {
  static const double _visibleWindowSec = 30.0;
  static const double _shrinkAlpha = 0.12;
  static const double _xSnapStepSec = 0.5;
  static const int _downsampleThreshold = 5000;
  static const int _maxRenderPoints = 1200;
  static const double _minWindowSec = 0.5;
  static const double _panFractionStep = 0.25;
  static const double _zoomFactorIn = 0.7;
  static const double _zoomFactorOut = 1.4;
  static const double _minSelectionLogicalWidth = 0.2;
  static const double _minSelectionScreenWidth = 12.0;
  static const double _chartLeftReservedPx = 48.0;

  double? _stableMinY;
  double? _stableMaxY;

  // ── UX: Pan & Zoom State ──
  double? _userMinX;
  double? _userMaxX;
  double? _userMinY;
  double? _userMaxY;
  double _startMinX = 0;
  double _startMaxX = 0;
  double _scaleStartFocalDx = 0;
  _ChartInteractionMode _interactionMode = _ChartInteractionMode.pan;
  int? _selectionPointerId;
  double? _selectionStartDx;
  double? _selectionCurrentDx;

  @override
  void didUpdateWidget(covariant _ChartView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sensor != widget.sensor) {
      _stableMinY = null;
      _stableMaxY = null;
      _userMinX = null;
      _userMaxX = null;
      _userMinY = null;
      _userMaxY = null;
    }
    if (widget.isRunning && !oldWidget.isRunning) {
      // Сброс зума при новом запуске
      _userMinX = null;
      _userMaxX = null;
      _userMinY = null;
      _userMaxY = null;
      _interactionMode = _ChartInteractionMode.pan;
    }
  }

  bool get _hasManualXRange => _userMinX != null && _userMaxX != null;
  bool get _hasManualYRange => _userMinY != null && _userMaxY != null;
  bool get _hasSelectionPreview =>
      _selectionStartDx != null && _selectionCurrentDx != null;

  ({double minX, double maxX}) _clampXWindow({
    required double minX,
    required double maxX,
    required double maxDataTime,
  }) {
    double newMinX = minX;
    double newMaxX = maxX;
    double range = newMaxX - newMinX;

    if (!range.isFinite || range <= 0) {
      range = math.min(_visibleWindowSec, math.max(maxDataTime, _minWindowSec));
      newMinX = math.max(0.0, maxDataTime - range);
      newMaxX = newMinX + range;
    }

    if (range < _minWindowSec) {
      final center = (newMinX + newMaxX) / 2;
      range = _minWindowSec;
      newMinX = center - range / 2;
      newMaxX = center + range / 2;
    }

    if (range > maxDataTime && maxDataTime > 0) {
      range = maxDataTime;
      newMinX = 0;
      newMaxX = maxDataTime;
    }

    if (newMinX < 0) {
      newMinX = 0;
      newMaxX = newMinX + range;
    }
    if (newMaxX > maxDataTime) {
      newMaxX = maxDataTime;
      newMinX = newMaxX - range;
      if (newMinX < 0) newMinX = 0;
    }

    return (minX: newMinX, maxX: newMaxX);
  }

  void _resetView() {
    setState(() {
      _userMinX = null;
      _userMaxX = null;
      _userMinY = null;
      _userMaxY = null;
      _stableMinY = null;
      _stableMaxY = null;
      _selectionPointerId = null;
      _selectionStartDx = null;
      _selectionCurrentDx = null;
      _interactionMode = _ChartInteractionMode.pan;
    });
  }

  double _clampChartDx(double dx, double chartWidth) {
    return dx.clamp(_chartLeftReservedPx, _chartLeftReservedPx + chartWidth);
  }

  void _clearSelectionPreview() {
    if (!_hasSelectionPreview && _selectionPointerId == null) return;
    setState(() {
      _selectionPointerId = null;
      _selectionStartDx = null;
      _selectionCurrentDx = null;
    });
  }

  void _toggleInteractionMode(_ChartInteractionMode mode) {
    setState(() {
      _interactionMode = mode;
      _selectionPointerId = null;
      _selectionStartDx = null;
      _selectionCurrentDx = null;
    });
  }

  bool _canStartSelection(PointerDownEvent event) {
    if (widget.isRunning || _interactionMode != _ChartInteractionMode.selectZoom) {
      return false;
    }

    if (event.kind == PointerDeviceKind.mouse) {
      return (event.buttons & kPrimaryMouseButton) != 0;
    }

    return event.buttons != 0;
  }

  void _handleSelectionPointerDown(PointerDownEvent event, double chartWidth) {
    if (!_canStartSelection(event) || chartWidth <= 0) {
      return;
    }

    if (event.localPosition.dx < _chartLeftReservedPx ||
        event.localPosition.dx > _chartLeftReservedPx + chartWidth) {
      return;
    }

    final startDx = _clampChartDx(event.localPosition.dx, chartWidth);
    setState(() {
      _selectionPointerId = event.pointer;
      _selectionStartDx = startDx;
      _selectionCurrentDx = startDx;
    });
  }

  void _handleSelectionPointerMove(PointerMoveEvent event, double chartWidth) {
    if (chartWidth <= 0 || _selectionPointerId != event.pointer) {
      return;
    }

    setState(() {
      _selectionCurrentDx = _clampChartDx(event.localPosition.dx, chartWidth);
    });
  }

  void _handleSelectionPointerEnd(
    int pointer,
    double chartWidth,
    double minVisibleX,
    double maxX,
    double maxDataTime,
  ) {
    if (_selectionPointerId != pointer) {
      return;
    }

    if (chartWidth <= 0) {
      _clearSelectionPreview();
      return;
    }

    _applySelectionZoom(chartWidth, minVisibleX, maxX, maxDataTime);
  }

  void _applySelectionZoom(
    double chartWidth,
    double minVisibleX,
    double maxX,
    double maxDataTime,
  ) {
    final startDx = _selectionStartDx;
    final currentDx = _selectionCurrentDx;
    if (startDx == null || currentDx == null) return;

    final leftDx = math.min(startDx, currentDx);
    final rightDx = math.max(startDx, currentDx);
    final screenWidth = rightDx - leftDx;

    if (screenWidth < _minSelectionScreenWidth || chartWidth <= 0) {
      _clearSelectionPreview();
      return;
    }

    final range = maxX - minVisibleX;
    final startFraction = ((leftDx - _chartLeftReservedPx) / chartWidth).clamp(0.0, 1.0);
    final endFraction = ((rightDx - _chartLeftReservedPx) / chartWidth).clamp(0.0, 1.0);

    final selectedMinX = minVisibleX + range * startFraction;
    final selectedMaxX = minVisibleX + range * endFraction;
    final selectedWidth = selectedMaxX - selectedMinX;

    if (selectedWidth < _minSelectionLogicalWidth) {
      _clearSelectionPreview();
      return;
    }

    final clamped = _clampXWindow(
      minX: selectedMinX,
      maxX: selectedMaxX,
      maxDataTime: math.max(maxDataTime, _minWindowSec),
    );

    setState(() {
      _userMinX = clamped.minX;
      _userMaxX = clamped.maxX;
      _userMinY = null;
      _userMaxY = null;
      _stableMinY = null;
      _stableMaxY = null;
      _selectionPointerId = null;
      _selectionStartDx = null;
      _selectionCurrentDx = null;
      _interactionMode = _ChartInteractionMode.pan;
    });
  }

  void _fitAllX(double maxDataTime) {
    final clamped = _clampXWindow(
      minX: 0,
      maxX: math.max(maxDataTime, _minWindowSec),
      maxDataTime: math.max(maxDataTime, _minWindowSec),
    );
    setState(() {
      _userMinX = clamped.minX;
      _userMaxX = clamped.maxX;
      _userMinY = null;
      _userMaxY = null;
      _stableMinY = null;
      _stableMaxY = null;
    });
  }

  void _setXWindowFromStart(double startX, double range, double maxDataTime) {
    final clamped = _clampXWindow(
      minX: startX,
      maxX: startX + range,
      maxDataTime: math.max(maxDataTime, _minWindowSec),
    );
    setState(() {
      _userMinX = clamped.minX;
      _userMaxX = clamped.maxX;
    });
  }

  void _panByFraction(double fraction, double minVisibleX, double maxX, double maxDataTime) {
    final currentMin = _userMinX ?? minVisibleX;
    final currentMax = _userMaxX ?? maxX;
    final range = currentMax - currentMin;
    final shift = range * fraction;
    final clamped = _clampXWindow(
      minX: currentMin + shift,
      maxX: currentMax + shift,
      maxDataTime: math.max(maxDataTime, _minWindowSec),
    );
    setState(() {
      _userMinX = clamped.minX;
      _userMaxX = clamped.maxX;
    });
  }

  void _zoomXByFactor(
    double factor,
    double minVisibleX,
    double maxX,
    double maxDataTime, {
    double anchorFraction = 0.5,
  }) {
    final currentMin = _userMinX ?? minVisibleX;
    final currentMax = _userMaxX ?? maxX;
    final currentRange = currentMax - currentMin;
    final targetRange = (currentRange * factor)
        .clamp(_minWindowSec, math.max(maxDataTime, _minWindowSec));
    final center = currentMin + currentRange * anchorFraction;
    final clamped = _clampXWindow(
      minX: center - targetRange * anchorFraction,
      maxX: center + targetRange * (1 - anchorFraction),
      maxDataTime: math.max(maxDataTime, _minWindowSec),
    );
    setState(() {
      _userMinX = clamped.minX;
      _userMaxX = clamped.maxX;
    });
  }

  void _zoomYByFactor(double factor, double currentMinY, double currentMaxY) {
    final currentRange = (currentMaxY - currentMinY).abs();
    final safeRange = currentRange < widget.sensor.minRange
        ? widget.sensor.minRange
        : currentRange;
    final targetRange = (safeRange * factor).clamp(
      widget.sensor.minRange,
      widget.sensor.minRange * 500,
    );
    final center = (currentMinY + currentMaxY) / 2;

    setState(() {
      _userMinY = center - targetRange / 2;
      _userMaxY = center + targetRange / 2;
    });
  }

  void _resetYScale() {
    setState(() {
      _userMinY = null;
      _userMaxY = null;
      _stableMinY = null;
      _stableMaxY = null;
    });
  }

  /// Авто-масштаб оси Y: expand мгновенно, shrink плавно (EMA).
  ///
  /// Мировой стандарт (Vernier LabQuest, PASCO Capstone, LabVIEW):
  /// ось Y отслеживает видимый диапазон данных, а не max-envelope.
  ///
  /// Ключевое отличие от наивного подхода — min и max обрабатываются
  /// **независимо**: если данные прижаты к нижнему краю, верхний
  /// край всё равно может плавно сужаться (и наоборот).
  ///
  /// Скорость сужения (EMA α):
  ///   Live:    α=0.02 → ~3 с до 85% сходимости (30 FPS)
  ///   Stopped: α=0.12 → ~0.3 с — быстрая подгонка для анализа
  void _updateStableRange(double rawMin, double rawMax) {
    if (!rawMin.isFinite || !rawMax.isFinite) return;

    if (_stableMinY == null || _stableMaxY == null) {
      _stableMinY = rawMin;
      _stableMaxY = rawMax;
      return;
    }

    final currentMin = _stableMinY!;
    final currentMax = _stableMaxY!;
    final currentRange = (currentMax - currentMin).abs();
    final safeRange = currentRange < widget.sensor.minRange
        ? widget.sensor.minRange
        : currentRange;

    // 10% dead-zone: внутри — не дёргаем ось; за пределами — реагируем.
    final hysteresis = safeRange * 0.10;

    // Live: медленный EMA (α=0.02, ~3с). Stopped: быстрый (α=0.12, ~0.3с).
    final alpha = widget.isRunning ? 0.02 : _shrinkAlpha;

    // ── MIN (нижняя граница) — независимо ──
    if (rawMin < currentMin + hysteresis) {
      // Данные у нижнего края или вышли за него → расширяем мгновенно
      _stableMinY = math.min(currentMin, rawMin);
    } else {
      // Данные далеко от нижнего края → плавно сужаем
      _stableMinY = currentMin + (rawMin - currentMin) * alpha;
    }

    // ── MAX (верхняя граница) — независимо ──
    if (rawMax > currentMax - hysteresis) {
      // Данные у верхнего края или вышли за него → расширяем мгновенно
      _stableMaxY = math.max(currentMax, rawMax);
    } else {
      // Данные далеко от верхнего края → плавно сужаем
      _stableMaxY = currentMax + (rawMax - currentMax) * alpha;
    }

    // Гарантируем минимальный диапазон оси (стабильность мелких сигналов).
    final stableRange = (_stableMaxY! - _stableMinY!).abs();
    if (stableRange < widget.sensor.minRange) {
      final center = (_stableMaxY! + _stableMinY!) / 2;
      _stableMinY = center - widget.sensor.minRange / 2;
      _stableMaxY = center + widget.sensor.minRange / 2;
    }
  }

  /// Сбор точек из видимого окна + LTTB + Y-bounds за ОДИН проход.
  ///
  /// Оптимизации (senior level):
  /// - FlSpot напрямую (без промежуточного DataPoint → −N аллокаций)
  /// - min/max Y в том же цикле (−2 прохода по массиву)
  /// - LTTB при >5000 точек (редко с оконным снэпшотом ~3500)
  _ChartData? _collectSpotsAndBounds(
    List<SensorPacket> data,
    double minVisibleX,
    double maxVisibleX,
  ) {
    double minY = double.infinity;
    double maxY = double.negativeInfinity;

    // Обратный обход: от конца к началу, остановка при выходе за окно.
    final reversed = <FlSpot>[];
    for (int i = data.length - 1; i >= 0; i--) {
      final p = data[i];
      if (p.timeSeconds < minVisibleX) break;
      if (p.timeSeconds > maxVisibleX) continue;
      final v = SensorUtils.getCalibratedValue(p, widget.sensor,
          voltageCalibration: widget.voltageCalibration);
      if (v == null || !v.isFinite) continue;
      reversed.add(FlSpot(p.timeSeconds, v));
      if (v < minY) minY = v;
      if (v > maxY) maxY = v;
    }

    if (reversed.isEmpty) return null;
    final spots = reversed.reversed.toList(growable: false);

    // LTTB при >5000 точек (с оконным снэпшотом обычно не срабатывает)
    if (spots.length > _downsampleThreshold) {
      final Float64List dataPoints = Float64List(spots.length * 2);
      for (int i = 0; i < spots.length; i++) {
        dataPoints[i * 2] = spots[i].x;
        dataPoints[i * 2 + 1] = spots[i].y;
      }
      
      final Float64List downsampled = LTTB.downsample(dataPoints, _maxRenderPoints);
      minY = double.infinity;
      maxY = double.negativeInfinity;
      
      final int dsLength = downsampled.length ~/ 2;
      final dsSpots = List<FlSpot>.generate(dsLength, (i) {
        final double x = downsampled[i * 2];
        final double y = downsampled[i * 2 + 1];
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
        return FlSpot(x, y);
      }, growable: false);
      return _ChartData(dsSpots, minY, maxY);
    }

    return _ChartData(spots, minY, maxY);
  }

  double _snapDown(double value, double step) {
    if (!value.isFinite || step <= 0) return value;
    return (value / step).floor() * step;
  }

  double _snapUp(double value, double step) {
    if (!value.isFinite || step <= 0) return value;
    return (value / step).ceil() * step;
  }

  /// "Красивый" шаг оси (1-2-5 × 10^n) по алгоритму Heckbert 1990.
  ///
  /// Пороги — геометрические средние между соседними «красивыми» числами:
  ///   √(1×2) ≈ 1.5,  √(2×5) ≈ 3.16,  √(5×10) ≈ 7.07
  /// Это даёт оптимально плотные, но читаемые деления.
  double _niceStep(double rawStep) {
    if (!rawStep.isFinite || rawStep <= 0) return 1.0;
    final exponent = math.pow(10.0, (math.log(rawStep) / math.ln10).floor());
    final fraction = rawStep / exponent;

    // Heckbert rounding thresholds (geometric means)
    final double niceFraction;
    if (fraction < 1.5) {
      niceFraction = 1.0;
    } else if (fraction < 3.0) {
      niceFraction = 2.0;
    } else if (fraction < 7.0) {
      niceFraction = 5.0;
    } else {
      niceFraction = 10.0;
    }
    return niceFraction * exponent;
  }

  /// Число знаков после запятой для подписей, исходя из шага.
  /// step=0.5 → 1, step=0.01 → 2, step=2 → 0, step=100 → 0
  int _decimalPlacesForStep(double step) {
    if (!step.isFinite || step <= 0) return 1;
    final logVal = -(math.log(step) / math.ln10).floor();
    return logVal.clamp(0, 4);
  }

  /// «Красивый» шаг для оси времени.
  /// Использует расширенную последовательность: {0.1, 0.2, 0.5, 1, 2, 5, 10, 15, 30, 60}
  /// — человеку привычны 15 и 30 (часовые деления), а не только 1-2-5.
  double _niceTimeStep(double rawStep) {
    const steps = [0.1, 0.2, 0.5, 1.0, 2.0, 5.0, 10.0, 15.0, 30.0, 60.0, 120.0, 300.0];
    for (final s in steps) {
      if (s >= rawStep * 0.9) return s;
    }
    return steps.last;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.data.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      widget.sensor.color.withValues(alpha: 0.18),
                      widget.sensor.color.withValues(alpha: 0.06),
                    ],
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: widget.sensor.color.withValues(alpha: 0.35),
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  Icons.show_chart_rounded,
                  size: 40,
                  color: widget.sensor.color,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'График появится после старта',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Нажмите «Старт» внизу, чтобы начать запись. Вы сможете остановить в любой момент и затем масштабировать график колёсиком мыши или жестами.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.45,
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
      );
    }

    final latestX = widget.data.last.timeSeconds;

    // ── ПЛАВНАЯ ПРОКРУТКА НА WALL-CLOCK (30 FPS) ──
    // maxX = elapsedSeconds + 1.0 → ~3% «будущего» в 30-секундном окне
    // (LabVIEW: 5-10%, осциллографы: 5%, Vernier: 5%. 1 секунда — оптимально).
    // При остановке — snap к сетке для аккуратного отображения.
    double maxX;
    double minVisibleX;
    if (widget.isRunning) {
      maxX = widget.elapsedSeconds + 1.0;
      minVisibleX = math.max(0.0, maxX - _visibleWindowSec);
    } else {
      if (_userMinX != null && _userMaxX != null) {
        minVisibleX = _userMinX!;
        maxX = _userMaxX!;
      } else {
        maxX = _snapUp(latestX, _xSnapStepSec);
        minVisibleX = math.max(
          0.0,
          _snapDown(latestX, _xSnapStepSec) - _visibleWindowSec,
        );
      }
    }

    // ── NICE X-AXIS INTERVAL ──
    // ~6 делений в окне — оптимально для оси времени (Heckbert 1990).
    final xVisibleRange = maxX - minVisibleX;
    final xStep = _niceTimeStep(xVisibleRange / 6.0);
    final xDecimals = _decimalPlacesForStep(xStep);

    // ── СБОР ТОЧЕК: один проход, FlSpot напрямую, min/max сразу ──
    final chartData = _collectSpotsAndBounds(widget.data, minVisibleX, maxX);

    if (chartData == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.sensors_off, size: 56, color: AppColors.textHint),
            SizedBox(height: 12),
            Text(
              'Нет данных для этого датчика',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    final spots = chartData.spots;
    var minY = chartData.minY;
    var maxY = chartData.maxY;
    final range = maxY - minY;

    if (range < widget.sensor.minRange) {
      final center = (maxY + minY) / 2;
      minY = center - widget.sensor.minRange / 2;
      maxY = center + widget.sensor.minRange / 2;
    }

    final pad = (maxY - minY) * 0.06;
    _updateStableRange(minY - pad, maxY + pad);

    final chartMinYRaw = _userMinY ?? _stableMinY ?? (minY - pad);
    final chartMaxYRaw = _userMaxY ?? _stableMaxY ?? (maxY + pad);

    // Квантование границ Y снижает «дрожание» шкалы при мелком шуме.
    // ~6-8 делений на ось Y — золотой стандарт (Heckbert, D3, Matplotlib).
    final rawAxisRange = (chartMaxYRaw - chartMinYRaw).abs();
    final yStep = _niceStep(rawAxisRange / 6.0);
    final chartMinY = _snapDown(chartMinYRaw, yStep);
    final chartMaxY = _snapUp(chartMaxYRaw, yStep);
    final yDecimals = _decimalPlacesForStep(yStep);

    final maxDataTime = widget.data.isNotEmpty ? widget.data.last.timeSeconds : _visibleWindowSec;
    final visibleDuration =
      (maxX - minVisibleX)
        .clamp(_minWindowSec, math.max(maxDataTime, _minWindowSec).toDouble())
        .toDouble();
    final timelineScrollableExtent =
      math.max(0.0, maxDataTime - visibleDuration).toDouble();
    final showTimelineNavigator = !widget.isRunning && timelineScrollableExtent > 0.25;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 16, 8),
        child: Column(
          children: [
            if (!widget.isRunning)
              StoppedReviewPanel(
                isSelectionMode: _interactionMode == _ChartInteractionMode.selectZoom,
                visibleRangeLabel:
                    'Сейчас видно: ${minVisibleX.toStringAsFixed(xDecimals)}–${maxX.toStringAsFixed(xDecimals)} с',
                onFitAll: () => _fitAllX(maxDataTime),
                onResetView: _resetView,
                onToggleSelectionMode: () => _toggleInteractionMode(
                  _interactionMode == _ChartInteractionMode.selectZoom
                      ? _ChartInteractionMode.pan
                      : _ChartInteractionMode.selectZoom,
                ),
                onResetYScale: _resetYScale,
              ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final double chartWidth = constraints.maxWidth - _chartLeftReservedPx;

                        return Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (event) {
                      _handleSelectionPointerDown(event, chartWidth);
                    },
                    onPointerMove: (event) {
                      _handleSelectionPointerMove(event, chartWidth);
                    },
                    onPointerUp: (event) {
                      _handleSelectionPointerEnd(
                        event.pointer,
                        chartWidth,
                        minVisibleX,
                        maxX,
                        maxDataTime,
                      );
                    },
                    onPointerCancel: (event) {
                      if (_selectionPointerId == event.pointer) {
                        _clearSelectionPreview();
                      }
                    },
                    onPointerSignal: (signal) {
                      if (widget.isRunning || signal is! PointerScrollEvent) {
                        return;
                      }

                      final pressedKeys = HardwareKeyboard.instance.logicalKeysPressed;
                      final isShiftPressed = pressedKeys.contains(LogicalKeyboardKey.shiftLeft) ||
                          pressedKeys.contains(LogicalKeyboardKey.shiftRight);
                      final isCtrlPressed = pressedKeys.contains(LogicalKeyboardKey.controlLeft) ||
                          pressedKeys.contains(LogicalKeyboardKey.controlRight);

                      if (isShiftPressed) {
                        final fraction = signal.scrollDelta.dy > 0
                            ? _panFractionStep / 2
                            : -_panFractionStep / 2;
                        _panByFraction(fraction, minVisibleX, maxX, maxDataTime);
                        return;
                      }

                      if (isCtrlPressed) {
                        if (signal.scrollDelta.dy > 0) {
                          _zoomYByFactor(_zoomFactorOut, chartMinY, chartMaxY);
                        } else if (signal.scrollDelta.dy < 0) {
                          _zoomYByFactor(_zoomFactorIn, chartMinY, chartMaxY);
                        }
                        return;
                      }

                      if (signal.scrollDelta.dy > 0) {
                        _zoomXByFactor(_zoomFactorOut, minVisibleX, maxX, maxDataTime);
                      } else if (signal.scrollDelta.dy < 0) {
                        _zoomXByFactor(_zoomFactorIn, minVisibleX, maxX, maxDataTime);
                      }
                    },
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onDoubleTap: () {
                        if (widget.isRunning) return;
                        _resetView();
                      },
                      onHorizontalDragStart: (details) {
                        if (widget.isRunning) return;
                        if (_interactionMode == _ChartInteractionMode.selectZoom) {
                          return;
                        }
                        _startMinX = _userMinX ?? minVisibleX;
                        _startMaxX = _userMaxX ?? maxX;
                      },
                      onHorizontalDragUpdate: (details) {
                        if (widget.isRunning) return;
                        if (_interactionMode == _ChartInteractionMode.selectZoom) {
                          return;
                        }
                        if (chartWidth <= 0) return;

                        final currentRange = _startMaxX - _startMinX;
                        final timeDelta = -(details.delta.dx / chartWidth) * currentRange;
                        final clamped = _clampXWindow(
                          minX: (_userMinX ?? _startMinX) + timeDelta,
                          maxX: (_userMaxX ?? _startMaxX) + timeDelta,
                          maxDataTime: math.max(maxDataTime, _minWindowSec),
                        );
                        setState(() {
                          _userMinX = clamped.minX;
                          _userMaxX = clamped.maxX;
                        });
                      },
                      onHorizontalDragEnd: (_) {
                        if (widget.isRunning) return;
                        if (_interactionMode == _ChartInteractionMode.selectZoom) return;
                      },
                      onHorizontalDragCancel: () {
                        if (_interactionMode == _ChartInteractionMode.selectZoom) {
                          return;
                        }
                      },
                      onScaleStart: (details) {
                        if (widget.isRunning) return;
                        if (_interactionMode == _ChartInteractionMode.selectZoom) return;
                        _startMinX = _userMinX ?? minVisibleX;
                        _startMaxX = _userMaxX ?? maxX;
                        _scaleStartFocalDx = details.localFocalPoint.dx;
                      },
                      onScaleUpdate: (details) {
                        if (widget.isRunning) return;
                        final double chartWidth = constraints.maxWidth - _chartLeftReservedPx;
                        if (chartWidth <= 0) return;

                        if (_interactionMode == _ChartInteractionMode.selectZoom) return;

                        final double startRange = _startMaxX - _startMinX;
                        final bool looksLikePan = (details.scale - 1.0).abs() < 0.02;

                        if (looksLikePan) {
                          final double deltaFraction =
                              (_scaleStartFocalDx - details.localFocalPoint.dx) /
                                  chartWidth;
                          final clamped = _clampXWindow(
                            minX: _startMinX + startRange * deltaFraction,
                            maxX: _startMaxX + startRange * deltaFraction,
                            maxDataTime: math.max(maxDataTime, _minWindowSec),
                          );
                          setState(() {
                            _userMinX = clamped.minX;
                            _userMaxX = clamped.maxX;
                          });
                          return;
                        }

                        double newRange = startRange / details.scale;
                        final double safeMaxDataTime = math.max(maxDataTime, _minWindowSec);
                        if (newRange < _minWindowSec) newRange = _minWindowSec;
                        if (newRange > safeMaxDataTime) newRange = safeMaxDataTime;

                        double focalX = details.localFocalPoint.dx - 48;
                        if (focalX < 0) focalX = 0;
                        if (focalX > chartWidth) focalX = chartWidth;

                        final double focalFraction = focalX / chartWidth;
                        final double logicalFocalStart = _startMinX + startRange * focalFraction;
                        final clamped = _clampXWindow(
                          minX: logicalFocalStart - newRange * focalFraction,
                          maxX: logicalFocalStart + newRange * (1 - focalFraction),
                          maxDataTime: safeMaxDataTime,
                        );

                        setState(() {
                          _userMinX = clamped.minX;
                          _userMaxX = clamped.maxX;
                        });
                      },
                      onScaleEnd: (_) {
                        if (widget.isRunning) return;
                        if (_interactionMode == _ChartInteractionMode.selectZoom) return;
                      },
                      child: MouseRegion(
                        cursor: !widget.isRunning &&
                                _interactionMode == _ChartInteractionMode.selectZoom
                            ? SystemMouseCursors.precise
                            : SystemMouseCursors.basic,
                        child: Stack(
                          clipBehavior: Clip.hardEdge,
                          children: [
                            LineChart(
                              // duration: zero отключает tween-анимацию между кадрами.
                              // (Из исследования FL Chart: lerp() создаёт полную копию данных
                              // на каждый кадр → двойная GC-нагрузка на Celeron N4000.)
                              duration: widget.isRunning
                                  ? Duration.zero
                                  : const Duration(milliseconds: 250),
                              LineChartData(
                                clipData: const FlClipData.all(),
                                gridData: FlGridData(
                                  show: true,
                                  drawVerticalLine: true,
                                  // Сетка привязана к тем же nice-интервалам, что и подписи →
                                  // линии всегда совпадают с числами (Heckbert / LabVIEW / D3).
                                  horizontalInterval: yStep,
                                  verticalInterval: xStep,
                                  getDrawingHorizontalLine: (_) => const FlLine(
                                    color: AppColors.cardBorder,
                                    strokeWidth: 0.5,
                                  ),
                                  getDrawingVerticalLine: (_) => const FlLine(
                                    color: AppColors.cardBorder,
                                    strokeWidth: 0.5,
                                  ),
                                ),
                                titlesData: FlTitlesData(
                                  bottomTitles: AxisTitles(
                                    axisNameSize: 20,
                                    axisNameWidget: const Text(
                                      'Время, с',
                                      style: TextStyle(fontSize: 11, color: AppColors.textHint),
                                    ),
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      reservedSize: 24,
                                      interval: xStep,
                                      getTitlesWidget: (v, _) => Text(
                                        v.toStringAsFixed(xDecimals),
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: AppColors.textHint,
                                        ),
                                      ),
                                    ),
                                  ),
                                  leftTitles: AxisTitles(
                                    axisNameSize: 24,
                                    axisNameWidget: Text(
                                      widget.sensor.axisLabel,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textHint,
                                      ),
                                    ),
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      reservedSize: 48,
                                      interval: yStep,
                                      getTitlesWidget: (v, _) => Padding(
                                        padding: const EdgeInsets.only(right: 4),
                                        child: Text(
                                          v.toStringAsFixed(yDecimals),
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: AppColors.textHint,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  topTitles: const AxisTitles(
                                    sideTitles: SideTitles(showTitles: false),
                                  ),
                                  rightTitles: const AxisTitles(
                                    sideTitles: SideTitles(showTitles: false),
                                  ),
                                ),
                                borderData: FlBorderData(
                                  show: true,
                                  border: Border.all(
                                    color: AppColors.cardBorder,
                                    width: 0.5,
                                  ),
                                ),
                                minX: minVisibleX,
                                maxX: maxX,
                                minY: chartMinY,
                                maxY: chartMaxY,
                                lineBarsData: [
                                  LineChartBarData(
                                    spots: spots,
                                    // Для физики важна точность формы сигнала, а не визуальное сглаживание.
                                    // Curved-режим искажает пики/перегибы и добавляет нагрузку.
                                    isCurved: false,
                                    color: widget.sensor.color,
                                    barWidth: 2,
                                    isStrokeCapRound: true,
                                    dotData: const FlDotData(show: false),
                                    belowBarData: BarAreaData(
                                      show: true,
                                      color: widget.sensor.color.withValues(alpha: 0.06),
                                    ),
                                  ),
                                ],
                                lineTouchData: LineTouchData(
                                  enabled: !(!widget.isRunning &&
                                      _interactionMode ==
                                          _ChartInteractionMode.selectZoom),
                                  touchTooltipData: LineTouchTooltipData(
                                    getTooltipItems: (spots) => spots.map((s) {
                                      return LineTooltipItem(
                                        '${s.y.toStringAsFixed(widget.sensor.defaultDecimalPlaces)} ${widget.sensor.unit}\n${s.x.toStringAsFixed(2)} с',
                                        TextStyle(
                                          color: widget.sensor.color,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ),
                            ),
                            if (!widget.isRunning && (_hasManualXRange || _hasManualYRange))
                              Positioned(
                                top: 8,
                                right: 8,
                                child: Material(
                                  color: AppColors.surfaceLight.withValues(alpha: 0.88),
                                  borderRadius: BorderRadius.circular(20),
                                  clipBehavior: Clip.antiAlias,
                                  child: InkWell(
                                    onTap: _resetView,
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.zoom_out_map,
                                            size: 16,
                                            color: AppColors.textPrimary,
                                          ),
                                          SizedBox(width: 6),
                                          Text(
                                            'Сбросить вид',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            if (!widget.isRunning && _hasSelectionPreview)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: Builder(
                                    builder: (context) {
                                      final startDx = _selectionStartDx!;
                                      final currentDx = _selectionCurrentDx!;
                                      final left = math.min(startDx, currentDx);
                                      final width = (startDx - currentDx).abs();
                                      return Stack(
                                        children: [
                                          Positioned(
                                            left: left,
                                            top: 0,
                                            bottom: 0,
                                            width: width,
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: AppColors.primary.withValues(alpha: 0.14),
                                                border: Border.all(
                                                  color: AppColors.primary.withValues(alpha: 0.75),
                                                  width: 1.5,
                                                ),
                                              ),
                                            ),
                                          ),
                                          Positioned(
                                            left: left,
                                            top: 10,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 4,
                                              ),
                                              decoration: BoxDecoration(
                                                color: AppColors.primary.withValues(alpha: 0.95),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: const Text(
                                                'Отпустите мышь, чтобы приблизить участок',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                      },
                    ),
                  ),
                ],
              ),
            ),
            if (showTimelineNavigator) ...[
              const SizedBox(height: 10),
              _TimelineNavigator(
                totalDuration: math.max(maxDataTime, _minWindowSec).toDouble(),
                visibleStart: minVisibleX,
                visibleEnd: maxX,
                onChanged: (newStart) =>
                    _setXWindowFromStart(newStart, visibleDuration, maxDataTime),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TimelineNavigator extends StatelessWidget {
  final double totalDuration;
  final double visibleStart;
  final double visibleEnd;
  final ValueChanged<double> onChanged;

  const _TimelineNavigator({
    required this.totalDuration,
    required this.visibleStart,
    required this.visibleEnd,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final visibleDuration = (visibleEnd - visibleStart).clamp(0.1, totalDuration);
    final scrollableExtent = math.max(0.0, totalDuration - visibleDuration);

    if (scrollableExtent <= 0) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${visibleStart.toStringAsFixed(1)}–${visibleEnd.toStringAsFixed(1)} с',
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
          Row(
            children: [
              const Text(
                '0 c',
                style: TextStyle(fontSize: 9, color: AppColors.textHint),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final trackWidth = constraints.maxWidth;
                    final viewportWidth = math.max(36.0, trackWidth * (visibleDuration / totalDuration));
                    final travel = math.max(1.0, trackWidth - viewportWidth);
                    final viewportLeft = (visibleStart / scrollableExtent).clamp(0.0, 1.0) * travel;

                    double positionToStart(double left) {
                      final normalized = (left / travel).clamp(0.0, 1.0);
                      return scrollableExtent * normalized;
                    }

                    double desiredLeftFromPointer(double localDx) {
                      return (localDx - viewportWidth / 2).clamp(0.0, travel);
                    }

                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (details) {
                        final desiredLeft = desiredLeftFromPointer(details.localPosition.dx);
                        onChanged(positionToStart(desiredLeft));
                      },
                      onHorizontalDragUpdate: (details) {
                        final currentLeft = desiredLeftFromPointer(details.localPosition.dx);
                        onChanged(positionToStart(currentLeft));
                      },
                      child: SizedBox(
                        height: 18,
                        child: Stack(
                          alignment: Alignment.centerLeft,
                          children: [
                            Container(
                              height: 6,
                              decoration: BoxDecoration(
                                color: AppColors.background.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                            Positioned(
                              left: viewportLeft,
                              top: 1,
                              child: Container(
                                width: viewportWidth,
                                height: 16,
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: AppColors.primary.withValues(alpha: 0.65),
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 6,
                                      offset: Offset(0, 1),
                                    ),
                                  ],
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.drag_indicator_rounded, size: 12, color: AppColors.primary),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${totalDuration.toStringAsFixed(1)} c',
                style: const TextStyle(fontSize: 9, color: AppColors.textHint),
              ),
            ],
          ),
        ],
      ),
    );
  }
}


// ═══════════════════════════════════════════════════════════════
//  ТАБЛИЦА ДАННЫХ
// ═══════════════════════════════════════════════════════════════

class _DataTableView extends StatelessWidget {
  final List<SensorPacket> data;
  final SensorType sensor;
  final VoltageCalibration? voltageCalibration;

  const _DataTableView({required this.data, required this.sensor, this.voltageCalibration});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: sensor.color.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: sensor.color.withValues(alpha: 0.30),
                  ),
                ),
                child: Icon(
                  Icons.table_rows_outlined,
                  size: 32,
                  color: sensor.color.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Таблица пуста',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Нажмите «Старт», чтобы начать запись. Значения появятся здесь по мере поступления данных.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  height: 1.4,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Показываем последние 500 строк (прокрутка к концу)
    final display = data.length > 500 ? data.sublist(data.length - 500) : data;
    final baseIndex = data.length - display.length;

    return Card(
      child: Column(
        children: [
          // Заголовок таблицы (фиксированный)
          Container(
            color: AppColors.surfaceLight,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                const SizedBox(width: 48, child: Text('№', style: TextStyle(fontWeight: FontWeight.w600))),
                const SizedBox(width: 100, child: Text('Время, с', style: TextStyle(fontWeight: FontWeight.w600))),
                Expanded(
                  child: Text(
                    '${sensor.title}, ${sensor.unit}',
                    style: TextStyle(fontWeight: FontWeight.w600, color: sensor.color),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.cardBorder),
          // Виртуализированный список (рендерит только видимые ~15 строк)
          // (Из исследования: DataTable рендерит ВСЕ 200 строк сразу,
          // ListView.builder — только видимые. На Celeron: 10× разница.)
          Expanded(
            child: ListView.builder(
              itemCount: display.length,
              itemExtent: 40, // фиксированная высота → O(1) layout
              reverse: true, // новые данные сверху
              itemBuilder: (context, index) {
                // reverse=true → index 0 = последний элемент
                final dataIdx = display.length - 1 - index;
                final p = display[dataIdx];
                final v = SensorUtils.getCalibratedValue(p, sensor,
                    voltageCalibration: voltageCalibration);
                final rowNum = baseIndex + dataIdx + 1;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 48,
                        child: Text(
                          '$rowNum',
                          style: const TextStyle(fontSize: 13, color: AppColors.textHint),
                        ),
                      ),
                      SizedBox(
                        width: 100,
                        child: Text(
                          p.timeSeconds.toStringAsFixed(2),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          v != null ? SensorUtils.formatValue(v, sensor) : '—',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: sensor.color,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
