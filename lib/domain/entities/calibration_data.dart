import 'dart:convert';

// ═══════════════════════════════════════════════════════════════
//  CALIBRATION DATA — Software calibration model
//
//  Архитектура калибровки (Vernier/PASCO/Fluke standard):
//
//  Формула: calibrated = raw × gain + offset
//
//  Уровни калибровки (3-tier, как Keithley):
//  L1: Factory  — gain=1.0, offset=0.0 (заводская)
//  L2: User     — двухточечная, сохраняется в JSON
//  L3: Session  — быстрый ноль, живёт до перезапуска
//
//  Двухточечная линейная калибровка:
//  Point1 (rawLo, refLo) — обычно (rawZero, 0.0)
//  Point2 (rawHi, refHi) — опорное напряжение (rawRef, 5.0)
//  gain   = (refHi - refLo) / (rawHi - rawLo)
//  offset = refLo - gain × rawLo
// ═══════════════════════════════════════════════════════════════

/// Уровень калибровки (от простого к сложному)
enum CalibrationLevel {
  /// Заводская: gain=1.0, offset=0.0
  factory,

  /// Пользовательская: двухточечная, сохранена на диск
  user,

  /// Сессионная: быстрый ноль, живёт до перезапуска
  session,
}

/// Точка калибровки: (сырое значение, эталонное значение)
class CalibrationPoint {
  final double rawValue;
  final double referenceValue;

  const CalibrationPoint({
    required this.rawValue,
    required this.referenceValue,
  });

  Map<String, dynamic> toJson() => {
        'raw': rawValue,
        'ref': referenceValue,
      };

  factory CalibrationPoint.fromJson(Map<String, dynamic> json) {
    return CalibrationPoint(
      rawValue: (json['raw'] as num).toDouble(),
      referenceValue: (json['ref'] as num).toDouble(),
    );
  }

  @override
  String toString() => 'CalibrationPoint(raw=$rawValue, ref=$referenceValue)';
}

/// Полное состояние калибровки для одного датчика напряжения
class VoltageCalibration {
  /// Множитель (по умолчанию 1.0)
  final double gain;

  /// Смещение (по умолчанию 0.0)
  final double offset;

  /// Уровень калибровки
  final CalibrationLevel level;

  /// Время последней калибровки
  final DateTime? calibratedAt;

  /// Нулевая точка (опционально)
  final CalibrationPoint? zeroPoint;

  /// Опорная точка (опционально)
  final CalibrationPoint? referencePoint;

  const VoltageCalibration({
    this.gain = 1.0,
    this.offset = 0.0,
    this.level = CalibrationLevel.factory,
    this.calibratedAt,
    this.zeroPoint,
    this.referencePoint,
  });

  /// Заводская калибровка (чистый пропуск)
  const VoltageCalibration.factory()
      : gain = 1.0,
        offset = 0.0,
        level = CalibrationLevel.factory,
        calibratedAt = null,
        zeroPoint = null,
        referencePoint = null;

  /// Применить калибровку к сырому значению
  double apply(double rawValue) => rawValue * gain + offset;

  /// Обратное преобразование: calibrated → raw
  double inverse(double calibratedValue) {
    if (gain == 0) return calibratedValue;
    return (calibratedValue - offset) / gain;
  }

  /// Есть ли отклонение от заводской?
  bool get isModified => gain != 1.0 || offset != 0.0;

  /// Русское название уровня
  String get levelName => switch (level) {
        CalibrationLevel.factory => 'Заводская',
        CalibrationLevel.user => 'Пользовательская',
        CalibrationLevel.session => 'Сессионная',
      };

  VoltageCalibration copyWith({
    double? gain,
    double? offset,
    CalibrationLevel? level,
    DateTime? calibratedAt,
    CalibrationPoint? zeroPoint,
    bool clearZeroPoint = false,
    CalibrationPoint? referencePoint,
    bool clearReferencePoint = false,
  }) {
    return VoltageCalibration(
      gain: gain ?? this.gain,
      offset: offset ?? this.offset,
      level: level ?? this.level,
      calibratedAt: calibratedAt ?? this.calibratedAt,
      zeroPoint: clearZeroPoint ? null : (zeroPoint ?? this.zeroPoint),
      referencePoint:
          clearReferencePoint ? null : (referencePoint ?? this.referencePoint),
    );
  }

  /// Сериализация в JSON (для персистентности)
  Map<String, dynamic> toJson() => {
        'gain': gain,
        'offset': offset,
        'level': level.name,
        'calibratedAt': calibratedAt?.toIso8601String(),
        if (zeroPoint != null) 'zeroPoint': zeroPoint!.toJson(),
        if (referencePoint != null) 'referencePoint': referencePoint!.toJson(),
      };

  /// Десериализация из JSON
  factory VoltageCalibration.fromJson(Map<String, dynamic> json) {
    return VoltageCalibration(
      gain: (json['gain'] as num?)?.toDouble() ?? 1.0,
      offset: (json['offset'] as num?)?.toDouble() ?? 0.0,
      level: CalibrationLevel.values.firstWhere(
        (l) => l.name == json['level'],
        orElse: () => CalibrationLevel.factory,
      ),
      calibratedAt: json['calibratedAt'] != null
          ? DateTime.tryParse(json['calibratedAt'] as String)
          : null,
      zeroPoint: json['zeroPoint'] != null
          ? CalibrationPoint.fromJson(json['zeroPoint'] as Map<String, dynamic>)
          : null,
      referencePoint: json['referencePoint'] != null
          ? CalibrationPoint.fromJson(
              json['referencePoint'] as Map<String, dynamic>)
          : null,
    );
  }

  /// Сериализация в строку JSON
  String toJsonString() => jsonEncode(toJson());

  /// Десериализация из строки JSON
  factory VoltageCalibration.fromJsonString(String jsonString) {
    return VoltageCalibration.fromJson(
      jsonDecode(jsonString) as Map<String, dynamic>,
    );
  }

  @override
  String toString() => 'VoltageCalibration(gain=${gain.toStringAsFixed(6)}, '
      'offset=${offset.toStringAsFixed(6)}, level=$level)';
}

/// Состояние двухточечного мастера калибровки
enum TwoPointWizardStep {
  /// Начальное состояние — мастер не запущен
  idle,

  /// Шаг 1: Зафиксировать нулевую точку
  setZero,

  /// Шаг 2: Зафиксировать опорную точку
  setReference,

  /// Калибровка применена
  done,
}
