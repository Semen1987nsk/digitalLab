import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/di/providers.dart';
import 'core/logging.dart';
import 'data/datasources/local/experiment_autosave_service.dart';
import 'domain/entities/subject_area.dart';
import 'presentation/pages/platform/subject_selection_page.dart';
import 'presentation/pages/shell/app_shell.dart';
import 'presentation/pages/splash/splash_screen.dart';
import 'presentation/themes/app_theme.dart';
import 'presentation/themes/theme_mode_provider.dart';

// ═══════════════════════════════════════════════════════════════
//  ЦИФРОВАЯ ЛАБОРАТОРИЯ ПО ФИЗИКЕ — «Лабосфера»
//
//  Точка входа приложения.
//  • ProviderScope — корень Riverpod
//  • AppTheme — тёмная тема
// ═══════════════════════════════════════════════════════════════

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // P0 FIX: инициализируем файловый логгер ДО всего остального
      await Logger.init();

      // Ловим все необработанные ошибки Flutter — приложение НЕ падает
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        Logger.error(
          'FlutterError: ${details.exceptionAsString()}',
          details.exception,
          details.stack,
        );
      };

      // Вместо красного экрана смерти — информативное сообщение на русском
      ErrorWidget.builder = (FlutterErrorDetails details) {
        return Material(
          color: const Color(0xFF1E1E1E),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 48,
                    color: Color(0xFFFFB74D),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Ошибка отображения',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    details.exceptionAsString(),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white38,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Перезапустите приложение или обратитесь к учителю',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: Colors.white24),
                  ),
                ],
              ),
            ),
          ),
        );
      };

      PlatformDispatcher.instance.onError = (error, stack) {
        Logger.error('PlatformDispatcherError', error, stack);
        return true;
      };

      runApp(const ProviderScope(child: DigitalLabApp()));
    },
    (error, stack) {
      Logger.error('ZoneError', error, stack);
    },
  );
}

class DigitalLabApp extends ConsumerStatefulWidget {
  const DigitalLabApp({super.key});

  @override
  ConsumerState<DigitalLabApp> createState() => _DigitalLabAppState();
}

class _DigitalLabAppState extends ConsumerState<DigitalLabApp> {
  bool _showSplash = true;
  SubjectArea? _selectedSubject;
  RecoveredExperimentSession? _pendingRecovery;

  @override
  void initState() {
    super.initState();
    unawaited(_initializeStartup());
  }

  Future<void> _initializeStartup() async {
    try {
      final autosave = ref.read(autosaveServiceProvider);
      final recovery = await autosave.detectRecoverableSession();
      if (!mounted) return;
      setState(() {
        _pendingRecovery = recovery;
      });
    } catch (e) {
      debugPrint('Main: ошибка startup recovery: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: 'ЛАБОСФЕРА — Цифровые лаборатории',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: _showSplash
          ? SplashScreen(
              onComplete: () {
                setState(() {
                  _showSplash = false;
                });
              },
            )
          : _selectedSubject == null
              ? SubjectSelectionPage(
                  onSubjectSelected: (subject) {
                    setState(() {
                      _selectedSubject = subject;
                    });
                  },
                )
              : AppShell(
                  subject: _selectedSubject!,
                  onSubjectSelectionRequested: () {
                    setState(() {
                      _selectedSubject = null;
                    });
                  },
                  pendingRecovery: _pendingRecovery,
                  onRecoveryHandled: () {
                    if (!mounted || _pendingRecovery == null) return;
                    setState(() {
                      _pendingRecovery = null;
                    });
                  },
                ),
    );
  }
}
