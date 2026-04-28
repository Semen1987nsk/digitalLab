import 'package:flutter/material.dart';

import '../../themes/app_theme.dart';
import '../../themes/design_tokens.dart';
import '../../widgets/labosfera_app_bar.dart';

/// «Связка датчиков» — раздел в разработке.
///
/// Это сложная фича (X-Y параметрика, dual-axis, наложение опытов,
/// мульти-устройство). До MVP-релиза отображаем красивую заглушку
/// с понятным набором планируемых сценариев — без нагромождения
/// длинных текстовых секций.
class SensorLinkingPage extends StatelessWidget {
  const SensorLinkingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.background,
      appBar: const LabosferaAppBar(
        title: 'Связка датчиков',
        subtitle: 'Совместный анализ нескольких параметров',
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(DS.sp6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _HeroIcon(),
                DSGap.h6,
                Text(
                  'Раздел в разработке',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                DSGap.h3,
                Text(
                  'Здесь будет инструмент для совместного анализа: '
                  'два параметра на одном графике, двойная ось Y, '
                  'X-Y параметрические зависимости и сравнение опытов.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                DSGap.h6,
                const Wrap(
                  spacing: DS.sp2,
                  runSpacing: DS.sp2,
                  alignment: WrapAlignment.center,
                  children: [
                    _FeatureChip(
                      icon: Icons.stacked_line_chart,
                      label: 'Мульти-канал',
                    ),
                    _FeatureChip(
                      icon: Icons.align_vertical_bottom,
                      label: 'Двойная ось Y',
                    ),
                    _FeatureChip(
                      icon: Icons.show_chart,
                      label: 'X-Y параметрика',
                    ),
                    _FeatureChip(
                      icon: Icons.layers_outlined,
                      label: 'Наложение опытов',
                    ),
                  ],
                ),
                DSGap.h8,
                Container(
                  padding: const EdgeInsets.all(DS.sp4),
                  decoration: BoxDecoration(
                    color: palette.surface,
                    borderRadius: BorderRadius.circular(DS.rLg),
                    border: Border.all(color: palette.cardBorder),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.lightbulb_outline,
                        color: AppColors.warning,
                      ),
                      DSGap.w3,
                      Expanded(
                        child: Text(
                          'А пока — открывайте датчики на главном экране '
                          'и сравнивайте результаты через раздел «История».',
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: 13,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary.withValues(alpha: 0.18),
            AppColors.version360.withValues(alpha: 0.10),
          ],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.25),
        ),
      ),
      alignment: Alignment.center,
      child: const Icon(
        Icons.cable_rounded,
        size: 44,
        color: AppColors.primary,
      ),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  const _FeatureChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: DS.sp3, vertical: DS.sp2),
      decoration: BoxDecoration(
        color: palette.surfaceLight,
        borderRadius: BorderRadius.circular(DS.rFull),
        border: Border.all(color: palette.cardBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: DS.iconSm, color: palette.textSecondary),
          DSGap.w1,
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: palette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
