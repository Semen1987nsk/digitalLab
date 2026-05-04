import 'package:flutter/material.dart';

import '../../themes/app_theme.dart';

/// Таймер записи эксперимента: MM:SS.d, пульсирующая красная точка при `isRunning`.
///
/// Время приходит снаружи (`elapsedSeconds`) и обновляется родительским
/// провайдером с частотой ~30 FPS. Собственного `Timer` у виджета нет —
/// это даёт zero drift между экспериментом и таймером.
///
/// Анимация пульсации использует `SingleTickerProviderStateMixin` — один
/// `AnimationController` на виджет, корректно останавливается при `isRunning=false`.
class ExperimentTimer extends StatefulWidget {
  final double elapsedSeconds;
  final bool isRunning;

  const ExperimentTimer({
    super.key,
    required this.elapsedSeconds,
    required this.isRunning,
  });

  @override
  State<ExperimentTimer> createState() => _ExperimentTimerState();
}

class _ExperimentTimerState extends State<ExperimentTimer>
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
  void didUpdateWidget(covariant ExperimentTimer old) {
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

  /// MM:SS.d (десятые секунды).
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
                      color: AppColors.error
                          .withValues(alpha: _pulseAnim.value * 0.5),
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
              color: elapsed > 0 ? AppColors.textSecondary : AppColors.textHint,
            ),
          const SizedBox(width: 8),
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
