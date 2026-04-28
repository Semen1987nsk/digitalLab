import 'package:flutter/material.dart';
import '../../../domain/entities/subject_area.dart';
import '../../themes/app_theme.dart';

class SubjectSelectionPage extends StatelessWidget {
  final ValueChanged<SubjectArea> onSubjectSelected;

  const SubjectSelectionPage({
    super.key,
    required this.onSubjectSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.background,
              AppColors.heroBackground,
              AppColors.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SubjectSelectionHero(),
                    const SizedBox(height: 16),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final isWide = constraints.maxWidth >= 900;
                          final cards = SubjectArea.values
                              .map(
                                (subject) => _SubjectCard(
                                  subject: subject,
                                  onTap: () =>
                                      _handleSubjectTap(context, subject),
                                ),
                              )
                              .toList(growable: false);

                          if (isWide) {
                            return GridView.count(
                              crossAxisCount: 2,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              childAspectRatio: 1.8,
                              children: cards,
                            );
                          }

                          return ListView.separated(
                            itemCount: cards.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (_, index) => cards[index],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 14),
                    const _StartupInfoPanel(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _handleSubjectTap(BuildContext context, SubjectArea subject) {
    if (subject.isAvailableNow) {
      onSubjectSelected(subject);
      return;
    }

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Icon(subject.icon, color: subject.accentColor),
            const SizedBox(width: 10),
            Expanded(child: Text(subject.title)),
          ],
        ),
        content: Text(
          '${subject.title} появится как отдельная рабочая область платформы. '
          'Сейчас полностью готова физическая лаборатория, поэтому рекомендуем начать с неё.',
          style: const TextStyle(height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Понятно'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              onSubjectSelected(SubjectArea.physics);
            },
            child: const Text('Открыть физику'),
          ),
        ],
      ),
    );
  }
}

class _SubjectSelectionHero extends StatelessWidget {
  const _SubjectSelectionHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(18),
              border:
                  Border.all(color: AppColors.primary.withValues(alpha: 0.26)),
            ),
            child: const Icon(
              Icons.dashboard_customize_rounded,
              size: 30,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Выберите рабочую область',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'ЛАБОСФЕРА развивается как единая платформа для разных предметов. '
                  'На этом шаге вы выбираете предметную среду, а подключение датчиков начинается уже внутри выбранной лаборатории.',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _HeroPill(
                      icon: Icons.school_rounded,
                      label: 'Школьный сценарий',
                      color: AppColors.primary,
                    ),
                    _HeroPill(
                      icon: Icons.usb_rounded,
                      label: 'Датчики подключаются после выбора',
                      color: AppColors.accent,
                    ),
                    _HeroPill(
                      icon: Icons.grid_view_rounded,
                      label: 'Единая платформа по предметам',
                      color: AppColors.warning,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _HeroPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SubjectCard extends StatelessWidget {
  final SubjectArea subject;
  final VoidCallback onTap;

  const _SubjectCard({
    required this.subject,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final canOpen = subject.isAvailableNow;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: canOpen
                  ? subject.accentColor.withValues(alpha: 0.38)
                  : AppColors.cardBorder,
            ),
            boxShadow: canOpen
                ? [
                    BoxShadow(
                      color: subject.accentColor.withValues(alpha: 0.08),
                      blurRadius: 14,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: subject.accentColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(subject.icon,
                          size: 22, color: subject.accentColor),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: canOpen
                            ? AppColors.success.withValues(alpha: 0.12)
                            : AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        subject.statusLabel,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: canOpen
                              ? AppColors.success
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  subject.title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subject.subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: Text(
                    subject.description,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: canOpen
                          ? FilledButton.icon(
                              onPressed: onTap,
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(0, 40),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                              ),
                              icon: const Icon(Icons.arrow_forward_rounded,
                                  size: 18),
                              label: const Text('Открыть'),
                            )
                          : OutlinedButton.icon(
                              onPressed: onTap,
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 40),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                              ),
                              icon: const Icon(Icons.visibility_outlined,
                                  size: 18),
                              label: const Text('Посмотреть статус'),
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StartupInfoPanel extends StatelessWidget {
  const _StartupInfoPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: AppColors.primary, size: 18),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Подключение датчиков, выбор порта и работа с оборудованием выполняются уже внутри выбранной предметной лаборатории. '
              'Так стартовый экран остаётся чистым, а каждая рабочая область может развиваться как самостоятельный продукт внутри единой платформы.',
              style: TextStyle(
                fontSize: 12,
                height: 1.45,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
