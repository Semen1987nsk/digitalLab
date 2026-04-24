import 'package:flutter_test/flutter_test.dart';
import 'package:digital_lab/domain/utils/circular_sample_buffer.dart';

void main() {
  group('CircularSampleBuffer', () {
    test('add and retrieve items', () {
      final buf = CircularSampleBuffer<int>(maxCapacity: 5);
      buf.add(1);
      buf.add(2);
      buf.add(3);
      expect(buf.length, 3);
      expect(buf.toList(), [1, 2, 3]);
    });

    test('evicts oldest items on overflow', () {
      final buf = CircularSampleBuffer<int>(maxCapacity: 3);
      buf.add(1);
      buf.add(2);
      buf.add(3);
      buf.add(4); // evicts 1
      expect(buf.toList(), [2, 3, 4]);
      expect(buf.totalEvicted, 1);
    });

    test('fillRatio is accurate', () {
      final buf = CircularSampleBuffer<int>(maxCapacity: 10);
      for (int i = 0; i < 5; i++) {
        buf.add(i);
      }
      expect(buf.fillRatio, closeTo(0.5, 0.001));
    });

    test('isFull returns true at capacity', () {
      final buf = CircularSampleBuffer<int>(maxCapacity: 3);
      buf.add(1);
      buf.add(2);
      expect(buf.isFull, false);
      buf.add(3);
      expect(buf.isFull, true);
    });

    test('takeLast returns correct subset', () {
      final buf = CircularSampleBuffer<int>(maxCapacity: 100);
      for (int i = 0; i < 20; i++) {
        buf.add(i);
      }
      expect(buf.takeLast(5), [15, 16, 17, 18, 19]);
    });

    test('takeLast with count > length returns all', () {
      final buf = CircularSampleBuffer<int>(maxCapacity: 100);
      buf.add(1);
      buf.add(2);
      expect(buf.takeLast(10), [1, 2]);
    });

    test('clear resets everything', () {
      final buf = CircularSampleBuffer<int>(maxCapacity: 5);
      buf.add(1);
      buf.add(2);
      buf.clear();
      expect(buf.length, 0);
      expect(buf.isEmpty, true);
      expect(buf.totalAdded, 0);
      expect(buf.totalEvicted, 0);
    });

    group('warning threshold', () {
      test('fires callback at 80% capacity', () {
        int warningCount = 0;
        final buf = CircularSampleBuffer<int>(
          maxCapacity: 10,
          warningThreshold: 0.8,
          onWarningThreshold: () => warningCount++,
        );

        // Add 7 items — no warning (70%)
        for (int i = 0; i < 7; i++) {
          buf.add(i);
        }
        expect(warningCount, 0);

        // 8th item triggers warning (80%)
        buf.add(8);
        expect(warningCount, 1);

        // 9th item — warning already fired, should not fire again
        buf.add(9);
        expect(warningCount, 1);
      });

      test('warning fires only once per fill cycle', () {
        int warningCount = 0;
        final buf = CircularSampleBuffer<int>(
          maxCapacity: 5,
          warningThreshold: 0.8,
          onWarningThreshold: () => warningCount++,
        );

        // Fill to overflow — warning should fire only once
        for (int i = 0; i < 20; i++) {
          buf.add(i);
        }
        expect(warningCount, 1);
      });

      test('clear resets warning flag', () {
        int warningCount = 0;
        final buf = CircularSampleBuffer<int>(
          maxCapacity: 5,
          warningThreshold: 0.8,
          onWarningThreshold: () => warningCount++,
        );

        // Fill to trigger warning
        for (int i = 0; i < 5; i++) {
          buf.add(i);
        }
        expect(warningCount, 1);

        // Clear and re-fill — warning should fire again
        buf.clear();
        for (int i = 0; i < 5; i++) {
          buf.add(i);
        }
        expect(warningCount, 2);
      });

      test('resetWarning allows re-firing', () {
        int warningCount = 0;
        final buf = CircularSampleBuffer<int>(
          maxCapacity: 10,
          warningThreshold: 0.8,
          onWarningThreshold: () => warningCount++,
        );

        // Trigger warning at 80%
        for (int i = 0; i < 8; i++) {
          buf.add(i);
        }
        expect(warningCount, 1);

        // Reset and add more — should fire again at next add
        buf.resetWarning();
        buf.add(99);
        expect(warningCount, 2);
      });

      test('no callback when onWarningThreshold is null', () {
        final buf = CircularSampleBuffer<int>(
          maxCapacity: 5,
          warningThreshold: 0.8,
        );

        // Should not throw
        for (int i = 0; i < 10; i++) {
          buf.add(i);
        }
        expect(buf.length, 5);
      });
    });
  });
}
