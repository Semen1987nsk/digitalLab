import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/di/providers.dart';
import '../../../data/datasources/local/app_database.dart';
import '../../themes/app_theme.dart';
import '../../themes/design_tokens.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/labosfera_app_bar.dart';

/// Провайдер: список всех экспериментов из БД.
/// AutoDispose + Future — перечитывается каждый раз, когда страница
/// открывается (дёшево — таблица маленькая, индекс по дате).
final _experimentsListProvider =
    FutureProvider.autoDispose<List<ExperimentEntry>>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  return db.allExperiments();
});

class HistoryPage extends ConsumerWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final asyncExperiments = ref.watch(_experimentsListProvider);

    return Scaffold(
      backgroundColor: palette.background,
      appBar: LabosferaAppBar(
        title: 'История экспериментов',
        subtitle: _buildSubtitle(asyncExperiments),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: 'Обновить список',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(_experimentsListProvider),
          ),
        ],
      ),
      body: asyncExperiments.when(
        loading: () => const _LoadingState(),
        error: (e, _) => _ErrorState(
          message: e.toString(),
          onRetry: () => ref.invalidate(_experimentsListProvider),
        ),
        data: (items) => items.isEmpty
            ? const _EmptyState()
            : _ExperimentsList(
                items: items,
                onDelete: (exp) => _deleteExperiment(context, ref, exp),
                onOpen: (exp) => _openDetails(context, exp),
              ),
      ),
    );
  }

  String _buildSubtitle(AsyncValue<List<ExperimentEntry>> async) {
    return async.maybeWhen(
      data: (items) {
        if (items.isEmpty) return 'Сохранённые опыты появятся здесь';
        return 'Сохранено опытов: ${items.length}';
      },
      orElse: () => 'Загрузка архива...',
    );
  }

  Future<void> _deleteExperiment(
    BuildContext context,
    WidgetRef ref,
    ExperimentEntry exp,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _DeleteConfirmDialog(experiment: exp),
    );
    if (confirmed != true) return;

    final db = ref.read(appDatabaseProvider);
    await db.deleteExperiment(exp.id);
    ref.invalidate(_experimentsListProvider);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Эксперимент «${_titleFor(exp)}» удалён'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _openDetails(BuildContext context, ExperimentEntry exp) {
    showDialog(
      context: context,
      builder: (ctx) => _ExperimentDetailsDialog(experiment: exp),
    );
  }
}

String _titleFor(ExperimentEntry e) {
  if (e.title.isNotEmpty) return e.title;
  final fmt = DateFormat('dd.MM.yyyy');
  return 'Опыт от ${fmt.format(e.startTime)}';
}

// ═══════════════════════════════════════════════════════════════
//  СОСТОЯНИЯ
// ═══════════════════════════════════════════════════════════════

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: 32,
        height: 32,
        child: CircularProgressIndicator(strokeWidth: 2.5),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DS.sp8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                size: DS.iconHuge, color: AppColors.error),
            DSGap.h4,
            Text(
              'Не удалось загрузить историю',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            DSGap.h2,
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.textSecondary),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            DSGap.h5,
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Повторить'),
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      illustration: EmptyStateIllustration.waveform,
      title: 'Пока нет сохранённых опытов',
      message:
          'Начните эксперимент на главной — после остановки он автоматически '
          'сохранится сюда. Вы сможете вернуться к графику, сравнить опыты и '
          'выгрузить данные.',
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  СПИСОК ЭКСПЕРИМЕНТОВ
// ═══════════════════════════════════════════════════════════════

class _ExperimentsList extends StatelessWidget {
  const _ExperimentsList({
    required this.items,
    required this.onDelete,
    required this.onOpen,
  });

  final List<ExperimentEntry> items;
  final void Function(ExperimentEntry) onDelete;
  final void Function(ExperimentEntry) onOpen;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(DS.sp5),
      itemCount: items.length,
      separatorBuilder: (_, __) => DSGap.h3,
      itemBuilder: (context, i) {
        final exp = items[i];
        return _ExperimentCard(
          experiment: exp,
          onDelete: () => onDelete(exp),
          onOpen: () => onOpen(exp),
        );
      },
    );
  }
}

class _ExperimentCard extends StatefulWidget {
  const _ExperimentCard({
    required this.experiment,
    required this.onDelete,
    required this.onOpen,
  });

  final ExperimentEntry experiment;
  final VoidCallback onDelete;
  final VoidCallback onOpen;

  @override
  State<_ExperimentCard> createState() => _ExperimentCardState();
}

class _ExperimentCardState extends State<_ExperimentCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final exp = widget.experiment;
    final duration = exp.endTime?.difference(exp.startTime);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: DS.animFast,
        decoration: BoxDecoration(
          color: _hover ? palette.surfaceLight : palette.surface,
          borderRadius: BorderRadius.circular(DS.rLg),
          border: Border.all(
            color: _hover
                ? AppColors.primary.withValues(alpha: 0.4)
                : palette.cardBorder,
          ),
          boxShadow: _hover ? DS.shadowSm(Colors.black) : null,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(DS.rLg),
          onTap: widget.onOpen,
          child: Padding(
            padding: const EdgeInsets.all(DS.sp4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _StatusIcon(status: exp.status),
                DSGap.w4,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _titleFor(exp),
                        style: Theme.of(context).textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      DSGap.h1,
                      Wrap(
                        spacing: DS.sp3,
                        runSpacing: 2,
                        children: [
                          _MetaItem(
                            icon: Icons.schedule,
                            text: DateFormat('dd.MM.yyyy · HH:mm')
                                .format(exp.startTime),
                          ),
                          if (duration != null)
                            _MetaItem(
                              icon: Icons.timer_outlined,
                              text: _formatDuration(duration),
                            ),
                          _MetaItem(
                            icon: Icons.scatter_plot_outlined,
                            text: '${exp.measurementCount} точек',
                          ),
                          _MetaItem(
                            icon: Icons.speed,
                            text: '${exp.sampleRateHz} Гц',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                DSGap.w2,
                _StatusBadge(status: exp.status),
                DSGap.w1,
                IconButton(
                  tooltip: 'Удалить эксперимент',
                  icon:
                      Icon(Icons.delete_outline, color: palette.textSecondary),
                  onPressed: widget.onDelete,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _formatDuration(Duration d) {
  if (d.inHours >= 1) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    return '$h ч $m мин';
  }
  if (d.inMinutes >= 1) {
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60);
    return '$m мин $s с';
  }
  return '${d.inSeconds} с';
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status});

  final ExperimentStatus status;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (status) {
      ExperimentStatus.completed => (AppColors.success, Icons.check_circle),
      ExperimentStatus.running => (AppColors.warning, Icons.circle),
      ExperimentStatus.interrupted => (AppColors.error, Icons.error_outline),
    };
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(DS.rMd),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: color, size: DS.iconMd),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final ExperimentStatus status;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      ExperimentStatus.completed => (AppColors.success, 'Завершён'),
      ExperimentStatus.running => (AppColors.warning, 'Идёт запись'),
      ExperimentStatus.interrupted => (AppColors.error, 'Прерван'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: DS.sp3, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(DS.rFull),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _MetaItem extends StatelessWidget {
  const _MetaItem({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: DS.iconXs, color: palette.textHint),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: palette.textSecondary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  ДИАЛОГИ
// ═══════════════════════════════════════════════════════════════

class _DeleteConfirmDialog extends StatelessWidget {
  const _DeleteConfirmDialog({required this.experiment});

  final ExperimentEntry experiment;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.delete_forever, color: AppColors.error),
          SizedBox(width: 12),
          Text('Удалить эксперимент?'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '«${_titleFor(experiment)}» и все ${experiment.measurementCount} измерений будут удалены без возможности восстановления.',
            style: const TextStyle(height: 1.5),
          ),
          DSGap.h3,
          Text(
            'Это действие нельзя отменить.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.error,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Отмена'),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.error,
          ),
          icon: const Icon(Icons.delete_forever, size: DS.iconSm),
          label: const Text('Удалить'),
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    );
  }
}

class _ExperimentDetailsDialog extends StatelessWidget {
  const _ExperimentDetailsDialog({required this.experiment});

  final ExperimentEntry experiment;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final duration = experiment.endTime?.difference(experiment.startTime);
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          _StatusIcon(status: experiment.status),
          DSGap.w3,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_titleFor(experiment),
                    style: Theme.of(context).textTheme.titleMedium),
                Text(
                  DateFormat('dd.MM.yyyy · HH:mm').format(experiment.startTime),
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
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DetailRow(
            label: 'Статус',
            value: switch (experiment.status) {
              ExperimentStatus.completed => 'Завершён нормально',
              ExperimentStatus.running => 'Идёт запись',
              ExperimentStatus.interrupted => 'Прерван (сбой)',
            },
          ),
          if (duration != null)
            _DetailRow(
              label: 'Длительность',
              value: _formatDuration(duration),
            ),
          _DetailRow(
            label: 'Частота',
            value: '${experiment.sampleRateHz} Гц',
          ),
          _DetailRow(
            label: 'Точек',
            value: '${experiment.measurementCount}',
          ),
          DSGap.h3,
          Container(
            padding: const EdgeInsets.all(DS.sp3),
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(DS.rMd),
              border: Border.all(color: AppColors.info.withValues(alpha: 0.25)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline,
                    color: AppColors.info, size: DS.iconSm),
                SizedBox(width: DS.sp2),
                Expanded(
                  child: Text(
                    'Полный просмотр графика и экспорт будут добавлены в следующем обновлении',
                    style: TextStyle(fontSize: 12, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Закрыть'),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(color: palette.textSecondary, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
