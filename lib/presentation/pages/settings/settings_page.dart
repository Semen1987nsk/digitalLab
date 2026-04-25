import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../blocs/experiment/experiment_provider.dart';
import '../../themes/app_theme.dart';
import '../../themes/design_tokens.dart';
import '../../themes/theme_mode_provider.dart';
import '../../widgets/labosfera_app_bar.dart';
import '../debug/usb_debug_page.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final halMode = ref.watch(halModeProvider);
    final palette = context.palette;

    return Scaffold(
      backgroundColor: palette.background,
      appBar: const LabosferaAppBar(
        title: 'Настройки',
        subtitle: 'Персонализация, подключение и сведения о системе',
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(DS.sp5),
        children: [
          _SectionCard(
            icon: Icons.palette_outlined,
            title: 'Оформление',
            subtitle: 'Тёмная тема по умолчанию — рекомендована СанПиН для длительных уроков',
            child: _ThemeSelector(
              current: themeMode,
              onChanged: (mode) =>
                  ref.read(themeModeProvider.notifier).set(mode),
            ),
          ),
          DSGap.h4,
          _SectionCard(
            icon: Icons.cable_rounded,
            title: 'Подключение',
            subtitle: 'Откуда приложение получает данные от датчика',
            child: _HalModeSelector(
              current: halMode,
              onChanged: (mode) =>
                  ref.read(halModeProvider.notifier).state = mode,
            ),
          ),
          DSGap.h4,
          _SectionCard(
            icon: Icons.bug_report_outlined,
            title: 'Диагностика',
            subtitle: 'Сервисные инструменты для сложных случаев',
            child: _DiagnosticsBlock(
              onOpenUsbDebug: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const UsbDebugPage()),
              ),
            ),
          ),
          DSGap.h4,
          const _AboutCard(),
          const SizedBox(height: DS.sp8),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  ОБЩИЙ SECTION CARD
// ═══════════════════════════════════════════════════════════════

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(DS.sp5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(DS.rMd),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon,
                      size: DS.iconMd, color: AppColors.primary),
                ),
                DSGap.w3,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: Theme.of(context).textTheme.titleMedium),
                      DSGap.h1,
                      Text(
                        subtitle,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: palette.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: DS.sp4),
            child,
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  ВЫБОР ТЕМЫ
// ═══════════════════════════════════════════════════════════════

class _ThemeSelector extends StatelessWidget {
  const _ThemeSelector({required this.current, required this.onChanged});

  final ThemeMode current;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return _SegmentedOptionRow<ThemeMode>(
      current: current,
      options: const [
        _Option(
          value: ThemeMode.system,
          label: 'Системная',
          icon: Icons.brightness_auto_outlined,
          description: 'Следует настройкам Windows',
        ),
        _Option(
          value: ThemeMode.light,
          label: 'Светлая',
          icon: Icons.light_mode_outlined,
          description: 'Для классов с ярким светом',
        ),
        _Option(
          value: ThemeMode.dark,
          label: 'Тёмная',
          icon: Icons.dark_mode_outlined,
          description: 'Меньше нагрузка на зрение',
        ),
      ],
      onChanged: onChanged,
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  ВЫБОР ПОДКЛЮЧЕНИЯ
// ═══════════════════════════════════════════════════════════════

class _HalModeSelector extends StatelessWidget {
  const _HalModeSelector({required this.current, required this.onChanged});

  final HalMode current;
  final ValueChanged<HalMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return _SegmentedOptionRow<HalMode>(
      current: current,
      options: const [
        _Option(
          value: HalMode.usb,
          label: 'USB (COM)',
          icon: Icons.usb,
          description: 'Проводное подключение мультидатчика',
        ),
        _Option(
          value: HalMode.ble,
          label: 'Bluetooth',
          icon: Icons.bluetooth,
          description: 'Беспроводное — для планшетов и ноутбуков',
        ),
        _Option(
          value: HalMode.mock,
          label: 'Симуляция',
          icon: Icons.developer_mode,
          description: 'Демонстрация без железа',
        ),
      ],
      onChanged: onChanged,
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  ДИАГНОСТИКА
// ═══════════════════════════════════════════════════════════════

class _DiagnosticsBlock extends StatelessWidget {
  const _DiagnosticsBlock({required this.onOpenUsbDebug});

  final VoidCallback onOpenUsbDebug;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _DiagnosticTile(
          icon: Icons.cable,
          title: 'USB-диагностика',
          subtitle: 'Поиск портов, тест драйверов, сырой лог датчика',
          onTap: onOpenUsbDebug,
        ),
      ],
    );
  }
}

class _DiagnosticTile extends StatefulWidget {
  const _DiagnosticTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  State<_DiagnosticTile> createState() => _DiagnosticTileState();
}

class _DiagnosticTileState extends State<_DiagnosticTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: DS.animFast,
        decoration: BoxDecoration(
          color: _hover ? palette.surfaceLight : Colors.transparent,
          borderRadius: BorderRadius.circular(DS.rMd),
          border: Border.all(
            color: _hover
                ? AppColors.primary.withValues(alpha: 0.4)
                : palette.cardBorder,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(DS.rMd),
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.all(DS.sp3 + 2),
            child: Row(
              children: [
                Icon(widget.icon,
                    size: DS.iconMd, color: palette.textSecondary),
                DSGap.w3,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.title,
                          style: Theme.of(context).textTheme.titleMedium),
                      Text(widget.subtitle,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right,
                    size: DS.iconMd, color: palette.textHint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  ABOUT
// ═══════════════════════════════════════════════════════════════

class _AboutCard extends StatelessWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(DS.sp5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.primary, AppColors.accent],
                    ),
                    borderRadius: BorderRadius.circular(DS.rLg),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.science,
                      color: Colors.white, size: DS.iconLg),
                ),
                DSGap.w4,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ЛАБОСФЕРА — Цифровая лаборатория',
                          style: Theme.of(context).textTheme.titleMedium),
                      DSGap.h1,
                      Text('Версия 0.1.0 — школьный выпуск',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: palette.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
            DSGap.h4,
            Text(
              'Цифровая лаборатория по физике для школ России. '
              'Сертифицирована для использования в ФГОС ОО. '
              'Подключается к мультидатчику Лабосферы через USB или Bluetooth.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(height: 1.5),
            ),
            DSGap.h4,
            const Wrap(
              spacing: DS.sp2,
              runSpacing: DS.sp2,
              children: [
                _AboutChip(icon: Icons.school, label: 'ФГОС ОО'),
                _AboutChip(icon: Icons.verified, label: 'Сертифицировано'),
                _AboutChip(icon: Icons.flag, label: 'Made in Russia'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AboutChip extends StatelessWidget {
  const _AboutChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: DS.sp3, vertical: DS.sp1 + 2),
      decoration: BoxDecoration(
        color: palette.surfaceLight,
        borderRadius: BorderRadius.circular(DS.rFull),
        border: Border.all(color: palette.cardBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: DS.iconXs, color: palette.textSecondary),
          DSGap.w1,
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: palette.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  РЕЮЗЕБЛ — SEGMENTED OPTION ROW
// ═══════════════════════════════════════════════════════════════

class _Option<T> {
  const _Option({
    required this.value,
    required this.label,
    required this.icon,
    required this.description,
    this.accent,
  });

  final T value;
  final String label;
  final IconData icon;
  final String description;
  final Color? accent;
}

class _SegmentedOptionRow<T> extends StatelessWidget {
  const _SegmentedOptionRow({
    required this.current,
    required this.options,
    required this.onChanged,
  });

  final T current;
  final List<_Option<T>> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: DS.sp3,
      runSpacing: DS.sp3,
      children: options
          .map((o) => _OptionTile<T>(
                option: o,
                selected: o.value == current,
                onTap: () => onChanged(o.value),
              ))
          .toList(),
    );
  }
}

class _OptionTile<T> extends StatefulWidget {
  const _OptionTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final _Option<T> option;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_OptionTile<T>> createState() => _OptionTileState<T>();
}

class _OptionTileState<T> extends State<_OptionTile<T>> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final accent = widget.option.accent ?? AppColors.primary;
    final selected = widget.selected;
    final highlight = selected || _hover;

    return SizedBox(
      width: 220,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: DS.animFast,
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.12)
                : (_hover ? palette.surfaceLight : palette.background),
            borderRadius: BorderRadius.circular(DS.rLg),
            border: Border.all(
              color: highlight ? accent : palette.cardBorder,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(DS.rLg),
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.all(DS.sp4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(widget.option.icon,
                          size: DS.iconLg,
                          color: selected ? accent : palette.textSecondary),
                      const Spacer(),
                      AnimatedOpacity(
                        duration: DS.animFast,
                        opacity: selected ? 1 : 0,
                        child: Icon(Icons.check_circle,
                            size: DS.iconSm, color: accent),
                      ),
                    ],
                  ),
                  DSGap.h3,
                  Text(
                    widget.option.label,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: selected ? accent : palette.textPrimary,
                        ),
                  ),
                  DSGap.h1,
                  Text(
                    widget.option.description,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
