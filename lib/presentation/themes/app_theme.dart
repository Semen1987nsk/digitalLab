import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// Имя bundled-шрифта (см. pubspec.yaml → fonts).
///
/// Раньше использовался GoogleFonts.runtime — он качал TTF из сети при
/// первом запуске. В школьном кабинете без интернета это давало system
/// fallback с другими метриками. Теперь шрифт лежит в assets/fonts/.
const String _kFontFamily = 'Inter';

/// Цветовая палитра ЛАБОСФЕРЫ.
///
/// Основа — GitHub Dark Default; для светлой темы рассчитаны
/// аналоги с тем же brand hue, но с инвертированной поверхностью.
class AppColors {
  AppColors._();

  // ─── Тёмная (по умолчанию) ─────────────────────────────────
  static const background = Color(0xFF0D1117);
  static const surface = Color(0xFF161B22);
  static const surfaceLight = Color(0xFF21262D);
  static const surfaceBright = Color(0xFF30363D);
  static const cardBorder = Color(0xFF30363D);

  // Акценты — общие для тем
  static const primary = Color(0xFF58A6FF);
  static const primaryDark = Color(0xFF388BFD);
  static const primaryContainer = Color(0xFF1F3A5F);
  static const onPrimaryContainer = Color(0xFFCDE1FF);

  /// Brand-зелёный — используется только в логотип-градиенте и success-статусах.
  /// Не использовать как primary action color (см. ElevatedButtonTheme — там primary).
  static const accent = Color(0xFF3FB950);
  static const accentSoft = Color(0xFF238636);

  // Третичный (фиолетовый) — для outline-вариантов и version 360
  static const tertiary = Color(0xFFA371F7);
  static const tertiaryContainer = Color(0xFF3D2D63);
  static const onTertiaryContainer = Color(0xFFE5DAFF);

  // Текст (тёмная тема)
  static const textPrimary = Color(0xFFE6EDF3);
  static const textSecondary = Color(0xFF8B949E);

  /// WCAG AA 4.5:1 на тёмном фоне (раньше было #484F58 — 3.2:1)
  static const textHint = Color(0xFF6E7681);

  // Статусы
  static const success = Color(0xFF3FB950);
  static const warning = Color(0xFFD29922);
  static const error = Color(0xFFF85149);
  static const info = Color(0xFF58A6FF);
  static const disconnected = Color(0xFF6E7681);

  // Версии продукта
  static const versionBase = Color(0xFF58A6FF);
  static const version360 = Color(0xFFA371F7);
  static const version360Badge = Color(0xFF6E40C9);

  // ─── Specialized surfaces ───────────────────────────────────
  /// Splash mid-gradient stop (между background и surface).
  static const splashMidGradient = Color(0xFF101722);

  /// Subject-selection background hero (slightly bluer чем splashMid).
  static const heroBackground = Color(0xFF0F1823);

  /// Console / диагностика журнала.
  static const diagnosticsSurface = Color(0xFF0F141A);

  // ─── Осциллограф (классическая «электронная» палитра) ──────
  /// Экран осциллографа — глубже background для контраста с трассой.
  static const oscScreenBg = Color(0xFF0A0E14);
  static const oscScreenBorder = Color(0xFF1C2128);
  static const oscPanelBg = Color(0xFF0F1318);
  static const oscGridMajor = Color(0xFF1C2833);
  static const oscGridMinor = Color(0xFF121A22);
  static const oscGridCenter = Color(0xFF2A3540);

  /// Канал 1 — жёлтый (стандарт de-facto в осциллографах).
  static const oscChannel1 = Color(0xFFFFEB3B);

  /// Канал 2 — голубой (стандарт de-facto).
  static const oscChannel2 = Color(0xFF00BFFF);

  // ─── Port-types ─────────────────────────────────────────────
  static const portBluetooth = Color(0xFF7C6DFF);
  static const portVirtual = Color(0xFFA371F7);

  // ─── Светлая тема (для класса с проектором) ────────────────
  static const lightBackground = Color(0xFFF6F8FA);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceLight = Color(0xFFF0F3F6);
  static const lightSurfaceBright = Color(0xFFE6EAEF);
  static const lightCardBorder = Color(0xFFD0D7DE);
  static const lightTextPrimary = Color(0xFF1F2328);
  static const lightTextSecondary = Color(0xFF59636E);
  static const lightTextHint = Color(0xFF6E7781);
  static const lightPrimaryContainer = Color(0xFFD8E6FF);
  static const lightOnPrimaryContainer = Color(0xFF0B2A52);
  static const lightTertiaryContainer = Color(0xFFEEDFFF);
  static const lightOnTertiaryContainer = Color(0xFF311A66);
}

/// Адаптивная палитра. Возвращает цвета поверхностей и текста, которые
/// зависят от текущей темы (через `Theme.of(context).brightness`).
///
/// Использовать вместо хардкода `AppColors.surface` в виджетах, которые
/// должны корректно выглядеть в обеих темах.
class AppPalette {
  final Color background;
  final Color surface;
  final Color surfaceLight;
  final Color surfaceBright;
  final Color cardBorder;
  final Color textPrimary;
  final Color textSecondary;
  final Color textHint;

  const AppPalette._({
    required this.background,
    required this.surface,
    required this.surfaceLight,
    required this.surfaceBright,
    required this.cardBorder,
    required this.textPrimary,
    required this.textSecondary,
    required this.textHint,
  });

  static const dark = AppPalette._(
    background: AppColors.background,
    surface: AppColors.surface,
    surfaceLight: AppColors.surfaceLight,
    surfaceBright: AppColors.surfaceBright,
    cardBorder: AppColors.cardBorder,
    textPrimary: AppColors.textPrimary,
    textSecondary: AppColors.textSecondary,
    textHint: AppColors.textHint,
  );

  static const light = AppPalette._(
    background: AppColors.lightBackground,
    surface: AppColors.lightSurface,
    surfaceLight: AppColors.lightSurfaceLight,
    surfaceBright: AppColors.lightSurfaceBright,
    cardBorder: AppColors.lightCardBorder,
    textPrimary: AppColors.lightTextPrimary,
    textSecondary: AppColors.lightTextSecondary,
    textHint: AppColors.lightTextHint,
  );
}

/// `context.palette` — короткий доступ к адаптивной палитре.
extension PaletteExtension on BuildContext {
  AppPalette get palette => Theme.of(this).brightness == Brightness.dark
      ? AppPalette.dark
      : AppPalette.light;
}

class AppTheme {
  AppTheme._();

  // ═══════════════════════════════════════════════════════════
  //  ТЁМНАЯ ТЕМА (по умолчанию)
  //
  //  ColorScheme заполнен по полному набору ролей Material 3:
  //  primary (синий бренд) — primary actions
  //  secondary (зелёный) — success-зона, brand accent
  //  tertiary (фиолетовый) — нейтральный outline, version 360
  //  *Container — tonal backgrounds для chip/banner/FilledButton.tonal
  //  surfaceContainer* — tonal-поверхности MD3 (вместо elevation overlay)
  // ═══════════════════════════════════════════════════════════
  static ThemeData get darkTheme {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: AppColors.primary,
      onPrimary: Colors.white,
      primaryContainer: AppColors.primaryContainer,
      onPrimaryContainer: AppColors.onPrimaryContainer,
      secondary: AppColors.accent,
      onSecondary: Colors.white,
      secondaryContainer: AppColors.accentSoft,
      onSecondaryContainer: Color(0xFFD8F5DD),
      tertiary: AppColors.tertiary,
      onTertiary: Colors.white,
      tertiaryContainer: AppColors.tertiaryContainer,
      onTertiaryContainer: AppColors.onTertiaryContainer,
      error: AppColors.error,
      onError: Colors.white,
      errorContainer: Color(0xFF5A1F1F),
      onErrorContainer: Color(0xFFFFD9D6),
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      onSurfaceVariant: AppColors.textSecondary,
      surfaceContainerLowest: AppColors.background,
      surfaceContainerLow: AppColors.surface,
      surfaceContainer: AppColors.surface,
      surfaceContainerHigh: AppColors.surfaceLight,
      surfaceContainerHighest: AppColors.surfaceBright,
      outline: AppColors.cardBorder,
      outlineVariant: AppColors.surfaceBright,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: AppColors.textPrimary,
      onInverseSurface: AppColors.background,
      inversePrimary: AppColors.primaryDark,
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: scheme,
      fontFamily: _kFontFamily,
    );
    return _applyShared(
      base,
      textPrimary: AppColors.textPrimary,
      textSecondary: AppColors.textSecondary,
      textHint: AppColors.textHint,
      surface: AppColors.surface,
      surfaceLight: AppColors.surfaceLight,
      surfaceBright: AppColors.surfaceBright,
      cardBorder: AppColors.cardBorder,
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  СВЕТЛАЯ ТЕМА (для проекторов)
  // ═══════════════════════════════════════════════════════════
  static ThemeData get lightTheme {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.primary,
      onPrimary: Colors.white,
      primaryContainer: AppColors.lightPrimaryContainer,
      onPrimaryContainer: AppColors.lightOnPrimaryContainer,
      secondary: AppColors.accentSoft,
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFD8F5DD),
      onSecondaryContainer: Color(0xFF0F3318),
      tertiary: AppColors.tertiary,
      onTertiary: Colors.white,
      tertiaryContainer: AppColors.lightTertiaryContainer,
      onTertiaryContainer: AppColors.lightOnTertiaryContainer,
      error: AppColors.error,
      onError: Colors.white,
      errorContainer: Color(0xFFFFD9D6),
      onErrorContainer: Color(0xFF5A1F1F),
      surface: AppColors.lightSurface,
      onSurface: AppColors.lightTextPrimary,
      onSurfaceVariant: AppColors.lightTextSecondary,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: AppColors.lightBackground,
      surfaceContainer: AppColors.lightSurfaceLight,
      surfaceContainerHigh: AppColors.lightSurfaceLight,
      surfaceContainerHighest: AppColors.lightSurfaceBright,
      outline: AppColors.lightCardBorder,
      outlineVariant: AppColors.lightSurfaceBright,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: AppColors.lightTextPrimary,
      onInverseSurface: AppColors.lightBackground,
      inversePrimary: AppColors.primary,
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.lightBackground,
      colorScheme: scheme,
      fontFamily: _kFontFamily,
    );
    return _applyShared(
      base,
      textPrimary: AppColors.lightTextPrimary,
      textSecondary: AppColors.lightTextSecondary,
      textHint: AppColors.lightTextHint,
      surface: AppColors.lightSurface,
      surfaceLight: AppColors.lightSurfaceLight,
      surfaceBright: AppColors.lightSurfaceBright,
      cardBorder: AppColors.lightCardBorder,
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  ОБЩАЯ ТИПОГРАФИКА И КОМПОНЕНТЫ
  //
  //  Шрифт — Inter v4, bundled в assets/fonts/ (см. pubspec.yaml).
  //  Cyrillic-набор полный, tabular figures поддерживаются через
  //  FontFeature. Раньше использовался GoogleFonts.runtime, но в школе
  //  без интернета он давал system fallback. fontFamily задан в
  //  ThemeData выше, поэтому здесь TextStyle без явного fontFamily.
  // ═══════════════════════════════════════════════════════════
  static ThemeData _applyShared(
    ThemeData base, {
    required Color textPrimary,
    required Color textSecondary,
    required Color textHint,
    required Color surface,
    required Color surfaceLight,
    required Color surfaceBright,
    required Color cardBorder,
  }) {
    final textTheme = base.textTheme.copyWith(
      headlineLarge: TextStyle(
        fontSize: 36,
        fontWeight: FontWeight.w800,
        color: textPrimary,
        letterSpacing: -1.2,
        height: 1.1,
      ),
      headlineMedium: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: textPrimary,
        letterSpacing: -0.5,
      ),
      headlineSmall: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: textPrimary,
        letterSpacing: -0.3,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: textPrimary,
        letterSpacing: -0.2,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        color: textPrimary,
        height: 1.5,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        color: textSecondary,
        height: 1.5,
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        color: textHint,
        height: 1.4,
      ),
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: textPrimary,
        letterSpacing: 0.1,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: textSecondary,
      ),
    );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 1,
        iconTheme: IconThemeData(color: textPrimary, size: 24),
        actionsIconTheme: IconThemeData(color: textPrimary, size: 24),
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: textPrimary,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DS.rLg),
          side: BorderSide(color: cardBorder, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          // Primary action — синий (бренд primary). Раньше был `accent`
          // (#3FB950) — тот же зелёный, что у success-статусов; визуально
          // путало «нажми кнопку» и «всё хорошо». Теперь зелёный остался
          // только для статусов и FilledButton.tonal-варианта.
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(120, 48),
          padding: const EdgeInsets.symmetric(horizontal: DS.sp6, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DS.rMd),
          ),
          elevation: 0,
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: DS.sp5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DS.rMd),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          minimumSize: const Size(100, 44),
          padding: const EdgeInsets.symmetric(horizontal: DS.sp5, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DS.rMd),
          ),
          side: BorderSide(color: surfaceBright),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: DS.sp4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DS.rSm),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceLight,
        selectedColor: AppColors.primary.withValues(alpha: 0.15),
        labelStyle: TextStyle(fontSize: 13, color: textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DS.rSm),
        ),
        side: BorderSide(color: cardBorder),
      ),
      dividerTheme: DividerThemeData(
        color: cardBorder,
        thickness: 1,
        space: 1,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DS.rXl),
        ),
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
        contentTextStyle: TextStyle(
          fontSize: 14,
          color: textSecondary,
          height: 1.5,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceBright,
        contentTextStyle: TextStyle(
          fontSize: 14,
          color: textPrimary,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DS.rMd),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: surfaceBright,
          borderRadius: BorderRadius.circular(DS.rSm),
          border: Border.all(color: cardBorder),
        ),
        textStyle: TextStyle(
          fontSize: 12,
          color: textPrimary,
        ),
        padding:
            const EdgeInsets.symmetric(horizontal: DS.sp3, vertical: DS.sp2),
        waitDuration: const Duration(milliseconds: 500),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.primary;
          return surfaceBright;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.primary.withValues(alpha: 0.4);
          }
          return surfaceLight;
        }),
      ),
      iconTheme: IconThemeData(color: textSecondary, size: 24),
      visualDensity: VisualDensity.standard,
    );
  }
}
