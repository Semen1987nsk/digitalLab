import 'package:flutter/material.dart';

import '../../themes/app_theme.dart';

class StoppedReviewPanel extends StatelessWidget {
  final bool isSelectionMode;
  final String visibleRangeLabel;
  final VoidCallback onFitAll;
  final VoidCallback onResetView;
  final VoidCallback onToggleSelectionMode;
  final VoidCallback onResetYScale;

  const StoppedReviewPanel({
    super.key,
    required this.isSelectionMode,
    required this.visibleRangeLabel,
    required this.onFitAll,
    required this.onResetView,
    required this.onToggleSelectionMode,
    required this.onResetYScale,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(left: 8, right: 8, bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.analytics_outlined,
                size: 16,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Просмотр записи',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (!isSelectionMode)
                Text(
                  visibleRangeLabel,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ReviewToolButton(
                icon: Icons.fit_screen,
                label: 'Весь график',
                onTap: onFitAll,
              ),
              ReviewToolButton(
                icon: Icons.restart_alt,
                label: 'Сбросить вид',
                onTap: onResetView,
                accent: true,
              ),
              ReviewToolButton(
                icon: Icons.select_all,
                label: isSelectionMode ? 'Отменить выделение' : 'Выделить участок',
                onTap: onToggleSelectionMode,
                accent: isSelectionMode,
              ),
              ReviewToolButton(
                icon: Icons.auto_graph,
                label: 'Авто Y',
                onTap: onResetYScale,
              ),
            ],
          ),
          if (isSelectionMode) ...[
            const SizedBox(height: 6),
            const Text(
              'Проведите по графику, чтобы приблизить нужный участок.',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ReviewToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool accent;

  const ReviewToolButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = accent ? AppColors.primary : AppColors.textPrimary;
    final bg = accent
        ? AppColors.primary.withValues(alpha: 0.12)
        : AppColors.surfaceLight;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: fg),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

