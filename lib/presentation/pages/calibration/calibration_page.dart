import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../domain/entities/calibration_data.dart';
import '../../../domain/entities/sensor_data.dart';
import '../../blocs/calibration/voltage_calibration_provider.dart';
import '../../blocs/experiment/experiment_provider.dart';
import '../../themes/app_theme.dart';
import '../../widgets/labosfera_app_bar.dart';

// ═══════════════════════════════════════════════════════════════
//  КАЛИБРОВКА НАПРЯЖЕНИЯ — Premium Calibration Page
//
//  Вдохновлено:
//  • Vernier Go Direct — 2-point wizard, clean UX
//  • Fluke 5520A — precision display, tolerance checking
//  • PASCO SPARKvue — touch-friendly, visual feedback
//  • Keithley 2450 — professional metering digits
//
//  Архитектура: 3-уровневая калибровка
//  L1: Заводская (gain=1.0, offset=0.0) — default
//  L2: Пользовательская (2-point, сохраняется в JSON)
//  L3: Сессионная (Quick Zero, живёт до перезапуска)
//
//  Формула: calibrated = raw × gain + offset
// ═══════════════════════════════════════════════════════════════

/// Цвет напряжения (из SensorType.voltage.color = AppColors.oscChannel1).
/// Не выносим в SensorType.color напрямую, т. к. dim-вариант — strictly UI-токен.
const _kVoltageColor = AppColors.oscChannel1;
const _kVoltageColorDim = Color(0xFFCDBB30);

class CalibrationPage extends ConsumerStatefulWidget {
  const CalibrationPage({super.key});

  @override
  ConsumerState<CalibrationPage> createState() => _CalibrationPageState();
}

class _CalibrationPageState extends ConsumerState<CalibrationPage> {
  final _referenceController = TextEditingController(text: '5.000');

  @override
  void dispose() {
    _referenceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final calState = ref.watch(voltageCalibrationProvider);
    final connectionState = ref.watch(sensorConnectionProvider);
    final isConnected = connectionState.status == ConnectionStatus.connected;

    // Live voltage from sensor stream
    double? rawVoltage;
    if (isConnected) {
      ref.watch(sensorDataStreamProvider).whenData((p) {
        rawVoltage = p.voltageV;
      });
    }

    final calibratedVoltage =
        rawVoltage != null ? calState.calibration.apply(rawVoltage!) : null;

    return Scaffold(
      backgroundColor: context.palette.background,
      appBar: LabosferaAppBar(
        title: 'Калибровка напряжения',
        subtitle: 'Точность измерений — основа честного эксперимента',
        automaticallyImplyLeading: false,
        actions: [
          _CalibrationLevelBadge(level: calState.calibration.level),
          const SizedBox(width: 12),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── 1. Живой вольтметр ──────────────────────────────
          _VoltmeterCard(
            rawVoltage: rawVoltage,
            calibratedVoltage: calibratedVoltage,
            calibration: calState.calibration,
            isConnected: isConnected,
          ),
          const SizedBox(height: 16),

          // ── 2. Ошибка (если есть) ───────────────────────────
          if (calState.error != null) ...[
            _ErrorBanner(message: calState.error!),
            const SizedBox(height: 16),
          ],

          // ── 3. Быстрый ноль ─────────────────────────────────
          _QuickZeroCard(
            rawVoltage: rawVoltage,
            isConnected: isConnected,
            onZero: () {
              if (rawVoltage != null) {
                ref
                    .read(voltageCalibrationProvider.notifier)
                    .quickZero(rawVoltage!);
              }
            },
          ),
          const SizedBox(height: 16),

          // ── 4. Двухточечная калибровка ───────────────────────
          _TwoPointCard(
            calState: calState,
            rawVoltage: rawVoltage,
            isConnected: isConnected,
            referenceController: _referenceController,
            onStartWizard: () {
              ref
                  .read(voltageCalibrationProvider.notifier)
                  .startTwoPointWizard();
            },
            onCaptureZero: () {
              if (rawVoltage != null) {
                ref
                    .read(voltageCalibrationProvider.notifier)
                    .captureZeroPoint(rawVoltage!);
              }
            },
            onCaptureReference: () {
              if (rawVoltage != null) {
                final refValue =
                    double.tryParse(_referenceController.text) ?? 5.0;
                ref
                    .read(voltageCalibrationProvider.notifier)
                    .setReferenceValue(refValue);
                ref
                    .read(voltageCalibrationProvider.notifier)
                    .captureReferencePoint(rawVoltage!);
              }
            },
            onApply: () {
              ref.read(voltageCalibrationProvider.notifier).applyTwoPoint();
            },
            onCancel: () {
              ref.read(voltageCalibrationProvider.notifier).cancelWizard();
            },
          ),
          const SizedBox(height: 16),

          // ── 5. Информация о калибровке ──────────────────────
          _CalibrationInfoCard(calibration: calState.calibration),
          const SizedBox(height: 16),

          // ── 6. Сброс к заводским ────────────────────────────
          if (calState.calibration.isModified) ...[
            _ResetCard(
              onReset: () => _showResetDialog(context, ref),
            ),
            const SizedBox(height: 24),
          ],
        ],
      ),
    );
  }

  void _showResetDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.warning),
            SizedBox(width: 12),
            Text('Сброс калибровки'),
          ],
        ),
        content: const Text(
          'Все настройки калибровки напряжения будут удалены.\n'
          'Датчик вернётся к заводским параметрам (gain=1.0, offset=0.0).',
          style: TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            onPressed: () {
              ref.read(voltageCalibrationProvider.notifier).resetToFactory();
              Navigator.pop(ctx);
            },
            child: const Text('Сбросить'),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  БЕЙДЖ УРОВНЯ КАЛИБРОВКИ
// ═══════════════════════════════════════════════════════════════

class _CalibrationLevelBadge extends StatelessWidget {
  final CalibrationLevel level;
  const _CalibrationLevelBadge({required this.level});

  @override
  Widget build(BuildContext context) {
    final (color, icon, label) = switch (level) {
      CalibrationLevel.factory => (
          AppColors.textHint,
          Icons.factory_outlined,
          'Заводская',
        ),
      CalibrationLevel.user => (
          AppColors.primary,
          Icons.person,
          'Пользовательская',
        ),
      CalibrationLevel.session => (
          AppColors.warning,
          Icons.access_time,
          'Сессионная',
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  КАРТОЧКА ВОЛЬТМЕТРА — Большие цифры (Keithley/Fluke style)
//
//  • Калиброванное значение — крупный шрифт с glow
//  • Сырое значение — мелкий шрифт снизу (для контроля)
//  • Статус подключения с анимацией
// ═══════════════════════════════════════════════════════════════

class _VoltmeterCard extends StatelessWidget {
  final double? rawVoltage;
  final double? calibratedVoltage;
  final VoltageCalibration calibration;
  final bool isConnected;

  const _VoltmeterCard({
    required this.rawVoltage,
    required this.calibratedVoltage,
    required this.calibration,
    required this.isConnected,
  });

  @override
  Widget build(BuildContext context) {
    final displayValue = calibratedVoltage ?? rawVoltage;
    final displayText =
        displayValue != null ? displayValue.toStringAsFixed(3) : '—.———';

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isConnected
              ? _kVoltageColor.withValues(alpha: 0.3)
              : AppColors.cardBorder,
          width: isConnected ? 1.5 : 1,
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            isConnected
                ? _kVoltageColor.withValues(alpha: 0.06)
                : AppColors.surface,
            AppColors.surface,
          ],
        ),
      ),
      child: Column(
        children: [
          // Заголовок
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _kVoltageColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.bolt, color: _kVoltageColor, size: 24),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Вольтметр',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    isConnected ? 'Датчик подключён' : 'Датчик не подключён',
                    style: TextStyle(
                      fontSize: 12,
                      color: isConnected
                          ? AppColors.success
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              // Glow dot
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isConnected ? AppColors.success : AppColors.textHint,
                  boxShadow: isConnected
                      ? [
                          BoxShadow(
                            color: AppColors.success.withValues(alpha: 0.5),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Большое число (Keithley/Fluke DMM style) ──
          Text(
            displayText,
            style: TextStyle(
              fontSize: 56,
              fontWeight: FontWeight.w300,
              color: isConnected ? _kVoltageColor : AppColors.textHint,
              fontFeatures: const [FontFeature.tabularFigures()],
              letterSpacing: 2,
              shadows: isConnected
                  ? [
                      Shadow(
                        color: _kVoltageColor.withValues(alpha: 0.3),
                        blurRadius: 20,
                      ),
                    ]
                  : null,
            ),
          ),

          // Единица
          Text(
            'Вольт',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w400,
              color: isConnected
                  ? _kVoltageColor.withValues(alpha: 0.6)
                  : AppColors.textHint,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 16),

          // ── Сырое значение + дельта ──
          if (rawVoltage != null && calibration.isModified) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Сырое: ${rawVoltage!.toStringAsFixed(4)} В',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'Δ ${((calibratedVoltage ?? 0) - rawVoltage!).toStringAsFixed(4)} В',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.primary.withValues(alpha: 0.7),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ] else if (!isConnected) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Подключите датчик для калибровки',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textHint,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  БЫСТРЫЙ НОЛЬ (Zero-offset)
//
//  Один тап — и текущее значение становится нулём.
//  Самый частый сценарий в школе (Vernier Quick Zero).
// ═══════════════════════════════════════════════════════════════

class _QuickZeroCard extends StatelessWidget {
  final double? rawVoltage;
  final bool isConnected;
  final VoidCallback onZero;

  const _QuickZeroCard({
    required this.rawVoltage,
    required this.isConnected,
    required this.onZero,
  });

  @override
  Widget build(BuildContext context) {
    final canZero = isConnected && rawVoltage != null;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Заголовок
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.exposure_zero,
                    color: AppColors.accent, size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Быстрый ноль',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'Текущее значение станет нулём',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Инструкция
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline,
                    size: 18, color: AppColors.textSecondary),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Замкните щупы вольтметра или отключите входной '
                    'сигнал, затем нажмите кнопку.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Текущее значение + кнопка
          Row(
            children: [
              if (rawVoltage != null) ...[
                Text(
                  'Текущее: ',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary.withValues(alpha: 0.7),
                  ),
                ),
                Text(
                  '${rawVoltage!.toStringAsFixed(4)} В',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _kVoltageColor,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
              const Spacer(),
              ElevatedButton.icon(
                onPressed: canZero ? onZero : null,
                icon: const Icon(Icons.exposure_zero, size: 20),
                label: const Text('Обнулить'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      AppColors.surfaceBright.withValues(alpha: 0.5),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  ДВУХТОЧЕЧНАЯ КАЛИБРОВКА (Wizard)
//
//  Профессиональная калибровка (Vernier/Fluke standard):
//  Step 1: Нулевая точка (замкнуть щупы → Зафиксировать)
//  Step 2: Опорное напряжение (подать эталон → Ввести → Зафиксировать)
//  Step 3: Применить (gain + offset)
// ═══════════════════════════════════════════════════════════════

class _TwoPointCard extends StatelessWidget {
  final VoltageCalibrationState calState;
  final double? rawVoltage;
  final bool isConnected;
  final TextEditingController referenceController;
  final VoidCallback onStartWizard;
  final VoidCallback onCaptureZero;
  final VoidCallback onCaptureReference;
  final VoidCallback onApply;
  final VoidCallback onCancel;

  const _TwoPointCard({
    required this.calState,
    required this.rawVoltage,
    required this.isConnected,
    required this.referenceController,
    required this.onStartWizard,
    required this.onCaptureZero,
    required this.onCaptureReference,
    required this.onApply,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final wizardActive = calState.wizardStep != TwoPointWizardStep.idle;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: wizardActive
              ? AppColors.primary.withValues(alpha: 0.3)
              : AppColors.cardBorder,
          width: wizardActive ? 1.5 : 1,
        ),
        gradient: wizardActive
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.primary.withValues(alpha: 0.04),
                  AppColors.surface,
                ],
              )
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Заголовок
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.linear_scale,
                    color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Двухточечная калибровка',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'Профессиональная точность (gain + offset)',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (wizardActive)
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  color: AppColors.textSecondary,
                  onPressed: onCancel,
                  tooltip: 'Отмена',
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Контент мастера
          if (!wizardActive)
            _buildStartButton()
          else
            _buildWizardSteps(context),
        ],
      ),
    );
  }

  Widget _buildStartButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: isConnected ? onStartWizard : null,
        icon: const Icon(Icons.play_arrow_rounded, size: 20),
        label: const Text('Начать калибровку'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: BorderSide(
            color: isConnected
                ? AppColors.primary.withValues(alpha: 0.3)
                : AppColors.surfaceBright,
          ),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }

  Widget _buildWizardSteps(BuildContext context) {
    return Column(
      children: [
        // ── Step 1: Zero Point ──
        _WizardStep(
          stepNumber: 1,
          title: 'Нулевая точка',
          description: 'Замкните щупы вольтметра или подключите к точке с 0 В.',
          isActive: calState.wizardStep == TwoPointWizardStep.setZero,
          isCompleted:
              calState.wizardStep.index > TwoPointWizardStep.setZero.index,
          capturedValue: calState.pendingZeroPoint?.rawValue,
          rawVoltage: rawVoltage,
          onCapture: calState.wizardStep == TwoPointWizardStep.setZero &&
                  rawVoltage != null
              ? onCaptureZero
              : null,
        ),
        const SizedBox(height: 12),

        // ── Step 2: Reference Point ──
        _WizardStep(
          stepNumber: 2,
          title: 'Опорная точка',
          description: 'Подайте известное напряжение (батарея, блок питания).',
          isActive: calState.wizardStep == TwoPointWizardStep.setReference,
          isCompleted: calState.wizardStep == TwoPointWizardStep.done,
          capturedValue: calState.pendingReferencePoint?.rawValue,
          rawVoltage: rawVoltage,
          onCapture: calState.wizardStep == TwoPointWizardStep.setReference &&
                  rawVoltage != null
              ? onCaptureReference
              : null,
          referenceInput: calState.wizardStep == TwoPointWizardStep.setReference
              ? _buildReferenceInput(context)
              : null,
        ),

        // ── Apply Button ──
        if (calState.wizardStep == TwoPointWizardStep.setReference &&
            calState.pendingReferencePoint != null) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onApply,
              icon: const Icon(Icons.check_circle_outline, size: 20),
              label: const Text('Применить калибровку'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],

        // ── Success state ──
        if (calState.wizardStep == TwoPointWizardStep.done) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: AppColors.accent.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle,
                    color: AppColors.accent.withValues(alpha: 0.8), size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Калибровка применена!',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.accent,
                        ),
                      ),
                      Text(
                        'gain=${calState.calibration.gain.toStringAsFixed(6)}, '
                        'offset=${calState.calibration.offset.toStringAsFixed(6)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildReferenceInput(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          const Text(
            'Эталон:',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 120,
            child: TextField(
              controller: referenceController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9\.\-]')),
              ],
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: _kVoltageColor,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
              decoration: InputDecoration(
                suffixText: 'В',
                suffixStyle: TextStyle(
                  color: _kVoltageColor.withValues(alpha: 0.6),
                  fontSize: 14,
                ),
                filled: true,
                fillColor: AppColors.surfaceLight,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      BorderSide(color: _kVoltageColor.withValues(alpha: 0.3)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      BorderSide(color: _kVoltageColor.withValues(alpha: 0.2)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      const BorderSide(color: _kVoltageColor, width: 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            '(показания мультиметра)',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textHint,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  ШАГ МАСТЕРА — Step widget with progress indicator
// ═══════════════════════════════════════════════════════════════

class _WizardStep extends StatelessWidget {
  final int stepNumber;
  final String title;
  final String description;
  final bool isActive;
  final bool isCompleted;
  final double? capturedValue;
  final double? rawVoltage;
  final VoidCallback? onCapture;
  final Widget? referenceInput;

  const _WizardStep({
    required this.stepNumber,
    required this.title,
    required this.description,
    required this.isActive,
    required this.isCompleted,
    this.capturedValue,
    this.rawVoltage,
    this.onCapture,
    this.referenceInput,
  });

  @override
  Widget build(BuildContext context) {
    final stepColor = isCompleted
        ? AppColors.accent
        : isActive
            ? AppColors.primary
            : AppColors.textHint;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isActive
            ? AppColors.surfaceLight.withValues(alpha: 0.6)
            : isCompleted
                ? AppColors.accent.withValues(alpha: 0.04)
                : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive
              ? AppColors.primary.withValues(alpha: 0.3)
              : isCompleted
                  ? AppColors.accent.withValues(alpha: 0.15)
                  : AppColors.cardBorder.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Step number circle
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: stepColor.withValues(alpha: isCompleted ? 0.2 : 0.15),
                  border: Border.all(color: stepColor.withValues(alpha: 0.5)),
                ),
                child: Center(
                  child: isCompleted
                      ? Icon(Icons.check, size: 16, color: stepColor)
                      : Text(
                          '$stepNumber',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: stepColor,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isActive || isCompleted
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                      ),
                    ),
                    if (isActive)
                      Text(
                        description,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              // Captured value or capture button
              if (isCompleted && capturedValue != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${capturedValue!.toStringAsFixed(4)} В',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.accent,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                )
              else if (isActive)
                ElevatedButton(
                  onPressed: onCapture,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    minimumSize: Size.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Зафиксировать',
                      style: TextStyle(fontSize: 13)),
                ),
            ],
          ),

          // Live voltage during active step
          if (isActive && rawVoltage != null) ...[
            const SizedBox(height: 8),
            Text(
              'Текущее показание: ${rawVoltage!.toStringAsFixed(4)} В',
              style: const TextStyle(
                fontSize: 12,
                color: _kVoltageColorDim,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],

          // Reference input (for step 2)
          if (referenceInput != null) referenceInput!,
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  ИНФОРМАЦИЯ О КАЛИБРОВКЕ
// ═══════════════════════════════════════════════════════════════

class _CalibrationInfoCard extends StatelessWidget {
  final VoltageCalibration calibration;
  const _CalibrationInfoCard({required this.calibration});

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd.MM.yyyy HH:mm');

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Заголовок
          const Row(
            children: [
              Icon(Icons.info_outline,
                  size: 20, color: AppColors.textSecondary),
              SizedBox(width: 8),
              Text(
                'Параметры калибровки',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Таблица параметров
          _InfoRow(
            label: 'Коэффициент (gain)',
            value: calibration.gain.toStringAsFixed(6),
            isDefault: calibration.gain == 1.0,
          ),
          const SizedBox(height: 8),
          _InfoRow(
            label: 'Смещение (offset)',
            value: '${calibration.offset.toStringAsFixed(6)} В',
            isDefault: calibration.offset == 0.0,
          ),
          const SizedBox(height: 8),
          _InfoRow(
            label: 'Уровень',
            value: calibration.levelName,
            isDefault: calibration.level == CalibrationLevel.factory,
          ),
          if (calibration.calibratedAt != null) ...[
            const SizedBox(height: 8),
            _InfoRow(
              label: 'Дата калибровки',
              value: dateFormat.format(calibration.calibratedAt!),
              isDefault: false,
            ),
          ],

          // Формула
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'V = ${calibration.gain.toStringAsFixed(4)} × raw '
              '${calibration.offset >= 0 ? '+' : '−'} '
              '${calibration.offset.abs().toStringAsFixed(4)}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.primary,
                fontFeatures: [FontFeature.tabularFigures()],
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isDefault;

  const _InfoRow({
    required this.label,
    required this.value,
    required this.isDefault,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isDefault ? AppColors.textHint : AppColors.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  ОШИБКА
// ═══════════════════════════════════════════════════════════════

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.error,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  СБРОС К ЗАВОДСКИМ
// ═══════════════════════════════════════════════════════════════

class _ResetCard extends StatelessWidget {
  final VoidCallback onReset;
  const _ResetCard({required this.onReset});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onReset,
        icon: const Icon(Icons.restart_alt, size: 20),
        label: const Text('Сброс к заводским настройкам'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.error,
          side: BorderSide(color: AppColors.error.withValues(alpha: 0.3)),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }
}
