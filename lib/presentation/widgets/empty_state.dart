import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../themes/app_theme.dart';
import '../themes/design_tokens.dart';

/// Тип иллюстрации для пустого состояния.
enum EmptyStateIllustration {
  /// Осциллограмма — для истории экспериментов / отсутствующих записей.
  waveform,

  /// Датчик с расходящимися волнами — для BLE / списка устройств.
  sensorWaves,

  /// Сетка с пустым экраном — для общих пустых состояний.
  emptyGrid,
}

/// Унифицированный пустой стейт с фирменной иллюстрацией.
///
/// Раньше пустые экраны (HistoryPage, BleDevicePage) ограничивались
/// иконкой 96x96 в круге — это рабочий минимум, но не уровень Vernier
/// или PASCO. Теперь — лёгкая stylized-иллюстрация через CustomPainter.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.message,
    required this.illustration,
    this.action,
    this.illustrationSize = 180,
    this.accent,
  });

  final String title;
  final String message;
  final EmptyStateIllustration illustration;
  final Widget? action;
  final double illustrationSize;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final accentColor = accent ?? AppColors.primary;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(DS.sp6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: illustrationSize,
                height: illustrationSize,
                child: CustomPaint(
                  painter: _EmptyStatePainter(
                    illustration: illustration,
                    accent: accentColor,
                    surface: palette.surface,
                    grid: palette.cardBorder,
                  ),
                ),
              ),
              const SizedBox(height: DS.sp5),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: palette.textPrimary,
                    ),
              ),
              const SizedBox(height: DS.sp2),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: palette.textSecondary,
                      height: 1.5,
                    ),
              ),
              if (action != null) ...[
                const SizedBox(height: DS.sp6),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyStatePainter extends CustomPainter {
  final EmptyStateIllustration illustration;
  final Color accent;
  final Color surface;
  final Color grid;

  _EmptyStatePainter({
    required this.illustration,
    required this.accent,
    required this.surface,
    required this.grid,
  });

  @override
  void paint(Canvas canvas, Size size) {
    switch (illustration) {
      case EmptyStateIllustration.waveform:
        _paintWaveform(canvas, size);
      case EmptyStateIllustration.sensorWaves:
        _paintSensorWaves(canvas, size);
      case EmptyStateIllustration.emptyGrid:
        _paintEmptyGrid(canvas, size);
    }
  }

  // Стилизованная осциллограмма: рамка-экран + затухающая синусоида.
  void _paintWaveform(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final cardRect = Rect.fromCenter(
      center: rect.center,
      width: size.width * 0.86,
      height: size.height * 0.62,
    );

    // Фоновый круг-glow
    canvas.drawCircle(
      rect.center,
      size.width * 0.42,
      Paint()..color = accent.withValues(alpha: 0.08),
    );

    // Карточка-экран
    final cardPaint = Paint()..color = surface;
    final cardBorder = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = grid;
    final cardRRect = RRect.fromRectAndRadius(
      cardRect,
      const Radius.circular(DS.rLg),
    );
    canvas.drawRRect(cardRRect, cardPaint);
    canvas.drawRRect(cardRRect, cardBorder);

    // Сетка внутри экрана (3×3)
    final gridPaint = Paint()
      ..strokeWidth = 0.6
      ..color = grid.withValues(alpha: 0.6);
    for (int i = 1; i < 4; i++) {
      final x = cardRect.left + cardRect.width * i / 4;
      canvas.drawLine(
        Offset(x, cardRect.top + 8),
        Offset(x, cardRect.bottom - 8),
        gridPaint,
      );
    }
    for (int i = 1; i < 3; i++) {
      final y = cardRect.top + cardRect.height * i / 3;
      canvas.drawLine(
        Offset(cardRect.left + 8, y),
        Offset(cardRect.right - 8, y),
        gridPaint,
      );
    }

    // Синусоида с лёгким затуханием
    final wavePath = Path();
    final cy = cardRect.center.dy;
    final amp = cardRect.height * 0.30;
    const points = 60;
    for (int i = 0; i <= points; i++) {
      final t = i / points;
      final x = cardRect.left + 10 + (cardRect.width - 20) * t;
      final decay = math.exp(-t * 1.2);
      final y = cy + math.sin(t * math.pi * 4) * amp * decay;
      if (i == 0) {
        wavePath.moveTo(x, y);
      } else {
        wavePath.lineTo(x, y);
      }
    }
    final wavePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = accent;
    canvas.drawPath(wavePath, wavePaint);

    // Точка-«начало записи»
    canvas.drawCircle(
      Offset(cardRect.left + 10, cy),
      3.2,
      Paint()..color = accent,
    );
  }

  // Сенсор с расходящимися волнами (BLE / radio).
  void _paintSensorWaves(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Внешние круги-волны
    final wavePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    for (int i = 1; i <= 3; i++) {
      final radius = size.width * 0.16 * i;
      wavePaint.color = accent.withValues(alpha: 0.45 / i);
      canvas.drawCircle(center, radius, wavePaint);
    }

    // Корпус датчика
    final bodyRect = Rect.fromCenter(
      center: center,
      width: size.width * 0.30,
      height: size.height * 0.30,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bodyRect, const Radius.circular(DS.rMd)),
      Paint()..color = surface,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bodyRect, const Radius.circular(DS.rMd)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = grid,
    );

    // «LED» датчика
    canvas.drawCircle(
      center.translate(0, -bodyRect.height * 0.22),
      bodyRect.height * 0.10,
      Paint()..color = accent,
    );
    canvas.drawCircle(
      center.translate(0, -bodyRect.height * 0.22),
      bodyRect.height * 0.10,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = accent.withValues(alpha: 0.4),
    );
  }

  // Пустая сетка с лупой/курсором.
  void _paintEmptyGrid(Canvas canvas, Size size) {
    final padding = size.width * 0.12;
    final inner = Rect.fromLTWH(
      padding,
      padding,
      size.width - padding * 2,
      size.height - padding * 2,
    );

    final gridPaint = Paint()
      ..strokeWidth = 0.8
      ..color = grid.withValues(alpha: 0.6);
    const cells = 5;
    for (int i = 0; i <= cells; i++) {
      final t = i / cells;
      canvas.drawLine(
        Offset(inner.left + inner.width * t, inner.top),
        Offset(inner.left + inner.width * t, inner.bottom),
        gridPaint,
      );
      canvas.drawLine(
        Offset(inner.left, inner.top + inner.height * t),
        Offset(inner.right, inner.top + inner.height * t),
        gridPaint,
      );
    }

    // Подсвеченная клетка
    final cellSize = inner.width / cells;
    final highlightRect = Rect.fromLTWH(
      inner.left + cellSize * 2,
      inner.top + cellSize * 2,
      cellSize,
      cellSize,
    );
    canvas.drawRect(
      highlightRect,
      Paint()..color = accent.withValues(alpha: 0.18),
    );
    canvas.drawRect(
      highlightRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = accent,
    );
  }

  @override
  bool shouldRepaint(covariant _EmptyStatePainter old) {
    return old.illustration != illustration ||
        old.accent != accent ||
        old.surface != surface ||
        old.grid != grid;
  }
}
