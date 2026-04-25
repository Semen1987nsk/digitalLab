import 'package:flutter_test/flutter_test.dart';
import 'package:digital_lab/domain/utils/sensor_utils.dart';
import 'package:digital_lab/domain/entities/calibration_data.dart';
import 'package:digital_lab/domain/entities/sensor_data.dart';
import 'package:digital_lab/domain/entities/sensor_type.dart';

void main() {
  group('SensorUtils.getValue', () {
    test('returns null for null packet', () {
      expect(SensorUtils.getValue(null, SensorType.distance), isNull);
      expect(SensorUtils.getValue(null, SensorType.temperature), isNull);
    });

    test('converts distance from mm to cm', () {
      const packet = SensorPacket(timestampMs: 0, distanceMm: 500.0);
      expect(SensorUtils.getValue(packet, SensorType.distance), equals(50.0));
    });

    test('returns temperature directly in °C', () {
      const packet = SensorPacket(timestampMs: 0, temperatureC: 23.5);
      expect(SensorUtils.getValue(packet, SensorType.temperature), equals(23.5));
    });

    test('returns voltage directly', () {
      const packet = SensorPacket(timestampMs: 0, voltageV: 3.3);
      expect(SensorUtils.getValue(packet, SensorType.voltage), equals(3.3));
    });

    test('returns current directly', () {
      const packet = SensorPacket(timestampMs: 0, currentA: 0.15);
      expect(SensorUtils.getValue(packet, SensorType.current), equals(0.15));
    });

    test('computes acceleration magnitude from xyz', () {
      // |a| = sqrt(3^2 + 4^2 + 0^2) = 5.0
      const packet = SensorPacket(
        timestampMs: 0,
        accelX: 3.0,
        accelY: 4.0,
        accelZ: 0.0,
      );
      expect(SensorUtils.getValue(packet, SensorType.acceleration), closeTo(5.0, 0.001));
    });

    test('computes correct acceleration for gravity vector', () {
      // Gravity ≈ (0, 0, 9.81)
      const packet = SensorPacket(
        timestampMs: 0,
        accelX: 0.0,
        accelY: 0.0,
        accelZ: 9.81,
      );
      expect(SensorUtils.getValue(packet, SensorType.acceleration), closeTo(9.81, 0.001));
    });

    test('converts pressure from Pa to kPa', () {
      const packet = SensorPacket(timestampMs: 0, pressurePa: 101325.0);
      expect(SensorUtils.getValue(packet, SensorType.pressure), closeTo(101.325, 0.001));
    });

    test('returns null for absent sensor fields', () {
      const packet = SensorPacket(timestampMs: 0);
      expect(SensorUtils.getValue(packet, SensorType.distance), isNull);
      expect(SensorUtils.getValue(packet, SensorType.temperature), isNull);
      expect(SensorUtils.getValue(packet, SensorType.voltage), isNull);
      expect(SensorUtils.getValue(packet, SensorType.acceleration), isNull);
    });

    test('returns magnetic field value', () {
      const packet = SensorPacket(timestampMs: 0, magneticFieldMt: 48.0);
      expect(SensorUtils.getValue(packet, SensorType.magneticField), equals(48.0));
    });

    test('returns force value', () {
      const packet = SensorPacket(timestampMs: 0, forceN: 5.5);
      expect(SensorUtils.getValue(packet, SensorType.force), equals(5.5));
    });

    test('returns lux value', () {
      const packet = SensorPacket(timestampMs: 0, luxLx: 300.0);
      expect(SensorUtils.getValue(packet, SensorType.lux), equals(300.0));
    });

    test('returns radiation value', () {
      const packet = SensorPacket(timestampMs: 0, radiationCpm: 42.0);
      expect(SensorUtils.getValue(packet, SensorType.radiation), equals(42.0));
    });
  });

  group('SensorType metadata', () {
    test('all sensor types have correct units', () {
      expect(SensorType.distance.unit, equals('см'));
      expect(SensorType.temperature.unit, equals('°C'));
      expect(SensorType.voltage.unit, equals('В'));
      expect(SensorType.current.unit, equals('А'));
      expect(SensorType.acceleration.unit, equals('м/с²'));
      expect(SensorType.pressure.unit, equals('кПа'));
      expect(SensorType.magneticField.unit, equals('мТл'));
      expect(SensorType.force.unit, equals('Н'));
      expect(SensorType.lux.unit, equals('лк'));
      expect(SensorType.radiation.unit, equals('имп/мин'));
    });

    test('all sensor types have Russian titles', () {
      expect(SensorType.distance.title, equals('Расстояние'));
      expect(SensorType.temperature.title, equals('Температура'));
      expect(SensorType.voltage.title, equals('Напряжение'));
      expect(SensorType.current.title, equals('Сила тока'));
      expect(SensorType.acceleration.title, equals('Ускорение'));
      expect(SensorType.pressure.title, equals('Давление'));
    });

    test('all sensor types are enumerated', () {
      // Одна унифицированная версия продукта — все датчики всегда доступны.
      expect(SensorType.values, contains(SensorType.voltage));
      expect(SensorType.values, contains(SensorType.current));
      expect(SensorType.values, contains(SensorType.temperature));
      expect(SensorType.values, contains(SensorType.pressure));
      expect(SensorType.values, contains(SensorType.acceleration));
      expect(SensorType.values, contains(SensorType.magneticField));
      expect(SensorType.values, contains(SensorType.distance));
      expect(SensorType.values, contains(SensorType.force));
      expect(SensorType.values, contains(SensorType.lux));
      expect(SensorType.values, contains(SensorType.radiation));
    });

    test('minRange is positive for all types', () {
      for (final type in SensorType.values) {
        expect(type.minRange, greaterThan(0));
      }
    });
  });

  group('SensorUtils.formatValue', () {
    test('formats with correct decimal places', () {
      // Distance: 1 decimal place
      final distFormatted = SensorUtils.formatValue(12.345, SensorType.distance);
      expect(distFormatted, equals('12.3'));

      // Temperature: 1 decimal place
      final tempFormatted = SensorUtils.formatValue(23.456, SensorType.temperature);
      expect(tempFormatted, equals('23.5'));

      // Voltage: 2 decimal places
      final voltFormatted = SensorUtils.formatValue(3.141, SensorType.voltage);
      expect(voltFormatted, equals('3.14'));
    });
  });

  group('SensorUtils.getCalibratedValue', () {
    test('returns null for null packet', () {
      expect(
        SensorUtils.getCalibratedValue(null, SensorType.voltage),
        isNull,
      );
    });

    test('returns raw voltage when no calibration provided', () {
      const packet = SensorPacket(timestampMs: 100, voltageV: 2.51);
      final value = SensorUtils.getCalibratedValue(packet, SensorType.voltage);
      expect(value, equals(2.51));
    });

    test('applies voltage calibration (quickZero offset)', () {
      const packet = SensorPacket(timestampMs: 100, voltageV: 2.51);
      const cal = VoltageCalibration(gain: 1.0, offset: -2.51);
      final value = SensorUtils.getCalibratedValue(
        packet, SensorType.voltage,
        voltageCalibration: cal,
      );
      expect(value, closeTo(0.0, 1e-10));
    });

    test('applies voltage calibration (two-point gain+offset)', () {
      const packet = SensorPacket(timestampMs: 100, voltageV: 5.10);
      const cal = VoltageCalibration(gain: 0.99, offset: -0.05);
      final value = SensorUtils.getCalibratedValue(
        packet, SensorType.voltage,
        voltageCalibration: cal,
      );
      // 5.10 * 0.99 - 0.05 = 5.049 - 0.05 = 4.999
      expect(value, closeTo(4.999, 1e-10));
    });

    test('does NOT apply voltage calibration to non-voltage sensors', () {
      const packet = SensorPacket(timestampMs: 100, temperatureC: 25.0);
      const cal = VoltageCalibration(gain: 2.0, offset: -10.0);
      final value = SensorUtils.getCalibratedValue(
        packet, SensorType.temperature,
        voltageCalibration: cal,
      );
      // Temperature should NOT be affected by voltage calibration
      expect(value, equals(25.0));
    });

    test('returns null for absent sensor field', () {
      const packet = SensorPacket(timestampMs: 100, temperatureC: 25.0);
      const cal = VoltageCalibration(gain: 1.0, offset: -2.0);
      final value = SensorUtils.getCalibratedValue(
        packet, SensorType.voltage,
        voltageCalibration: cal,
      );
      // voltageV is null in this packet
      expect(value, isNull);
    });
  });
}
