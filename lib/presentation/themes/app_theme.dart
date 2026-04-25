import 'package:flutter/material.dart';

/// Семантические цвета приложения.
///
/// Статусные цвета (primary/accent/success/warning/error/info) одинаковы
/// в обеих темах для сохранения семантики. Поверхности и текст
/// адаптируются — см. [AppPalette].
class AppColors {
  AppColors._();

  // ── Акценты (brightness-neutral) ────────────────────────────────
  static const primary = Color(0xFF58A6FF);
  static const primaryDark = Color(0xFF388BFD);
  static const accent = Color(0xFF3FB950);
  static const accentSoft = Color(0xFF238636);

  // ── Статусы (brightness-neutral) ────────────────────────────────
  static const success = Color(0xFF3FB950);
  static const warning = Color(0xFFD29922);
  static const error = Color(0xFFF85149);
  static const info = Color(0xFF58A6FF);
  static const disconnected = Color(0xFF484F58);

  // ── Темная палитра (legacy доступ — используйте context.palette) ─
  static const background = Color(0xFF0D1117);
  static const surface = Color(0xFF161B22);
  static const surfaceLight = Color(0xFF21262D);
  static const surfaceBright = Color(0xFF30363D);
  static const cardBorder = Color(0xFF30363D);
  static const textPrimary = Color(0xFFE6EDF3);
  static const textSecondary = Color(0xFF8B949E);
  static const textHint = Color(0xFF484F58);
}

/// Палитра поверхностей и текста, привязанная к яркости темы.
///
/// Используйте через `context.palette` вместо прямых обращений к
/// [AppColors.background] и т.п., чтобы поддержать переключение темы.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.background,
    required this.surface,
    required this.surfaceLight,
    required this.surfaceBright,
    required this.cardBorder,
    required this.textPrimary,
    required this.textSecondary,
    required this.textHint,
  });

  final Color background;
  final Color surface;
  final Color surfaceLight;
  final Color surfaceBright;
  final Color cardBorder;
  final Color textPrimary;
  final Color textSecondary;
  final Color textHint;

  static const dark = AppPalette(
    background: Color(0xFF0D1117),
    surface: Color(0xFF161B22),
    surfaceLight: Color(0xFF21262D),
    surfaceBright: Color(0xFF30363D),
    cardBorder: Color(0xFF30363D),
    textPrimary: Color(0xFFE6EDF3),
    textSecondary: Color(0xFF8B949E),
    textHint: Color(0xFF484F58),
  );

  static const light = AppPalette(
    background: Color(0xFFF6F8FA),
    surface: Color(0xFFFFFFFF),
    surfaceLight: Color(0xFFF0F3F6),
    surfaceBright: Color(0xFFE1E4E8),
    cardBorder: Color(0xFFD0D7DE),
    textPrimary: Color(0xFF1F2328),
    textSecondary: Color(0xFF59636E),
    textHint: Color(0xFF8C959F),
  );

  @override
  AppPalette copyWith({
    Color? background,
    Color? surface,
    Color? surfaceLight,
    Color? surfaceBright,
    Color? cardBorder,
    Color? textPrimary,
    Color? textSecondary,
    Color? textHint,
  }) {
    return AppPalette(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceLight: surfaceLight ?? this.surfaceLight,
      surfaceBright: surfaceBright ?? this.surfaceBright,
      cardBorder: cardBorder ?? this.cardBorder,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textHint: textHint ?? this.textHint,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceLight: Color.lerp(surfaceLight, other.surfaceLight, t)!,
      surfaceBright: Color.lerp(surfaceBright, other.surfaceBright, t)!,
      cardBorder: Color.lerp(cardBorder, other.cardBorder, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textHint: Color.lerp(textHint, other.textHint, t)!,
    );
  }
}

/// Удобный доступ к палитре: `context.palette.surface`.
extension AppPaletteContext on BuildContext {
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.dark;
}

class AppTheme {
  AppTheme._();

  static ThemeData get darkTheme => _buildTheme(Brightness.dark);
  static ThemeData get lightTheme => _buildTheme(Brightness.light);

  static ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.accent,
      onSecondary: Colors.white,
      error: AppColors.error,
      onError: Colors.white,
      surface: palette.surface,
      onSurface: palette.textPrimary,
      surfaceContainerHighest: palette.surfaceBright,
      outline: palette.cardBorder,
      outlineVariant: palette.surfaceLight,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: palette.background,
      colorScheme: colorScheme,
      extensions: [palette],

      appBarTheme: AppBarTheme(
        backgroundColor: palette.surface,
        foregroundColor: palette.textPrimary,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 1,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: palette.textPrimary,
          letterSpacing: -0.5,
        ),
      ),

      cardTheme: CardThemeData(
        color: palette.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: palette.cardBorder, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          minimumSize: const Size(120, 52),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 0,
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.textPrimary,
          minimumSize: const Size(100, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          side: BorderSide(color: palette.surfaceBright),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: palette.surfaceLight,
        selectedColor: AppColors.primary.withValues(alpha: 0.15),
        labelStyle: TextStyle(fontSize: 14, color: palette.textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        side: BorderSide(color: palette.cardBorder),
      ),

      dividerTheme: DividerThemeData(
        color: palette.cardBorder,
        thickness: 1,
        space: 1,
      ),

      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 400),
        showDuration: const Duration(seconds: 4),
        decoration: BoxDecoration(
          color: isDark
              ? palette.surfaceBright
              : const Color(0xFF1F2328).withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: palette.cardBorder),
        ),
        textStyle: TextStyle(
          fontSize: 12,
          color: isDark ? palette.textPrimary : Colors.white,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),

      textTheme: TextTheme(
        headlineLarge: TextStyle(
          fontSize: 48,
          fontWeight: FontWeight.w700,
          color: palette.textPrimary,
          letterSpacing: -1.5,
        ),
        headlineMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w600,
          color: palette.textPrimary,
          letterSpacing: -0.5,
        ),
        headlineSmall: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: palette.textPrimary,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: palette.textPrimary,
          letterSpacing: -0.3,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: palette.textPrimary,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          color: palette.textPrimary,
          height: 1.5,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          color: palette.textSecondary,
          height: 1.5,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          color: palette.textHint,
          height: 1.4,
        ),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: palette.textPrimary,
          letterSpacing: 0.1,
        ),
        labelMedium: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: palette.textSecondary,
        ),
      ),
    );
  }
}
