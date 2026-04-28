import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../themes/design_tokens.dart';

/// Один общий «пульс» (0.0..1.0..0.0) для всего приложения.
///
/// Раньше каждый _ConnectionBadge / _PulseDot заводил собственный
/// AnimationController. На сетке из 12 датчиков это давало 12
/// vsync-таймеров. PulseClock даёт один Ticker, к нему подписываются
/// все потребители через [animation]. Если в дереве нет ни одного
/// слушателя — Ticker автоматически останавливается.
class PulseClock {
  PulseClock._();
  static final PulseClock _instance = PulseClock._();
  static PulseClock get instance => _instance;

  final ValueNotifier<double> _value = ValueNotifier(0);
  Ticker? _ticker;

  /// 0 → 1 → 0 циклически с периодом [DS.animPulse].
  ValueListenable<double> get animation => _value;

  void _ensureRunning() {
    if (_ticker != null && _ticker!.isActive) return;
    _ticker ??= Ticker(_onTick, debugLabel: 'PulseClock');
    _ticker!.start();
  }

  void _onTick(Duration elapsed) {
    final periodMs = DS.animPulse.inMilliseconds;
    final t = (elapsed.inMilliseconds % periodMs) / periodMs;
    // Треугольник 0..1..0 для эффекта pulse (вместо синуса — дешевле).
    final tri = t < 0.5 ? t * 2 : 2 - t * 2;
    _value.value = 0.5 + tri * 0.5; // 0.5..1.0..0.5 → видимая «дышащая» зона
  }

  /// Подписаться. Возвращает виджет, который перестраивает ребёнка
  /// при смене значения. Использовать вместо AnimatedBuilder.
  Widget listen({required ValueWidgetBuilder<double> builder, Widget? child}) {
    _ensureRunning();
    return ValueListenableBuilder<double>(
      valueListenable: _value,
      builder: builder,
      child: child,
    );
  }
}
