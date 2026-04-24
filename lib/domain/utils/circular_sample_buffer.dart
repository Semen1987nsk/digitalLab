import 'dart:collection';

/// Efficient circular buffer for experiment data.
///
/// Avoids O(N) jank from `List.removeRange(0, count)` on overflow.
/// Uses `dart:collection` `Queue` (doubly-linked list) under the hood
/// for O(1) `addLast` and O(1) `removeFirst`.
///
/// Memory: fixed max capacity, oldest data discarded automatically.
/// Thread-safety: Dart is single-threaded (event loop), no locks needed.
class CircularSampleBuffer<T> {
  final int _maxCapacity;
  final Queue<T> _queue = Queue<T>();

  /// Total items ever added (including evicted ones).
  int _totalAdded = 0;

  /// Number of items evicted due to overflow.
  int _totalEvicted = 0;

  /// Callback fired once when buffer reaches [warningThreshold] percent full.
  /// Used to warn the user before data loss begins.
  void Function()? onWarningThreshold;

  /// Percentage (0.0-1.0) at which [onWarningThreshold] fires.
  final double warningThreshold;

  /// Whether warning has already been fired for this fill cycle.
  bool _warningFired = false;

  CircularSampleBuffer({
    required int maxCapacity,
    this.onWarningThreshold,
    this.warningThreshold = 0.8,
  }) : _maxCapacity = maxCapacity;

  /// Add a sample. If buffer is full, oldest sample is evicted (O(1)).
  void add(T item) {
    _queue.addLast(item);
    _totalAdded++;

    if (_queue.length > _maxCapacity) {
      _queue.removeFirst();
      _totalEvicted++;
    }

    // Fire warning once at threshold
    if (!_warningFired &&
        onWarningThreshold != null &&
        _queue.length >= (_maxCapacity * warningThreshold).toInt()) {
      _warningFired = true;
      onWarningThreshold!();
    }
  }

  /// Number of samples currently in buffer.
  int get length => _queue.length;

  /// Whether buffer is empty.
  bool get isEmpty => _queue.isEmpty;

  /// Whether buffer is at max capacity.
  bool get isFull => _queue.length >= _maxCapacity;

  /// Max capacity of the buffer.
  int get maxCapacity => _maxCapacity;

  /// Total samples ever added (including evicted).
  int get totalAdded => _totalAdded;

  /// Number of evicted (lost) samples.
  int get totalEvicted => _totalEvicted;

  /// Fill percentage (0.0 - 1.0).
  double get fillRatio =>
      _maxCapacity > 0 ? _queue.length / _maxCapacity : 0.0;

  /// Get the last N items as a List (for chart rendering).
  ///
  /// This is O(N) but N is bounded by [count] (typically ~3500 for charts).
  /// Much cheaper than `List.sublist()` on a 500K list.
  List<T> takeLast(int count) {
    if (count >= _queue.length) return _queue.toList();
    return _queue.skip(_queue.length - count).toList();
  }

  /// Get ALL items as a List (for export/save).
  /// O(N) — use only when experiment stops (not during live charting).
  List<T> toList() => _queue.toList();

  /// Clear all data and reset counters.
  void clear() {
    _queue.clear();
    _totalAdded = 0;
    _totalEvicted = 0;
    _warningFired = false;
  }

  /// Reset only the warning flag (e.g., after user acknowledges).
  void resetWarning() {
    _warningFired = false;
  }
}
