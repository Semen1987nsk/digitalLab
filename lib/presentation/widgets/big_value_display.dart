import 'package:flutter/material.dart';
import '../../../domain/entities/sensor_type.dart';

// ═══════════════════════════════════════════════════════════════
//  ВИДЖЕТ «ТАБЛО» — крупное значение для проектора / демонстрации
//
//  Используется на главном экране и отдельно для полноэкранного
//  режима отображения одного показателя.
// ═══════════════════════════════════════════════════════════════

class BigValueDisplay extends StatelessWidget {
  /// Текущее значение или null если нет данных.
  final double? value;

  /// Тип датчика (цвет, единица, округление).
  final SensorType sensor;

  /// Размер шрифта основного числа.
  final double fontSize;

  /// Показывать ли подзаголовок с названием.
  final bool showLabel;

  const BigValueDisplay({
    super.key,
    required this.value,
    required this.sensor,
    this.fontSize = 80,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    final formatted = value != null
        ? value!.toStringAsFixed(sensor.defaultDecimalPlaces)
        : '—';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showLabel) ...[
          Text(
            sensor.title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: sensor.color.withValues(alpha: 0.7),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
        ],
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                formatted,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w700,
                  color: sensor.color,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  letterSpacing: -2,
                  height: 1.0,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                sensor.unit,
                style: TextStyle(
                  fontSize: fontSize * 0.3,
                  fontWeight: FontWeight.w500,
                  color: sensor.color.withValues(alpha: 0.55),
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
//  АНИМИРОВАННОЕ ЧИСЛО — плавный переход значений
// ═══════════════════════════════════════════════════════════════

class AnimatedBigValue extends StatelessWidget {
  final double? value;
  final SensorType sensor;
  final double fontSize;

  const AnimatedBigValue({
    super.key,
    required this.value,
    required this.sensor,
    this.fontSize = 80,
  });

  @override
  Widget build(BuildContext context) {
    if (value == null) {
      return BigValueDisplay(value: null, sensor: sensor, fontSize: fontSize);
    }

    return TweenAnimationBuilder<double>(
      tween: Tween(end: value!),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      builder: (_, animatedValue, __) => BigValueDisplay(
        value: animatedValue,
        sensor: sensor,
        fontSize: fontSize,
      ),
    );
  }
}
