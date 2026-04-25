import 'package:flutter/material.dart';

/// Design tokens для всего приложения.
/// Используй вместо магических чисел — это основа visual consistency.
///
/// Источник правды для spacing, radius, durations, icon sizes и других
/// визуальных констант. Любое новое hardcoded значение — red flag:
/// скорее всего, нужно добавить токен сюда.
class DS {
  DS._();

  // ── Spacing (8px grid) ──────────────────────────────────────────
  /// 4px — микро-gap между иконкой и текстом
  static const double sp1 = 4;

  /// 8px — базовая единица
  static const double sp2 = 8;

  /// 12px — между тесно связанными элементами
  static const double sp3 = 12;

  /// 16px — стандартный padding карточек
  static const double sp4 = 16;

  /// 20px — padding страниц
  static const double sp5 = 20;

  /// 24px — разделение секций
  static const double sp6 = 24;

  /// 32px — большое разделение
  static const double sp8 = 32;

  /// 40px — hero-spacing
  static const double sp10 = 40;

  /// 56px — огромные gap-ы (между hero и контентом)
  static const double sp14 = 56;

  // ── Border radius ───────────────────────────────────────────────
  static const double rSm = 6;
  static const double rMd = 10;
  static const double rLg = 12;
  static const double rXl = 16;
  static const double rFull = 999;

  // ── Icon sizes ──────────────────────────────────────────────────
  /// 14px — inline в тексте
  static const double iconXs = 14;

  /// 16px — compact badges
  static const double iconSm = 16;

  /// 20px — кнопки панели инструментов
  static const double iconMd = 20;

  /// 24px — стандарт Material
  static const double iconLg = 24;

  /// 32px — акцентные иконки в карточках
  static const double iconXl = 32;

  /// 48px — hero-иконки в empty state
  static const double iconHero = 48;

  /// 64px — very large empty-state иконки
  static const double iconHuge = 64;

  // ── Touch targets (desktop минимум) ─────────────────────────────
  /// 40px — минимальный размер для desktop interactive элемента
  static const double touchMin = 40;

  /// 44px — комфортный размер (Apple HIG)
  static const double touchComfortable = 44;

  /// 52px — primary кнопки
  static const double touchPrimary = 52;

  // ── Animation durations ─────────────────────────────────────────
  static const Duration animFast = Duration(milliseconds: 120);
  static const Duration animNormal = Duration(milliseconds: 200);
  static const Duration animSmooth = Duration(milliseconds: 300);
  static const Duration animPulse = Duration(milliseconds: 1500);
  static const Duration animSplash = Duration(milliseconds: 900);
  static const Duration animSplashProgress = Duration(milliseconds: 1600);

  // ── Curves ──────────────────────────────────────────────────────
  static const Curve curveDefault = Curves.easeOutCubic;
  static const Curve curveEmphasized = Curves.easeOutExpo;

  // ── Layout breakpoints ──────────────────────────────────────────
  /// 900px — переход от list к grid в subject selection
  static const double breakpointWide = 900;

  /// 1280px — desktop-оптимизированный layout
  static const double breakpointDesktop = 1280;

  // ── Grid ────────────────────────────────────────────────────────
  /// 280px — максимальная ширина sensor-карточки
  static const double sensorCardMaxWidth = 280;

  /// 1.2 — aspect ratio sensor-карточки
  static const double sensorCardAspectRatio = 1.2;

  /// 12px — gap в sensor-grid
  static const double sensorGridSpacing = 12;

  // ── Tooltip ─────────────────────────────────────────────────────
  static const Duration tooltipWait = Duration(milliseconds: 400);
  static const Duration tooltipShow = Duration(seconds: 4);

  // ── Elevation shadows (manual, вместо Material elevation) ───────
  static List<BoxShadow> shadowSm(Color base) => [
        BoxShadow(
          color: base.withValues(alpha: 0.06),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];

  static List<BoxShadow> shadowMd(Color base) => [
        BoxShadow(
          color: base.withValues(alpha: 0.12),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ];

  static List<BoxShadow> shadowGlow(Color accent) => [
        BoxShadow(
          color: accent.withValues(alpha: 0.25),
          blurRadius: 24,
          spreadRadius: -4,
          offset: const Offset(0, 8),
        ),
      ];

  // ── Display font sizes (для BigValueDisplay и подобных) ─────────
  static const double displayLg = 56;
  static const double displayMd = 40;
  static const double displaySm = 28;
}

/// Padding пресеты для быстрого использования.
class DSPad {
  DSPad._();

  static const page = EdgeInsets.all(DS.sp5);
  static const pageH = EdgeInsets.symmetric(horizontal: DS.sp5);
  static const card = EdgeInsets.all(DS.sp4);
  static const cardSm = EdgeInsets.all(DS.sp3);
  static const button = EdgeInsets.symmetric(
    horizontal: DS.sp6,
    vertical: DS.sp3 + 2,
  );
}

/// Gap-виджеты вместо SizedBox(height/width: X) для читабельности.
class DSGap {
  DSGap._();

  static const h1 = SizedBox(height: DS.sp1);
  static const h2 = SizedBox(height: DS.sp2);
  static const h3 = SizedBox(height: DS.sp3);
  static const h4 = SizedBox(height: DS.sp4);
  static const h5 = SizedBox(height: DS.sp5);
  static const h6 = SizedBox(height: DS.sp6);
  static const h8 = SizedBox(height: DS.sp8);

  static const w1 = SizedBox(width: DS.sp1);
  static const w2 = SizedBox(width: DS.sp2);
  static const w3 = SizedBox(width: DS.sp3);
  static const w4 = SizedBox(width: DS.sp4);
  static const w5 = SizedBox(width: DS.sp5);
  static const w6 = SizedBox(width: DS.sp6);
}
