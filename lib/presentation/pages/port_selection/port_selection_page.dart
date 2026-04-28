import 'package:flutter/material.dart';
import '../../../data/hal/port_scanner.dart';
import '../../../data/hal/port_connection_manager.dart';
import '../../themes/app_theme.dart';
import '../../widgets/labosfera_app_bar.dart';

/// Страница выбора COM-порта с диагностикой
class PortSelectionPage extends StatefulWidget {
  /// Callback при успешном выборе порта
  final void Function(String portName)? onPortSelected;

  const PortSelectionPage({super.key, this.onPortSelected});

  @override
  State<PortSelectionPage> createState() => _PortSelectionPageState();
}

class _PortSelectionPageState extends State<PortSelectionPage> {
  final PortScanner _scanner = PortScanner();
  List<PortInfo> _ports = [];
  bool _isScanning = false;
  bool _isConnecting = false;
  bool _showDiagnostics = false;
  String? _selectedPort;
  String _log = '';

  @override
  void initState() {
    super.initState();
    _scanPorts();
  }

  void _addLog(String message) {
    setState(() {
      _log = '$_log\n$message';
    });
  }

  Future<void> _scanPorts() async {
    setState(() {
      _isScanning = true;
      _selectedPort = null; // Сбрасываем выбор
      _log = 'Сканирование портов...\n';
    });

    final ports = await _scanner.scanPorts(
      testAvailability: true,
      onProgress: _addLog,
    );

    setState(() {
      _ports = ports;
      _isScanning = false;
    });

    _addLog('\nНайдено ${ports.length} портов');

    // Автоматически выбираем ТОЛЬКО если это наш датчик (FTDI)
    final best = _scanner.findBestSensorPort(ports);
    if (best != null && best.isLikelyOurSensor) {
      setState(() => _selectedPort = best.name);
      _addLog('✓ Датчик найден: ${best.name}');
    } else {
      _addLog('⚠ Датчик НЕ найден! Подключите USB-датчик.');
    }
  }

  Future<void> _connectToPort(PortInfo port) async {
    setState(() {
      _isConnecting = true;
      _log = '$_log\n\n--- Подключение к ${port.name} ---\n';
    });

    final manager = PortConnectionManager(
      onLog: _addLog,
    );

    final result = await manager.connect(port.name);

    if (result.success) {
      _addLog('\n✅ УСПЕШНО подключено!');
      _addLog('Метод: ${result.methodUsed}');

      // Закрываем тестовое подключение
      manager.closePort(result.port);

      // Вызываем callback
      widget.onPortSelected?.call(port.name);

      // Показываем сообщение об успехе
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Порт ${port.name} готов к работе'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } else {
      _addLog('\n❌ ОШИБКА подключения');
      _addLog(result.errorMessage ?? 'Неизвестная ошибка');

      // Показываем диалог с ошибкой
      if (mounted) {
        _showErrorDialog(result.errorMessage ?? 'Не удалось подключиться');
      }
    }

    setState(() => _isConnecting = false);
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: AppColors.error),
            SizedBox(width: 8),
            Text('Ошибка подключения'),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedPortInfo =
        _ports.where((p) => p.name == _selectedPort).firstOrNull;

    return Scaffold(
      backgroundColor: context.palette.background,
      appBar: LabosferaAppBar(
        title: 'Выбор COM-порта',
        subtitle: _hasSensorPort
            ? 'Датчик найден — выберите порт для подключения'
            : 'Подключите USB-датчик и обновите список',
        actions: [
          IconButton(
            icon: _isScanning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: _isScanning ? null : _scanPorts,
            tooltip: 'Обновить список',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildOverviewCard(selectedPortInfo),
          const SizedBox(height: 16),
          _buildConnectionChecklist(),
          const SizedBox(height: 16),
          _buildPortSection(),
          const SizedBox(height: 16),
          _buildDiagnosticsSection(),
        ],
      ),
    );
  }

  /// Проверяет, есть ли среди портов наш датчик (FTDI)
  bool get _hasSensorPort => _ports.any((p) => p.isLikelyOurSensor);

  Widget _buildPortSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Доступные порты',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Сначала выберите датчик, затем нажмите «Подключить».',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _isScanning ? null : _scanPorts,
                  icon: _isScanning
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: Text(_isScanning ? 'Поиск...' : 'Обновить'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildPortList(),
          ],
        ),
      ),
    );
  }

  Widget _buildPortList() {
    if (_isScanning && _ports.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Ищем доступные COM-порты...'),
          ],
        ),
      );
    }

    if (_ports.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.usb_off, size: 64, color: AppColors.textHint),
            const SizedBox(height: 16),
            const Text(
              'COM-порты не найдены',
              style: TextStyle(fontSize: 18, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            const Text(
              'Подключите датчик и нажмите "Обновить"',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _scanPorts,
              icon: const Icon(Icons.refresh),
              label: const Text('Обновить'),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_hasSensorPort)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.warning.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: AppColors.warning,
                  size: 28,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Датчик не обнаружен!',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: AppColors.warning,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Подключите USB-датчик и нажмите "Обновить" (↻)',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _scanPorts,
                  icon: const Icon(Icons.refresh, color: AppColors.warning),
                  tooltip: 'Обновить список портов',
                ),
              ],
            ),
          ),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _ports.length,
          itemBuilder: (ctx, index) => _buildPortCard(_ports[index]),
        ),
      ],
    );
  }

  Widget _buildPortCard(PortInfo port) {
    final isSelected = port.name == _selectedPort;
    final isOurSensor = port.isLikelyOurSensor;

    return _HoverablePortCard(
      isSelected: isSelected,
      isOurSensor: isOurSensor,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _selectedPort = port.name),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Иконка типа порта
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _getTypeColor(port.type).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _getTypeIcon(port.type),
                  color: _getTypeColor(port.type),
                ),
              ),
              const SizedBox(width: 16),

              // Информация о порте
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          port.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (isOurSensor) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              'ДАТЧИК',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: AppColors.success,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      port.description.isNotEmpty
                          ? port.description
                          : port.typeDescription,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _buildStatusBadge(port),
                        const SizedBox(width: 8),
                        Text(
                          port.typeDescription,
                          style: const TextStyle(
                            color: AppColors.textHint,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              if (isSelected)
                FilledButton(
                  onPressed: _isConnecting ? null : () => _connectToPort(port),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                  child: _isConnecting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Подключить'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(PortInfo port) {
    Color color;
    String text;

    switch (port.availability) {
      case PortAvailability.available:
        color = AppColors.success;
        text = 'Доступен';
        break;
      case PortAvailability.accessDenied:
        color = AppColors.warning;
        text = 'Запрещён';
        break;
      case PortAvailability.busy:
        color = AppColors.error;
        text = 'Занят';
        break;
      case PortAvailability.error:
        color = AppColors.error;
        text = 'Ошибка';
        break;
      case PortAvailability.untested:
        color = AppColors.textHint;
        text = '???';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  IconData _getTypeIcon(PortType type) {
    switch (type) {
      case PortType.ftdi:
        return Icons.sensors;
      case PortType.arduino:
        return Icons.developer_board;
      case PortType.bluetooth:
        return Icons.bluetooth;
      case PortType.builtin:
        return Icons.computer;
      case PortType.virtual:
        return Icons.cloud;
      case PortType.unknown:
        return Icons.usb;
    }
  }

  Color _getTypeColor(PortType type) {
    switch (type) {
      case PortType.ftdi:
        return AppColors.success;
      case PortType.arduino:
        return AppColors.primary;
      case PortType.bluetooth:
        return AppColors.portBluetooth;
      case PortType.builtin:
        return AppColors.textSecondary;
      case PortType.virtual:
        return AppColors.portVirtual;
      case PortType.unknown:
        return AppColors.warning;
    }
  }

  Widget _buildOverviewCard(PortInfo? selectedPortInfo) {
    final hasSensor = _hasSensorPort;
    final selectedName = selectedPortInfo?.name;
    final title = hasSensor
        ? 'Датчик найден. Можно подключаться.'
        : 'Сначала найдите подключённый USB-датчик.';
    final subtitle = selectedName != null
        ? 'Выбран порт $selectedName. После проверки нажмите «Подключить».'
        : hasSensor
            ? 'Мы отметили подходящие порты. Выберите нужный порт в списке ниже.'
            : 'Если датчик уже подключён, обновите список и проверьте кабель USB.';
    final color = hasSensor ? AppColors.success : AppColors.warning;
    final icon = hasSensor ? Icons.check_circle_outline : Icons.usb_off;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
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

  Widget _buildConnectionChecklist() {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Как подключить датчик',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            SizedBox(height: 12),
            _ChecklistRow(
              icon: Icons.cable,
              text: 'Подключите датчик к компьютеру по USB.',
            ),
            _ChecklistRow(
              icon: Icons.refresh,
              text: 'Нажмите «Обновить», чтобы заново проверить COM-порты.',
            ),
            _ChecklistRow(
              icon: Icons.sensors,
              text:
                  'Выберите порт с пометкой «ДАТЧИК» или подходящий COM-порт.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiagnosticsSection() {
    return Card(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: _showDiagnostics,
          onExpansionChanged: (value) =>
              setState(() => _showDiagnostics = value),
          tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          leading: const Icon(Icons.manage_search, color: AppColors.info),
          title: const Text(
            'Диагностика подключения',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          subtitle: const Text(
            'Журнал для сложных случаев, если датчик не определяется.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          children: [
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 140, maxHeight: 260),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.diagnosticsSurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Системный журнал',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => setState(() => _log = ''),
                        icon: const Icon(Icons.delete_outline, size: 16),
                        label: const Text('Очистить'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      reverse: true,
                      child: Text(
                        _log.isEmpty ? 'Журнал пока пуст.' : _log,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: AppColors.textPrimary,
                          height: 1.45,
                        ),
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

class _ChecklistRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _ChecklistRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Port card с hover-эффектом и поднятием при наведении мыши.
/// Стилизация берётся из родительского _buildPortCard через props,
/// но hover-logic и AnimatedContainer изолированы здесь.
class _HoverablePortCard extends StatefulWidget {
  const _HoverablePortCard({
    required this.isSelected,
    required this.isOurSensor,
    required this.child,
  });

  final bool isSelected;
  final bool isOurSensor;
  final Widget child;

  @override
  State<_HoverablePortCard> createState() => _HoverablePortCardState();
}

class _HoverablePortCardState extends State<_HoverablePortCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final baseBorder = widget.isSelected
        ? AppColors.primary.withValues(alpha: 0.45)
        : widget.isOurSensor
            ? AppColors.success.withValues(alpha: 0.35)
            : AppColors.cardBorder;
    final hoverBorder = widget.isOurSensor
        ? AppColors.success.withValues(alpha: 0.75)
        : AppColors.primary.withValues(alpha: 0.55);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        transform: _hover
            ? (Matrix4.identity()..translateByDouble(0.0, -2.0, 0.0, 1.0))
            : Matrix4.identity(),
        child: Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: _hover ? hoverBorder : baseBorder,
              width:
                  (widget.isSelected || widget.isOurSensor || _hover) ? 1.5 : 1,
            ),
          ),
          color: widget.isSelected
              ? AppColors.primary.withValues(alpha: 0.08)
              : AppColors.surface,
          child: widget.child,
        ),
      ),
    );
  }
}
