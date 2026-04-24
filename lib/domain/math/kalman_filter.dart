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
  
  /// Инициализирован ли фильтр (для подклассов)
  bool get initialized => _initialized;
  
  /// Сбросить фильтр в начальное состояние
  void reset() {
    _estimate = 0.0;
    _errorEstimate = 1.0;
    _initialized = false;
  }
  
  /// Обновить фильтр новым измерением и получить отфильтрованное значение
  double update(double measurement) {
    return updateWithNoise(measurement, processNoise, measurementNoise);
  }
  
  /// Обновить фильтр с указанными параметрами шума
  /// Используется подклассами для адаптивной фильтрации
  double updateWithNoise(double measurement, double qNoise, double rNoise) {
    if (!_initialized) {
      _estimate = measurement;
      _errorEstimate = 1.0;
      _initialized = true;
      return _estimate;
    }
    
    // Prediction step
    final predictedEstimate = _estimate;
    final predictedErrorEstimate = _errorEstimate + qNoise;
    
    // Update step
    final kalmanGain = predictedErrorEstimate / (predictedErrorEstimate + rNoise);
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
/// 
/// Автоматически увеличивает шум процесса (Q) при резких изменениях
/// сигнала, что позволяет фильтру быстрее реагировать на реальные
/// изменения, сохраняя при этом сильное сглаживание в покое.
class AdaptiveKalmanFilter extends KalmanFilter {
  /// Минимальный шум процесса
  final double minProcessNoise;
  
  /// Максимальный шум процесса  
  final double maxProcessNoise;
  
  /// Скорость адаптации (0..1)
  /// Больше значение = быстрее реагирует на изменение скорости сигнала
  final double adaptationRate;
  
  double _lastMeasurement = 0.0;
  double _currentAdaptedNoise = 0.0;
  
  AdaptiveKalmanFilter({
    super.processNoise = 0.01,
    super.measurementNoise = 0.1,
    this.minProcessNoise = 0.001,
    this.maxProcessNoise = 1.0,
    this.adaptationRate = 0.1,
  }) {
    _currentAdaptedNoise = processNoise;
  }
  
  /// Текущий адаптированный шум процесса (для отладки)
  double get currentAdaptedNoise => _currentAdaptedNoise;
  
  @override
  void reset() {
    super.reset();
    _lastMeasurement = 0.0;
    _currentAdaptedNoise = processNoise;
  }
  
  @override
  double update(double measurement) {
    if (initialized) {
      // Адаптируем шум процесса на основе скорости изменения сигнала
      final delta = (measurement - _lastMeasurement).abs();
      _currentAdaptedNoise = (processNoise + adaptationRate * delta)
          .clamp(minProcessNoise, maxProcessNoise);
    }
    
    _lastMeasurement = measurement;
    
    // Используем адаптированный шум процесса вместо фиксированного
    return updateWithNoise(measurement, _currentAdaptedNoise, measurementNoise);
  }
}
