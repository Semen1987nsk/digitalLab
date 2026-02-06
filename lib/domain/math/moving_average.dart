import 'dart:collection';

/// Фильтр скользящего среднего
/// 
/// Простой и эффективный способ сгладить шумные данные.
/// Хорошо подходит когда нужно быстрое и предсказуемое сглаживание.
/// 
/// Пример использования:
/// ```dart
/// final filter = MovingAverageFilter(windowSize: 5);
/// 
/// for (final raw in rawData) {
///   final smoothed = filter.add(raw);
///   print(smoothed);
/// }
/// ```
class MovingAverageFilter {
  /// Размер окна усреднения
  final int windowSize;
  
  /// Буфер последних значений
  final Queue<double> _buffer = Queue<double>();
  
  /// Текущая сумма (для оптимизации)
  double _sum = 0.0;
  
  MovingAverageFilter({this.windowSize = 5});
  
  /// Сбросить фильтр
  void reset() {
    _buffer.clear();
    _sum = 0.0;
  }
  
  /// Добавить новое значение и получить усреднённое
  double add(double value) {
    _buffer.addLast(value);
    _sum += value;
    
    // Удаляем старые значения если буфер переполнен
    while (_buffer.length > windowSize) {
      _sum -= _buffer.removeFirst();
    }
    
    return _sum / _buffer.length;
  }
  
  /// Текущее среднее значение
  double get current => _buffer.isEmpty ? 0.0 : _sum / _buffer.length;
  
  /// Количество значений в буфере
  int get count => _buffer.length;
  
  /// Буфер заполнен?
  bool get isFull => _buffer.length >= windowSize;
}

/// Экспоненциальное скользящее среднее (EMA)
/// 
/// Даёт больший вес последним значениям, быстрее реагирует на изменения.
/// 
/// Пример:
/// ```dart
/// final ema = ExponentialMovingAverage(alpha: 0.3);
/// final smoothed = ema.add(newValue);
/// ```
class ExponentialMovingAverage {
  /// Коэффициент сглаживания (0 < alpha <= 1)
  /// Больше alpha = быстрее реакция, меньше сглаживания
  /// Меньше alpha = медленнее реакция, больше сглаживания
  final double alpha;
  
  double _value = 0.0;
  bool _initialized = false;
  
  ExponentialMovingAverage({this.alpha = 0.2});
  
  /// Сбросить фильтр
  void reset() {
    _value = 0.0;
    _initialized = false;
  }
  
  /// Добавить новое значение и получить сглаженное
  double add(double value) {
    if (!_initialized) {
      _value = value;
      _initialized = true;
      return _value;
    }
    
    _value = alpha * value + (1 - alpha) * _value;
    return _value;
  }
  
  /// Текущее сглаженное значение
  double get current => _value;
}

/// Медианный фильтр - отлично убирает выбросы
/// 
/// Особенно полезен для:
/// - Ультразвуковых датчиков (случайные ложные показания)
/// - Датчиков с редкими выбросами
class MedianFilter {
  final int windowSize;
  final Queue<double> _buffer = Queue<double>();
  
  MedianFilter({this.windowSize = 5});
  
  void reset() {
    _buffer.clear();
  }
  
  double add(double value) {
    _buffer.addLast(value);
    
    while (_buffer.length > windowSize) {
      _buffer.removeFirst();
    }
    
    // Сортируем и берём медиану
    final sorted = _buffer.toList()..sort();
    final mid = sorted.length ~/ 2;
    
    if (sorted.length % 2 == 0) {
      return (sorted[mid - 1] + sorted[mid]) / 2;
    } else {
      return sorted[mid];
    }
  }
  
  double get current {
    if (_buffer.isEmpty) return 0.0;
    final sorted = _buffer.toList()..sort();
    return sorted[sorted.length ~/ 2];
  }
}
