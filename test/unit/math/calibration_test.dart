import 'package:flutter_test/flutter_test.dart';
import 'package:digital_lab/domain/entities/calibration_data.dart';

// ═══════════════════════════════════════════════════════════════
//  VOLTAGE CALIBRATION — Unit Tests
//
//  Tests cover:
//  • Factory calibration (identity: gain=1.0, offset=0.0)
//  • Quick zero (1-point offset)
//  • Two-point linear calibration (gain + offset)
//  • Edge cases (zero delta, negative values, large gain)
//  • Serialization/deserialization (JSON round-trip)
//  • Inverse transform
// ═══════════════════════════════════════════════════════════════

void main() {
  group('VoltageCalibration', () {
    test('factory calibration is identity transform', () {
      const cal = VoltageCalibration.factory();
      expect(cal.gain, 1.0);
      expect(cal.offset, 0.0);
      expect(cal.level, CalibrationLevel.factory);
      expect(cal.isModified, false);
      expect(cal.calibratedAt, isNull);
    });

    test('factory apply() returns raw value unchanged', () {
      const cal = VoltageCalibration.factory();
      expect(cal.apply(3.14), 3.14);
      expect(cal.apply(0.0), 0.0);
      expect(cal.apply(-1.5), -1.5);
    });

    test('quick zero applies negative offset', () {
      // Simulate: raw reads 0.023V, user zeros → offset = -0.023
      final cal = VoltageCalibration(
        gain: 1.0,
        offset: -0.023,
        level: CalibrationLevel.session,
        calibratedAt: DateTime.now(),
        zeroPoint: const CalibrationPoint(
          rawValue: 0.023,
          referenceValue: 0.0,
        ),
      );

      // After zero: 0.023 → 0.000
      expect(cal.apply(0.023), closeTo(0.0, 1e-12));
      // 5.023 → 5.000
      expect(cal.apply(5.023), closeTo(5.0, 1e-12));
      expect(cal.isModified, true);
      expect(cal.level, CalibrationLevel.session);
    });

    test('two-point linear calibration computes gain and offset', () {
      // Reference points:
      // Point 1: raw=0.05V, actual=0.0V
      // Point 2: raw=5.10V, actual=5.0V
      // gain = (5.0 - 0.0) / (5.10 - 0.05) = 5.0 / 5.05 ≈ 0.990099
      // offset = 0.0 - 0.990099 * 0.05 ≈ -0.04950

      const rawLo = 0.05;
      const rawHi = 5.10;
      const refLo = 0.0;
      const refHi = 5.0;

      const gain = (refHi - refLo) / (rawHi - rawLo);
      const offset = refLo - gain * rawLo;

      final cal = VoltageCalibration(
        gain: gain,
        offset: offset,
        level: CalibrationLevel.user,
        calibratedAt: DateTime.now(),
        zeroPoint:
            const CalibrationPoint(rawValue: rawLo, referenceValue: refLo),
        referencePoint:
            const CalibrationPoint(rawValue: rawHi, referenceValue: refHi),
      );

      // Verify: applying to raw zero point should give ref zero
      expect(cal.apply(rawLo), closeTo(refLo, 1e-10));
      // Verify: applying to raw hi point should give ref hi
      expect(cal.apply(rawHi), closeTo(refHi, 1e-10));
      // Midpoint should be linear
      const rawMid = (rawLo + rawHi) / 2;
      const refMid = (refLo + refHi) / 2;
      expect(cal.apply(rawMid), closeTo(refMid, 1e-10));
      expect(cal.isModified, true);
    });

    test('inverse transform recovers raw value', () {
      final cal = VoltageCalibration(
        gain: 0.990099,
        offset: -0.04950,
        level: CalibrationLevel.user,
        calibratedAt: DateTime.now(),
      );

      const rawValue = 3.5;
      final calibrated = cal.apply(rawValue);
      final recovered = cal.inverse(calibrated);
      expect(recovered, closeTo(rawValue, 1e-6));
    });

    test('inverse with gain=0 returns input (safety)', () {
      const cal = VoltageCalibration(gain: 0, offset: 1.0);
      expect(cal.inverse(5.0), 5.0);
    });

    test('levelName returns Russian names', () {
      expect(
          const VoltageCalibration(level: CalibrationLevel.factory).levelName,
          'Заводская');
      expect(const VoltageCalibration(level: CalibrationLevel.user).levelName,
          'Пользовательская');
      expect(
          const VoltageCalibration(level: CalibrationLevel.session).levelName,
          'Сессионная');
    });

    test('copyWith preserves unmodified fields', () {
      final original = VoltageCalibration(
        gain: 1.5,
        offset: -0.1,
        level: CalibrationLevel.user,
        calibratedAt: DateTime(2026, 1, 15),
        zeroPoint: const CalibrationPoint(rawValue: 0.1, referenceValue: 0.0),
      );

      final modified = original.copyWith(gain: 2.0);
      expect(modified.gain, 2.0);
      expect(modified.offset, -0.1);
      expect(modified.level, CalibrationLevel.user);
      expect(modified.zeroPoint?.rawValue, 0.1);
    });

    test('copyWith clearZeroPoint works', () {
      const original = VoltageCalibration(
        gain: 1.0,
        offset: 0.0,
        zeroPoint: CalibrationPoint(rawValue: 0.5, referenceValue: 0.0),
      );

      final cleared = original.copyWith(clearZeroPoint: true);
      expect(cleared.zeroPoint, isNull);
    });
  });

  group('CalibrationPoint', () {
    test('stores raw and reference values', () {
      const point = CalibrationPoint(rawValue: 3.14, referenceValue: 3.0);
      expect(point.rawValue, 3.14);
      expect(point.referenceValue, 3.0);
    });

    test('toString is readable', () {
      const point = CalibrationPoint(rawValue: 1.5, referenceValue: 1.0);
      expect(point.toString(), contains('1.5'));
      expect(point.toString(), contains('1.0'));
    });
  });

  group('JSON serialization', () {
    test('factory calibration round-trips', () {
      const original = VoltageCalibration.factory();
      final json = original.toJsonString();
      final restored = VoltageCalibration.fromJsonString(json);

      expect(restored.gain, original.gain);
      expect(restored.offset, original.offset);
      expect(restored.level, original.level);
    });

    test('full calibration round-trips', () {
      final original = VoltageCalibration(
        gain: 0.995,
        offset: -0.012,
        level: CalibrationLevel.user,
        calibratedAt: DateTime(2026, 1, 15, 14, 30),
        zeroPoint: const CalibrationPoint(rawValue: 0.012, referenceValue: 0.0),
        referencePoint:
            const CalibrationPoint(rawValue: 5.036, referenceValue: 5.0),
      );

      final json = original.toJsonString();
      final restored = VoltageCalibration.fromJsonString(json);

      expect(restored.gain, closeTo(original.gain, 1e-12));
      expect(restored.offset, closeTo(original.offset, 1e-12));
      expect(restored.level, original.level);
      expect(restored.calibratedAt, original.calibratedAt);
      expect(restored.zeroPoint?.rawValue, original.zeroPoint?.rawValue);
      expect(restored.zeroPoint?.referenceValue,
          original.zeroPoint?.referenceValue);
      expect(
          restored.referencePoint?.rawValue, original.referencePoint?.rawValue);
      expect(restored.referencePoint?.referenceValue,
          original.referencePoint?.referenceValue);
    });

    test('CalibrationPoint JSON round-trips', () {
      const point = CalibrationPoint(rawValue: 3.14, referenceValue: 3.0);
      final json = point.toJson();
      final restored = CalibrationPoint.fromJson(json);

      expect(restored.rawValue, point.rawValue);
      expect(restored.referenceValue, point.referenceValue);
    });

    test('fromJson handles missing optional fields', () {
      final cal = VoltageCalibration.fromJson({
        'gain': 1.0,
        'offset': 0.0,
        'level': 'factory',
      });

      expect(cal.gain, 1.0);
      expect(cal.offset, 0.0);
      expect(cal.calibratedAt, isNull);
      expect(cal.zeroPoint, isNull);
      expect(cal.referencePoint, isNull);
    });

    test('fromJson handles unknown level gracefully', () {
      final cal = VoltageCalibration.fromJson({
        'gain': 1.0,
        'offset': 0.0,
        'level': 'unknown_level',
      });

      expect(cal.level, CalibrationLevel.factory); // fallback
    });
  });

  group('TwoPointWizardStep', () {
    test('has correct ordering via index', () {
      expect(TwoPointWizardStep.idle.index, 0);
      expect(TwoPointWizardStep.setZero.index, 1);
      expect(TwoPointWizardStep.setReference.index, 2);
      expect(TwoPointWizardStep.done.index, 3);
      expect(
        TwoPointWizardStep.setReference.index >
            TwoPointWizardStep.setZero.index,
        true,
      );
    });
  });

  group('Edge cases', () {
    test('calibration with negative raw values', () {
      final cal = VoltageCalibration(
        gain: 1.0,
        offset: 0.5,
        level: CalibrationLevel.session,
        calibratedAt: DateTime.now(),
      );
      expect(cal.apply(-0.5), closeTo(0.0, 1e-12));
      expect(cal.apply(-1.0), closeTo(-0.5, 1e-12));
    });

    test('calibration preserves precision for small values', () {
      // Zero offset of 12mV (common for INA226)
      final cal = VoltageCalibration(
        gain: 1.0,
        offset: -0.012,
        level: CalibrationLevel.session,
        calibratedAt: DateTime.now(),
      );
      expect(cal.apply(0.012), closeTo(0.0, 1e-12));
      expect(cal.apply(0.112), closeTo(0.1, 1e-12));
    });

    test('two-point with very close gain to 1.0', () {
      // Realistic scenario: gain=1.002, offset=-0.005
      final cal = VoltageCalibration(
        gain: 1.002,
        offset: -0.005,
        level: CalibrationLevel.user,
        calibratedAt: DateTime.now(),
      );
      // 5.0V raw → 5.0 * 1.002 - 0.005 = 5.005
      expect(cal.apply(5.0), closeTo(5.005, 1e-10));
      expect(cal.isModified, true);
    });
  });
}
