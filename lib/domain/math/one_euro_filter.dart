import 'dart:math';

/// **1€ Filter** — мировой стандарт фильтрации шумных сенсоров
/// с минимальной задержкой.
///
/// Используется в:
/// - Apple (стилус, тач) — низкая задержка на iPad Pro
/// - Google (ARCore, VR tracking)
/// - Microsoft Research (Surface Pen, HoloLens hand tracking)
/// - Meta (Oculus Quest controller tracking)
/// - Промышленные роботы, CNC-станки
///
/// ## Принцип работы
///
/// Адаптивный low-pass фильтр: частота среза зависит от скорости
/// изменения сигнала.
///
/// - **Покой** (скорость ≈ 0): cutoff = [minCutoff] → сильное
///   сглаживание → идеально ровная линия
/// - **Движение** (скорость велика): cutoff = minCutoff + β·|speed|
///   → слабое сглаживание → мгновенная реакция (≤1 сэмпл)
///
/// ## Модификация для квантованных датчиков
///
/// Датчики с грубым разрешением (например, 1 см) дают чередующиеся
/// значения (70мм, 80мм, 70мм...) при реальном расстоянии 75мм.
///
/// [derivativeDeadZone] подавляет шум квантования с помощью
/// **направленного анализа**: изменения ≤ порога проверяются
/// на монотонность. Чередование направлений (70↔80мм) подавляется,
/// а последовательное движение (70→80→90) — пропускается.
///
/// Это даёт одновременно ровную линию в покое И мгновенный отклик
/// при движении (задержка всего 1 сэмпл при смене направления).
///
/// ## Ссылка
///
/// Casiez, Roussel, Vogel — CHI 2012
/// "1€ Filter: A Simple Speed-Based Low-Pass Filter for
/// Noisy Input in Interactive Systems"
/// https://cristal.univ-lille.fr/~casiez/1euro/
///
/// ## Пример использования
///
/// ```dart
/// final filter = OneEuroFilter(
///   frequency: 10.0,       // Частота датчика (Гц)
///   minCutoff: 0.3,        // Плавность в покое
///   beta: 0.5,             // Скорость реакции
///   dCutoff: 1.0,          // Сглаживание производной
///   derivativeDeadZone: 10.0, // Подавление квантования (мм)
/// );
///
/// for (final raw in sensorData) {
///   final smooth = filter.filter(raw);
///   print(smooth); // Ровно в покое, мгновенно при движении
/// }
/// ```
class OneEuroFilter {
  /// Минимальная частота среза (Гц). Определяет сглаживание в покое.
  /// Ниже значение → ровнее линия, но чуть медленнее начальный отклик.
  /// Рекомендуется: 0.1–1.0
  final double minCutoff;

  /// Коэффициент скорости. Определяет, насколько быстро фильтр
  /// переключается на отслеживание при движении.
  /// Больше значение → быстрее реакция.
  /// Рекомендуется: 0.01–1.0
  final double beta;

  /// Частота среза для сглаживания производной (Гц).
  /// Обычно 1.0. Уменьшение → стабильнее оценка скорости.
  final double dCutoff;

  /// Зона нечувствительности для производной (в единицах сигнала).
  ///
  /// Для квантованных датчиков (шаг = N единиц): deadZone = N.
  ///
  /// **Логика:** если |изменение| ≤ порога, алгоритм проверяет
  /// направление: монотонное движение (одно направление) — пропускает,
  /// чередование (смена направления) — подавляет как шум квантования.
  /// Первый шаг в новом направлении подавляется (100мс стоимость).
  ///
  /// Для датчика расстояния с шагом 10мм: deadZone = 10.0
  /// Для аналогового датчика: deadZone = 0.0 (отключено)
  final double derivativeDeadZone;

  /// Текущая оценка частоты дискретизации (Гц)
  double _freq;

  // Внутреннее состояние
  double _xPrev = 0.0;
  double _dxFiltered = 0.0;
  double _xFiltered = 0.0;
  bool _initialized = false;

  /// Направление последнего ненулевого изменения (+1 или -1).
  /// Используется для различения шума квантования (чередование)
  /// и реального движения (монотонное направление).
  int _lastNonZeroDeltaSign = 0;

  OneEuroFilter({
    double frequency = 10.0,
    this.minCutoff = 1.0,
    this.beta = 0.0,
    this.dCutoff = 1.0,
    this.derivativeDeadZone = 0.0,
  }) : _freq = frequency;

  /// Сбросить фильтр в начальное состояние
  void reset() {
    _initialized = false;
    _xPrev = 0.0;
    _dxFiltered = 0.0;
    _xFiltered = 0.0;
    _lastNonZeroDeltaSign = 0;
  }

  /// Текущее отфильтрованное значение
  double get currentValue => _xFiltered;

  /// Инициализирован ли фильтр
  bool get initialized => _initialized;

  /// Текущая адаптивная частота среза (для отладки)
  double get currentCutoff =>
      _initialized ? minCutoff + beta * _dxFiltered.abs() : minCutoff;

  /// Вычислить коэффициент alpha для EMA из частоты среза
  ///
  /// alpha = 1 / (1 + tau/Te)
  /// где tau = 1/(2π·cutoff), Te = 1/freq
  static double computeAlpha(double cutoff, double freq) {
    if (freq <= 0) return 1.0;
    final tau = 1.0 / (2.0 * pi * cutoff);
    final te = 1.0 / freq;
    return (1.0 / (1.0 + tau / te)).clamp(0.0, 1.0);
  }

  /// Обработать одно измерение и вернуть отфильтрованное значение.
  ///
  /// [x] — сырое значение от датчика.
  /// [dt] — время с предыдущего измерения (секунды). Если не задано,
  /// используется фиксированная частота [_freq].
  double filter(double x, {double? dt}) {
    if (!_initialized) {
      _xPrev = x;
      _xFiltered = x;
      _dxFiltered = 0.0;
      _initialized = true;
      return x;
    }

    // Обновляем частоту если задан dt
    if (dt != null && dt > 0) {
      _freq = 1.0 / dt;
    }

    // ─── 1. Оценка скорости (производная) ───
    final perSampleDelta = x - _xPrev;
    double dx = perSampleDelta * _freq; // мм/с (или ед/с)

    // Direction-based dead-zone: подавление шума квантования
    // БЕЗ потери реального движения.
    //
    // Проблема: для квантованных датчиков (шаг 10мм) и шум (70↔80),
    // и реальное движение (70→80→90) дают |delta|=10мм.
    // Простая отсечка по амплитуде убивает оба.
    //
    // Решение: анализ НАПРАВЛЕНИЯ:
    //   Чередование (+10, -10, +10) → шум → dx=0
    //   Монотонное  (+10, +10, +10) → движение → dx проходит
    //   Первый шаг в новом направлении → подавлен (100мс)
    //   Изменения > deadZone → всегда проходят (большой скачок)
    if (derivativeDeadZone > 0) {
      final absDelta = perSampleDelta.abs();
      if (absDelta <= derivativeDeadZone) {
        if (perSampleDelta == 0.0) {
          // Нет изменения → точно покой
          dx = 0.0;
        } else {
          final sign = perSampleDelta > 0 ? 1 : -1;
          if (sign == _lastNonZeroDeltaSign) {
            // То же направление → реальное движение → пропускаем dx
          } else {
            // Смена направления или первый шаг → подавляем
            _lastNonZeroDeltaSign = sign;
            dx = 0.0;
          }
        }
      } else {
        // Большое изменение > deadZone → точно движение
        _lastNonZeroDeltaSign = perSampleDelta > 0 ? 1 : -1;
      }
    }

    // ─── 2. Сглаженная производная (EMA) ───
    final alphaDx = computeAlpha(dCutoff, _freq);
    _dxFiltered = alphaDx * dx + (1.0 - alphaDx) * _dxFiltered;

    // ─── 3. Адаптивная частота среза ───
    final cutoff = minCutoff + beta * _dxFiltered.abs();

    // ─── 4. Основное сглаживание (EMA) ───
    final alphaX = computeAlpha(cutoff, _freq);
    _xFiltered = alphaX * x + (1.0 - alphaX) * _xFiltered;

    _xPrev = x;
    return _xFiltered;
  }
}
