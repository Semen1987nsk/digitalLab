import 'package:flutter_test/flutter_test.dart';
import 'package:digital_lab/domain/entities/sensor_type.dart';
import 'package:digital_lab/domain/math/signal_processor.dart';

void main() {
  group('SignalProcessor', () {
    test('returns raw value when disabled', () {
      final processor = SignalProcessor(sensorType: SensorType.distance);
      processor.enabled = false;

      final result = processor.process(999.0);
      expect(result, equals(999.0));
    });

    test('filters noisy distance data', () {
      final processor = SignalProcessor(sensorType: SensorType.distance);

      // Feed several consistent values then check smoothing
      double result = 0;
      for (int i = 0; i < 20; i++) {
        result = processor.process(100.0);
      }

      // After many identical values, output should converge
      expect(result, closeTo(100.0, 5.0));
    });

    test('removes outliers from distance data', () {
      final processor = SignalProcessor(sensorType: SensorType.distance);

      // Build up stable baseline
      for (int i = 0; i < 10; i++) {
        processor.process(100.0);
      }

      // Inject outlier (9999mm — way beyond maxDelta=500mm)
      // SpikeGuard holds first spike, returns lastValid
      final afterOutlier = processor.process(9999.0);

      // SpikeGuard returns last valid (≈100mm), not the spike
      expect(afterOutlier, lessThan(200.0));

      // Normal value after spike — SpikeGuard resets pending
      final afterRecovery = processor.process(100.0);
      expect(afterRecovery, closeTo(100.0, 5.0));
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
      expect(lastValue, greaterThan(20.0)); // But should start moving after 10 samples
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
