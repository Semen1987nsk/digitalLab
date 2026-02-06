import 'kalman_filter.dart';
import 'moving_average.dart';

/// Комбинированный процессор сигнала для датчиков
/// 
/// Применяет цепочку фильтров для получения качественных данных:
/// 1. Медианный фильтр - убирает выбросы
/// 2. Фильтр Калмана - сглаживает шум
/// 
/// Пример использования:
/// ```dart
/// final processor = SignalProcessor(
///   sensorType: SensorType.distance,
/// );
/// 
/// for (final raw in rawData) {
///   final clean = processor.process(raw);
///   print(clean);
/// }
/// ```
class SignalProcessor {
  final SensorType sensorType;
  
  late final MedianFilter _medianFilter;
  late final KalmanFilter _kalmanFilter;
  
  /// Включить/выключить фильтрацию (для отладки)
  bool enabled = true;
  
  SignalProcessor({
    required this.sensorType,
  }) {
    // Настраиваем фильтры под тип датчика
    switch (sensorType) {
      case SensorType.distance:
        // Датчик расстояния - БЫСТРАЯ реакция + убираем мелкий шум
        // processNoise высокий = быстро следует за реальными изменениями
        // measurementNoise низкий = доверяем измерениям больше
        _medianFilter = MedianFilter(windowSize: 3);  // Убирает выбросы
        _kalmanFilter = KalmanFilter(
          processNoise: 100.0,     // ВЫСОКИЙ - быстро реагирует на изменения
          measurementNoise: 50.0,  // Умеренный - немного сглаживает шум ±10мм
        );
        break;
        
      case SensorType.temperature:
        // Температура меняется очень медленно
        _medianFilter = MedianFilter(windowSize: 5);
        _kalmanFilter = KalmanFilter(
          processNoise: 0.001,     // Очень медленные изменения
          measurementNoise: 0.5,   // Умеренный шум
        );
        break;
        
      case SensorType.voltage:
      case SensorType.current:
        // Электрические величины - быстрая реакция
        _medianFilter = MedianFilter(windowSize: 3);
        _kalmanFilter = KalmanFilter(
          processNoise: 0.1,       // Может быстро меняться
          measurementNoise: 0.5,   // Низкий шум
        );
        break;
        
      case SensorType.acceleration:
      case SensorType.gyroscope:
        // IMU - очень быстрые изменения
        _medianFilter = MedianFilter(windowSize: 3);
        _kalmanFilter = KalmanFilter(
          processNoise: 1.0,       // Быстрые изменения
          measurementNoise: 0.3,   // Современные IMU точные
        );
        break;
        
      case SensorType.pressure:
      case SensorType.humidity:
        // Атмосферные - медленные изменения
        _medianFilter = MedianFilter(windowSize: 5);
        _kalmanFilter = KalmanFilter(
          processNoise: 0.01,
          measurementNoise: 1.0,
        );
        break;
    }
  }
  
  /// Обработать одно измерение
  double process(double rawValue) {
    if (!enabled) return rawValue;
    
    // 1. Медианный фильтр убирает выбросы
    final afterMedian = _medianFilter.add(rawValue);
    
    // 2. Калман сглаживает оставшийся шум
    final afterKalman = _kalmanFilter.update(afterMedian);
    
    return afterKalman;
  }
  
  /// Сбросить все фильтры
  void reset() {
    _medianFilter.reset();
    _kalmanFilter.reset();
  }
  
  /// Текущее отфильтрованное значение
  double get currentValue => _kalmanFilter.currentEstimate;
}

/// Типы датчиков для настройки фильтров
enum SensorType {
  distance,
  temperature,
  voltage,
  current,
  acceleration,
  gyroscope,
  pressure,
  humidity,
}
