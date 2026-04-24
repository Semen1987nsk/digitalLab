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

/// Защита от выбросов с **нулевой задержкой** для нормальных значений.
///
/// В отличие от MedianFilter (задержка = 1 сэмпл = 100мс @ 10Гц),
/// SpikeGuard пропускает нормальные значения мгновенно.
///
/// ## Алгоритм
///
/// - |delta| ≤ [maxDelta] → **немедленный пропуск** (0 мс задержки)
/// - |delta| > maxDelta, первый раз → **задержать на 1 сэмпл** (возможный выброс)
/// - |delta| > maxDelta, второй раз подряд → **пропустить** (реальное быстрое движение)
///
/// ## Сравнение с MedianFilter(3)
///
/// | Ситуация           | Median(3) | SpikeGuard |
/// |---------------------|-----------|------------|
/// | Нормальное значение | 100мс     | **0мс**    |
/// | Одиночный выброс    | отброшен  | отброшен   |
/// | Быстрое движение    | 100мс     | 100мс      |
///
/// ## Пример
///
/// ```dart
/// final guard = SpikeGuard(maxDelta: 500.0); // 500mm = 5 м/с @ 10Гц
/// final clean = guard.process(rawValue);
/// ```
class SpikeGuard {
  /// Максимальное допустимое изменение за 1 сэмпл (в единицах сигнала).
  /// Для HC-SR04 @ 10Гц: 500мм = движение 5 м/с — быстрее руки не бывает.
  final double maxDelta;

  double _lastValid = double.nan;
  bool _hasPending = false;

  SpikeGuard({required this.maxDelta});

  /// Обработать одно измерение. Возвращает чистое значение.
  double process(double value) {
    // Первое значение — принимаем безусловно
    if (_lastValid.isNaN) {
      _lastValid = value;
      return value;
    }

    final delta = (value - _lastValid).abs();

    if (delta <= maxDelta) {
      // Нормальное значение — МГНОВЕННЫЙ пропуск (0мс задержки)
      _lastValid = value;
      _hasPending = false;
      return value;
    }

    // delta > maxDelta — возможный выброс
    if (_hasPending) {
      // Второй подряд «выброс» → это реальное быстрое движение
      _lastValid = value;
      _hasPending = false;
      return value;
    }

    // Первый выброс → задержать на 1 сэмпл для подтверждения
    _hasPending = true;
    return _lastValid;
  }

  /// Сбросить состояние
  void reset() {
    _lastValid = double.nan;
    _hasPending = false;
  }

  /// Последнее валидное значение
  double get current => _lastValid.isNaN ? 0.0 : _lastValid;
}
