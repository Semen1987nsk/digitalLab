import 'package:flutter_test/flutter_test.dart';
import 'package:digital_lab/domain/math/kalman_filter.dart';

void main() {
  group('KalmanFilter', () {
    late KalmanFilter filter;

    setUp(() {
      filter = KalmanFilter(processNoise: 0.01, measurementNoise: 0.1);
    });

    test('first update returns measurement value', () {
      final result = filter.update(100.0);
      expect(result, equals(100.0));
    });

    test('subsequent updates smooth the data', () {
      filter.update(100.0);
      final result = filter.update(110.0);
      // Kalman gain < 1, so result should be between 100 and 110
      expect(result, greaterThan(100.0));
      expect(result, lessThan(110.0));
    });

    test('stable input converges to that value', () {
      for (int i = 0; i < 100; i++) {
        filter.update(50.0);
      }
      expect(filter.currentEstimate, closeTo(50.0, 0.01));
    });

    test('filters out noise on constant signal', () {
      filter = KalmanFilter(processNoise: 0.001, measurementNoise: 1.0);
      final measurements = <double>[
        100,
        102,
        98,
        101,
        99,
        103,
        97,
        100,
        101,
        99,
        100,
        98,
        102,
        100,
        99,
        101,
        100,
        98,
        102,
        100,
      ];

      double lastEstimate = 0;
      for (final m in measurements) {
        lastEstimate = filter.update(m);
      }

      // Should converge close to 100 despite noise
      expect(lastEstimate, closeTo(100.0, 2.0));
    });

    test('reset clears state', () {
      filter.update(100.0);
      filter.update(200.0);
      filter.reset();

      // After reset, first update should return the measurement
      final result = filter.update(50.0);
      expect(result, equals(50.0));
    });

    test('currentKalmanGain is between 0 and 1', () {
      filter.update(100.0);
      filter.update(110.0);

      final gain = filter.currentKalmanGain;
      expect(gain, greaterThan(0.0));
      expect(gain, lessThan(1.0));
    });

    test('updateWithNoise uses custom noise parameters', () {
      filter.update(100.0); // Initialize

      // High Q, low R → trust measurement more
      final highTrust = filter.updateWithNoise(200.0, 10.0, 0.01);

      filter.reset();
      filter.update(100.0); // Re-initialize

      // Low Q, high R → trust prediction more
      final lowTrust = filter.updateWithNoise(200.0, 0.001, 10.0);

      // High trust should be closer to 200
      expect(highTrust, greaterThan(lowTrust));
    });
  });

  group('AdaptiveKalmanFilter', () {
    late AdaptiveKalmanFilter filter;

    setUp(() {
      filter = AdaptiveKalmanFilter(
        processNoise: 0.01,
        measurementNoise: 0.1,
        minProcessNoise: 0.001,
        maxProcessNoise: 5.0,
        adaptationRate: 0.5,
      );
    });

    test('first update returns measurement value', () {
      final result = filter.update(100.0);
      expect(result, equals(100.0));
    });

    test('adapts noise on rapid changes', () {
      filter.update(100.0);
      filter.update(100.0);

      final noiseBeforeJump = filter.currentAdaptedNoise;

      // Big jump
      filter.update(200.0);

      final noiseAfterJump = filter.currentAdaptedNoise;

      // Adapted noise should increase after a big change
      expect(noiseAfterJump, greaterThan(noiseBeforeJump));
    });

    test('adapted noise stays within min/max bounds', () {
      filter.update(0.0);

      // Very large jump
      filter.update(10000.0);
      expect(filter.currentAdaptedNoise, lessThanOrEqualTo(5.0));

      // Very small change
      filter.update(10000.0);
      filter.update(10000.0);
      filter.update(10000.0);
      expect(filter.currentAdaptedNoise, greaterThanOrEqualTo(0.001));
    });

    test('reset clears adapted noise', () {
      filter.update(100.0);
      filter.update(500.0); // Big jump

      filter.reset();

      expect(filter.currentAdaptedNoise, equals(0.01)); // Back to initial
    });

    test('tracks fast-changing signal better than base Kalman', () {
      final baseFilter =
          KalmanFilter(processNoise: 0.01, measurementNoise: 0.1);

      // Initialize both
      baseFilter.update(0.0);
      filter.update(0.0);

      // Apply sudden step change
      for (int i = 0; i < 10; i++) {
        baseFilter.update(100.0);
        filter.update(100.0);
      }

      // Adaptive should converge faster (closer to 100)
      expect(filter.currentEstimate,
          greaterThanOrEqualTo(baseFilter.currentEstimate));
    });
  });
}
