import 'package:flutter/material.dart';

import '../../../domain/entities/sensor_type.dart';
import '../../../domain/utils/sensor_utils.dart';
import '../../themes/app_theme.dart';
import '../../widgets/sensor_icon.dart';

/// Крупное число во весь экран — для демонстрации с проектора.
class BigDisplay extends StatelessWidget {
  final double? value;
  final SensorType sensor;

  const BigDisplay({super.key, required this.value, required this.sensor});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SensorIcon(
              sensor: sensor,
              size: 48,
              color: sensor.color.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text(
            sensor.title,
            style:
                const TextStyle(fontSize: 20, color: AppColors.textSecondary),
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
                  value != null ? SensorUtils.formatValue(value!, sensor) : '—',
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
