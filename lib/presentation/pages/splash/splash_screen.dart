import 'package:flutter/material.dart';
import '../../themes/app_theme.dart';
import '../../themes/design_tokens.dart';

class SplashScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const SplashScreen({super.key, required this.onComplete});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // ── Тайминги (вынесены в токены) ──────────────────────────────
  static const _contentDuration = DS.animSplash; // 900ms
  static const _progressDuration = DS.animSplashProgress; // 1600ms

  // Прогресс-бар стартует с небольшим опережением, когда hero-контент
  // ещё въезжает — так вся анимация сливается в один кадр намерения.
  static const _progressStartOffset = Duration(milliseconds: 120);

  // Пауза после завершения прогресса, прежде чем уступить место главному
  // экрану — даёт глазу «поймать» 100% прогресса.
  static const _completionHold = Duration(milliseconds: 180);

  late AnimationController _contentController;
  late AnimationController _progressController;

  late Animation<double> _contentOpacity;
  late Animation<double> _logoScale;
  late Animation<Offset> _contentSlide;

  @override
  void initState() {
    super.initState();

    _contentController = AnimationController(
      duration: _contentDuration,
      vsync: this,
    );

    _contentOpacity = CurvedAnimation(
      parent: _contentController,
      curve: Curves.easeOutCubic,
    );

    _logoScale = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(
        parent: _contentController,
        curve: Curves.easeOutBack,
      ),
    );

    _contentSlide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _contentController,
        curve: Curves.easeOutCubic,
      ),
    );

    _progressController = AnimationController(
      duration: _progressDuration,
      vsync: this,
    );

    _startAnimations();
  }

  /// Запускаем hero и прогресс-бар параллельно через Future.wait:
  /// — hero стартует сразу
  /// — прогресс — через _progressStartOffset, чтобы не конкурировал с
  ///   первыми миллисекундами логотипа
  /// — завершение — строго после обеих анимаций + короткая пауза для
  ///   восприятия 100%-отметки
  /// При unmount все awaits прерываются проверкой mounted — без падений.
  Future<void> _startAnimations() async {
    final heroFuture = _runController(_contentController);
    final progressFuture = () async {
      await Future<void>.delayed(_progressStartOffset);
      if (!mounted) return;
      await _runController(_progressController);
    }();

    await Future.wait<void>([heroFuture, progressFuture]);
    if (!mounted) return;

    await Future<void>.delayed(_completionHold);
    if (!mounted) return;
    widget.onComplete();
  }

  /// Обёртка над AnimationController.forward() — подавляет ошибку
  /// TickerCanceled, которая прилетает при dispose во время анимации.
  Future<void> _runController(AnimationController c) async {
    try {
      await c.forward();
    } on TickerCanceled {
      // ignore — виджет был disposed
    }
  }

  @override
  void dispose() {
    _contentController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.background,
                  Color(0xFF101722),
                  AppColors.surface,
                ],
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.3),
                  radius: 0.7,
                  colors: [
                    AppColors.primary.withValues(alpha: 0.14),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Center(
            child: AnimatedBuilder(
              animation: _contentController,
              builder: (context, child) {
                return SlideTransition(
                  position: _contentSlide,
                  child: FadeTransition(
                    opacity: _contentOpacity,
                    child: child,
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ScaleTransition(
                        scale: _logoScale,
                        child: Container(
                          width: 92,
                          height: 92,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceLight,
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.28),
                            ),
                          ),
                          child: const Icon(
                            Icons.science_outlined,
                            size: 46,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      const Text(
                        'ЛАБОСФЕРА',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2.4,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Единая платформа цифровых лабораторий',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          color: AppColors.textSecondary,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 36),
                      AnimatedBuilder(
                        animation: _progressController,
                        builder: (context, child) {
                          return Column(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: LinearProgressIndicator(
                                  value: _progressController.value,
                                  minHeight: 6,
                                  backgroundColor:
                                      AppColors.surfaceLight.withValues(alpha: 0.9),
                                  valueColor: const AlwaysStoppedAnimation<Color>(
                                    AppColors.primary,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              const Text(
                                'Подготовка лаборатории...',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 28,
            left: 0,
            right: 0,
            child: FadeTransition(
              opacity: _contentOpacity,
              child: const Text(
                'для российских школ',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textHint,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
