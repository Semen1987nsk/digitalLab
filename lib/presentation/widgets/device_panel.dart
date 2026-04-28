import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/sensor_data.dart';
import '../blocs/experiment/experiment_provider.dart';
import '../themes/app_theme.dart';

// ═══════════════════════════════════════════════════════════════════
//  DEVICE PANEL — Панель подключённых устройств
//
//  Вдохновлено лучшими мировыми практиками:
//
//  • Vernier Graphical Analysis: sidebar с per-sensor каналами,
//    цветными точками статуса, живыми значениями
//
//  • PASCO Capstone: Hardware Panel — дерево устройств с
//    индивидуальным статусом и пропускной способностью
//
//  • Saleae Logic: channel list с enable toggles,
//    data rate per device, status bar
//
//  • Phyphox: per-BLE-device cards с ID-тегами и
//    independent lifecycle management
//
//  Ключевые принципы:
//  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  1. КАЖДОЕ устройство — отдельная карточка с индивидуальным статусом
//  2. Цветовое кодирование: зелёный/жёлтый/красный/серый
//  3. Live pkt/s показатель (как Saleae data rate indicator)
//  4. Ошибка показывается ПО УСТРОЙСТВУ (не общая)
//  5. Большие touch-friendly элементы (48dp+) для проекторов
//  6. Анимированные переходы (expand/collapse, pulse)
// ═══════════════════════════════════════════════════════════════════

class DevicePanel extends ConsumerWidget {
  const DevicePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionState = ref.watch(sensorConnectionProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        children: [
          // Основной баннер (всегда)
          _MainBanner(
            status: connectionState.status,
            deviceInfo: connectionState.deviceInfo,
            isMultiDevice: connectionState.isMultiDevice,
            isRecovering: connectionState.isRecovering,
            deviceCount: connectionState.deviceStatuses.length,
            connectedCount: connectionState.deviceStatuses
                .where((d) => d.status == ConnectionStatus.connected)
                .length,
            onConnect: () =>
                ref.read(sensorConnectionProvider.notifier).connect(),
            onDisconnect: () =>
                ref.read(sensorConnectionProvider.notifier).disconnect(),
          ),

          // Per-device cards (только для multi-device при подключении/подключённых)
          if (connectionState.isMultiDevice &&
              connectionState.deviceStatuses.isNotEmpty) ...[
            const SizedBox(height: 6),
            ...connectionState.deviceStatuses.map(
              (device) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: _DeviceCard(device: device),
              ),
            ),
          ],

          // Error message
          if (connectionState.errorMessage != null &&
              connectionState.status == ConnectionStatus.error &&
              !connectionState.isMultiDevice) ...[
            const SizedBox(height: 6),
            _ErrorCard(message: connectionState.errorMessage!),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  MAIN BANNER — Основной баннер статуса (compact)
// ═══════════════════════════════════════════════════════════════════

class _MainBanner extends StatelessWidget {
  final ConnectionStatus status;
  final DeviceInfo? deviceInfo;
  final bool isMultiDevice;
  final bool isRecovering;
  final int deviceCount;
  final int connectedCount;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  const _MainBanner({
    required this.status,
    required this.deviceInfo,
    required this.isMultiDevice,
    required this.isRecovering,
    required this.deviceCount,
    required this.connectedCount,
    required this.onConnect,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _bgColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _bgColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          // Status icon with pulse animation
          _StatusIcon(status: status, color: _bgColor),
          const SizedBox(width: 14),
          // Title + subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: _bgColor,
                    fontSize: 14,
                  ),
                ),
                if (_subtitle != null)
                  Text(
                    _subtitle!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          // Action button
          _buildAction(),
        ],
      ),
    );
  }

  Widget _buildAction() {
    // Во время авто-восстановления показываем спиннер —
    // не нужно пугать учителя кнопкой "Подключить" при коротком обрыве.
    if (isRecovering && status == ConnectionStatus.disconnected) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2.5),
      );
    }
    switch (status) {
      case ConnectionStatus.disconnected:
      case ConnectionStatus.error:
        return FilledButton.tonal(
          onPressed: onConnect,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accent.withValues(alpha: 0.15),
            foregroundColor: AppColors.accent,
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          child: Text(
              status == ConnectionStatus.error ? 'Повторить' : 'Подключить'),
        );
      case ConnectionStatus.connecting:
        return const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        );
      case ConnectionStatus.connected:
        return FilledButton.tonal(
          onPressed: onDisconnect,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.surfaceLight,
            foregroundColor: AppColors.textSecondary,
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          child: const Text('Отключить'),
        );
    }
  }

  Color get _bgColor {
    if (isRecovering && status == ConnectionStatus.disconnected) {
      return AppColors.warning;
    }
    return switch (status) {
      ConnectionStatus.disconnected => AppColors.textHint,
      ConnectionStatus.connecting => AppColors.warning,
      ConnectionStatus.connected => AppColors.success,
      ConnectionStatus.error => AppColors.error,
    };
  }

  String get _title {
    if (isRecovering && status == ConnectionStatus.disconnected) {
      return 'Восстановление связи…';
    }
    if (status == ConnectionStatus.connected && isMultiDevice) {
      return '$connectedCount из $deviceCount устройств подключено';
    }
    return switch (status) {
      ConnectionStatus.disconnected => 'Датчик не подключён',
      ConnectionStatus.connecting => 'Подключение…',
      ConnectionStatus.connected => deviceInfo?.name ?? 'Подключено',
      ConnectionStatus.error => isMultiDevice
          ? 'Нужно проверить подключение устройств'
          : 'Нужно проверить подключение',
    };
  }

  String? get _subtitle {
    if (isRecovering && status == ConnectionStatus.disconnected) {
      return 'Соединение восстанавливается автоматически';
    }
    if (status == ConnectionStatus.connected && !isMultiDevice) {
      return 'v${deviceInfo?.firmwareVersion ?? "?"} · 🔋 ${deviceInfo?.batteryPercent ?? 0}%';
    }
    return switch (status) {
      ConnectionStatus.disconnected => 'Поиск датчиков начнётся автоматически',
      ConnectionStatus.connecting => isMultiDevice
          ? (deviceCount > 0
              ? 'Подключение $deviceCount устройств…'
              : 'Сканирование USB-портов…')
          : 'Поиск устройства…',
      ConnectionStatus.connected => null,
      ConnectionStatus.error => isMultiDevice && deviceCount == 0
          ? 'USB-датчики не обнаружены'
          : 'Соединение восстанавливается автоматически.',
    };
  }
}

// ═══════════════════════════════════════════════════════════════════
//  DEVICE CARD — Per-device status card (Vernier/PASCO style)
// ═══════════════════════════════════════════════════════════════════

class _DeviceCard extends StatelessWidget {
  final DeviceStatusInfo device;

  const _DeviceCard({required this.device});

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor;
    final isConnected = device.status == ConnectionStatus.connected;
    final hasError =
        device.error != null && device.status != ConnectionStatus.connected;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: statusColor.withValues(alpha: hasError ? 0.3 : 0.12),
        ),
      ),
      child: Row(
        children: [
          // ── Status dot (animated pulse for connected) ──
          _PulseDot(
            color: statusColor,
            isActive: isConnected,
            size: 10,
          ),
          const SizedBox(width: 12),

          // ── Device type icon ──
          Icon(
            _deviceIcon,
            size: 18,
            color: statusColor.withValues(alpha: 0.8),
          ),
          const SizedBox(width: 10),

          // ── Name + status text ──
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isConnected
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (hasError)
                  Text(
                    device.error!,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.error.withValues(alpha: 0.9),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),

          // ── Live packet rate (always visible for stable layout) ──
          const SizedBox(width: 8),
          if (isConnected)
            _PacketRateBadge(
              packetsPerSecond: device.packetsPerSecond,
              totalPackets: device.totalPackets,
            )
          else
            // Reserve same space when disconnected to prevent layout jump
            _StatusBadge(status: device.status),
        ],
      ),
    );
  }

  Color get _statusColor => switch (device.status) {
        ConnectionStatus.connected => AppColors.success,
        ConnectionStatus.connecting => AppColors.warning,
        ConnectionStatus.error => AppColors.error,
        ConnectionStatus.disconnected => AppColors.textHint,
      };

  IconData get _deviceIcon {
    final name = device.name.toLowerCase();
    if (name.contains('мульти') || name.contains('arduino')) {
      return Icons.developer_board;
    }
    if (name.contains('расстояни') || name.contains('ftdi')) {
      return Icons.straighten;
    }
    return Icons.sensors;
  }
}

// ═══════════════════════════════════════════════════════════════════
//  PACKET RATE BADGE — Live data rate indicator (Saleae Logic style)
//
//  Shows "10 Гц" when data is flowing, "0" when stalled.
//  Color-coded: green = healthy, yellow = slow, red = stalled.
// ═══════════════════════════════════════════════════════════════════

class _PacketRateBadge extends StatelessWidget {
  final double packetsPerSecond;
  final int totalPackets;

  const _PacketRateBadge({
    required this.packetsPerSecond,
    required this.totalPackets,
  });

  @override
  Widget build(BuildContext context) {
    final rate = packetsPerSecond;
    final color = rate > 5
        ? AppColors.success
        : rate > 1
            ? AppColors.warning
            : AppColors.error;

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 64),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.speed,
              size: 12,
              color: color.withValues(alpha: 0.8),
            ),
            const SizedBox(width: 4),
            Text(
              '${rate.toStringAsFixed(0)} Гц',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  STATUS BADGE — Small status label
// ═══════════════════════════════════════════════════════════════════

class _StatusBadge extends StatelessWidget {
  final ConnectionStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      ConnectionStatus.disconnected => ('Откл.', AppColors.textHint),
      ConnectionStatus.connecting => ('...', AppColors.warning),
      ConnectionStatus.error => ('Проверьте', AppColors.error),
      ConnectionStatus.connected => ('OK', AppColors.success),
    };

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 64),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color.withValues(alpha: 0.8),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  STATUS ICON — Icon with animated container
// ═══════════════════════════════════════════════════════════════════

class _StatusIcon extends StatelessWidget {
  final ConnectionStatus status;
  final Color color;

  const _StatusIcon({required this.status, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(_icon, color: color, size: 22),
    );
  }

  IconData get _icon => switch (status) {
        ConnectionStatus.disconnected => Icons.sensors_off,
        ConnectionStatus.connecting => Icons.sensors,
        ConnectionStatus.connected => Icons.sensors,
        ConnectionStatus.error => Icons.error_outline,
      };
}

// ═══════════════════════════════════════════════════════════════════
//  PULSE DOT — Animated status indicator (green pulse = alive)
//
//  Like Vernier's green dot next to each sensor channel.
//  Pulses gently when connected to indicate live data flow.
// ═══════════════════════════════════════════════════════════════════

class _PulseDot extends StatefulWidget {
  final Color color;
  final bool isActive;
  final double size;

  const _PulseDot({
    required this.color,
    required this.isActive,
    this.size = 10,
  });

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _animation = Tween(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    if (widget.isActive) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _PulseDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _controller.repeat(reverse: true);
    } else if (!widget.isActive && oldWidget.isActive) {
      _controller.stop();
      _controller.value = 0.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Semantics гарантирует, что screen reader объявит состояние
    // в дополнение к цветовому маркеру — важно для доступности.
    final semanticLabel =
        widget.isActive ? 'Устройство активно' : 'Устройство неактивно';

    if (!widget.isActive) {
      // Неактивное состояние — сплошной кружок с контрастной обводкой,
      // чтобы отличалось от активного не только цветом.
      return Semantics(
        label: semanticLabel,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: 0.4),
            shape: BoxShape.circle,
            border: Border.all(
              color: widget.color.withValues(alpha: 0.8),
              width: 1.2,
            ),
          ),
        ),
      );
    }

    return Semantics(
      label: semanticLabel,
      liveRegion: true,
      child: AnimatedBuilder(
        animation: _animation,
        builder: (_, __) => Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: _animation.value * 0.5),
                blurRadius: widget.size * _animation.value,
                spreadRadius: widget.size * 0.2 * _animation.value,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  ERROR CARD — Detailed error display
// ═══════════════════════════════════════════════════════════════════

class _ErrorCard extends StatelessWidget {
  final String message;
  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 16,
            color: AppColors.error.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.error.withValues(alpha: 0.9),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
