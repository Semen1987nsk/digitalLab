import '../entities/sensor_type.dart';
import 'kalman_filter.dart';
import 'moving_average.dart';
import 'one_euro_filter.dart';

/// Комбинированный процессор сигнала для датчиков
///
/// Применяет оптимальную цепочку фильтров под тип датчика:
///
/// **Датчик расстояния** (квантованный, шаг 10мм):
///   SpikeGuard(500мм) → 1€ Filter с dead-zone
///   - Нулевая задержка для нормальных значений (vs MedianFilter: +100мс)
///   - Ровная линия в покое (dead-zone подавляет чередование 70↔80мм)
///   - Мгновенная реакция на реальное движение (≤100мс)
///
/// **Остальные датчики** (аналоговые):
///   MedianFilter → KalmanFilter
///   - Стандартная фильтрация шума
///
/// ## Бюджет задержки (distance @ 10Гц)
///
/// | Этап         | Было (Median) | Стало (SpikeGuard) |
/// |--------------|---------------|--------------------|
/// | Spike guard  | 100мс         | **0мс**            |
/// | Dead-zone    | 100мс         | 100мс              |
/// | 1€ EMA       | ~50мс         | ~30мс              |
/// | **Итого**    | **~250мс**    | **~130мс**         |
///
/// ## Ссылки
///
/// 1€ Filter: Casiez, Roussel, Vogel — CHI 2012
/// Используется в Apple (iPad Pencil), Google (ARCore),
/// Microsoft (Surface Pen), Meta (Quest controllers)
class SignalProcessor {
  final SensorType sensorType;

  late final MedianFilter _medianFilter;

  /// Kalman filter for analog sensors (temperature, voltage, etc.)
  KalmanFilter? _kalmanFilter;

  /// 1€ Filter for quantized sensors (distance) — world-class standard
  OneEuroFilter? _oneEuro;

  /// Zero-latency spike guard for distance (replaces MedianFilter)
  SpikeGuard? _spikeGuard;

  /// Включить/выключить фильтрацию (для отладки)
  bool enabled = true;

  SignalProcessor({
    required this.sensorType,
  }) {
    // Настраиваем фильтры под тип датчика
    switch (sensorType) {
      case SensorType.temperature:
        // Температура меняется очень медленно
        _medianFilter = MedianFilter(windowSize: 5);
        _kalmanFilter = KalmanFilter(
          processNoise: 0.001,
          measurementNoise: 0.5,
        );

      case SensorType.voltage:
      case SensorType.current:
        // Электрические величины — быстрая реакция
        _medianFilter = MedianFilter(windowSize: 3);
        _kalmanFilter = KalmanFilter(
          processNoise: 0.1,
          measurementNoise: 0.5,
        );

      case SensorType.acceleration:
      case SensorType.magneticField:
        // IMU — очень быстрые изменения
        _medianFilter = MedianFilter(windowSize: 3);
        _kalmanFilter = KalmanFilter(
          processNoise: 1.0,
          measurementNoise: 0.3,
        );

      case SensorType.pressure:
        // Атмосферное давление — медленные изменения
        _medianFilter = MedianFilter(windowSize: 5);
        _kalmanFilter = KalmanFilter(
          processNoise: 0.01,
          measurementNoise: 1.0,
        );
    }
  }

  /// Обработать одно измерение
  double process(double rawValue) {
    if (!enabled) return rawValue;

    // Для distance: SpikeGuard (0мс) → 1€ Filter
    if (_spikeGuard != null && _oneEuro != null) {
      final afterGuard = _spikeGuard!.process(rawValue);
      return _oneEuro!.filter(afterGuard);
    }

    // Для остальных: MedianFilter → Kalman
    final afterMedian = _medianFilter.add(rawValue);
    return _kalmanFilter!.update(afterMedian);
  }

  /// Сбросить все фильтры
  void reset() {
    _medianFilter.reset();
    _kalmanFilter?.reset();
    _oneEuro?.reset();
    _spikeGuard?.reset();
  }

  /// Текущее отфильтрованное значение
  double get currentValue =>
      _oneEuro?.currentValue ?? _kalmanFilter?.currentEstimate ?? 0.0;
}
