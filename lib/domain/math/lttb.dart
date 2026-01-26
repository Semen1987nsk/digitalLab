import 'dart:math';

/// Точка данных для графика
class DataPoint {
  final double x;
  final double y;
  
  const DataPoint(this.x, this.y);
}

/// Алгоритм LTTB (Largest-Triangle-Three-Buckets)
/// Уменьшает количество точек для отрисовки без потери визуальной формы графика
/// 
/// Пример: 100,000 точек → 1,000 точек
/// Производительность на старых ПК увеличивается в 100 раз
class LTTB {
  /// Прореживание данных с сохранением формы
  /// 
  /// [data] - исходные точки
  /// [threshold] - желаемое количество точек на выходе
  static List<DataPoint> downsample(List<DataPoint> data, int threshold) {
    if (data.length <= threshold || threshold < 3) {
      return List.from(data);
    }
    
    final sampled = <DataPoint>[];
    
    // Всегда сохраняем первую точку
    sampled.add(data.first);
    
    // Размер корзины (bucket)
    final bucketSize = (data.length - 2) / (threshold - 2);
    
    int a = 0; // Индекс предыдущей выбранной точки
    
    for (int i = 0; i < threshold - 2; i++) {
      // Границы текущей корзины
      final avgRangeStart = ((i + 1) * bucketSize).floor() + 1;
      final avgRangeEnd = ((i + 2) * bucketSize).floor() + 1;
      final avgRangeLength = avgRangeEnd - avgRangeStart;
      
      // Вычисляем среднюю точку следующей корзины
      double avgX = 0;
      double avgY = 0;
      for (int j = avgRangeStart; j < avgRangeEnd && j < data.length; j++) {
        avgX += data[j].x;
        avgY += data[j].y;
      }
      avgX /= avgRangeLength;
      avgY /= avgRangeLength;
      
      // Границы текущей корзины для поиска
      final rangeStart = ((i) * bucketSize).floor() + 1;
      final rangeEnd = ((i + 1) * bucketSize).floor() + 1;
      
      // Ищем точку с максимальной площадью треугольника
      double maxArea = -1;
      int maxAreaIndex = rangeStart;
      
      final pointAX = data[a].x;
      final pointAY = data[a].y;
      
      for (int j = rangeStart; j < rangeEnd && j < data.length; j++) {
        // Площадь треугольника (A, B, Average)
        final area = ((pointAX - avgX) * (data[j].y - pointAY) -
                     (pointAX - data[j].x) * (avgY - pointAY)).abs() * 0.5;
        
        if (area > maxArea) {
          maxArea = area;
          maxAreaIndex = j;
        }
      }
      
      sampled.add(data[maxAreaIndex]);
      a = maxAreaIndex;
    }
    
    // Всегда сохраняем последнюю точку
    sampled.add(data.last);
    
    return sampled;
  }
  
  /// Быстрая версия для потоковых данных
  /// Возвращает индексы точек, которые нужно сохранить
  static List<int> downsampleIndices(int dataLength, int threshold) {
    if (dataLength <= threshold || threshold < 3) {
      return List.generate(dataLength, (i) => i);
    }
    
    final indices = <int>[0];
    final bucketSize = (dataLength - 2) / (threshold - 2);
    
    for (int i = 0; i < threshold - 2; i++) {
      final rangeStart = ((i) * bucketSize).floor() + 1;
      final rangeEnd = ((i + 1) * bucketSize).floor() + 1;
      
      // Берём точку из середины корзины (упрощённая версия)
      final midIndex = ((rangeStart + rangeEnd) / 2).floor();
      if (midIndex < dataLength) {
        indices.add(midIndex);
      }
    }
    
    indices.add(dataLength - 1);
    return indices;
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
