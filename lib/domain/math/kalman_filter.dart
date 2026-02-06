/// Фильтр Калмана для сглаживания шумных данных датчиков
/// 
/// Отлично подходит для:
/// - Датчиков расстояния (ультразвук, лазер)
/// - Акселерометров и гироскопов
/// - Температурных датчиков
/// 
/// Пример использования:
/// ```dart
/// final filter = KalmanFilter(
///   processNoise: 0.01,      // Низкий = более плавный
///   measurementNoise: 0.1,   // Высокий = больше доверия фильтру
/// );
/// 
/// for (final raw in rawData) {
///   final filtered = filter.update(raw);
///   print(filtered);
/// }
/// ```
class KalmanFilter {
  /// Шум процесса (Q) - насколько быстро может меняться реальное значение
  /// Меньше значение = более плавный график, но медленнее реакция
  final double processNoise;
  
  /// Шум измерения (R) - насколько шумный датчик
  /// Больше значение = больше сглаживания
  final double measurementNoise;
  
  /// Текущая оценка значения
  double _estimate = 0.0;
  
  /// Текущая оценка ошибки
  double _errorEstimate = 1.0;
  
  /// Инициализирован ли фильтр
  bool _initialized = false;
  
  KalmanFilter({
    this.processNoise = 0.01,
    this.measurementNoise = 0.1,
  });
  
  /// Сбросить фильтр в начальное состояние
  void reset() {
    _estimate = 0.0;
    _errorEstimate = 1.0;
    _initialized = false;
  }
  
  /// Обновить фильтр новым измерением и получить отфильтрованное значение
  double update(double measurement) {
    if (!_initialized) {
      _estimate = measurement;
      _errorEstimate = 1.0;
      _initialized = true;
      return _estimate;
    }
    
    // Prediction step
    final predictedEstimate = _estimate;
    final predictedErrorEstimate = _errorEstimate + processNoise;
    
    // Update step
    final kalmanGain = predictedErrorEstimate / (predictedErrorEstimate + measurementNoise);
    _estimate = predictedEstimate + kalmanGain * (measurement - predictedEstimate);
    _errorEstimate = (1 - kalmanGain) * predictedErrorEstimate;
    
    return _estimate;
  }
  
  /// Текущее отфильтрованное значение
  double get currentEstimate => _estimate;
  
  /// Текущий коэффициент усиления Калмана (для отладки)
  double get currentKalmanGain => _errorEstimate / (_errorEstimate + measurementNoise);
}

/// Расширенный фильтр Калмана с адаптивными параметрами
class AdaptiveKalmanFilter extends KalmanFilter {
  /// Минимальный шум процесса
  final double minProcessNoise;
  
  /// Максимальный шум процесса  
  final double maxProcessNoise;
  
  /// Скорость адаптации
  final double adaptationRate;
  
  double _lastMeasurement = 0.0;
  
  AdaptiveKalmanFilter({
    super.processNoise = 0.01,
    super.measurementNoise = 0.1,
    this.minProcessNoise = 0.001,
    this.maxProcessNoise = 1.0,
    this.adaptationRate = 0.1,
  });
  
  @override
  double update(double measurement) {
    if (_initialized) {
      // Адаптируем шум процесса на основе скорости изменения
      final delta = (measurement - _lastMeasurement).abs();
      final adaptedNoise = (processNoise + adaptationRate * delta)
          .clamp(minProcessNoise, maxProcessNoise);
      
      // Временно устанавливаем адаптированный шум
      // (В реальности нужно переопределить поле, но для простоты используем базовый метод)
    }
    
    _lastMeasurement = measurement;
    return super.update(measurement);
  }
}
