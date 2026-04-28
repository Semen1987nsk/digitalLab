import 'package:flutter/material.dart';

/// Маленький trend-график за последние N точек.
///
/// Используется на главном экране в карточке датчика, под live-значением.
/// Идея взята из PASCO SPARKvue: тайл сенсора показывает не только число,
/// но и характер сигнала (растёт/падает/шумит). Для проектора в классе это
/// читается лучше, чем чистая цифра.
///
/// Реализация — лёгкий CustomPainter без fl_chart: для 60-80 точек
/// полноценный chart-движок избыточен и тяжелее.
class SensorSparkline extends StatelessWidget {
  const SensorSparkline({
    super.key,
    required this.values,
    required this.color,
    this.height = 28,
    this.strokeWidth = 1.6,
    this.fillAlpha = 0.12,
  });

  /// Значения от старого к новому. Пустой список → ничего не рисуем.
  final List<double> values;

  /// Цвет линии и заливки (заливка с alpha).
  final Color color;
  final double height;
  final double strokeWidth;
  final double fillAlpha;

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) {
      // Для одной точки/пустого набора — просто пустое поле, чтобы не
      // прыгал layout при появлении данных.
      return SizedBox(height: height);
    }
    return RepaintBoundary(
      child: SizedBox(
        height: height,
        child: CustomPaint(
          painter: _SparklinePainter(
            values: values,
            color: color,
            strokeWidth: strokeWidth,
            fillAlpha: fillAlpha,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> values;
  final Color color;
  final double strokeWidth;
  final double fillAlpha;

  _SparklinePainter({
    required this.values,
    required this.color,
    required this.strokeWidth,
    required this.fillAlpha,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2 || size.width <= 0 || size.height <= 0) return;

    var min = values.first;
    var max = values.first;
    for (final v in values) {
      if (v < min) min = v;
      if (v > max) max = v;
    }
    final range = (max - min).abs();
    // Защита от div-by-zero и плоских сигналов: рисуем по центру.
    final span = range < 1e-9 ? 1.0 : range;

    final dx = size.width / (values.length - 1);
    final path = Path();
    final fillPath = Path();

    for (int i = 0; i < values.length; i++) {
      final x = i * dx;
      final norm = (values[i] - min) / span;
      final y = size.height * (1 - norm);
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }
    fillPath.lineTo((values.length - 1) * dx, size.height);
    fillPath.close();

    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = color.withValues(alpha: fillAlpha);
    canvas.drawPath(fillPath, fillPaint);

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth
      ..color = color;
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) {
    return old.values != values ||
        old.color != color ||
        old.strokeWidth != strokeWidth ||
        old.fillAlpha != fillAlpha;
  }
}
