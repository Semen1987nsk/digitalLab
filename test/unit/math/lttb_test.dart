import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_lab/domain/math/lttb.dart';

void main() {
  group('LTTB Downsampling', () {
    test('should return same data if below threshold', () {
      final data = Float64List.fromList([
        0,
        10,
        1,
        20,
        2,
        15,
      ]);

      final result = LTTB.downsample(data, 10);

      expect(result.length, equals(data.length));
    });

    test('should downsample to threshold count', () {
      // Создаём 1000 точек (2000 элементов)
      final data = Float64List(2000);
      for (int i = 0; i < 1000; i++) {
        data[i * 2] = i.toDouble();
        data[i * 2 + 1] = (i % 100).toDouble();
      }

      final result = LTTB.downsample(data, 100);

      expect(result.length, equals(200)); // 100 точек * 2
    });

    test('should preserve first and last points', () {
      final data = Float64List(1000);
      for (int i = 0; i < 500; i++) {
        data[i * 2] = i.toDouble();
        data[i * 2 + 1] = i * 2.0;
      }

      final result = LTTB.downsample(data, 50);

      expect(result[0], equals(data[0]));
      expect(result[1], equals(data[1]));
      expect(result[result.length - 2], equals(data[data.length - 2]));
      expect(result[result.length - 1], equals(data[data.length - 1]));
    });

    test('should handle threshold of 3', () {
      final data = Float64List(200);
      for (int i = 0; i < 100; i++) {
        data[i * 2] = i.toDouble();
        data[i * 2 + 1] = i.toDouble();
      }

      final result = LTTB.downsample(data, 3);

      expect(result.length, equals(6));
      expect(result[0], equals(0));
      expect(result[result.length - 2], equals(99));
    });
  });

  group('Statistics', () {
    test('mean should calculate average', () {
      final values = [10.0, 20.0, 30.0, 40.0, 50.0];
      expect(Statistics.mean(values), equals(30.0));
    });

    test('mean of empty list should be 0', () {
      expect(Statistics.mean([]), equals(0));
    });

    test('standardDeviation should calculate correctly', () {
      final values = [2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0];
      final std = Statistics.standardDeviation(values);
      expect(std, closeTo(2.138, 0.001));
    });

    test('min and max should work correctly', () {
      final values = [5.0, 2.0, 8.0, 1.0, 9.0];
      expect(Statistics.min(values), equals(1.0));
      expect(Statistics.max(values), equals(9.0));
    });
  });
}
