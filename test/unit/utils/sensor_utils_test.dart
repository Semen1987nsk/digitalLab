import 'package:flutter_test/flutter_test.dart';
import 'package:digital_lab/domain/utils/sensor_utils.dart';
import 'package:digital_lab/domain/entities/sensor_data.dart';
import 'package:digital_lab/domain/entities/sensor_type.dart';

void main() {
  group('SensorUtils.getValue', () {
    test('returns null for null packet', () {
      expect(SensorUtils.getValue(null, SensorType.voltage), isNull);
      expect(SensorUtils.getValue(null, SensorType.temperature), isNull);
    });

    test('returns temperature directly in °C', () {
      const packet = SensorPacket(timestampMs: 0, temperatureC: 23.5);
      expect(
          SensorUtils.getValue(packet, SensorType.temperature), equals(23.5));
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
      expect(SensorUtils.getValue(packet, SensorType.acceleration),
          closeTo(5.0, 0.001));
    });

    test('computes correct acceleration for gravity vector', () {
      // Gravity ≈ (0, 0, 9.81)
      const packet = SensorPacket(
        timestampMs: 0,
        accelX: 0.0,
        accelY: 0.0,
        accelZ: 9.81,
      );
      expect(SensorUtils.getValue(packet, SensorType.acceleration),
          closeTo(9.81, 0.001));
    });

    test('converts pressure from Pa to kPa', () {
      const packet = SensorPacket(timestampMs: 0, pressurePa: 101325.0);
      expect(SensorUtils.getValue(packet, SensorType.pressure),
          closeTo(101.325, 0.001));
    });

    test('returns null for absent sensor fields', () {
      const packet = SensorPacket(timestampMs: 0);
      expect(SensorUtils.getValue(packet, SensorType.temperature), isNull);
      expect(SensorUtils.getValue(packet, SensorType.voltage), isNull);
      expect(SensorUtils.getValue(packet, SensorType.acceleration), isNull);
    });

    test('returns magnetic field value', () {
      const packet = SensorPacket(timestampMs: 0, magneticFieldMt: 48.0);
      expect(
          SensorUtils.getValue(packet, SensorType.magneticField), equals(48.0));
    });
  });

  group('SensorType metadata', () {
    test('all sensor types have correct units', () {
      expect(SensorType.temperature.unit, equals('°C'));
      expect(SensorType.voltage.unit, equals('В'));
      expect(SensorType.current.unit, equals('А'));
      expect(SensorType.acceleration.unit, equals('м/с²'));
      expect(SensorType.pressure.unit, equals('кПа'));
      expect(SensorType.magneticField.unit, equals('мТл'));
    });

    test('all sensor types have Russian titles', () {
      expect(SensorType.temperature.title, equals('Температура'));
      expect(SensorType.voltage.title, equals('Напряжение'));
      expect(SensorType.current.title, equals('Сила тока'));
      expect(SensorType.acceleration.title, equals('Ускорение'));
      expect(SensorType.pressure.title, equals('Давление'));
      expect(SensorType.magneticField.title, equals('Магнитное поле'));
    });

    test('only six multisensor types are enumerated', () {
      // Мультидатчик: 6 величин — без отдельных модулей.
      expect(SensorType.values.length, equals(6));
      expect(SensorType.values, contains(SensorType.voltage));
      expect(SensorType.values, contains(SensorType.current));
      expect(SensorType.values, contains(SensorType.temperature));
      expect(SensorType.values, contains(SensorType.pressure));
      expect(SensorType.values, contains(SensorType.acceleration));
      expect(SensorType.values, contains(SensorType.magneticField));
    });

    test('minRange is positive for all types', () {
      for (final type in SensorType.values) {
        expect(type.minRange, greaterThan(0));
      }
    });
  });

  group('SensorUtils.formatValue', () {
    test('formats with correct decimal places', () {
      // Temperature: 1 decimal place
      final tempFormatted =
          SensorUtils.formatValue(23.456, SensorType.temperature);
      expect(tempFormatted, equals('23.5'));

      // Voltage: 2 decimal places
      final voltFormatted = SensorUtils.formatValue(3.141, SensorType.voltage);
      expect(voltFormatted, equals('3.14'));

      // Current: 3 decimal places
      final currFormatted = SensorUtils.formatValue(0.1234, SensorType.current);
      expect(currFormatted, equals('0.123'));
    });
  });
}
