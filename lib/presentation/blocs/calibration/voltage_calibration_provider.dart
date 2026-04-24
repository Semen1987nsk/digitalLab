import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../../../domain/entities/calibration_data.dart';

// ═══════════════════════════════════════════════════════════════
//  VOLTAGE CALIBRATION PROVIDER
//
//  Программная калибровка напряжения (Vernier/PASCO-style):
//  • Quick Zero: offset = -raw, gain = 1.0
//  • Two-Point Linear: gain + offset из двух опорных точек
//  • Persistence: JSON файл через path_provider
//  • Reset to Factory: gain=1.0, offset=0.0
//
//  Калибровка применяется В ПРИЛОЖЕНИИ, не в прошивке.
//  HAL выдаёт сырые данные → UI применяет calibration.apply(raw).
//
//  Usage in UI:
//    final calState = ref.watch(voltageCalibrationProvider);
//    final rawPacket = ref.watch(sensorDataStreamProvider);
//    final calibrated = calState.calibration.apply(rawPacket.voltageV);
// ═══════════════════════════════════════════════════════════════

/// Полное состояние UI калибровки
class VoltageCalibrationState {
  /// Текущая калибровка
  final VoltageCalibration calibration;

  /// Шаг мастера двухточечной калибровки
  final TwoPointWizardStep wizardStep;

  /// Временная нулевая точка (пока мастер не применён)
  final CalibrationPoint? pendingZeroPoint;

  /// Временная опорная точка (пока мастер не применён)
  final CalibrationPoint? pendingReferencePoint;

  /// Введённое пользователем опорное значение (эталон)
  final double? pendingReferenceValue;

  /// Флаг загрузки (для персистентности)
  final bool isLoading;

  /// Последняя ошибка
  final String? error;

  const VoltageCalibrationState({
    this.calibration = const VoltageCalibration.factory(),
    this.wizardStep = TwoPointWizardStep.idle,
    this.pendingZeroPoint,
    this.pendingReferencePoint,
    this.pendingReferenceValue,
    this.isLoading = false,
    this.error,
  });

  VoltageCalibrationState copyWith({
    VoltageCalibration? calibration,
    TwoPointWizardStep? wizardStep,
    CalibrationPoint? pendingZeroPoint,
    bool clearPendingZero = false,
    CalibrationPoint? pendingReferencePoint,
    bool clearPendingReference = false,
    double? pendingReferenceValue,
    bool clearPendingReferenceValue = false,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return VoltageCalibrationState(
      calibration: calibration ?? this.calibration,
      wizardStep: wizardStep ?? this.wizardStep,
      pendingZeroPoint:
          clearPendingZero ? null : (pendingZeroPoint ?? this.pendingZeroPoint),
      pendingReferencePoint: clearPendingReference
          ? null
          : (pendingReferencePoint ?? this.pendingReferencePoint),
      pendingReferenceValue: clearPendingReferenceValue
          ? null
          : (pendingReferenceValue ?? this.pendingReferenceValue),
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class VoltageCalibrationNotifier
    extends StateNotifier<VoltageCalibrationState> {
  VoltageCalibrationNotifier() : super(const VoltageCalibrationState()) {
    _loadFromDisk();
  }

  // ── Persistence ────────────────────────────────────────────

  static const _fileName = 'voltage_calibration.json';

  Future<File> get _file async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<void> _loadFromDisk() async {
    state = state.copyWith(isLoading: true);
    try {
      final file = await _file;
      if (await file.exists()) {
        final json = await file.readAsString();
        final calibration = VoltageCalibration.fromJsonString(json);
        state = state.copyWith(
          calibration: calibration,
          isLoading: false,
        );
        debugPrint('Calibration: loaded from disk — $calibration');
      } else {
        state = state.copyWith(isLoading: false);
        debugPrint('Calibration: no saved data, using factory defaults');
      }
    } catch (e) {
      debugPrint('Calibration: ошибка загрузки: $e');
      state = state.copyWith(
        isLoading: false,
        error: 'Не удалось загрузить калибровку',
      );
    }
  }

  Future<void> _saveToDisk(VoltageCalibration calibration) async {
    try {
      final file = await _file;
      await file.writeAsString(calibration.toJsonString());
      debugPrint('Calibration: saved to disk — $calibration');
    } catch (e) {
      debugPrint('Calibration: ошибка сохранения: $e');
    }
  }

  // ── Quick Zero (1-point) ───────────────────────────────────
  //
  // Самый частый сценарий: учитель нажимает «Ноль» перед экспериментом.
  // Offset = -rawValue, gain = 1.0
  // Результат: дисплей показывает 0.000 В при текущем значении.

  void quickZero(double currentRawValue) {
    final calibration = VoltageCalibration(
      gain: 1.0,
      offset: -currentRawValue,
      level: CalibrationLevel.session,
      calibratedAt: DateTime.now(),
      zeroPoint: CalibrationPoint(
        rawValue: currentRawValue,
        referenceValue: 0.0,
      ),
    );

    state = state.copyWith(
      calibration: calibration,
      clearError: true,
    );

    debugPrint(
      'Calibration: quick zero applied '
      '(raw=$currentRawValue → offset=${calibration.offset})',
    );

    // Сессионная калибровка НЕ сохраняется на диск (живёт до перезапуска)
  }

  // ── Two-Point Linear Calibration ───────────────────────────
  //
  // Профессиональная калибровка (Vernier/Fluke standard):
  // 1. Учитель задаёт нулевую точку (вход замкнут / 0В)
  // 2. Учитель подаёт опорное напряжение (батарея / блок питания)
  // 3. Вводит эталонное значение (показания мультиметра)
  // 4. Система вычисляет gain + offset

  /// Начать мастер двухточечной калибровки
  void startTwoPointWizard() {
    state = state.copyWith(
      wizardStep: TwoPointWizardStep.setZero,
      clearPendingZero: true,
      clearPendingReference: true,
      clearPendingReferenceValue: true,
      clearError: true,
    );
  }

  /// Шаг 1: Зафиксировать нулевую точку
  void captureZeroPoint(double rawValue) {
    state = state.copyWith(
      pendingZeroPoint: CalibrationPoint(
        rawValue: rawValue,
        referenceValue: 0.0,
      ),
      wizardStep: TwoPointWizardStep.setReference,
    );
    debugPrint('Calibration: zero point captured (raw=$rawValue)');
  }

  /// Шаг 2: Зафиксировать опорную точку
  void captureReferencePoint(double rawValue) {
    state = state.copyWith(
      pendingReferencePoint: CalibrationPoint(
        rawValue: rawValue,
        referenceValue: state.pendingReferenceValue ?? 5.0,
      ),
    );
    debugPrint('Calibration: reference point captured (raw=$rawValue)');
  }

  /// Установить эталонное значение (из мультиметра)
  void setReferenceValue(double value) {
    state = state.copyWith(pendingReferenceValue: value);

    // Если точка уже зафиксирована — обновляем referenceValue
    if (state.pendingReferencePoint != null) {
      state = state.copyWith(
        pendingReferencePoint: CalibrationPoint(
          rawValue: state.pendingReferencePoint!.rawValue,
          referenceValue: value,
        ),
      );
    }
  }

  /// Шаг 3: Применить двухточечную калибровку
  void applyTwoPoint() {
    final zero = state.pendingZeroPoint;
    final ref = state.pendingReferencePoint;

    if (zero == null || ref == null) {
      state = state.copyWith(
        error: 'Необходимо задать обе точки калибровки',
      );
      return;
    }

    // Защита от деления на ноль
    final deltaRaw = ref.rawValue - zero.rawValue;
    if (deltaRaw.abs() < 1e-9) {
      state = state.copyWith(
        error: 'Сырые значения в двух точках совпадают. '
            'Подайте другое напряжение для второй точки.',
      );
      return;
    }

    // Вычисляем gain и offset
    final gain = (ref.referenceValue - zero.referenceValue) / deltaRaw;
    final offset = zero.referenceValue - gain * zero.rawValue;

    // Валидация: gain должен быть разумным (0.1–10.0 для вольтметра)
    if (gain <= 0 || gain > 10.0) {
      state = state.copyWith(
        error:
            'Вычисленный коэффициент gain=${gain.toStringAsFixed(4)} '
            'выходит за допустимый диапазон. Проверьте опорные значения.',
      );
      return;
    }

    final calibration = VoltageCalibration(
      gain: gain,
      offset: offset,
      level: CalibrationLevel.user,
      calibratedAt: DateTime.now(),
      zeroPoint: zero,
      referencePoint: ref,
    );

    state = state.copyWith(
      calibration: calibration,
      wizardStep: TwoPointWizardStep.done,
      clearError: true,
    );

    // Пользовательская калибровка сохраняется на диск
    _saveToDisk(calibration);

    debugPrint(
      'Calibration: two-point applied '
      '(gain=${gain.toStringAsFixed(6)}, offset=${offset.toStringAsFixed(6)})',
    );
  }

  /// Отменить мастер
  void cancelWizard() {
    state = state.copyWith(
      wizardStep: TwoPointWizardStep.idle,
      clearPendingZero: true,
      clearPendingReference: true,
      clearPendingReferenceValue: true,
      clearError: true,
    );
  }

  // ── Reset ──────────────────────────────────────────────────

  /// Сброс к заводским настройкам
  void resetToFactory() {
    state = state.copyWith(
      calibration: const VoltageCalibration.factory(),
      wizardStep: TwoPointWizardStep.idle,
      clearPendingZero: true,
      clearPendingReference: true,
      clearPendingReferenceValue: true,
      clearError: true,
    );

    // Удаляем файл калибровки
    _deleteDiskFile();
    debugPrint('Calibration: reset to factory');
  }

  Future<void> _deleteDiskFile() async {
    try {
      final file = await _file;
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('Calibration: ошибка удаления файла: $e');
    }
  }
}

// ═══════════════════════════════════════════════════════════════
//  RIVERPOD PROVIDER
// ═══════════════════════════════════════════════════════════════

/// Провайдер калибровки напряжения — глобальный синглтон
final voltageCalibrationProvider = StateNotifierProvider<
    VoltageCalibrationNotifier, VoltageCalibrationState>(
  (ref) => VoltageCalibrationNotifier(),
);
