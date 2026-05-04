import 'package:flutter/material.dart';

import '../../../domain/entities/sensor_type.dart';
import '../../../domain/utils/sensor_utils.dart';
import '../../themes/app_theme.dart';
import 'experiment_timer.dart';

/// Главная панель управления над контентом эксперимента.
///
/// Содержит:
/// - Status pill («Идёт запись» / «Готов к записи» / «Режим анализа»)
/// - Кнопки Старт/Стоп/Калибровка/Очистить/Экспорт (Wrap-layout)
/// - Сводку справа: таймер, текущее значение, число точек
class ControlBar extends StatelessWidget {
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

  const ControlBar({
    super.key,
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
                SessionStatusPill(
                  isRunning: isRunning,
                  isReviewMode: isReviewMode,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ActionButton(
                      onPressed:
                          isRunning ? onStop : (isConnected ? onStart : null),
                      icon: primaryIcon,
                      label: primaryLabel,
                      color: isRunning ? AppColors.error : AppColors.accent,
                      filled: true,
                    ),
                    if (isReviewMode)
                      ActionButton(
                        onPressed: onExport,
                        icon: Icons.download_rounded,
                        label: 'Экспорт',
                        color: AppColors.primary,
                      )
                    else
                      ActionButton(
                        onPressed: onCalibrate,
                        icon: Icons.tune_rounded,
                        label: isCalibrated ? 'Ноль ✓' : 'Ноль',
                        color: isCalibrated ? AppColors.accent : null,
                      ),
                    ActionButton(
                      onPressed: isRunning || !hasRecordedData ? null : onClear,
                      icon: Icons.delete_outline_rounded,
                      label: isReviewMode ? 'Удалить запись' : 'Очистить',
                    ),
                    if (!isReviewMode)
                      ActionButton(
                        onPressed:
                            isRunning || !hasRecordedData ? null : onExport,
                        icon: Icons.download_rounded,
                        label: 'Экспорт',
                      ),
                    if (isReviewMode)
                      ActionButton(
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
          ExperimentSummary(
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

/// Pill-индикатор «Идёт запись» / «Готов к записи» / «Режим анализа».
class SessionStatusPill extends StatelessWidget {
  final bool isRunning;
  final bool isReviewMode;

  const SessionStatusPill({
    super.key,
    required this.isRunning,
    required this.isReviewMode,
  });

  @override
  Widget build(BuildContext context) {
    final (icon, label, color) = isRunning
        ? (Icons.fiber_manual_record_rounded, 'Идёт запись', AppColors.error)
        : isReviewMode
            ? (Icons.analytics_outlined, 'Режим анализа', AppColors.primary)
            : (
                Icons.play_circle_outline_rounded,
                'Готов к записи',
                AppColors.textSecondary
              );

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

/// Сводка эксперимента: таймер + текущее значение + число точек.
class ExperimentSummary extends StatelessWidget {
  final SensorType sensor;
  final double? currentValue;
  final int measurementCount;
  final double elapsedSeconds;
  final bool isRunning;
  final double valueBoxWidth;

  const ExperimentSummary({
    super.key,
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
        ExperimentTimer(
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

/// Унифицированная кнопка действий в [ControlBar].
///
/// `filled=true` → primary action (контрастная заливка).
/// `filled=false` → secondary (outline).
class ActionButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final String label;
  final Color? color;
  final bool filled;

  const ActionButton({
    super.key,
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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
        side: BorderSide(
            color: color?.withValues(alpha: 0.3) ?? AppColors.surfaceBright),
      ),
    );
  }
}
