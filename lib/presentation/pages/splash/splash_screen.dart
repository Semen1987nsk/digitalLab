import 'package:flutter/material.dart';
import '../../themes/app_theme.dart';

class SplashScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const SplashScreen({super.key, required this.onComplete});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _contentController;
  late AnimationController _progressController;

  late Animation<double> _contentOpacity;
  late Animation<double> _logoScale;
  late Animation<Offset> _contentSlide;

  @override
  void initState() {
    super.initState();

    _contentController = AnimationController(
      duration: const Duration(milliseconds: 900),
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
      duration: const Duration(milliseconds: 1600),
      vsync: this,
    );

    _startAnimations();
  }

  Future<void> _startAnimations() async {
    _contentController.forward();
    await Future.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
    await _progressController.forward();
    await Future.delayed(const Duration(milliseconds: 180));
    if (!mounted) return;
    widget.onComplete();
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
