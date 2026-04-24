import 'package:flutter_test/flutter_test.dart';
import 'package:digital_lab/domain/math/moving_average.dart';

void main() {
  group('MovingAverageFilter', () {
    late MovingAverageFilter filter;
    
    setUp(() {
      filter = MovingAverageFilter(windowSize: 5);
    });
    
    test('first value returns itself', () {
      expect(filter.add(10.0), equals(10.0));
    });
    
    test('averages values within window', () {
      filter.add(10.0);
      filter.add(20.0);
      filter.add(30.0);
      filter.add(40.0);
      final result = filter.add(50.0);
      
      // Average of [10, 20, 30, 40, 50] = 30
      expect(result, equals(30.0));
    });
    
    test('slides window correctly', () {
      // Fill window: [10, 20, 30, 40, 50]
      for (final v in [10.0, 20.0, 30.0, 40.0, 50.0]) {
        filter.add(v);
      }
      
      // Add 60: window becomes [20, 30, 40, 50, 60]
      final result = filter.add(60.0);
      expect(result, equals(40.0)); // (20+30+40+50+60)/5 = 40
    });
    
    test('count tracks buffer size', () {
      expect(filter.count, equals(0));
      filter.add(1.0);
      expect(filter.count, equals(1));
      filter.add(2.0);
      expect(filter.count, equals(2));
      
      // Fill beyond window
      for (int i = 0; i < 10; i++) {
        filter.add(0.0);
      }
      expect(filter.count, equals(5)); // Capped at windowSize
    });
    
    test('isFull works correctly', () {
      expect(filter.isFull, isFalse);
      for (int i = 0; i < 5; i++) {
        filter.add(1.0);
      }
      expect(filter.isFull, isTrue);
    });
    
    test('reset clears all state', () {
      for (int i = 0; i < 5; i++) {
        filter.add(100.0);
      }
      filter.reset();
      
      expect(filter.count, equals(0));
      expect(filter.current, equals(0.0));
    });
    
    test('window size 1 returns last value', () {
      final f = MovingAverageFilter(windowSize: 1);
      f.add(10.0);
      expect(f.add(20.0), equals(20.0));
      expect(f.add(30.0), equals(30.0));
    });
  });
  
  group('ExponentialMovingAverage', () {
    late ExponentialMovingAverage ema;
    
    setUp(() {
      ema = ExponentialMovingAverage(alpha: 0.3);
    });
    
    test('first value returns itself', () {
      expect(ema.add(100.0), equals(100.0));
    });
    
    test('smooths subsequent values', () {
      ema.add(100.0);
      final result = ema.add(200.0);
      
      // EMA = 0.3 * 200 + 0.7 * 100 = 60 + 70 = 130
      expect(result, closeTo(130.0, 0.001));
    });
    
    test('converges to constant input', () {
      for (int i = 0; i < 100; i++) {
        ema.add(50.0);
      }
      expect(ema.current, closeTo(50.0, 0.001));
    });
    
    test('alpha=1 gives no smoothing', () {
      final noSmooth = ExponentialMovingAverage(alpha: 1.0);
      noSmooth.add(100.0);
      expect(noSmooth.add(200.0), equals(200.0));
    });
    
    test('reset clears state', () {
      ema.add(100.0);
      ema.add(200.0);
      ema.reset();
      
      // After reset, first value should be returned as-is
      expect(ema.add(50.0), equals(50.0));
    });
  });
  
  group('MedianFilter', () {
    late MedianFilter filter;
    
    setUp(() {
      filter = MedianFilter(windowSize: 5);
    });
    
    test('single value returns itself', () {
      expect(filter.add(42.0), equals(42.0));
    });
    
    test('odd window returns middle value', () {
      filter.add(1.0);
      filter.add(100.0);  // Outlier
      filter.add(2.0);
      filter.add(3.0);
      final result = filter.add(4.0);
      
      // Sorted: [1, 2, 3, 4, 100] → median = 3
      expect(result, equals(3.0));
    });
    
    test('removes outliers effectively', () {
      // Normal values with one outlier
      filter.add(10.0);
      filter.add(11.0);
      filter.add(9999.0);  // Huge outlier
      filter.add(10.0);
      final result = filter.add(12.0);
      
      // Sorted: [10, 10, 11, 12, 9999] → median = 11
      expect(result, equals(11.0));
    });
    
    test('even count uses average of two middle values', () {
      final f = MedianFilter(windowSize: 4);
      f.add(10.0);
      f.add(20.0);
      f.add(30.0);
      final result = f.add(40.0);
      
      // Sorted: [10, 20, 30, 40] → median = (20+30)/2 = 25
      expect(result, equals(25.0));
    });
    
    test('reset clears buffer', () {
      filter.add(100.0);
      filter.add(200.0);
      filter.reset();
      
      // After reset should behave as new
      expect(filter.add(42.0), equals(42.0));
    });
  });

  group('SpikeGuard', () {
    late SpikeGuard guard;

    setUp(() {
      guard = SpikeGuard(maxDelta: 500.0);
    });

    test('first value passes through', () {
      expect(guard.process(100.0), equals(100.0));
    });

    test('normal values pass immediately (zero latency)', () {
      guard.process(100.0);
      // 200mm delta < 500mm maxDelta → immediate
      expect(guard.process(300.0), equals(300.0));
      expect(guard.process(350.0), equals(350.0));
      expect(guard.process(100.0), equals(100.0));
    });

    test('single spike is suppressed', () {
      guard.process(100.0);
      guard.process(100.0);
      // 9999mm delta >> 500mm → spike → returns last valid
      expect(guard.process(9999.0), equals(100.0));
      // Normal value after spike → passes through
      expect(guard.process(105.0), equals(105.0));
    });

    test('two consecutive spikes pass (real fast movement)', () {
      guard.process(100.0);
      // First "spike" → held
      expect(guard.process(5000.0), equals(100.0));
      // Second consecutive "spike" in same frame → real movement
      expect(guard.process(5100.0), equals(5100.0));
    });

    test('spike then normal → spike discarded', () {
      guard.process(100.0);
      guard.process(9999.0); // spike → held
      guard.process(102.0);  // normal → spike was fake
      expect(guard.current, equals(102.0));
    });

    test('reset clears state', () {
      guard.process(100.0);
      guard.process(9999.0); // pending spike
      guard.reset();
      // After reset, first value accepted
      expect(guard.process(50.0), equals(50.0));
    });

    test('exactly at maxDelta passes through', () {
      guard.process(100.0);
      // Exactly 500mm delta = maxDelta → passes (<=)
      expect(guard.process(600.0), equals(600.0));
    });

    test('just over maxDelta is held', () {
      guard.process(100.0);
      // 501mm delta > 500mm → spike → held
      expect(guard.process(601.0), equals(100.0));
    });
  });
}
