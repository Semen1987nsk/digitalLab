import 'package:flutter_test/flutter_test.dart';
import 'package:digital_lab/domain/math/unit_formatter.dart';

void main() {
  group('DistanceFormatter', () {
    test('formats small values as mm', () {
      expect(DistanceFormatter.format(5.0), equals('5.0 мм'));
      expect(DistanceFormatter.format(9.9), equals('9.9 мм'));
    });

    test('formats medium values as cm', () {
      expect(DistanceFormatter.format(50.0), equals('5.0 см'));
      expect(DistanceFormatter.format(100.0), equals('10.0 см'));
    });

    test('formats large values as m', () {
      expect(DistanceFormatter.format(1000.0), equals('1.0 м'));
      expect(DistanceFormatter.format(15000.0), equals('15.0 м'));
    });

    test('handles negative values', () {
      expect(DistanceFormatter.format(-5.0), equals('-5.0 мм'));
      expect(DistanceFormatter.format(-1500.0), equals('-1.5 м'));
    });

    test('converts between units', () {
      expect(
          DistanceFormatter.convert(1000.0, DistanceUnit.mm), equals(1000.0));
      expect(DistanceFormatter.convert(1000.0, DistanceUnit.cm), equals(100.0));
      expect(DistanceFormatter.convert(1000.0, DistanceUnit.m), equals(1.0));
    });

    test('returns correct unit names', () {
      expect(DistanceFormatter.unitName(DistanceUnit.mm), equals('мм'));
      expect(DistanceFormatter.unitName(DistanceUnit.cm), equals('см'));
      expect(DistanceFormatter.unitName(DistanceUnit.m), equals('м'));
    });

    test('bestUnit selects appropriate unit for range', () {
      expect(DistanceFormatter.bestUnit(0, 5), equals(DistanceUnit.mm));
      expect(DistanceFormatter.bestUnit(0, 500), equals(DistanceUnit.cm));
      expect(DistanceFormatter.bestUnit(0, 5000), equals(DistanceUnit.m));
    });

    test('respects decimals parameter', () {
      expect(DistanceFormatter.format(5.123, decimals: 2), equals('5.12 мм'));
      expect(DistanceFormatter.format(5.0, decimals: 0), equals('5 мм'));
    });
  });

  group('TemperatureFormatter', () {
    test('formats with °C', () {
      expect(TemperatureFormatter.format(23.5), equals('23.5 °C'));
    });

    test('converts to Kelvin', () {
      expect(TemperatureFormatter.toKelvin(0.0), closeTo(273.15, 0.001));
      expect(TemperatureFormatter.toKelvin(100.0), closeTo(373.15, 0.001));
    });

    test('converts to Fahrenheit', () {
      expect(TemperatureFormatter.toFahrenheit(0.0), closeTo(32.0, 0.001));
      expect(TemperatureFormatter.toFahrenheit(100.0), closeTo(212.0, 0.001));
    });
  });

  group('VoltageFormatter', () {
    test('formats volts', () {
      expect(VoltageFormatter.format(3.30), equals('3.30 В'));
      expect(VoltageFormatter.format(12.0), equals('12.00 В'));
    });

    test('formats millivolts for small values', () {
      expect(VoltageFormatter.format(0.5), contains('мВ'));
    });
  });

  group('CurrentFormatter', () {
    test('formats amps', () {
      expect(CurrentFormatter.format(1.5), equals('1.500 А'));
    });

    test('formats milliamps', () {
      final result = CurrentFormatter.format(0.015);
      expect(result, contains('мА'));
    });

    test('formats microamps', () {
      final result = CurrentFormatter.format(0.0005);
      expect(result, contains('мкА'));
    });
  });

  group('PressureFormatter', () {
    test('formats Pa for small values', () {
      expect(PressureFormatter.format(500.0), equals('500.0 Па'));
    });

    test('formats kPa for large values', () {
      expect(PressureFormatter.format(101325.0), equals('101.3 кПа'));
    });

    test('formats mmHg', () {
      final result = PressureFormatter.formatMmHg(101325.0);
      expect(result, contains('мм рт.ст.'));
      // 101325 Pa ≈ 760 mmHg
      expect(PressureFormatter.formatMmHg(101325.0, decimals: 0),
          equals('760 мм рт.ст.'));
    });

    test('formats atm', () {
      final result = PressureFormatter.formatAtm(101325.0);
      expect(result, contains('атм'));
    });
  });

  group('TimeFormatter', () {
    test('formats milliseconds', () {
      expect(TimeFormatter.format(500), equals('500 мс'));
    });

    test('formats seconds', () {
      expect(TimeFormatter.format(2500), equals('2.5 с'));
    });

    test('formats minutes:seconds', () {
      final result = TimeFormatter.format(65000); // 1 min 5 sec
      expect(result, contains('1:'));
    });

    test('formatAxisX returns seconds', () {
      expect(TimeFormatter.formatAxisX(1500), equals('1.5'));
    });
  });

  group('PhysicsFormatter', () {
    test('formats distance by type name', () {
      expect(PhysicsFormatter.format(50.0, 'distance'), equals('5.0 см'));
    });

    test('formats temperature by type name', () {
      expect(PhysicsFormatter.format(23.5, 'temperature'), equals('23.5 °C'));
    });

    test('formats voltage by type name', () {
      expect(PhysicsFormatter.format(3.3, 'voltage'), equals('3.30 В'));
    });

    test('supports Russian type names', () {
      expect(PhysicsFormatter.format(50.0, 'расстояние'), equals('5.0 см'));
      expect(PhysicsFormatter.format(23.5, 'температура'), equals('23.5 °C'));
    });

    test('returns default format for unknown types', () {
      expect(PhysicsFormatter.format(3.14159, 'unknown'), equals('3.14'));
    });
  });
}
