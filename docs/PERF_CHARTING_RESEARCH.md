# High-Performance Real-Time Charting on Low-End Hardware

> **Target**: Intel Celeron N4000, 4 GB RAM, HDD  
> **Stack**: Flutter desktop + FL Chart + Dart isolates  
> **Date**: February 2026  
> **Sources**: imaNNeo/fl_chart, predict-idlab/tsdownsample, sveinn-steinarsson/flot-downsample, MinMaxLTTB paper (arXiv:2305.00332)

---

## 1. FL Chart — Architecture & Known Pitfalls

### 1.1 How FL Chart Renders

FL Chart uses Flutter's `RenderObject` pipeline directly. Each chart type (LineChart, BarChart, etc.) has:

```
LineChart (ImplicitlyAnimatedWidget)
  └─ LineChartLeaf (LeafRenderObjectWidget)
       └─ RenderLineChart (RenderBox)
            └─ LineChartPainter.paint(canvas, PaintHolder)
```

- **Every data change** calls `markNeedsPaint()` → full repaint of the entire chart.
- `LineChartData` uses **Equatable** — if the data object is identical, the repaint is skipped.
- The animation tween system (`LineChartDataTween`) creates a **full copy** of data per animation frame via `lerp()`.

### 1.2 Known Memory Leak (Issue #1106, #1693, fixed in v0.69.0)

FL Chart cached `minX/maxX/minY/maxY` calculations to avoid redundant computation. This caching caused memory retention because the old `LineChartData` objects were referenced from the cache. **Fix**: caching was disabled in v0.69.0. Implication for us:

> ⚠️ **We must supply explicit `minX, maxX, minY, maxY`** in `LineChartData` to avoid FL Chart iterating all spots every frame. This is critical with large FlSpot lists.

### 1.3 Real-Time Live Data Pattern (line_chart_sample10)

FL Chart's official real-time example uses:

```dart
// From imaNNeo/fl_chart example/line_chart_sample10.dart
final limitCount = 100;
final sinPoints = <FlSpot>[];

Timer.periodic(Duration(milliseconds: 40), (timer) {
  while (sinPoints.length > limitCount) {
    sinPoints.removeAt(0);  // ← O(n) operation!
  }
  setState(() {
    sinPoints.add(FlSpot(xValue, math.sin(xValue)));
  });
});
```

**Problems identified:**
1. `removeAt(0)` is **O(n)** — shifts entire list. Deadly at scale.
2. `setState()` rebuilds entire chart widget tree.
3. `FlSpot` is a heap-allocated object — each new spot creates GC pressure.
4. No RepaintBoundary isolation — chart repaints also trigger ancestor layouts.
5. Animation tween (`lerp`) runs on **every** data change → double the allocations.

### 1.4 FlSpot Internals

```dart
class FlSpot {
  const FlSpot(this.x, this.y, {this.xError, this.yError});
  final double x;
  final double y;
  final FlErrorRange? xError;
  final FlErrorRange? yError;
  // ... Equatable mixin, copyWith, lerp static methods
}
```

Each `FlSpot` is ~48–64 bytes on the heap (2 doubles + 2 nullable refs + object header). For 100K spots ≈ **5–6 MB** just in FlSpot objects, plus GC metadata.

---

## 2. Downsampling Strategy Comparison

### 2.1 Algorithms Analyzed

| Algorithm | Time Complexity | Preserves Shape | Parallelizable | Streaming? | Best For |
|-----------|----------------|-----------------|----------------|------------|----------|
| **LTTB** | O(n) | ★★★★★ | ❌ (sequential dependency) | ❌ | Offline/batch downsampling |
| **MinMax** | O(n) | ★★★☆☆ | ✅ (per-bin independent) | ✅ | Real-time, large datasets |
| **M4** (first/last/min/max) | O(n) | ★★★★☆ | ✅ (per-bin independent) | ✅ | Pixel-perfect rendering |
| **MinMaxLTTB** | O(n) but ~10× faster than LTTB | ★★★★★ | ✅ (MinMax phase) | Partially | >100K points, best quality |
| **Douglas-Peucker** | O(n log n) | ★★★★☆ | ❌ | ❌ | Geometric simplification |
| **Every-Nth** | O(1) per point | ★☆☆☆☆ | ✅ | ✅ | Only when speed is all that matters |

### 2.2 MinMaxLTTB — Recommended for Our Use Case

From the paper (Van Der Donckt et al., arXiv:2305.00332):

> MinMaxLTTB is a two-step algorithm: (1) MinMax preselects `n_out × minmax_ratio` min/max data points, then (2) LTTB is applied only on these preselected points.

- With `minmax_ratio = 4` (recommended default), LTTB runs on only 4× the output size instead of the full dataset.
- **Benchmarks from tsdownsample** (Rust): 50M points → 2K output in ~50ms (MinMaxLTTB parallel) vs ~800ms (LTTB).
- In Dart (single-threaded equivalent): expect ~10× speedup over pure LTTB for large datasets.

**Implication**: For 500K points → 1K display points:
- Pure LTTB: scans all 500K points
- MinMaxLTTB: MinMax reduces to 4K → LTTB reduces 4K → 1K

### 2.3 Recommended Hybrid Strategy

```
Data Pipeline:
  
  Isolate (Core data)          Main thread (UI)
  ┌──────────────────┐        ┌──────────────────┐
  │ Ring Buffer (raw) │──────►│ Display Buffer    │
  │ 500K Float64 pts  │  msg  │ 800-1200 FlSpots  │
  │                   │──────►│                    │
  │ MinMaxLTTB every  │       │ FL Chart renders   │
  │ 500ms or on zoom  │       │ these only         │
  └──────────────────┘        └──────────────────┘
```

**For live streaming** (≤10K visible window): MinMax (per-bin min/max) — fastest, good enough visually.  
**For historical review** (10K–500K): MinMaxLTTB — best quality, still fast.  
**For export/analysis**: Raw data from ring buffer — no downsampling.

---

## 3. Buffer Management — Ring Buffer vs Growing List

### 3.1 Problem with `List<FlSpot>`

```dart
// Anti-pattern from FL Chart example:
sinPoints.removeAt(0);  // O(n) — copies entire list
sinPoints.add(spot);     // Amortized O(1) but triggers GC on resize
```

For 100K points, `removeAt(0)` copies 799,992 bytes every tick. At 25 Hz → **20 million bytes/sec** of needless copying.

### 3.2 Columnar Ring Buffer (Recommended)

Store data in parallel `Float64List` arrays, not object lists:

```dart
class ColumnarRingBuffer {
  final int capacity;
  late final Float64List _timestamps;
  late final Float64List _values;
  int _head = 0;
  int _count = 0;
  
  ColumnarRingBuffer(this.capacity)
    : _timestamps = Float64List(capacity),
      _values = Float64List(capacity);
  
  void add(double timestamp, double value) {
    final idx = (_head + _count) % capacity;
    _timestamps[idx] = timestamp;
    _values[idx] = value;
    if (_count < capacity) {
      _count++;
    } else {
      _head = (_head + 1) % capacity;
    }
  }
  
  // O(1) access, no GC pressure, cache-friendly
  double timestampAt(int i) => _timestamps[(_head + i) % capacity];
  double valueAt(int i) => _values[(_head + i) % capacity];
}
```

**Advantages over `List<FlSpot>`:**

| Metric | `List<FlSpot>` | Columnar `Float64List` |
|--------|---------------|----------------------|
| Memory per point | ~48-64 bytes (object) | 16 bytes (2 × double) |
| 500K points | ~30 MB + GC overhead | 8 MB, zero GC |
| Cache locality | Poor (pointer chasing) | Excellent (contiguous) |
| `removeAt(0)` | O(n) copy | O(1) head pointer move |
| GC pressure | High (500K objects) | Zero (2 fixed arrays) |
| Isolate transfer | Expensive (deep copy) | Cheap (TransferableTypedData) |

### 3.3 Float64List vs List\<double\> in Dart

`Float64List` (from `dart:typed_data`):
- Backed by a contiguous C-style array of IEEE 754 doubles
- No boxing — values stored as raw 8-byte doubles
- Can be transferred between isolates via `TransferableTypedData` (zero-copy)
- SIMD-friendly memory layout

`List<double>`:
- Dart VM may or may not optimize to unboxed storage
- Each element could be a boxed `double` object (~24 bytes vs 8 bytes)
- Cannot use `TransferableTypedData`

> ✅ **Always use `Float64List` for sensor data buffers.** Only convert to `List<FlSpot>` at the last moment for FL Chart consumption.

---

## 4. GC Pressure Reduction Techniques

### 4.1 Object Allocation Budget

On Celeron N4000, Dart VM minor GC pauses are ~1-3ms, major GC ~10-50ms. At 60 FPS, the frame budget is 16.6ms. A major GC can eat 3 frames.

**Sources of GC pressure in charting:**

| Source | Allocation Rate | Mitigation |
|--------|----------------|------------|
| `FlSpot` creation per frame | 1K objects × 60 FPS = 60K/sec | Pre-allocate display buffer, reuse |
| `List<FlSpot>` for `LineChartBarData.spots` | New list per update | Mutate in place when possible |
| FL Chart `lerp()` animation | Full data copy per frame | **Disable animation** for real-time: `duration: Duration.zero` |
| `LineChartData.copyWith()` | Full tree copy | Minimize calls per frame |
| String allocations (axis labels) | Per-repaint | Cache `TextPainter` objects |

### 4.2 Pre-Allocated FlSpot Display Buffer

```dart
class DisplayBuffer {
  static const int maxDisplayPoints = 1000;
  
  // Pre-allocate once
  final List<FlSpot> _spots = List.generate(
    maxDisplayPoints, 
    (_) => FlSpot.zero,
  );
  
  int _activeCount = 0;
  
  /// Update spots in-place from downsampled data
  void updateFrom(Float64List timestamps, Float64List values, int count) {
    _activeCount = count;
    for (int i = 0; i < count; i++) {
      // FlSpot is immutable, so we must replace — but the List itself is reused
      _spots[i] = FlSpot(timestamps[i], values[i]);
    }
  }
  
  List<FlSpot> get activeSpots => _spots.sublist(0, _activeCount);
}
```

This creates 1K `FlSpot` objects per update (unavoidable with FL Chart's immutable design) but avoids list reallocation.

### 4.3 Disable Implicit Animations for Real-Time

```dart
LineChart(
  data,
  duration: Duration.zero,  // ← CRITICAL: disables lerp allocations
  curve: Curves.linear,
)
```

FL Chart's `AnimatedWidgetBaseState` creates a `LineChartDataTween` that calls `lerp()` per frame during animation. For real-time data at 25 Hz update rate, this doubles allocations for zero visual benefit.

---

## 5. Frame Rate Control

### 5.1 Update Throttling Strategy

On Celeron N4000, target **20-30 FPS** for chart updates (not 60). Sensor data arrives at 100-1000 Hz but the chart only needs to refresh at display rate.

```dart
class ChartUpdateThrottler {
  static const _minFrameInterval = Duration(milliseconds: 40); // 25 FPS max
  DateTime _lastUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _pendingUpdate;
  
  void scheduleUpdate(VoidCallback updateFn) {
    final now = DateTime.now();
    final elapsed = now.difference(_lastUpdate);
    
    if (elapsed >= _minFrameInterval) {
      _lastUpdate = now;
      updateFn();
    } else {
      // Coalesce: schedule one update at next available slot
      _pendingUpdate?.cancel();
      _pendingUpdate = Timer(
        _minFrameInterval - elapsed,
        () {
          _lastUpdate = DateTime.now();
          updateFn();
        },
      );
    }
  }
}
```

### 5.2 RepaintBoundary Isolation

```dart
Widget build(BuildContext context) {
  return Column(
    children: [
      // Sensor value display — updates at 10 Hz
      RepaintBoundary(
        child: SensorValueDisplay(value: currentValue),
      ),
      
      // Chart — updates at 25 Hz, isolated from parent repaints
      RepaintBoundary(
        child: SizedBox(
          height: 300,
          child: LineChart(chartData, duration: Duration.zero),
        ),
      ),
      
      // Controls — rarely change
      RepaintBoundary(
        child: ExperimentControls(),
      ),
    ],
  );
}
```

Without `RepaintBoundary`, a text update in `SensorValueDisplay` would trigger repaint of the entire subtree including the expensive chart.

### 5.3 Isolate Data Pipeline

```
┌─────────────────────────────────────────────────────────┐
│                    DATA ISOLATE                          │
│                                                          │
│  HAL Stream ──► Ring Buffer (Float64List, 500K cap)     │
│                     │                                    │
│                     ├──► MinMax downsample (live view)   │
│                     ├──► MinMaxLTTB (on zoom/scroll)     │
│                     └──► Kalman filter (optional)        │
│                                                          │
│  Output: SendPort ──► TransferableTypedData             │
│          (Float64List timestamps + Float64List values)   │
└─────────────────────────────────────────────────────────┘
                          │
                    ReceivePort
                          │
┌─────────────────────────────────────────────────────────┐
│                    UI ISOLATE (main)                     │
│                                                          │
│  Receive Float64List ──► Convert to List<FlSpot> (1K)   │
│                          ──► Update LineChartData        │
│                          ──► setState (throttled 25 Hz)  │
└─────────────────────────────────────────────────────────┘
```

Key: **TransferableTypedData** allows zero-copy transfer of `Float64List` between isolates. This is far cheaper than serializing `List<FlSpot>`.

---

## 6. Common Anti-Patterns in Flutter Charting

### ❌ Anti-Pattern 1: Rendering All Raw Points

```dart
// WRONG: 100K FlSpots directly to FL Chart
LineChartBarData(spots: allRawDataAsFlSpots) // → 2 FPS on Celeron
```

**Fix**: Always downsample to ≤1500 points before rendering.

### ❌ Anti-Pattern 2: Rebuilding Data Objects Every Frame

```dart
// WRONG: creates new LineChartData + LineChartBarData + List<FlSpot> each frame
setState(() {
  chartData = LineChartData(
    lineBarsData: [
      LineChartBarData(spots: newSpots.map((p) => FlSpot(p.x, p.y)).toList())
    ],
  );
});
```

**Fix**: Cache `LineChartBarData` configuration, only replace `spots` list.

### ❌ Anti-Pattern 3: Animation + Real-Time Data

```dart
// WRONG: implicit animation fights real-time updates
LineChart(data, duration: Duration(milliseconds: 150)) // lerp 150ms behind
```

**Fix**: `duration: Duration.zero` for live data.

### ❌ Anti-Pattern 4: Auto-Calculating Axis Bounds

```dart
// WRONG: FL Chart iterates all spots to find min/max each frame
LineChartData(lineBarsData: [...]) // minX, maxX, minY, maxY are NaN → auto-calc
```

**Fix**: Always provide explicit bounds:
```dart
LineChartData(
  minX: windowStart,
  maxX: windowEnd,
  minY: knownMinY,
  maxY: knownMaxY,
  lineBarsData: [...],
)
```

### ❌ Anti-Pattern 5: Using removeAt(0) for Scrolling Window

```dart
// WRONG: O(n) per removal
while (points.length > limit) {
  points.removeAt(0);
}
```

**Fix**: Use ring buffer or `Queue`/`ListQueue` (O(1) addLast/removeFirst).

### ❌ Anti-Pattern 6: Titles Rebuilt Every Frame

```dart
// WRONG: new widget tree per tick
getTitlesWidget: (value, meta) {
  return Text(value.toStringAsFixed(1)); // new Text + RenderParagraph every frame
}
```

**Fix**: Cache title widgets by value, or use `SideTitleFitInsideData` with minimal titles.

---

## 7. Memory Management for 500K+ Point Sessions

### 7.1 Memory Budget (4 GB RAM target)

| Component | Memory | Notes |
|-----------|--------|-------|
| Flutter engine + framework | ~80-120 MB | Baseline |
| App code + assets | ~30-50 MB | Themes, fonts, lab work content |
| Raw data ring buffer (500K × 2 doubles) | 8 MB | Fixed allocation |
| Display buffer (1K FlSpots) | ~64 KB | Negligible |
| SQLite (Drift) working set | ~10-50 MB | Depends on query patterns |
| OS + other processes | ~1.5-2 GB | Astra Linux / Windows |
| **Available headroom** | **~1.5-2 GB** | Comfortable |

### 7.2 Multi-Channel Strategy

For 6 sensor channels at 100 Hz for 1 hour:
- Raw data: 6 channels × 360K points × 16 bytes = **34 MB**
- Use one ring buffer per channel, all `Float64List`

### 7.3 Tiered Storage

```
Tier 1: Ring Buffer (RAM)     — Last N points, fast access
         ↓ overflow
Tier 2: SQLite (Drift/HDD)   — Persistent, queryable
         ↓ export
Tier 3: CSV/PDF               — User export
```

When ring buffer fills, batch-write to SQLite in the data isolate (not main thread). For reviewing historical data, query SQLite and downsample before display.

### 7.4 Session Lifecycle

```dart
class ExperimentSession {
  // Fixed-size buffers allocated at experiment start
  late final Map<String, ColumnarRingBuffer> channelBuffers;
  
  void start(List<String> channels, {int bufferSize = 500000}) {
    channelBuffers = {
      for (final ch in channels) ch: ColumnarRingBuffer(bufferSize),
    };
  }
  
  void stop() {
    // Flush remaining data to SQLite
    // Buffers persist until session is disposed
  }
  
  void dispose() {
    channelBuffers.clear(); // Float64Lists eligible for GC
  }
}
```

---

## 8. Recommended Architecture Summary

### 8.1 Data Flow

```
ESP32 BLE/USB ──► HAL (Isolate) ──► Ring Buffer (Float64List)
                                           │
                                    ┌──────┴──────┐
                                    ▼              ▼
                              Live View      Historical Review
                              MinMax @25Hz   MinMaxLTTB on demand
                                    │              │
                                    ▼              ▼
                           TransferableTypedData   TransferableTypedData
                                    │              │
                                    ▼              ▼
                              Main Isolate    Main Isolate
                              FlSpot[1000]    FlSpot[1000]
                                    │              │
                                    ▼              ▼
                              FL Chart        FL Chart
                              (no animation)  (pan/zoom enabled)
```

### 8.2 Configuration Matrix

| Scenario | Buffer Size | Downsample | Update Rate | Animation |
|----------|-------------|------------|-------------|-----------|
| Live monitoring | 50K ring | MinMax → 800 pts | 25 Hz | `Duration.zero` |
| Recording experiment | 500K ring + SQLite | MinMax → 1000 pts | 20 Hz | `Duration.zero` |
| Reviewing history | SQLite query | MinMaxLTTB → 1200 pts | On demand | 150ms ease |
| Exporting/printing | Full dataset | None (or LTTB for PDF) | Once | N/A |
| Табло (scoreboard) mode | 1 point | None | 10 Hz | `Duration.zero` |

### 8.3 Key Implementation Priorities

1. **Implement MinMaxLTTB in Dart** — two-step: MinMax preselection → LTTB on reduced set. Our current `LTTB.downsample()` is correct but needs the MinMax pre-stage for datasets >50K.

2. **Replace `List<FlSpot>` storage with `Float64List` columnar ring buffer** — current LTTB uses `List<DataPoint>` heap objects. Migrate to columnar.

3. **Add chart update throttler** — coalesce rapid `setState` calls to max 25 Hz.

4. **Wrap chart in `RepaintBoundary`** — prevent chart repaints from cascading.

5. **Always set `duration: Duration.zero`** on LineChart for real-time mode.

6. **Always provide explicit `minX/maxX/minY/maxY`** — avoid auto-calculation scan.

7. **Use `TransferableTypedData`** for isolate communication of sensor buffers.

---

## 9. Benchmarking Targets

| Metric | Target (Celeron N4000) | Measurement Method |
|--------|----------------------|-------------------|
| Chart frame time | < 12ms (allowing 4ms for GC) | `dart:developer` Timeline |
| Update-to-pixel latency | < 80ms | Timestamp in data vs vsync |
| Memory growth rate | < 1 MB/min during recording | DevTools memory view |
| GC pause P99 | < 5ms | DevTools GC log |
| Downsample 100K→1K | < 5ms | Stopwatch in isolate |
| Downsample 500K→1K (MinMaxLTTB) | < 20ms | Stopwatch in isolate |
| Cold start to first chart frame | < 3s | Wall clock |

---

## 10. References

1. **FL Chart source**: github.com/imaNNeo/fl_chart — `line_chart_painter.dart`, `line_chart_sample10.dart`
2. **LTTB original paper**: Steinarsson, S. "Downsampling Time Series for Visual Representation" (2013), hdl.handle.net/1946/15343
3. **MinMaxLTTB paper**: Van Der Donckt et al. "MinMaxLTTB: Leveraging MinMax-Preselection to Scale LTTB" (2023), arXiv:2305.00332
4. **tsdownsample implementation**: github.com/predict-idlab/tsdownsample — M4, MinMax, LTTB, MinMaxLTTB in Rust
5. **FL Chart memory leak fix**: CHANGELOG v0.69.0, issues #1106, #1693
6. **Dart typed_data**: api.dart.dev/dart-typed_data — Float64List, TransferableTypedData
7. **LTTB Dart port reference**: github.com/bnap00/dart-lttb (listed in flot-downsample README)
