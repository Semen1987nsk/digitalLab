import 'package:flutter/material.dart';
import '../themes/app_theme.dart';
import 'labosfera_app_bar.dart';

class PagePreviewSection {
  final String title;
  final String? subtitle;
  final List<(IconData, String)> items;

  const PagePreviewSection({
    required this.title,
    this.subtitle,
    required this.items,
  });
}

class PagePreviewScaffold extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final String statusLabel;
  final String readinessNote;
  final List<PagePreviewSection> sections;

  const PagePreviewScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    required this.statusLabel,
    required this.readinessNote,
    required this.sections,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: LabosferaAppBar(
        title: title,
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _PreviewHero(
            title: title,
            subtitle: subtitle,
            icon: icon,
            accentColor: accentColor,
            statusLabel: statusLabel,
            readinessNote: readinessNote,
          ),
          const SizedBox(height: 16),
          ...sections.expand(
            (section) => [
              _PreviewSectionCard(section: section, accentColor: accentColor),
              const SizedBox(height: 16),
            ],
          ),
        ],
      ),
    );
  }
}

class _PreviewHero extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final String statusLabel;
  final String readinessNote;

  const _PreviewHero({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    required this.statusLabel,
    required this.readinessNote,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(icon, color: accentColor, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: AppColors.warning.withValues(alpha: 0.35),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.schedule_rounded, size: 16, color: AppColors.warning),
                      SizedBox(width: 8),
                      Text(
                        'Раздел развивается',
                        style: TextStyle(
                          color: AppColors.warning,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      color: accentColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 18, color: accentColor),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      readinessNote,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
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
    );
  }
}

class _PreviewSectionCard extends StatelessWidget {
  final PagePreviewSection section;
  final Color accentColor;

  const _PreviewSectionCard({required this.section, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: accentColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  section.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            if (section.subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                section.subtitle!,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
            const SizedBox(height: 14),
            ...section.items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(item.$1, size: 16, color: accentColor),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        item.$2,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
