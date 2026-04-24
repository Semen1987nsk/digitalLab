import 'dart:math';
import 'dart:typed_data';

/// Алгоритм LTTB (Largest-Triangle-Three-Buckets)
/// Уменьшает количество точек для отрисовки без потери визуальной формы графика
/// 
/// Оптимизированная версия: использует Float64List для минимизации нагрузки на GC.
/// Входные и выходные данные представлены в виде interleaved массива: [x0, y0, x1, y1, ...]
class LTTB {
  /// Прореживание данных с сохранением формы
  /// 
  /// [data] - исходные точки в формате [x0, y0, x1, y1, ...]
  /// [threshold] - желаемое количество точек на выходе
  static Float64List downsample(Float64List data, int threshold) {
    final int dataLength = data.length ~/ 2;
    if (dataLength <= threshold || threshold < 3) {
      return Float64List.fromList(data);
    }
    
    final Float64List sampled = Float64List(threshold * 2);
    int sampledIndex = 0;
    
    // Всегда сохраняем первую точку
    sampled[sampledIndex++] = data[0];
    sampled[sampledIndex++] = data[1];
    
    // Размер корзины (bucket)
    final double bucketSize = (dataLength - 2) / (threshold - 2);
    
    int a = 0; // Индекс предыдущей выбранной точки
    
    for (int i = 0; i < threshold - 2; i++) {
      // Границы следующей корзины для расчета среднего
      final int avgRangeStart = ((i + 1) * bucketSize).floor() + 1;
      final int avgRangeEnd = ((i + 2) * bucketSize).floor() + 1;
      
      final int actualAvgRangeEnd = avgRangeEnd < dataLength ? avgRangeEnd : dataLength;
      final int avgRangeLength = actualAvgRangeEnd - avgRangeStart;
      
      double avgX = 0.0;
      double avgY = 0.0;
      
      if (avgRangeLength > 0) {
        for (int j = avgRangeStart; j < actualAvgRangeEnd; j++) {
          avgX += data[j * 2];
          avgY += data[j * 2 + 1];
        }
        avgX /= avgRangeLength;
        avgY /= avgRangeLength;
      }
      
      // Границы текущей корзины для поиска
      final int rangeStart = ((i) * bucketSize).floor() + 1;
      final int rangeEnd = ((i + 1) * bucketSize).floor() + 1;
      final int actualRangeEnd = rangeEnd < dataLength ? rangeEnd : dataLength;
      
      double maxArea = -1.0;
      int maxAreaIndex = rangeStart;
      
      final double pointAX = data[a * 2];
      final double pointAY = data[a * 2 + 1];
      
      for (int j = rangeStart; j < actualRangeEnd; j++) {
        final double pX = data[j * 2];
        final double pY = data[j * 2 + 1];
        
        // Площадь треугольника (A, B, Average)
        final double area = ((pointAX - avgX) * (pY - pointAY) -
                             (pointAX - pX) * (avgY - pointAY)).abs() * 0.5;
        
        if (area > maxArea) {
          maxArea = area;
          maxAreaIndex = j;
        }
      }
      
      sampled[sampledIndex++] = data[maxAreaIndex * 2];
      sampled[sampledIndex++] = data[maxAreaIndex * 2 + 1];
      a = maxAreaIndex;
    }
    
    // Всегда сохраняем последнюю точку
    sampled[sampledIndex++] = data[(dataLength - 1) * 2];
    sampled[sampledIndex++] = data[(dataLength - 1) * 2 + 1];
    
    return sampled;
  }
}

/// Статистические функции для обработки данных эксперимента
class Statistics {
  /// Среднее арифметическое
  static double mean(List<double> values) {
    if (values.isEmpty) return 0;
    return values.reduce((a, b) => a + b) / values.length;
  }
  
  /// Стандартное отклонение
  static double standardDeviation(List<double> values) {
    if (values.length < 2) return 0;
    final m = mean(values);
    final variance = values.map((v) => pow(v - m, 2)).reduce((a, b) => a + b) / (values.length - 1);
    return sqrt(variance);
  }
  
  /// Погрешность среднего
  static double standardError(List<double> values) {
    if (values.length < 2) return 0;
    return standardDeviation(values) / sqrt(values.length);
  }
  
  /// Минимум
  static double min(List<double> values) {
    if (values.isEmpty) return 0;
    return values.reduce((a, b) => a < b ? a : b);
  }
  
  /// Максимум
  static double max(List<double> values) {
    if (values.isEmpty) return 0;
    return values.reduce((a, b) => a > b ? a : b);
  }
}
