import 'package:flutter/material.dart';

import '../themes/app_theme.dart';
import '../themes/design_tokens.dart';

/// Единый AppBar приложения «Лабосфера».
///
/// Все экраны (кроме home) используют эту оболочку — так обеспечивается
/// визуальная непрерывность. Заголовок — строка, подзаголовок — 12pt
/// вторичный. Кнопка назад автоматически получает корректную семантику.
///
/// Для home-страницы используйте [LabosferaSliverAppBar] с логотипом.
class LabosferaAppBar extends StatelessWidget implements PreferredSizeWidget {
  const LabosferaAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.actions,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.bottom,
    this.centerTitle = false,
  });

  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final Widget? leading;
  final bool automaticallyImplyLeading;
  final PreferredSizeWidget? bottom;
  final bool centerTitle;

  @override
  Size get preferredSize => Size.fromHeight(
        (subtitle == null ? kToolbarHeight : kToolbarHeight + 12) +
            (bottom?.preferredSize.height ?? 0),
      );

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);

    final titleWidget = subtitle == null
        ? Text(title)
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 2),
              Text(
                subtitle!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: palette.textSecondary,
                  height: 1.2,
                ),
              ),
            ],
          );

    return AppBar(
      leading: leading,
      automaticallyImplyLeading: automaticallyImplyLeading,
      title: titleWidget,
      centerTitle: centerTitle,
      actions: _wrapActionsWithPadding(actions),
      bottom: bottom,
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 1,
      shadowColor: palette.cardBorder,
      shape: Border(
        bottom: BorderSide(
          color: palette.cardBorder.withValues(alpha: 0.6),
          width: 0.5,
        ),
      ),
    );
  }

  List<Widget>? _wrapActionsWithPadding(List<Widget>? actions) {
    if (actions == null || actions.isEmpty) return actions;
    return [
      ...actions,
      const SizedBox(width: DS.sp2),
    ];
  }
}

/// Брендовый логотип + двухстрочный заголовок для главного экрана.
///
/// Используется в SliverAppBar на home. Отдельный виджет, чтобы можно
/// было переиспользовать (например, в splash или about).
class LabosferaBrand extends StatelessWidget {
  const LabosferaBrand({
    super.key,
    this.compact = false,
    this.subtitle = 'Цифровые лаборатории',
  });

  final bool compact;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final logoSize = compact ? 30.0 : 34.0;
    final titleSize = compact ? 16.0 : 18.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: logoSize,
          height: logoSize,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.primary, AppColors.accent],
            ),
            borderRadius: BorderRadius.circular(DS.rMd - 1),
            boxShadow: DS.shadowSm(AppColors.primary),
          ),
          child: Icon(
            Icons.science,
            size: logoSize * 0.6,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: DS.sp3),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'ЛАБОСФЕРА',
              style: TextStyle(
                fontSize: titleSize,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                height: 1.1,
                color: palette.textPrimary,
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: palette.textSecondary,
                letterSpacing: 0.3,
                height: 1.3,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Брендированный SliverAppBar для home-страницы.
///
/// Поддерживает те же actions, что и [LabosferaAppBar], но живёт
/// внутри CustomScrollView и плавает при скролле.
class LabosferaSliverAppBar extends StatelessWidget {
  const LabosferaSliverAppBar({
    super.key,
    this.actions,
    this.floating = true,
    this.snap = true,
    this.pinned = false,
  });

  final List<Widget>? actions;
  final bool floating;
  final bool snap;
  final bool pinned;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SliverAppBar(
      floating: floating,
      snap: snap,
      pinned: pinned,
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 1,
      shape: Border(
        bottom: BorderSide(
          color: palette.cardBorder.withValues(alpha: 0.6),
          width: 0.5,
        ),
      ),
      title: const LabosferaBrand(),
      actions: actions,
    );
  }
}
