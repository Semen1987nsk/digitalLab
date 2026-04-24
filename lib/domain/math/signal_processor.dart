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
      case SensorType.distance:
        // ── SpikeGuard + 1€ Filter (мировой стандарт, v2) ──
        //
        // Проблема: V802 даёт целые сантиметры (70мм, 80мм).
        // При реальном расстоянии 75мм чередуются 70↔80.
        // Kalman/EMA не справляются — слишком медленные или
        // пропускают шум квантования.
        //
        // Решение: 1€ Filter с direction-based dead-zone.
        //   - Dead-zone = 10мм (1 квант) с анализом НАПРАВЛЕНИЯ:
        //     чередование 70↔80 (смена знака) → шум → подавлен
        //     монотонное 70→80→90 (один знак) → движение → пропущен
        //   - Первый шаг в новом направлении → подавлен (100мс)
        //   - Изменения >10мм за сэмпл → мгновенный отклик
        //
        // v2: SpikeGuard вместо MedianFilter:
        //   Median(3) добавлял 100мс к КАЖДОМУ значению.
        //   SpikeGuard: 0мс для нормальных, 100мс только для выбросов.
        //   maxDelta=500мм = 5м/с @ 10Гц — быстрее руки не бывает.
        //
        // v2: minCutoff 0.3→0.5Hz:
        //   α покоя: 0.16→0.24. С dead-zone джиттер и так подавлен,
        //   поэтому можно увеличить cutoff для быстрого settling.
        //
        // Параметры (оптимизированы для V802 @ 10Hz):
        //   minCutoff=0.5Hz → alpha≈0.24 в покое → быстрое settling
        //   beta=0.5 → при 100мм/с: cutoff=50Hz → alpha≈0.97 → instant
        //   dCutoff=1.0 → стандартное сглаживание производной
        //
        // Бюджет задержки (v1 → v2):
        //   Spike guard: 100мс → **0мс** (SpikeGuard vs Median)
        //   Dead-zone:   100мс → 100мс (без изменений)
        //   1€ settling: ~50мс → ~30мс (minCutoff 0.3→0.5)
        //   ИТОГО:       ~250мс → **~130мс** (почти 2× быстрее)
        _medianFilter = MedianFilter(windowSize: 3); // for other sensors
        _spikeGuard = SpikeGuard(maxDelta: 500.0);
        _oneEuro = OneEuroFilter(
          frequency: 10.0,
          minCutoff: 0.5,
          beta: 0.5,
          dCutoff: 1.0,
          derivativeDeadZone: 10.0,
        );

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

      case SensorType.force:
        // Силомер — средняя динамика
        _medianFilter = MedianFilter(windowSize: 3);
        _kalmanFilter = KalmanFilter(
          processNoise: 0.5,
          measurementNoise: 0.3,
        );

      case SensorType.lux:
        // Освещённость — умеренная динамика
        _medianFilter = MedianFilter(windowSize: 3);
        _kalmanFilter = KalmanFilter(
          processNoise: 5.0,
          measurementNoise: 2.0,
        );

      case SensorType.radiation:
        // Счётчик Гейгера — статистический шум, усреднение
        _medianFilter = MedianFilter(windowSize: 5);
        _kalmanFilter = KalmanFilter(
          processNoise: 2.0,
          measurementNoise: 10.0,
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
