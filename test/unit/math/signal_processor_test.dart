import 'package:flutter_test/flutter_test.dart';
import 'package:digital_lab/domain/entities/sensor_type.dart';
import 'package:digital_lab/domain/math/signal_processor.dart';

void main() {
  group('SignalProcessor', () {
    test('returns raw value when disabled', () {
      final processor = SignalProcessor(sensorType: SensorType.voltage);
      processor.enabled = false;

      final result = processor.process(999.0);
      expect(result, equals(999.0));
    });

    test('temperature filters converge slowly', () {
      final processor = SignalProcessor(sensorType: SensorType.temperature);

      // Start at 20°C
      for (int i = 0; i < 20; i++) {
        processor.process(20.0);
      }

      // Jump to 25°C — temperature has slow processNoise so should lag
      // Feed several values to allow Kalman to start moving
      double lastValue = 20.0;
      for (int i = 0; i < 10; i++) {
        lastValue = processor.process(25.0);
      }
      expect(lastValue, lessThan(25.0)); // Should not immediately reach 25
      expect(lastValue,
          greaterThan(20.0)); // But should start moving after 10 samples
    });

    test('reset returns processor to initial state', () {
      final processor = SignalProcessor(sensorType: SensorType.voltage);

      for (int i = 0; i < 10; i++) {
        processor.process(5.0);
      }

      processor.reset();

      // After reset, the first value should be accepted more directly
      final afterReset = processor.process(10.0);
      // Kalman first value is accepted as-is after reset
      expect(afterReset, closeTo(10.0, 1.0));
    });

    test('currentValue returns last filtered value', () {
      final processor = SignalProcessor(sensorType: SensorType.voltage);

      processor.process(3.3);
      final current = processor.currentValue;
      expect(current, closeTo(3.3, 0.5));
    });

    test('all sensor types construct without error', () {
      for (final type in SensorType.values) {
        expect(
          () => SignalProcessor(sensorType: type),
          returnsNormally,
        );
      }
    });
  });
}
