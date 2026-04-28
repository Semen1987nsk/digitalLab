import 'package:flutter/material.dart';

import '../themes/design_tokens.dart';

/// Хелпер-обёртка: на mouse hover приподнимает дочерний виджет на
/// заданное число пикселей и меняет курсор на pointer.
///
/// До появления этого виджета один и тот же паттерн дублировался в
/// _SensorCard, _HoverablePortCard и других интерактивных карточках.
/// Параметры — в DS-токенах, чтобы поведение оставалось согласованным
/// по всему приложению (160ms easeOutCubic — тактовый «отклик» десктопа).
class HoverLift extends StatefulWidget {
  const HoverLift({
    super.key,
    required this.child,
    this.lift = -2.0,
    this.cursor = SystemMouseCursors.click,
    this.duration = DS.animFast,
    this.curve = DS.curveDefault,
    this.onHoverChanged,
  });

  /// Высота подъёма в пикселях (отрицательное → вверх).
  final double lift;

  /// Курсор при наведении.
  final MouseCursor cursor;
  final Duration duration;
  final Curve curve;

  /// Callback, чтобы потребитель мог отреагировать на hover (например,
  /// поменять border-цвет).
  final ValueChanged<bool>? onHoverChanged;

  final Widget child;

  @override
  State<HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<HoverLift> {
  bool _hover = false;

  void _setHover(bool v) {
    if (_hover == v) return;
    setState(() => _hover = v);
    widget.onHoverChanged?.call(v);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.cursor,
      onEnter: (_) => _setHover(true),
      onExit: (_) => _setHover(false),
      child: AnimatedContainer(
        duration: widget.duration,
        curve: widget.curve,
        transform: _hover
            ? (Matrix4.identity()
              ..translateByDouble(0.0, widget.lift, 0.0, 1.0))
            : Matrix4.identity(),
        child: widget.child,
      ),
    );
  }
}
