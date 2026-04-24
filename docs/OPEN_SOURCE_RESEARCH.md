# Open-Source Educational Lab Software — Comparative Research

> **Date**: January 2026  
> **Purpose**: Architectural best practices analysis for digitalLab project  
> **Projects Analyzed**: phyphox, Arduino Science Journal, openDAQ, PSLab Desktop, Vernier Go Direct

---

## Executive Summary

Five open-source projects covering educational sensor dashboards and data acquisition were analyzed across eight dimensions: architecture, sensor abstraction, real-time data flow, persistence, experiment lifecycle, calibration, reliability patterns, and export. The findings directly inform the digitalLab Flutter application and ESP32 firmware architecture.

**Key Takeaway**: Arduino Science Journal has the best separation of concerns for a mobile sensor app. phyphox has the richest experiment definition format. openDAQ has the most sophisticated signal/data model. PSLab demonstrates effective Python↔Electron bridging. Vernier shows the simplest possible sensor API wrapper.

---

## 1. Project Overviews

| Project | Language | Platform | Focus | Maturity |
|---------|----------|----------|-------|----------|
| **phyphox** (RWTH Aachen) | Java (Android) / Swift (iOS) | Mobile | Phone sensors + BLE external | Production (university-maintained) |
| **Arduino Science Journal** | Java (Android) | Mobile | Phone sensors + Arduino BLE | Production (formerly Google) |
| **openDAQ** | C++ | Desktop/Embedded SDK | High-performance DAQ framework | Production (industrial) |
| **PSLab Desktop** | Electron + Python | Desktop | Hardware oscilloscope/multimeter | Beta |
| **Vernier Go Direct** | Python / JavaScript | Cross-platform | Commercial sensor wrapper | Production (educational) |

---

## 2. Architecture Patterns

### 2.1 phyphox — Monolithic XML-Driven

```
┌──────────────────────────────────────────┐
│           PhyphoxExperiment              │  ← God object (Serializable)
│  Vector<SensorInput>                     │
│  Vector<DataBuffer>                      │
│  Vector<AnalysisModule>                  │
│  Vector<ExpView>                         │
│  processAnalysis() → main loop           │
└──────────────────────────────────────────┘
         ↕ XML (.phyphox format v1.14)
┌──────────────────────────────────────────┐
│  SensorInput → Lock → DataBuffer         │
│  RateStrategy: auto|request|generate|limit│
│  ValueBuffer (averaging per interval)    │
└──────────────────────────────────────────┘
```

**Pattern**: Monolithic Activity-based. NOT Clean Architecture or MVVM.  
**Data Flow**: Pull-based — sensors push to buffers → analysis processes periodically → views pull from buffers.  
**State**: `writeStateFile()` serializes all buffers to XML for persistence.  
**iOS Mirror**: Swift implementation with identical architecture. `DataBuffer` uses `stateToken: UUID` that changes on mutation (observer pattern). `DynamicViewModule` protocol with `DataBufferObserver` for reactive UI.

**Strengths**:
- XML experiment format enables community-contributed experiments (100+ built-in)
- Rate strategies (auto/request/generate/limit) handle diverse sensor timing elegantly
- Cross-platform experiment sharing via `.phyphox` files

**Weaknesses**:
- God-object `PhyphoxExperiment` holds ALL state
- Thread safety via `java.util.concurrent.locks.Lock` (coarse-grained)
- No dependency injection or modular architecture

### 2.2 Arduino Science Journal — Service-Oriented with Clean Interfaces

```
┌─────────────────────────────────────────────┐
│  RecorderController (interface)             │
│    ├── startObserving(sensorId)             │
│    ├── startRecording() / stopRecording()   │
│    └── Map<String, StatefulRecorder>        │
├─────────────────────────────────────────────┤
│  SensorChoice (abstract)                    │
│    ├── createPresenter(DataViewOptions...)   │
│    └── createRecorder(Context, Observer...)  │
├─────────────────────────────────────────────┤
│  SensorProvider (interface)                 │
│    ├── buildSensor(sensorId, spec)          │
│    └── buildSensorSpec(name, config)        │
├─────────────────────────────────────────────┤
│  SensorDiscoverer (interface)               │
│    ├── startScanning(ScanListener)          │
│    ├── stopScanning()                       │
│    └── getProvider() → SensorProvider       │
├─────────────────────────────────────────────┤
│  DataController / RecordingDataController   │
│    ├── uiThread, metaDataThread,            │
│    │   sensorDataThread (separate executors) │
│    └── SensorDatabase + MetaDataManager      │
└─────────────────────────────────────────────┘
```

**Pattern**: Service-oriented with RxJava reactive streams. Observer pattern via `RecorderListenerRegistry`. Dagger 2 for DI.  
**Data Flow**: `SensorRecorder` → `StreamConsumer` → `ScalarStreamConsumer.recordData()` → `ZoomRecorder` + `DataController`.  
**Key Innovation**: `ZoomRecorder` — multi-resolution data storage. For each N×2 points in tier X, stores 2 points (min/max) in tier X+1. Default ratio: 20:1.

**Strengths**:
- **Best separation of concerns**: Clean interfaces between discovery, recording, presentation, storage
- `SensorProvider` + `SensorDiscoverer` + `SensorChoice` — excellent pluggable sensor abstraction
- Separate thread executors for UI, metadata, and sensor data
- `BehaviorSubject<RecordingStatus>` for reactive state management
- Multi-tier zoom recording (like LOD for data)
- Protobuf for internal serialization (GoosciSensorSpec, GoosciSnapshotValue)

**Weaknesses**:
- Heavy abstraction layer (many interfaces)
- RxJava boilerplate
- Archived/deprecated project (Google discontinued)

### 2.3 openDAQ — Component-Based Signal/Packet SDK

```
┌─────────────────────────────────────────────┐
│  Signal Hierarchy                           │
│  OutputSignalBase → OutputDomainSignalBase   │
│                   → OutputValueSignalBase    │
│                   → OutputConstValueSignal   │
│  InputSignalBase  → InputDomainSignal        │
│                   → InputExplicitDataSignal  │
│                   → InputConstantDataSignal  │
├─────────────────────────────────────────────┤
│  DataPacketImpl                             │
│    domainPacket, descriptor, sampleCount     │
│    offset, externalMemory + deleter          │
│    scaleData(), calculateRule()              │
├─────────────────────────────────────────────┤
│  DataDescriptorImpl                         │
│    name, sampleType, unit, valueRange        │
│    dataRule (Linear/Constant)                │
│    scaling (PostScaling), origin             │
│    tickResolution, structFields, metadata    │
├─────────────────────────────────────────────┤
│  StreamReader                               │
│    Factory: StreamReader(Signal, ReadMode)   │
│    Automatic position tracking               │
│    Scaled/raw read modes                     │
├─────────────────────────────────────────────┤
│  StreamingManager (server-side)             │
│    RegisteredServerSignal (daqSignal+numId)  │
│    RegisteredClientSignal (stringId+clientId)│
│    Pub/sub with automatic event packets      │
└─────────────────────────────────────────────┘
```

**Pattern**: Component-based C++ SDK with strict signal/packet/descriptor separation.  
**Data Flow**: Publisher-subscriber. Signals produce DataPackets → StreamReaders consume. Domain/value signal duality (time vs data).  
**Protocol**: Native streaming + WebSocket protocols. Signal descriptors carry full metadata.

**Strengths**:
- **Most sophisticated data model**: Rich descriptors with sample type, unit, value range, data rules, scaling
- `LinearScaling(scale, offset, rawType, scaledType)` in descriptors — calibration built into the type system
- Packet-based transport with domain alignment — elegant memory management
- Multi-protocol streaming (native + websocket)
- `RefChannelImpl` with `PacketBuffer` for efficient sample generation

**Weaknesses**:
- Industrial complexity — overkill for educational use
- C++ learning curve
- No experiment/session concept — pure data acquisition

### 2.4 PSLab Desktop — Electron + Python Bridge

```
┌─────────────────────────────────────────────┐
│  React UI (Electron renderer)               │
│    Oscilloscope, LogicAnalyzer, Multimeter   │
│    WaveGenerator, PowerSource, Sensors       │
│    ipcRenderer.on('OSC_VOLTAGE_DATA', ...)   │
├─────────────────────────────────────────────┤
│  linker.html (background task)              │
│    preProcessor.js → parse JSON → ipc send   │
├─────────────────────────────────────────────┤
│  bridge.py (Python subprocess)              │
│    stdin/stdout JSON protocol                │
│    Instrument class per module               │
│    threading.Thread per capture mode          │
│    json.dumps(output) → sys.stdout.flush()   │
├─────────────────────────────────────────────┤
│  PSLab Python library                        │
│    device.oscilloscope.capture(channels,     │
│      samples, time_gap, trigger, ...)         │
│    device.oscilloscope.fetch_data()          │
└─────────────────────────────────────────────┘
```

**Pattern**: Layered bridge — React → ipcRenderer → background HTML worker → Python subprocess via stdin/stdout JSON.  
**Data Flow**: Python capture thread → `json.dumps()` → `sys.stdout.flush()` → Electron preProcessor → ipcRenderer → React state.  
**Instruments**: Oscilloscope (4-ch, FFT, XY plot), Logic Analyzer, Wave Generator, Power Source, Multimeter, Sensors.

**Strengths**:
- Each instrument is a separate Python class with dedicated threads
- Simple JSON bridge protocol between Python and JS
- `file_write.update_buffer()` for logging with channel/timestamp metadata
- Clean instrument isolation (Oscilloscope, LogicAnalyser, Multimeter, etc.)

**Weaknesses**:
- JSON over stdout is bandwidth-limited for high-sample-rate data
- No experiment/session model
- Minimal error handling in bridge communication
- I2C sensor scanning but limited sensor abstraction
- No calibration framework visible

### 2.5 Vernier Go Direct — Thin Procedural Wrapper

```
┌─────────────────────────────────────────────┐
│  gdx.py (class GDX)                        │
│    devices[], device_sensors[][], buffer[][] │
│    open(connection='usb'|'ble')             │
│    select_sensors([1, 2, 3])                │
│    start(period=ms)                         │
│    read() → 1D list of values               │
│    stop() / close()                         │
├─────────────────────────────────────────────┤
│  godirect library (proprietary)             │
│    device.list_sensors() → dict             │
│    device.enable_sensors(sensors=[])        │
│    sensor.values → list                     │
│    sensor.clear()                           │
│    sensor._mutual_exclusion_mask            │
├─────────────────────────────────────────────┤
│  JavaScript API (event-driven)              │
│    sensor.on('value-changed', callback)     │
│    sensor.value, sensor.unit, sensor.name   │
└─────────────────────────────────────────────┘
```

**Pattern**: Simple procedural wrapper. No experiment/session model. Sensor selection by number.  
**Data Flow**: Blocking `read()` → `sensor.values` list → `sensor.clear()`. Buffer system for fast sampling overflow.  
**JS variant**: Event-driven with `sensor.on('value-changed', callback)`.

**Strengths**:
- **Simplest possible API** — 6 methods cover entire workflow
- 2D buffer system handles fast sampling overflow gracefully
- USB + BLE connection abstraction in single `open()` call
- VPython integration for visualization (buttons, sliders, charts)

**Weaknesses**:
- No experiment model, session management, or persistence
- Calibration handled entirely in firmware/library (opaque)
- No error recovery or reconnection logic visible
- Export is manual CSV only

---

## 3. Sensor Abstraction Comparison

| Aspect | phyphox | Arduino SJ | openDAQ | PSLab | Vernier |
|--------|---------|------------|---------|-------|---------|
| **Base class** | `SensorInput` + `SensorEventListener` | `SensorChoice` (abstract) | `InputSignalBase` hierarchy | Per-instrument Python class | `gdx` wrapper class |
| **Discovery** | XML `<sensor type="...">` | `SensorDiscoverer` interface | Component enumeration | I2C scan | `GoDirect(use_ble, use_usb)` |
| **Registration** | `Vector<SensorInput>` | `SensorRegistry` (LinkedHashMap) | Signal graph | Hardcoded instruments | `device.list_sensors()` dict |
| **Configuration** | XML attributes (rate, rateStrategy) | `SensorProvider.buildSensor()` + `BleSensorSpec` | `DataDescriptor` (unit, range, scaling, rule) | Python class constructor args | `select_sensors([1,2,3])` |
| **Data Output** | Named `DataBuffer` (x/y/z/t/abs/accuracy) | `StreamConsumer` + `SensorObserver` | `DataPacket` + `StreamReader` | JSON over stdout | `sensor.values` list |
| **Threading** | Lock per SensorInput | Separate thread executors | Async signal delivery | threading.Thread per mode | Blocking `read()` |
| **BLE Support** | External via Bluetooth GATT XML config | `BleSensorSpec` + `NativeBleDiscoverer` + `MkrSciBleSensor` | Native protocol streaming | N/A (USB only) | `GoDirect(use_ble=True)` |

### Best Practice Recommendations for digitalLab:

1. **Adopt Arduino SJ's `SensorProvider` + `SensorDiscoverer` pattern** — Maps perfectly to your `HALInterface` with BLE/USB/Mock implementations
2. **Use phyphox's rate strategies** (auto/request/generate/limit) — Essential for diverse hardware sensors with different timing characteristics
3. **Implement openDAQ-style descriptors** — Attach unit, range, scaling metadata to each sensor channel
4. **Keep Vernier's simplicity for the public API** — `open() → select_sensors() → start() → read() → stop() → close()`

---

## 4. Real-Time Data Flow

### 4.1 Data Ingestion Patterns

| Project | Pattern | Throughput | Buffering |
|---------|---------|------------|-----------|
| **phyphox** | Pull-based: sensor → Lock → DataBuffer → analysis → view | Medium (phone sensors ~100Hz) | DataBuffer with configurable size (0 = unlimited) |
| **Arduino SJ** | Reactive: sensor → StreamConsumer → ZoomRecorder → DB + UI | Medium | ZoomRecorder multi-tier min/max storage |
| **openDAQ** | Packet-based: Signal → DataPacket → StreamReader | Very High (industrial) | PacketBuffer with external memory support |
| **PSLab** | Thread-based: capture thread → JSON stdout → ipc → React | Low-Medium | numpy arrays in Python, spread arrays in JS |
| **Vernier** | Blocking: device.read() → sensor.values → clear() | Low-Medium | 2D buffer for fast sampling overflow |

### 4.2 Key Insights for digitalLab

**ZoomRecorder (Arduino SJ)** — Most relevant for your LTTB approach:
```
Tier 0: All raw data points
Tier 1: For every 20 points in Tier 0, store 2 (min + max)
Tier 2: For every 20 points in Tier 1, store 2 (min + max)
...
```
This is essentially a pre-computed LOD pyramid for time-series data. When zoomed out, read from higher tiers. This complements LTTB by reducing DB reads.

**phyphox Rate Strategies** — Solves the "sensor delivers data at wrong rate" problem:
- `auto`: Pass through as-is
- `request`: Request specific hardware rate
- `generate`: Interpolate to desired rate when hardware can't deliver
- `limit`: Drop excess samples, keeping latest

**openDAQ Domain/Value Signal Duality** — Separates time domain from value signals:
```
DomainSignal (timestamps) ←→ ValueSignal (measurements)
DataPacket has: domainPacket reference + value data
```
This enables efficient storage: store timestamps once, reference from multiple value channels.

---

## 5. Persistence & Storage

| Project | Technology | Schema | Offline Support |
|---------|------------|--------|-----------------|
| **phyphox** | XML state files + in-memory DataBuffers | Flat: buffer name → array of doubles | State saved to XML on pause; no DB |
| **Arduino SJ** | SQLite (`SimpleMetaDataManager`) + file system | Experiments → Trials → SensorLayouts → ScalarReadings. Separate zoom tier tables. | Full offline. File-based experiment storage with ZIP import/export |
| **openDAQ** | N/A (SDK — no built-in persistence) | Signal descriptors are self-describing | N/A |
| **PSLab** | `FileWrite` class → CSV files per instrument | Timestamp, datetime, channel, xData, yData, timebase | CSV logging per capture session |
| **Vernier** | None built-in (manual CSV) | N/A | N/A |

### Best Practice for digitalLab:
- **Adopt Arduino SJ's hierarchical model**: `Experiment → Trial → SensorLayout → ScalarReadings`
- **Add zoom tiers** (Arduino SJ's approach) to your Drift/SQLite schema for efficient graph rendering
- **Use phyphox's named buffer concept** for the analysis pipeline — maps well to Dart Streams

---

## 6. Experiment Lifecycle

### 6.1 Comparison

| Phase | phyphox | Arduino SJ | openDAQ | PSLab | Vernier |
|-------|---------|------------|---------|-------|---------|
| **Define** | XML `.phyphox` file with full experiment definition (sensors, views, analysis, export) | `Experiment.newExperiment()` with empty state | N/A | Hardcoded per instrument | N/A |
| **Configure** | XML `<input>` + `<data-containers>` | `updateSensorLayout()`, `experimentSensors` list | Signal/Channel configuration | `set_config(ch1, ch2, timeBase, ...)` | `select_sensors([1,2,3])` |
| **Start** | `SensorInput.start()` + `analysis.start()` | `RecorderController.startObserving()` | Signal subscription | `start_read()` → threading | `start(period=ms)` |
| **Record** | Implicit (DataBuffer accumulates) | `RecorderController.startRecording()` → creates Trial | Packet streaming | Continuous thread output | Blocking `read()` loop |
| **Stop** | `SensorInput.stop()` + `analysis.stop()` | `RecorderController.stopRecording()` → finalize Trial + stats | Unsubscribe | `stop_read()` → thread join | `stop()` |
| **Export** | CSV/Excel/ZIP with multiple format options | CSV (timestamp + sensor columns) + SJ ZIP format | CSV writer example | CSV per channel | Manual CSV |
| **Share** | `.phyphox` file sharing + web remote control | ZIP with Protobuf + file sync | N/A | N/A | N/A |

### 6.2 phyphox Experiment XML Format (Best-in-Class)

```xml
<phyphox version="1.14">
    <title>Acceleration</title>
    <category>Mechanics</category>
    <description>Measure acceleration...</description>
    
    <data-containers>
        <container size="0">accX</container>
        <container size="0">accY</container>
        <container size="0">acc_time</container>
    </data-containers>
    
    <input>
        <sensor type="accelerometer" rate="0.01">
            <output component="x">accX</output>
            <output component="y">accY</output>
            <output component="t">acc_time</output>
        </sensor>
    </input>
    
    <views>
        <view label="Graph">
            <graph label="Acceleration" labelX="t (s)" labelY="a (m/s²)" 
                   partialUpdate="true">
                <input axis="x">acc_time</input>
                <input axis="y">accX</input>
            </graph>
        </view>
    </views>
    
    <analysis>
        <!-- Processing pipeline modules -->
    </analysis>
    
    <export>
        <set name="Accelerometer">
            <data name="Time (s)">acc_time</data>
            <data name="X (m/s²)">accX</data>
        </set>
    </export>
</phyphox>
```

### Best Practice for digitalLab:
- **Adopt JSON-based experiment definitions** (like phyphox XML but in JSON/Protobuf) for your `lab_works/` assets
- **Implement the Trial model from Arduino SJ** — Experiment contains Trials (recording sessions)
- **Add SensorLayout snapshots** (Arduino SJ) — save which sensors were active and how they were displayed per trial

---

## 7. Calibration Approaches

| Project | Calibration Method | User Control | Storage |
|---------|-------------------|--------------|---------|
| **phyphox** | Calibrated/uncalibrated magnetometer toggle; accuracy tracking (0-3 scale); device time offset correction (`fixDeviceTimeOffset`) | Toggle in UI menu | In-memory per session |
| **Arduino SJ** | `ScaleTransform` on BLE sensors; `BleSensorSpec.setCustomScaleTransform()`; per-sensor-type defaults (`TEN_BITS_TO_PERCENT` for raw) | Pin/frequency/scale config dialog | Stored in `ExternalSensorSpec` config bytes |
| **openDAQ** | `LinearScaling(scale, offset, rawType, scaledType)` in `DataDescriptor`; `PostScaling` applied automatically; `DataRule` (Linear/Constant) for computed values | Programmatic | Part of signal descriptor (always available) |
| **PSLab** | None visible in desktop app | N/A | N/A |
| **Vernier** | Handled internally by godirect firmware/library | None (opaque) | In firmware |

### Best Practice for digitalLab:
- **Implement openDAQ-style `LinearScaling`** in your sensor descriptors — `calibrated_value = raw_value * scale + offset`
- **Store calibration in NVS** on ESP32 (per-sensor, per-unit)
- **Provide phyphox-style calibrated/uncalibrated toggle** for educational transparency
- **Add Arduino SJ's `ScaleTransform`** concept to your `SensorPacket` protobuf

---

## 8. Export Formats

| Project | Formats | Multi-sensor | Metadata | Sharing |
|---------|---------|-------------|----------|---------|
| **phyphox** | CSV (comma/tab/semicolon), Excel (.xls via Apache POI), ZIP | Export sets group related buffers | Device metadata + sensor metadata + time references | Web remote + QR code + file share |
| **Arduino SJ** | CSV (with relative/absolute time), SJ archive (ZIP with Protobuf) | Multi-sensor columns aligned by timestamp | Experiment name, trial title, sensor IDs | Share intent + local download + cloud sync |
| **openDAQ** | CSV (via Recorder example) | StreamReader per signal | Signal descriptors embedded | N/A |
| **PSLab** | CSV per instrument/channel | Per-channel files | Timestamp, datetime, channel, timebase | File system |
| **Vernier** | CSV (manual, via csv.writer) | One row per read cycle | Sensor name, unit | File system |

### phyphox Export Detail (Most Comprehensive):
```
Export formats:
├── CSV: configurable separator (comma/tab/semicolon)
│       configurable decimal (point/comma) — for European locales
├── Excel: Apache POI .xls with multiple sheets
└── ZIP: all export sets as separate CSVs + metadata
    └── meta/device.csv + meta/time.csv (time reference mappings)
```

### Best Practice for digitalLab:
- **Implement phyphox's locale-aware CSV** — Critical for Russian schools (semicolon separator, comma decimal)
- **Add Arduino SJ's timestamp alignment** — align multi-sensor data by timestamp in export
- **Support ZIP bundle** with experiment metadata for sharing between students/teachers
- **PDF generation** (already planned) — unique differentiator vs all analyzed projects

---

## 9. Reliability Patterns & Error Handling

### 9.1 Observed Patterns

| Project | Connection Recovery | Data Integrity | Error Communication |
|---------|-------------------|----------------|-------------------|
| **phyphox** | `SensorError.sensorUnavailable(SensorType)` enum; `verifySensorAvailibility()` before start; `ignoreUnavailable` flag for graceful degradation | Lock-based buffer access; stateToken (UUID) for change detection | Exception propagation to UI |
| **Arduino SJ** | `SensorStatusListener` interface; `FailureListener` for async errors; connection state via `BehaviorSubject<RecordingStatus>` | Separate thread executors prevent UI blocking; `MaybeConsumer` for nullable async results | `ExportProgress.fromThrowable()` for export errors |
| **openDAQ** | Boost.asio async reconnection; `NativeStreamingClientHandler.connect()` with error callbacks | Packet-based — lost packets detectable via sequence; `DataPacket` validation | Signal event packets for status |
| **PSLab** | `CONNECTION_STATUS` ipc events; `device_detection.async_connect()` | JSON parse errors silently dropped | No structured error handling visible |
| **Vernier** | Basic try/except around connection | `sensor.clear()` prevents stale data | Print-based error output |

### 9.2 Best Practice for digitalLab:
1. **Implement Arduino SJ's `SensorStatusListener`** pattern — connection/error/data states as enum
2. **Use phyphox's `ignoreUnavailable`** flag — graceful degradation when sensors are missing
3. **Adopt openDAQ's packet validation** approach — CRC/sequence number in your Protobuf packets
4. **Russian-language error messages** — none of the analyzed projects support localized errors (your differentiator)

---

## 10. Architectural Recommendations for digitalLab

### 10.1 From phyphox — ADOPT:
- [x] Rate strategies (auto/request/generate/limit) for `ExperimentSensorInput`
- [x] DataBuffer concept with named buffers for analysis pipeline
- [x] XML/JSON experiment definition format for `lab_works/`
- [x] Web remote control server (they serve from device, you serve from ESP32)
- [x] Locale-aware export (semicolon CSV for Russian schools)

### 10.2 From Arduino Science Journal — ADOPT:
- [x] **`SensorProvider` → `SensorChoice` → `SensorRecorder`** abstraction → maps to your `HALInterface`
- [x] **`SensorDiscoverer`** interface → your BLE scanning abstraction
- [x] **`ZoomRecorder`** multi-tier storage → complement your LTTB for efficient graph rendering
- [x] **`Experiment → Trial → SensorLayout`** hierarchy → your Drift database schema
- [x] **Separate thread executors** for UI, metadata, sensor data → your Isolates
- [x] **Protobuf for internal data** (they use GoosciSensorSpec) → you already plan nanopb

### 10.3 From openDAQ — ADOPT:
- [x] **Rich signal descriptors** with unit, range, scaling → extend your `SensorPacket` protobuf
- [x] **`LinearScaling(scale, offset)`** for calibration → ESP32 NVS + protobuf field
- [x] **Domain/value signal separation** → separate timestamp stream from data streams
- [ ] ~~Packet-based transport~~ (too complex — your Protobuf stream is sufficient)

### 10.4 From PSLab — ADOPT:
- [x] **Instrument-per-class isolation** → separate BLoC/provider per experiment mode
- [ ] ~~Python bridge pattern~~ (not applicable to Flutter)

### 10.5 From Vernier — ADOPT:
- [x] **Simple 6-method public API** → your `HALInterface`: `connect() → configure() → start() → read() → stop() → disconnect()`
- [x] **2D buffer for fast sampling overflow** → ring buffer in your Isolate

### 10.6 Unique digitalLab Differentiators (Not Found in Any Analyzed Project):
- **LTTB downsampling** — None of the 5 projects implement LTTB (Arduino SJ uses min/max zoom tiers instead)
- **Kalman filter in sensor pipeline** — Only openDAQ has comparable DSP, but at SDK level
- **Built-in ESP32 web UI fallback** — phyphox has web remote, but not a standalone fallback UI
- **OTA firmware updates via BLE** — None of the analyzed projects have this
- **Astra Linux support** — Completely unique
- **Integrated lab work instructions** — phyphox has experiment descriptions, but not step-by-step guides
- **PDF report generation** — No analyzed project generates formatted reports

---

## 11. Proposed digitalLab Architecture (Synthesis)

Based on this analysis, the recommended architecture combines the best patterns:

```
┌────────────────────────── Flutter App ──────────────────────────┐
│                                                                  │
│  presentation/                                                   │
│  ├── BLoC per mode (from PSLab instrument isolation)            │
│  │   ├── ConnectionBloc (SensorStatusListener from Arduino SJ)  │
│  │   ├── ExperimentBloc (Experiment→Trial model from Arduino SJ)│
│  │   └── SettingsBloc                                           │
│  ├── pages/ (Табло, График, Таблица, Лаборатория)               │
│  └── widgets/chart/ (LTTB + ZoomTier hybrid rendering)          │
│                                                                  │
│  domain/                                                         │
│  ├── entities/                                                   │
│  │   ├── Experiment → Trial → SensorLayout (from Arduino SJ)   │
│  │   ├── SensorDescriptor (unit, range, scaling from openDAQ)   │
│  │   └── LabWork (JSON definitions like phyphox XML)            │
│  ├── math/ (LTTB, Kalman, approximation — unique)               │
│  └── usecases/ (6-method flow from Vernier simplicity)          │
│                                                                  │
│  data/                                                           │
│  ├── hal/ (SensorProvider+SensorDiscoverer from Arduino SJ)     │
│  │   ├── hal_interface.dart  Stream<SensorPacket>               │
│  │   ├── ble_hal.dart                                           │
│  │   ├── usb_hal.dart                                           │
│  │   └── mock_hal.dart (rate strategies from phyphox)           │
│  ├── datasources/                                                │
│  │   └── local/ Drift (ZoomTier tables from Arduino SJ)         │
│  └── repositories/                                               │
│                                                                  │
│  core/                                                           │
│  ├── Isolate for sensor reading + DSP                           │
│  └── Ring buffer (2D overflow from Vernier)                     │
└──────────────────────────────────────────────────────────────────┘

┌────────────────────────── ESP32-S3 ─────────────────────────────┐
│  SensorPacket protobuf with:                                     │
│  ├── LinearScaling fields (from openDAQ descriptor model)        │
│  ├── CRC32 validation (from reliability analysis)               │
│  └── Sequence numbers (from openDAQ packet model)               │
│                                                                  │
│  NVS: per-sensor calibration (scale + offset)                   │
│  Web UI: standalone fallback (unique, inspired by phyphox web)  │
│  OTA: BLE chunked transfer (unique)                             │
└──────────────────────────────────────────────────────────────────┘
```

---

## Appendix A: Repository Links

| Project | Repository | License |
|---------|-----------|---------|
| phyphox Android | [phyphox/phyphox-android](https://github.com/phyphox/phyphox-android) | GPL-3.0 |
| phyphox iOS | [phyphox/phyphox-ios](https://github.com/phyphox/phyphox-ios) | GPL-3.0 |
| Arduino Science Journal | [arduino/Arduino-Science-Journal-Android](https://github.com/arduino/Arduino-Science-Journal-Android) | Apache-2.0 |
| openDAQ | [openDAQ/openDAQ](https://github.com/openDAQ/openDAQ) | Apache-2.0 |
| PSLab Desktop | [fossasia/pslab-desktop](https://github.com/fossasia/pslab-desktop) | GPL-3.0 |
| Vernier Go Direct | [VernierST/godirect-examples](https://github.com/VernierST/godirect-examples) | BSD-3-Clause |

## Appendix B: Key Files Analyzed

### phyphox-android
- `SensorInput.java` — Core sensor abstraction with RateStrategy enum
- `PhyphoxExperiment.java` — Central experiment state holder
- `DataExport.java` — Multi-format export (CSV/Excel/ZIP)
- `PhyphoxFile.java` — XML parser for `.phyphox` format v1.14

### phyphox-ios (Swift)
- `ExperimentSensorInput.swift` — iOS sensor input with ValueBuffer averaging
- `DataBuffer.swift` — Thread-safe buffer with stateToken (UUID) observer
- `ExperimentExport.swift` — Export with CSV/ZIP support
- `ExperimentGraphView.swift` — Graph rendering from buffers
- `ExperimentWebServer.swift` — Web remote control server

### Arduino Science Journal
- `SensorChoice.java` — Abstract: `createPresenter()` + `createRecorder()`
- `ScalarSensor.java` — Base scalar sensor with ScalarStreamConsumer
- `ZoomRecorder.java` — Multi-tier min/max downsampling
- `SensorRegistry.java` — LinkedHashMap sensor registry
- `SensorProvider.java` — Interface: `buildSensor()` + `buildSensorSpec()`
- `SensorDiscoverer.java` — Interface: `startScanning()` + `getProvider()`
- `RecorderControllerImpl.java` — Central recording controller
- `DataControllerImpl.java` — Thread-separated data controller
- `ExportService.java` — Background export with progress tracking
- `Experiment.java` — Experiment → Trial → SensorLayout hierarchy
- `BluetoothSensor.java` — BLE sensor with GATT flow
- `NativeBleDiscoverer.java` — BLE scanning implementation

### openDAQ
- `InputSignalBase` / `OutputSignalBase` — Signal hierarchy
- `DataPacketImpl` — Packet transport with descriptors
- `DataDescriptorImpl` — Rich metadata (unit, range, scaling, rules)
- `StreamReader` — Abstracted packet reading
- `StreamingManager` — Pub/sub signal management
- `RefChannelImpl` — Reference channel with descriptor builders

### PSLab Desktop
- `bridge.py` — Python subprocess entry point, instrument routing
- `oscilloscope.py` — 4-channel oscilloscope with FFT/XY modes
- `Oscilloscope.js` — React component with ipcRenderer communication
- `preProcessor.js` — JSON data transformation layer
- `Sensors.js` — I2C sensor scanning UI

### Vernier Go Direct
- `gdx.py` — Main wrapper: open/select/start/read/stop/close
- `godirect-sensor-readout.py` — Low-level API example
- JavaScript examples — Event-driven sensor.on('value-changed')
