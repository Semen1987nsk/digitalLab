import 'package:flutter_test/flutter_test.dart';
import 'package:digital_lab/domain/math/one_euro_filter.dart';

void main() {
  group('OneEuroFilter', () {
    test('first sample passes through unchanged', () {
      final f = OneEuroFilter(frequency: 10, minCutoff: 1.0, beta: 0.0);
      expect(f.filter(42.0), 42.0);
    });

    test('constant input converges to that value', () {
      final f = OneEuroFilter(frequency: 10, minCutoff: 1.0, beta: 0.0);
      double out = 0;
      for (int i = 0; i < 50; i++) {
        out = f.filter(100.0);
      }
      expect(out, closeTo(100.0, 0.1));
    });

    test('alternating quantized input (70/80) stabilizes with dead-zone', () {
      final f = OneEuroFilter(
        frequency: 10,
        minCutoff: 0.3,
        beta: 0.5,
        dCutoff: 1.0,
        derivativeDeadZone: 10.0,
      );

      // Simulate V802 sensor: alternating 70mm / 80mm
      double out = 0;
      for (int i = 0; i < 100; i++) {
        final raw = (i % 2 == 0) ? 70.0 : 80.0;
        out = f.filter(raw);
      }

      // After convergence, output should be near 75mm ± < 1mm
      // (dead-zone suppresses the 10mm alternation)
      expect(out, closeTo(75.0, 2.0));

      // Check jitter over last 10 samples
      final outputs = <double>[];
      for (int i = 0; i < 10; i++) {
        final raw = (i % 2 == 0) ? 70.0 : 80.0;
        outputs.add(f.filter(raw));
      }
      final maxJitter = outputs.reduce((a, b) => a > b ? a : b) -
          outputs.reduce((a, b) => a < b ? a : b);
      // Jitter should be < 2mm (invisible on chart)
      expect(maxJitter, lessThan(2.0));
    });

    test('responds instantly to real movement (step > dead-zone)', () {
      final f = OneEuroFilter(
        frequency: 10,
        minCutoff: 0.3,
        beta: 0.5,
        dCutoff: 1.0,
        derivativeDeadZone: 10.0,
      );

      // Stabilize at 100mm
      for (int i = 0; i < 30; i++) {
        f.filter(100.0);
      }
      expect(f.currentValue, closeTo(100.0, 0.5));

      // Step to 200mm (100mm jump >> 10mm dead-zone → instant response)
      double out = 0;
      for (int i = 0; i < 5; i++) {
        out = f.filter(200.0);
      }
      // After 5 samples at 10Hz (500ms) should be at least 80% tracked
      expect(out, greaterThan(180.0));
    });

    test('responds instantly to large movement', () {
      final f = OneEuroFilter(
        frequency: 10,
        minCutoff: 0.3,
        beta: 0.5,
        dCutoff: 1.0,
        derivativeDeadZone: 10.0,
      );

      // Stabilize at 50mm
      for (int i = 0; i < 20; i++) {
        f.filter(50.0);
      }

      // Move to 300mm in one jump
      final out = f.filter(300.0);
      // Even first sample should show significant response
      // (beta=0.5 × speed → high cutoff → high alpha)
      expect(out, greaterThan(100.0));
    });

    test('tracks monotonic single-step movement (10mm steps)', () {
      // THIS IS THE KEY TEST: direction-based dead-zone must let
      // through monotonic movement even when each step = dead-zone.
      // Old magnitude-only dead-zone would suppress ALL steps → broken!
      final f = OneEuroFilter(
        frequency: 10,
        minCutoff: 0.3,
        beta: 0.5,
        dCutoff: 1.0,
        derivativeDeadZone: 10.0,
      );

      // Stabilize at 100mm
      for (int i = 0; i < 30; i++) {
        f.filter(100.0);
      }
      expect(f.currentValue, closeTo(100.0, 0.5));

      // Simulate slow movement: 100 → 110 → 120 → 130 → 140 → 150 → 160
      // Each step is exactly 10mm (= dead-zone threshold)
      // Direction-based dead-zone: first step suppressed (new direction),
      // subsequent same-direction steps pass through → fast tracking
      final outputs = <double>[];
      for (int i = 1; i <= 7; i++) {
        outputs.add(f.filter(100.0 + i * 10.0));
      }

      // After 7 steps (700ms), should track most of the way to 170mm
      // (first step suppressed, but samples 2-7 pass through → fast)
      expect(outputs.last, greaterThan(155.0));

      // Must show clear upward trend (NOT flat like old dead-zone)
      expect(outputs[3], greaterThan(outputs[0]));
      expect(outputs[5], greaterThan(outputs[2]));
    });

    test('tracks slow monotonic movement with gaps (10mm steps with zeros)',
        () {
      // Real sensor pattern: 80, 80, 90, 90, 90, 100, 100, 100, 110
      final f = OneEuroFilter(
        frequency: 10,
        minCutoff: 0.3,
        beta: 0.5,
        dCutoff: 1.0,
        derivativeDeadZone: 10.0,
      );

      // Stabilize at 80mm
      for (int i = 0; i < 30; i++) {
        f.filter(80.0);
      }

      // Slow movement with repeating values
      final rawValues = [80.0, 90.0, 90.0, 90.0, 100.0, 100.0, 100.0, 110.0];
      double lastOut = f.currentValue;
      for (final v in rawValues) {
        lastOut = f.filter(v);
      }

      // Should have tracked toward 110mm
      expect(lastOut, greaterThan(100.0));
    });

    test('suppresses alternation after movement stops', () {
      final f = OneEuroFilter(
        frequency: 10,
        minCutoff: 0.3,
        beta: 0.5,
        dCutoff: 1.0,
        derivativeDeadZone: 10.0,
      );

      // Movement: 80 → 90 → 100 → 110
      for (int i = 0; i < 20; i++) {
        f.filter(80.0);
      }
      f.filter(90.0); // first step: suppressed (new direction)
      f.filter(100.0); // second: same dir → passes through
      f.filter(110.0); // third: same dir → passes through

      // Now stop at boundary: alternation 110 ↔ 100
      final settling = <double>[];
      for (int i = 0; i < 20; i++) {
        final raw = (i % 2 == 0) ? 110.0 : 100.0;
        settling.add(f.filter(raw));
      }

      // Last 10 samples should have minimal jitter
      final last10 = settling.sublist(10);
      final maxVal = last10.reduce((a, b) => a > b ? a : b);
      final minVal = last10.reduce((a, b) => a < b ? a : b);
      expect(maxVal - minVal, lessThan(3.0));
    });

    test('computeAlpha returns valid range', () {
      expect(OneEuroFilter.computeAlpha(1.0, 10.0), greaterThan(0.0));
      expect(OneEuroFilter.computeAlpha(1.0, 10.0), lessThan(1.0));
      expect(OneEuroFilter.computeAlpha(100.0, 10.0), closeTo(1.0, 0.05));
      expect(OneEuroFilter.computeAlpha(0.01, 10.0), closeTo(0.0, 0.01));
    });

    test('reset clears state', () {
      final f = OneEuroFilter(frequency: 10, minCutoff: 1.0, beta: 0.0);
      for (int i = 0; i < 20; i++) {
        f.filter(200.0);
      }
      expect(f.currentValue, closeTo(200.0, 1.0));

      f.reset();
      expect(f.initialized, false);

      // After reset, first value passes through
      final out = f.filter(50.0);
      expect(out, 50.0);
    });

    test('without dead-zone, alternating input has more jitter', () {
      // Compare: WITH dead-zone vs WITHOUT
      final withDZ = OneEuroFilter(
        frequency: 10,
        minCutoff: 0.3,
        beta: 0.5,
        derivativeDeadZone: 10.0,
      );
      final withoutDZ = OneEuroFilter(
        frequency: 10,
        minCutoff: 0.3,
        beta: 0.5,
        derivativeDeadZone: 0.0,
      );

      // Warm up both
      for (int i = 0; i < 100; i++) {
        final raw = (i % 2 == 0) ? 70.0 : 80.0;
        withDZ.filter(raw);
        withoutDZ.filter(raw);
      }

      // Measure jitter
      final jitterDZ = <double>[];
      final jitterNoDZ = <double>[];
      for (int i = 0; i < 20; i++) {
        final raw = (i % 2 == 0) ? 70.0 : 80.0;
        jitterDZ.add(withDZ.filter(raw));
        jitterNoDZ.add(withoutDZ.filter(raw));
      }

      final rangeDZ = jitterDZ.reduce((a, b) => a > b ? a : b) -
          jitterDZ.reduce((a, b) => a < b ? a : b);
      final rangeNoDZ = jitterNoDZ.reduce((a, b) => a > b ? a : b) -
          jitterNoDZ.reduce((a, b) => a < b ? a : b);

      // Dead-zone version should have significantly less jitter
      expect(rangeDZ, lessThan(rangeNoDZ));
    });

    test('works with variable dt', () {
      final f = OneEuroFilter(
        frequency: 10,
        minCutoff: 1.0,
        beta: 0.0,
      );

      f.filter(100.0, dt: 0.1);
      final out = f.filter(100.0, dt: 0.2);
      expect(out, closeTo(100.0, 1.0));
    });
  });
}
