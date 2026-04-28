import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../../data/datasources/local/experiment_autosave_service.dart';
import '../../../domain/entities/sensor_data.dart';
import '../../../domain/entities/subject_area.dart';
import '../../../core/di/providers.dart';
import '../../blocs/experiment/experiment_provider.dart';
import '../../themes/app_theme.dart';
import '../../themes/design_tokens.dart';
import '../home/home_page.dart';
import '../history/history_page.dart';
import '../calibration/calibration_page.dart';
import '../linking/sensor_linking_page.dart';
import '../settings/settings_page.dart';

/// Sidebar navigation destinations
class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final String tooltip;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.tooltip,
  });
}

const _kNavItems = [
  _NavItem(
    icon: Icons.sensors_outlined,
    activeIcon: Icons.sensors,
    label: 'Датчики',
    tooltip: 'Панель датчиков',
  ),
  _NavItem(
    icon: Icons.history_outlined,
    activeIcon: Icons.history,
    label: 'История',
    tooltip: 'История экспериментов',
  ),
  _NavItem(
    icon: Icons.tune_outlined,
    activeIcon: Icons.tune,
    label: 'Калибровка',
    tooltip: 'Калибровка датчиков',
  ),
  _NavItem(
    icon: Icons.cable_outlined,
    activeIcon: Icons.cable,
    label: 'Связка',
    tooltip: 'Связка датчиков',
  ),
  _NavItem(
    icon: Icons.settings_outlined,
    activeIcon: Icons.settings,
    label: 'Настройки',
    tooltip: 'Настройки приложения',
  ),
];

const double _kSidebarWidth = 96;

class AppShell extends ConsumerStatefulWidget {
  final SubjectArea subject;
  final VoidCallback? onSubjectSelectionRequested;
  final RecoveredExperimentSession? pendingRecovery;
  final VoidCallback? onRecoveryHandled;

  const AppShell({
    super.key,
    required this.subject,
    this.onSubjectSelectionRequested,
    this.pendingRecovery,
    this.onRecoveryHandled,
  });

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

/// Интент переключения вкладки сайдбара по Ctrl+1..5.
class _NavigateTabIntent extends Intent {
  const _NavigateTabIntent(this.index);
  final int index;
}

class _AppShellState extends ConsumerState<AppShell> {
  int _selectedIndex = 0;
  final FocusNode _shellFocusNode = FocusNode(
    debugLabel: 'AppShell',
    skipTraversal: true,
  );

  @override
  void dispose() {
    _shellFocusNode.dispose();
    super.dispose();
  }

  void _selectTab(int i) {
    if (i < 0 || i >= _kNavItems.length) return;
    setState(() => _selectedIndex = i);
  }

  @override
  Widget build(BuildContext context) {
    final connectionStatus = ref.watch(
      sensorConnectionProvider.select((s) => s.status),
    );

    // ── Клавиатурные шорткаты уровня shell ──────────────────────
    // Ctrl+1..5 — мгновенное переключение между пятью разделами.
    // Работает в любом месте приложения, где виден shell (кроме
    // открытых модальных страниц — они перехватывают focus).
    final shortcuts = <LogicalKeySet, Intent>{
      LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.digit1):
          const _NavigateTabIntent(0),
      LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.digit2):
          const _NavigateTabIntent(1),
      LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.digit3):
          const _NavigateTabIntent(2),
      LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.digit4):
          const _NavigateTabIntent(3),
      LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.digit5):
          const _NavigateTabIntent(4),
    };

    return Stack(
      children: [
        Shortcuts(
          shortcuts: shortcuts,
          child: Actions(
            actions: <Type, Action<Intent>>{
              _NavigateTabIntent: CallbackAction<_NavigateTabIntent>(
                onInvoke: (intent) {
                  _selectTab(intent.index);
                  return null;
                },
              ),
            },
            child: Focus(
              focusNode: _shellFocusNode,
              autofocus: true,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Breakpoint: при ширине < 700 переключаемся на bottom bar
                  // (типичный планшет в портрете). Десктоп и планшет в
                  // ландшафте используют боковой rail.
                  final isCompact = constraints.maxWidth < 700;
                  return isCompact
                      ? _buildCompactScaffold(connectionStatus)
                      : _buildExpandedScaffold(connectionStatus);
                },
              ),
            ),
          ),
        ),
        RecoveryPromptPresenter(
          pendingRecovery: widget.pendingRecovery,
          onRecoveryHandled: widget.onRecoveryHandled,
        ),
      ],
    );
  }

  /// Десктоп / планшет в ландшафте — боковая панель 96dp.
  Widget _buildExpandedScaffold(ConnectionStatus connectionStatus) {
    return Scaffold(
      body: Row(
        children: [
          _PremiumSidebar(
            subject: widget.subject,
            onSubjectSelectionRequested: widget.onSubjectSelectionRequested,
            selectedIndex: _selectedIndex,
            onSelected: _selectTab,
            connectionStatus: connectionStatus,
          ),
          Expanded(child: _buildContentStack()),
        ],
      ),
    );
  }

  /// Планшет в портрете / телефон — bottom NavigationBar (Material 3).
  /// Выбор предмета и связь устройства уезжают в overflow-меню AppBar
  /// каждой страницы (это родная роль AppBar.actions).
  Widget _buildCompactScaffold(ConnectionStatus connectionStatus) {
    return Scaffold(
      body: SafeArea(child: _buildContentStack()),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _selectTab,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          for (final item in _kNavItems)
            NavigationDestination(
              icon: Icon(item.icon),
              selectedIcon: Icon(item.activeIcon),
              label: item.label,
              tooltip: item.tooltip,
            ),
        ],
      ),
    );
  }

  Widget _buildContentStack() {
    return IndexedStack(
      index: _selectedIndex,
      children: const [
        HomePage(),
        HistoryPage(),
        CalibrationPage(),
        SensorLinkingPage(),
        SettingsPage(),
      ],
    );
  }
}

class RecoveryPromptPresenter extends ConsumerStatefulWidget {
  final RecoveredExperimentSession? pendingRecovery;
  final VoidCallback? onRecoveryHandled;

  const RecoveryPromptPresenter({
    super.key,
    required this.pendingRecovery,
    this.onRecoveryHandled,
  });

  @override
  ConsumerState<RecoveryPromptPresenter> createState() =>
      _RecoveryPromptPresenterState();
}

class _RecoveryPromptPresenterState
    extends ConsumerState<RecoveryPromptPresenter> {
  bool _recoveryDialogShown = false;

  @override
  void initState() {
    super.initState();
    _scheduleRecoveryPrompt();
  }

  @override
  void didUpdateWidget(covariant RecoveryPromptPresenter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pendingRecovery == null && widget.pendingRecovery != null) {
      _scheduleRecoveryPrompt();
    }
  }

  void _scheduleRecoveryPrompt() {
    if (_recoveryDialogShown || widget.pendingRecovery == null) return;
    _recoveryDialogShown = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || widget.pendingRecovery == null) return;

      final session = widget.pendingRecovery!;
      final shouldRestore = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.restore, color: AppColors.primary),
              SizedBox(width: 10),
              Text('Восстановить эксперимент?'),
            ],
          ),
          content: Text(
            'Найден прерванный эксперимент'
            '${session.title.isNotEmpty ? ' «${session.title}»' : ''}.\n\n'
            'Точек: ${session.measurementCount}\n'
            'Частота: ${session.sampleRateHz} Гц\n'
            'Начало: ${session.startTime.toLocal()}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Пропустить'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Восстановить'),
            ),
          ],
        ),
      );

      if (!mounted) return;

      try {
        if (shouldRestore == true) {
          ref
              .read(experimentControllerProvider.notifier)
              .restoreRecoveredSession(session);
        }

        await ref.read(autosaveServiceProvider).markRecoveryHandled(session);

        if (!mounted) return;

        if (shouldRestore == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Восстановлено ${session.measurementCount} точек из прерванного эксперимента',
              ),
            ),
          );
        }

        widget.onRecoveryHandled?.call();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось завершить восстановление эксперимента'),
          ),
        );
        debugPrint('RecoveryPrompt: ошибка завершения recovery flow: $e');
      }
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _PremiumSidebar extends StatelessWidget {
  final SubjectArea subject;
  final VoidCallback? onSubjectSelectionRequested;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final ConnectionStatus connectionStatus;

  const _PremiumSidebar({
    required this.subject,
    this.onSubjectSelectionRequested,
    required this.selectedIndex,
    required this.onSelected,
    required this.connectionStatus,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _kSidebarWidth,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          right: BorderSide(color: AppColors.cardBorder),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 16),
          _SidebarLogo(connectionStatus: connectionStatus),
          const SizedBox(height: 18),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: Divider(height: 1),
          ),
          const SizedBox(height: 12),
          for (int i = 0; i < _kNavItems.length; i++) ...[
            _NavButton(
              item: _kNavItems[i],
              isSelected: i == selectedIndex,
              onTap: () => onSelected(i),
            ),
            if (i < _kNavItems.length - 1) const SizedBox(height: 6),
          ],
          const Spacer(),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: Divider(height: 1),
          ),
          const SizedBox(height: DS.sp3),
          _WorkspaceSwitcher(
            subject: subject,
            onTap: onSubjectSelectionRequested,
          ),
          const SizedBox(height: DS.sp2),
          const _AppVersionLabel(),
          const SizedBox(height: DS.sp4),
        ],
      ),
    );
  }
}

/// Динамическая версия из pubspec.yaml через `package_info_plus`.
class _AppVersionLabel extends StatefulWidget {
  const _AppVersionLabel();

  @override
  State<_AppVersionLabel> createState() => _AppVersionLabelState();
}

class _AppVersionLabelState extends State<_AppVersionLabel> {
  String? _version;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _version = 'v${info.version}');
    }).catchError((_) {
      // На платформах без package info оставляем пустоту
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_version == null) return const SizedBox(height: 14);
    return Text(
      _version!,
      style: const TextStyle(
        fontSize: 10,
        color: AppColors.textHint,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.3,
      ),
    );
  }
}

class _WorkspaceSwitcher extends StatelessWidget {
  final SubjectArea subject;
  final VoidCallback? onTap;

  const _WorkspaceSwitcher({
    required this.subject,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Tooltip(
        message: onTap == null ? subject.title : 'Сменить предмет',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: subject.accentColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: subject.accentColor.withValues(alpha: 0.24),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(subject.icon, size: 20, color: subject.accentColor),
                const SizedBox(height: 6),
                Text(
                  subject.title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: subject.accentColor,
                  ),
                ),
                if (onTap != null) ...[
                  const SizedBox(height: 6),
                  const Text(
                    'Сменить',
                    style: TextStyle(
                      fontSize: 9,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarLogo extends StatelessWidget {
  final ConnectionStatus connectionStatus;
  const _SidebarLogo({required this.connectionStatus});

  @override
  Widget build(BuildContext context) {
    final isConnected = connectionStatus == ConnectionStatus.connected;
    final dotColor = switch (connectionStatus) {
      ConnectionStatus.connected => AppColors.success,
      ConnectionStatus.connecting => AppColors.warning,
      ConnectionStatus.error => AppColors.error,
      ConnectionStatus.disconnected => AppColors.disconnected,
    };
    final statusText = switch (connectionStatus) {
      ConnectionStatus.connected => 'Подключено',
      ConnectionStatus.connecting => 'Подключение...',
      ConnectionStatus.error => 'Ошибка',
      ConnectionStatus.disconnected => 'Не подключено',
    };

    return Tooltip(
      message: statusText,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isConnected
                    ? AppColors.primary.withValues(alpha: 0.35)
                    : AppColors.cardBorder,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Icon(Icons.science, size: 22, color: AppColors.primary),
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.surface, width: 2),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'ЛС',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: dotColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              statusText,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: dotColor,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _NavButton extends StatefulWidget {
  final _NavItem item;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavButton({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_NavButton> createState() => _NavButtonState();
}

class _NavButtonState extends State<_NavButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isSelected = widget.isSelected;
    final item = widget.item;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Material(
        color: Colors.transparent,
        child: Tooltip(
          message: item.tooltip,
          preferBelow: false,
          waitDuration: const Duration(milliseconds: 600),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(14),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                height: 68,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: isSelected
                      ? AppColors.primary.withValues(alpha: 0.12)
                      : _isHovered
                          ? AppColors.surfaceLight
                          : Colors.transparent,
                  border: Border.all(
                    color: isSelected
                        ? AppColors.primary.withValues(alpha: 0.28)
                        : Colors.transparent,
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      left: 0,
                      top: 16,
                      bottom: 16,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: isSelected ? 3 : 0,
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.horizontal(
                            right: Radius.circular(3),
                          ),
                        ),
                      ),
                    ),
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isSelected ? item.activeIcon : item.icon,
                            size: 23,
                            color: isSelected
                                ? AppColors.primary
                                : _isHovered
                                    ? AppColors.textPrimary
                                    : AppColors.textSecondary,
                          ),
                          const SizedBox(height: 6),
                          AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 180),
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: isSelected
                                  ? AppColors.textPrimary
                                  : AppColors.textSecondary,
                            ),
                            child: Text(item.label),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
