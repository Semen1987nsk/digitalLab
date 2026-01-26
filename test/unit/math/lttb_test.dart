import 'package:flutter_test/flutter_test.dart';
import 'package:digital_lab/domain/math/lttb.dart';

void main() {
  group('LTTB Downsampling', () {
    test('should return same data if below threshold', () {
      final data = [
        const DataPoint(0, 10),
        const DataPoint(1, 20),
        const DataPoint(2, 15),
      ];
      
      final result = LTTB.downsample(data, 10);
      
      expect(result.length, equals(data.length));
    });
    
    test('should downsample to threshold count', () {
      // Создаём 1000 точек
      final data = List.generate(
        1000,
        (i) => DataPoint(i.toDouble(), (i % 100).toDouble()),
      );
      
      final result = LTTB.downsample(data, 100);
      
      expect(result.length, equals(100));
    });
    
    test('should preserve first and last points', () {
      final data = List.generate(
        500,
        (i) => DataPoint(i.toDouble(), i * 2.0),
      );
      
      final result = LTTB.downsample(data, 50);
      
      expect(result.first.x, equals(data.first.x));
      expect(result.first.y, equals(data.first.y));
      expect(result.last.x, equals(data.last.x));
      expect(result.last.y, equals(data.last.y));
    });
    
    test('should handle threshold of 3', () {
      final data = List.generate(
        100,
        (i) => DataPoint(i.toDouble(), i.toDouble()),
      );
      
      final result = LTTB.downsample(data, 3);
      
      expect(result.length, equals(3));
      expect(result.first.x, equals(0));
      expect(result.last.x, equals(99));
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
