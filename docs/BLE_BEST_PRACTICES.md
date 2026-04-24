# BLE Sensor Data Streaming — Best Practices Research

> **Source**: 5 production-grade GitHub repositories  
> **Target**: Flutter app ↔ ESP32-S3 multisensor (digitalLab project)  
> **Date**: January 2026

---

## Table of Contents

1. [Connection State Machine Design](#1-connection-state-machine-design)
2. [Reconnection Strategy](#2-reconnection-strategy)
3. [MTU Negotiation](#3-mtu-negotiation)
4. [Packet Framing & Reassembly](#4-packet-framing--reassembly)
5. [Data Throughput Optimization](#5-data-throughput-optimization)
6. [Common Pitfalls](#6-common-pitfalls)
7. [Windows BLE-Specific Issues](#7-windows-ble-specific-issues)
8. [Recommendations for BleHAL](#8-recommendations-for-blehal)

---

## 1. Connection State Machine Design

### 1.1 Polar BLE SDK — 5-State Model

Polar uses a sophisticated 5-state machine for their heart rate / sensor SDK:

```
CLOSED → OPENING → OPEN_PARK → OPEN → CLOSING
                       ↑          │
                       └──────────┘  (link loss → park → re-open)
```

| State | Meaning |
|-------|---------|
| `CLOSED` | No connection, idle |
| `OPENING` | Connection attempt in progress |
| `OPEN_PARK` | Connected but "parked" — waiting for advertisement to confirm the device is back. Used during automatic reconnection |
| `OPEN` | Fully connected, services discovered, notifications enabled |
| `CLOSING` | Graceful disconnect in progress |

**Key insight**: The `OPEN_PARK` state is a "reconnection limbo" — the device was lost but the app still considers it logically connected and monitors for advertisements. This prevents UI thrashing during temporary BLE dropouts.

### 1.2 Nordic Android-BLE-Library — Kotlin Sealed Class States

Nordic uses a sealed-class state machine with disconnect reasons:

```kotlin
sealed class ConnectionState {
    object Connecting : ConnectionState()
    object Initializing : ConnectionState()  // service discovery + setup
    object Ready : ConnectionState()
    object Disconnecting : ConnectionState()
    data class Disconnected(val reason: DisconnectReason) : ConnectionState()
}
```

Disconnect reasons: `SUCCESS`, `UNKNOWN`, `TERMINATE_LOCAL_HOST`, `TERMINATE_PEER_USER`, `LINK_LOSS`, `NOT_SUPPORTED`, `CANCELLED`, `TIMEOUT`.

**Observer interface** (`ConnectionObserver`):
- `onDeviceConnecting(device)`
- `onDeviceConnected(device)`
- `onDeviceFailedToConnect(device, reason)`
- `onDeviceReady(device)`  ← Only after service discovery + characteristic setup
- `onDeviceDisconnecting(device)`
- `onDeviceDisconnected(device, reason)`

**Key insight**: The `Initializing` state between `Connected` and `Ready` is critical — service discovery, MTU negotiation, and CCCD writes all happen here. Nordic adds a **1600ms delay** before service discovery on bonded devices, and 300ms for non-bonded devices, to avoid Android GATT race conditions.

### 1.3 flutter_blue_plus — Simplified 2-State Model

flutter_blue_plus intentionally simplifies to just 2 observable states:

```dart
enum BluetoothConnectionState {
  disconnected,  // 0
  connected,     // 1
  // connecting/disconnecting are deprecated — not reliably streamed by OS
}
```

The `connecting` and `disconnecting` states are **deprecated** because Android and iOS don't actually stream intermediate states through their BLE callbacks — they only fire `STATE_CONNECTED` and `STATE_DISCONNECTED`.

**Key insight**: The library tracks internal state via `mCurrentlyConnectingDevices`, `mConnectedDevices`, and `mAutoConnected` maps, but exposes only 2 states to Dart. This is pragmatic — intermediate states can only be tracked in the Flutter layer, not observed from the OS.

### 1.4 ESP-IDF — Event-Driven Model

ESP-IDF uses a flat event-driven approach (no formal state machine):

```
BLE_GAP_EVENT_CONNECT → BLE_GAP_EVENT_MTU → BLE_GAP_EVENT_SUBSCRIBE → 
  notifications flowing → BLE_GAP_EVENT_DISCONNECT
```

**Key takeaway**: On the firmware side, keep it simple. ESP-IDF fires events; the firmware reacts. No need for a complex state machine on the MCU.

### ✅ Recommendation for digitalLab

Your current `BleHAL` uses `ConnectionStatus { connecting, connected, disconnected, error }`. Consider adding:

```dart
enum ConnectionStatus {
  disconnected,
  connecting,
  initializing,   // ← NEW: discovering services, negotiating MTU
  connected,       // ← rename to "ready" conceptually
  reconnecting,    // ← NEW: distinct from first connect
  error,
}
```

This distinguishes the service-discovery phase (where UI should show "Настройка...") from active reconnection attempts.

---

## 2. Reconnection Strategy

### 2.1 Nordic — Retry with Exponential Delay

Nordic's `ConnectRequest` supports:

```kotlin
connect(device)
    .retry(retryCount = 4, delay = 300)  // 300ms between retries
    .useAutoConnect(false)
    .done { /* ready */ }
    .fail { device, status -> /* failed after all retries */ }
```

**Critical distinctions**:
- **Error 133 (GATT_ERROR)**: Nordic distinguishes *timeout* (~30 seconds, device unreachable) from *error* (packet collision, transient failure) using elapsed time since connection initiation vs a `CONNECTION_TIMEOUT_THRESHOLD` of 20,000ms.
- **Retries only fire on errors**, NOT on timeouts. If a device is simply not in range, retrying is pointless.
- **Auto-connect on link loss**: When `shouldAutoConnect()` returns true and a link-loss event occurs, Nordic automatically calls `gatt.connect()` with `autoConnect=true`, which uses the Android scheduler for background reconnection.

### 2.2 flutter_blue_plus — autoConnect + Manual Reconnection

flutter_blue_plus provides two reconnection mechanisms:

**a) autoConnect parameter:**
```dart
await device.connect(autoConnect: true, mtu: null);
// Returns immediately! Must listen to connectionState for actual connection.
// Incompatible with mtu parameter — must call requestMtu manually after.
```

When `autoConnect` is enabled:
- The device is added to `_autoConnect` set
- On adapter state change (BLE turned ON), all autoConnect devices are re-connected
- On non-Android platforms, disconnection triggers automatic re-connect attempt
- `gatt.close()` is **NOT called** for autoConnect devices on disconnect (would prevent reconnection)

**b) Manual reconnection pattern (recommended by README):**
```dart
device.connectionState.listen((state) async {
    if (state == BluetoothConnectionState.disconnected) {
        print("${device.disconnectReason?.code} ${device.disconnectReason?.description}");
        // Start periodic reconnection timer, or call connect() again
    }
});
```

**c) Android disconnect-gap workaround:**
```dart
// 2000ms minimum gap between connect() and disconnect() on Android
// to prevent "stranded connection" (connection Android doesn't know about)
// See: https://issuetracker.google.com/issues/37121040
```

### 2.3 Polar — Session Park Strategy

Polar uses `OPEN_PARK` state: When a sensor disconnects, the SDK doesn't immediately surface "disconnected" to the UI. Instead it enters a parked state and monitors advertisements. If the device reappears within a timeout, it reconnects transparently.

### 2.4 ESP-IDF — `BLE_ENABLE_CONN_REATTEMPT`

On the firmware side, ESP-IDF has `BLE_ENABLE_CONN_REATTEMPT` config option for automatic reconnection attempts from the peripheral side. However, for a peripheral (sensor), reconnection is typically initiated by the central (app).

### ✅ Recommendation for digitalLab

Your current implementation has a good exponential backoff:

```dart
if (!_disposed && _reconnectAttempts < _maxReconnectAttempts) {
    _reconnectAttempts++;
    final delay = Duration(seconds: 2 * _reconnectAttempts);
    _reconnectTimer = Timer(delay, () { if (!_disposed) connect(); });
}
```

**Improvements to consider**:

1. **Distinguish disconnect reasons**: Check `device.disconnectReason?.code` — a link-loss (timeout) vs explicit disconnect vs error should trigger different behavior
2. **Don't retry on explicit user disconnect** or error 133 timeout (device not in range)
3. **Use autoConnect for long-running sessions**: After initial manual connect, switch to `autoConnect: true` for more resilient background reconnection:
   ```dart
   // After first successful connect + data flowing:
   // If link loss occurs, re-connect with autoConnect
   await device.connect(autoConnect: true, mtu: null);
   ```
4. **Add jitter** to backoff to prevent thundering herd with multiple sensors
5. **Cap backoff at 30 seconds**, not unlimited (current max = 10s which is good)

---

## 3. MTU Negotiation

### 3.1 Ranges & Defaults

| Source | Min MTU | Max MTU | Default | Payload = MTU - 3 |
|--------|---------|---------|---------|-------------------|
| BLE Spec | 23 | 517 | 23 | 20 (!) |
| Nordic Library | 23 | 517 (capped at 515) | 23 | 20 |
| ESP-IDF (Bluedroid) | 23 | 517 (`GATT_MAX_MTU_SIZE`) | 23 | 20 |
| ESP-IDF (NimBLE) | 23 | 512 (`BLE_ATT_MTU_MAX`) | 23 | 509 |
| flutter_blue_plus (Android) | 23 | 512 (requested) | 23 → 512 | 509 |
| flutter_blue_plus (iOS/macOS) | 23 | auto-negotiated | 135–255 typical | — |

### 3.2 flutter_blue_plus MTU Behavior

**Android**: By default, `connect()` requests MTU 512 automatically:
```dart
connect(mtu: 512)  // default parameter
// Internally: after connection, calls requestMtu(512)
```

**iOS/macOS**: MTU is negotiated automatically by the OS. No `requestMtu()` call needed or supported. FBP polls for MTU changes every 25ms:
```objc
// Timer fires every 0.025s to detect MTU changes
self.checkForMtuChangesTimer = [NSTimer scheduledTimerWithTimeInterval:0.025 ...]
```

**Critical race condition** (documented in FBP source):
```
1. You call requestMtu() right after connection
2. Some peripherals automatically send MTU update right after connection
3. Your call confuses the results from step 1 and step 2
4. User calls discoverServices(), thinking requestMtu() finished
5. discoverServices() fails/timeouts because requestMtu is still in progress
```

**Workaround**: FBP adds a `predelay` of 350ms before `requestMtu()`:
```dart
Future<int> requestMtu(int desiredMtu, {double predelay = 0.35}) async {
    await Future.delayed(Duration(milliseconds: (predelay * 1000).toInt()));
    // ... actual request
}
```

### 3.3 ESP-IDF MTU Setup (Firmware Side)

**NimBLE:**
```c
// Set preferred MTU (server side)
ble_att_set_preferred_mtu(BLE_ATT_MTU_MAX);  // typically 512

// When client connects, respond to MTU exchange
case BLE_GAP_EVENT_MTU:
    int mtu = event->mtu.value;
    int payload_max = mtu - 3;
    // Use payload_max for notification size
```

**Bluedroid:**
```c
esp_ble_gatt_set_local_mtu(517);  // GATT_MAX_MTU_SIZE
// After connection:
esp_ble_gattc_send_mtu_req(gattc_if, conn_id);
```

### 3.4 Nordic MTU Details

- `requestMtu()` internally caps at 515: `Math.min(515, mtu)`
- After MTU change, `onMtuChanged()` callback fires
- Maximum notification payload = **MTU - 3** bytes
- **Important**: FBP on Android sets default MTU to 23 immediately on connect, then negotiates up

### ✅ Recommendation for digitalLab

Your current `connect()` call:
```dart
await device.connect(timeout: const Duration(seconds: 10), autoConnect: false);
```
**Missing `mtu` parameter!** This means it uses the default `mtu: 512`, which is good. But verify this works with your ESP32-S3.

**Firmware side checklist**:
1. Call `ble_att_set_preferred_mtu(512)` in NimBLE init
2. Handle `BLE_GAP_EVENT_MTU` to learn the negotiated MTU
3. Cap notification payload at `negotiated_mtu - 3`
4. Your packet is 80 bytes (legacy) or 84 bytes (framed) — well within even the default 20-byte MTU limit? **No!** Default MTU payload = 20 bytes. **You MUST negotiate a larger MTU** for your 80-byte packets to arrive in a single notification.

**Critical issue**: If MTU negotiation fails and stays at 23 (payload=20), your 80-byte packets will be **silently fragmented by the BLE stack** on some platforms, or **truncated** on others. Your `_notifyBuffer` reassembly handles this gracefully, but it's much better to ensure MTU ≥ 84 + 3 = 87.

---

## 4. Packet Framing & Reassembly

### 4.1 Polar BLE SDK — RFC76 Framing Protocol

Polar uses a sophisticated multi-frame protocol with a 1-byte header per packet:

```
Header byte:
  bit 0:     next (more fragments follow)
  bits 1-2:  status (00=error, 01=last frame, 11=more frames)
  bits 4-7:  sequence number (0-15, wraps)
```

- **Multi-frame reassembly**: `BlePsFtpClient` uses a `LinkedBlockingQueue` to accumulate fragments until a "last frame" status is received
- **Timeout**: `PROTOCOL_TIMEOUT_SECONDS` for reassembly — if all fragments don't arrive in time, the partial frame is discarded
- **Flow control**: Every Nth packet (default 5) is sent with `write-with-response` for backpressure

### 4.2 ESP-IDF SPP — Simple Fragment Header

ESP-IDF's SPP (Serial Port Profile) example uses a 4-byte fragment header when MTU < 123:

```c
// Fragment header format:
// byte[0-1] = "##"  (fragment indicator magic bytes)
// byte[2]   = total_packet_count
// byte[3]   = current_packet_number (0-based)
```

When MTU >= 123, data is sent unfragmented. This is a practical threshold that balances overhead vs. fragmentation.

### 4.3 Nordic — PacketSplitter/Merger Pattern

Nordic provides `PacketSplitter` and `PacketMerger` for chunked BLE transfers:

```kotlin
// Splitting data for write
writeCharacteristic(char, data, WRITE_TYPE_NO_RESPONSE)
    .split(PacketSplitter())  // splits into MTU-3 sized chunks
    .done { }

// Merging notifications
enableNotifications(char)
    .merge(PacketMerger())    // reassembles multi-notification messages
    .with { _, data -> process(data) }
```

**Edge case fix**: If the last chunk size equals `maxLength` (MTU-3), a **space byte is appended** to signal "this is the final chunk" — otherwise the merger keeps waiting for more data.

### 4.4 Your Current Implementation — Analysis

Your `BleHAL` already has a robust framing system:

```dart
// Framed packet format (v1.1.0+):
// bytes[0-1] = 0x4C50 ("PL" magic, little-endian)
// byte[2]    = protocol version (1)
// byte[3]    = payload size (80)
// bytes[4-83] = sensor data payload
```

**Strengths**:
- ✅ Magic bytes for synchronization (`0x4C50`)
- ✅ Protocol version field for forward compatibility
- ✅ `_notifyBuffer` for multi-notification reassembly
- ✅ Buffer overflow protection (`_maxNotifyBufferBytes`)
- ✅ Byte-by-byte resynchronization on corruption
- ✅ Backwards compatibility with legacy unframed packets

**Potential improvements**:
- ❌ No CRC/checksum — a corrupted packet that passes `_isLikelyValidPacket()` range checks will slip through
- ❌ No sequence numbers — can't detect dropped packets
- ❌ `_notifyBuffer` uses `List<int>` (boxed integers) — could use `Uint8List` for better memory efficiency

### ✅ Recommendation for digitalLab

1. **Add a CRC8 or CRC16** to the frame header. CRC8 adds 1 byte overhead, CRC16 adds 2 bytes. For 80-byte payload, CRC16 is worth the investment:
   ```
   [magic:2][version:1][size:1][crc16:2][payload:80] = 86 bytes total
   ```

2. **Add a sequence counter** (1 byte, wraps 0-255). This lets you detect dropped packets:
   ```dart
   if (seq != (_lastSeq + 1) & 0xFF) {
     debugPrint('BLE HAL: Пропущены пакеты: $_lastSeq → $seq');
     _droppedPacketCount += (seq - _lastSeq - 1) & 0xFF;
   }
   ```

3. **Use `Uint8List` for the buffer**:
   ```dart
   // Instead of List<int> _notifyBuffer
   final _notifyBuffer = BytesBuilder(copy: false);
   ```

---

## 5. Data Throughput Optimization

### 5.1 Theoretical & Measured Throughput

| Stack | Direction | MTU | Conn Interval | Measured Throughput |
|-------|-----------|-----|---------------|---------------------|
| ESP-IDF NimBLE | Notify | 512 | 7.5ms | ~340 Kbps |
| ESP-IDF Bluedroid | Notify | 517 | 7.5ms | ~650-700 Kbps |
| Nordic (Android) | Notify | 512 | 7.5-15ms | ~200-400 Kbps (typical) |

**Note**: NimBLE's lower throughput vs Bluedroid is a known tradeoff for its smaller memory footprint and faster BLE stack initialization.

### 5.2 Connection Parameters for Maximum Throughput

From ESP-IDF throughput examples:

```c
// Optimal connection parameters for high throughput:
struct ble_gap_upd_params params = {
    .itvl_min = 6,            // 6 × 1.25ms = 7.5ms (BLE minimum)
    .itvl_max = 6,            // same — fixed interval
    .latency = 0,             // no skipped events
    .supervision_timeout = 500, // 500 × 10ms = 5 seconds
};
```

From Nordic:
```kotlin
// Request high priority connection (Android 6+):
// interval = 11.25-15ms (or 7.5-10ms on some devices)
requestConnectionPriority(CONNECTION_PRIORITY_HIGH)

// After data transfer complete, switch back:
requestConnectionPriority(CONNECTION_PRIORITY_BALANCED)  // interval = 30-50ms
```

### 5.3 Notification Flow Control (ESP-IDF)

ESP-IDF's throughput example uses a **counting semaphore** for notification flow control:

```c
// Before sending notification:
if (os_msys_num_free() >= MIN_REQUIRED_MBUF) {
    rc = ble_gatts_notify_custom(conn_handle, attr_handle, om);
    if (rc == BLE_HS_ENOMEM) {  // rc=6: mbuf exhaustion
        vTaskDelay(pdMS_TO_TICKS(10));  // back off 10ms
    }
} else {
    vTaskDelay(pdMS_TO_TICKS(10));  // wait for mbufs to free up
}
```

For Bluedroid:
```c
// Burst sending pattern:
int packets = esp_ble_get_cur_sendable_packets_num(conn_id);
for (int i = 0; i < packets; i++) {
    esp_ble_gatts_send_indicate(gatts_if, conn_id, attr_handle, len, data, false);
}
if (packets == 0) {
    vTaskDelay(pdMS_TO_TICKS(10));  // prevent CPU starvation
}
```

### 5.4 Throughput Estimation for digitalLab

Your sensor packet is 80 bytes (legacy) or 84 bytes (framed). At various sample rates:

| Sample Rate | Data Rate | BLE Throughput Needed | Feasibility (NimBLE 340Kbps) |
|-------------|-----------|----------------------|------------------------------|
| 10 Hz | 6.7 Kbps | 0.8 KB/s | ✅ Trivial |
| 100 Hz | 67 Kbps | 8.4 KB/s | ✅ Easy |
| 500 Hz | 336 Kbps | 42 KB/s | ⚠️ Near limit |
| 1000 Hz | 672 Kbps | 84 KB/s | ❌ Exceeds NimBLE |

### ✅ Recommendation for digitalLab

1. **At 10-100 Hz**: No optimization needed. Current implementation is fine.
2. **At 500+ Hz**: 
   - Request `CONNECTION_PRIORITY_HIGH` from Flutter side
   - Use NimBLE's burst notification pattern on firmware
   - Consider **compressing** packets: only send fields with `valid_flags` set, not all 80 bytes
   - Consider **delta encoding**: send only changed values since last packet
3. **On firmware**: Always check `os_msys_num_free()` before sending notifications. Add 10ms delay on mbuf exhaustion.
4. **On Flutter side**: Use `requestConnectionPriority(ConnectionPriority.high)` during measurement, `balanced` when idle:
   ```dart
   await device.requestConnectionPriority(
       connectionPriorityRequest: ConnectionPriority.high);
   ```

---

## 6. Common Pitfalls

### 6.1 Android-Specific

| Pitfall | Source | Solution |
|---------|--------|----------|
| **Error 133 (GATT_ERROR)** | Nordic | Distinguish timeout (>20s elapsed) from transient error. Only retry on transient errors. |
| **Samsung S8 + Android 9 + PHY LE 2M** | Nordic | Device fails to reconnect when PHY LE 2M is requested. Workaround: disable LE 2M on peripheral side. |
| **Service discovery race condition** | Nordic | Add **1600ms delay** before `discoverServices()` on bonded devices, 300ms on non-bonded. |
| **Connect/disconnect race condition** | flutter_blue_plus | Enforce **2000ms minimum gap** between connect and disconnect calls. FBP does this internally. |
| **autoConnect disconnect loop** | flutter_blue_plus (v1.31.17) | Calling `disconnect()` should always disable autoConnect, even if already disconnected. Bug was fixed. |
| **MTU not cleared on engine detach** | flutter_blue_plus (v1.12.3) | `mConnectionState` and `mMtu` must be cleared in `onDetachedFromEngine`. |
| **Unexpected connection events** | flutter_blue_plus | Android can fire `STATE_CONNECTED` for devices the app didn't request. FBP handles this by immediately disconnecting + closing unknown connections. |
| **gatt.close() is critical** | flutter_blue_plus | Must call `gatt.close()` after disconnect, otherwise BLE resources are exhausted and new connections fail. Exception: autoConnect devices. |

### 6.2 iOS/macOS-Specific

| Pitfall | Source | Solution |
|---------|--------|----------|
| **MTU 3 bytes too small** | flutter_blue_plus (v1.12.7) | Historical bug in original flutter_blue — iOS reported MTU 3 bytes smaller than actual. Fixed. |
| **No `didDisconnectPeripheral` on BLE off** | flutter_blue_plus | iOS does NOT call disconnect callback when Bluetooth adapter is turned off. Must clear all state manually on `adapterTurnOff`. |
| **No `requestMtu()` API** | flutter_blue_plus | iOS negotiates MTU automatically. `requestMtu()` throws `android-only` error. |
| **`kCBConnectOptionEnableAutoReconnect`** | flutter_blue_plus (v1.30.4) | Must explicitly set this iOS option for auto-reconnect behavior. |

### 6.3 Firmware-Specific (ESP32)

| Pitfall | Source | Solution |
|---------|--------|----------|
| **mbuf exhaustion (rc=6)** | ESP-IDF | Check `os_msys_num_free() >= 2` before sending. On exhaustion, delay 10ms. |
| **Notify data > MTU** | ESP-IDF | "the size of notify_data[] need less than MTU size." Always cap at `negotiated_mtu - 3`. |
| **CPU starvation** | ESP-IDF | Always add `vTaskDelay(10ms)` when no sendable buffers are available. Without this, the notification loop starves other FreeRTOS tasks. |
| **Notification caching timeout** | ESP-IDF | Default `GATTC_NOTIF_TIMEOUT = 3` seconds. If app doesn't process notifications fast enough, they're dropped. |
| **Indicate vs Notify** | ESP-IDF | Indicate requires ACK (reliable but slow). Notify is fire-and-forget (fast but lossy). For sensor streaming, always use Notify. |

### 6.4 Cross-Platform

| Pitfall | Source | Solution |
|---------|--------|----------|
| **Must re-discover services after reconnect** | flutter_blue_plus | Services are invalidated on disconnect. Always call `discoverServices()` after each reconnection. |
| **Characteristic storage leak** | Adafruit | Always call `deinit()` or equivalent cleanup when disconnecting to prevent memory leaks. |
| **JSON over BLE limited to 512 bytes** | Adafruit | Don't use JSON for sensor streaming. Use binary protocols (your flat-struct approach is correct). |
| **Default max_length = 20 bytes** | Adafruit | The legacy BLE 4.x ATT payload is 20 bytes. Always negotiate a larger MTU for packets > 20 bytes. |

### ✅ Key Pitfalls Affecting Your BleHAL

1. **Services rediscovery**: Your `connect()` calls `_discoverServices()` on every connection, which is correct ✅
2. **gatt.close()**: Handled by flutter_blue_plus internally ✅
3. **MTU for 80-byte packets**: Your packets WILL be fragmented at default MTU. The `_notifyBuffer` handles reassembly, but you should **explicitly verify MTU ≥ 87** after negotiation.
4. **Missing `requestConnectionPriority`**: Not called anywhere in your code. Add it before starting measurement.

---

## 7. Windows BLE-Specific Issues

### 7.1 Known Windows BLE Limitations

Windows BLE support is the **weakest** of all platforms. Key issues from flutter_blue_plus:

| Issue | Detail |
|-------|--------|
| **requestMtu** | `requestMtu` is listed as **Android-only** in the API reference table. Windows support is not documented. |
| **connectionPriority** | Not available on Windows. Only Android supports `requestConnectionPriority`. |
| **PHY support** | Windows BLE API does not expose PHY selection (LE 1M/2M/Coded). |
| **Bonding** | Windows BLE bonding behavior differs from Android/iOS. May require OS-level pairing. |
| **Adapter state** | Windows adapter state detection may be less reliable than Android/iOS. |
| **readRssi** | Listed as ❌ for Windows in the flutter_blue_plus API table. |
| **mtu stream** | Listed as ❌ for Windows in the flutter_blue_plus API table. |

### 7.2 flutter_blue_plus Windows API Support

From the README API reference table:

| API | Android | iOS | macOS | Windows | Web |
|-----|---------|-----|-------|---------|-----|
| `requestMtu` | ✅ | ❌ | ❌ | ❌ | ❌ |
| `mtu` (stream) | ✅ | ✅ | ❌ | ✅ | ❌ |
| `mtuNow` | ✅ | ✅ | ❌ | ✅ | ❌ |
| `readRssi` | ✅ | ✅ | ✅ | ✅ | ❌ |
| `requestConnectionPriority` | ✅ | ❌ | ❌ | ❌ | ❌ |
| `onServicesReset` | ✅ | ✅ | ✅ | ✅ | ❌ |

### 7.3 Windows BLE Stack Behavior

- Windows uses the **WinRT Bluetooth API** which automatically negotiates MTU
- MTU values on Windows are typically 23-251 depending on the adapter and peripheral
- Windows may silently **fragment** notifications larger than MTU-3 without notifying the app
- Some USB BLE adapters on Windows (common in school PCs) have poor BLE 5.0 support

### ✅ Recommendation for digitalLab (Astra Linux / Windows)

1. **Astra Linux**: Uses BlueZ stack (Linux). flutter_blue_plus Linux support is via BlueZ D-Bus. Generally reliable but test thoroughly.
2. **Windows (Celeron N4000 target)**: 
   - Cannot call `requestMtu()` — MTU negotiation is automatic
   - Cannot call `requestConnectionPriority()` — connection parameters are OS-controlled
   - Must handle potentially low MTU (23-251) gracefully → your `_notifyBuffer` reassembly is critical here
   - Test with common school USB BLE dongles (CSR8510, Broadcom BCM20702, Realtek RTL8761B)
3. **Cross-platform MTU handling**:
   ```dart
   // After connection:
   if (Platform.isAndroid) {
     await device.requestMtu(512);
   }
   // On all platforms, listen to MTU stream:
   device.mtu.listen((mtu) {
     debugPrint('Negotiated MTU: $mtu, max payload: ${mtu - 3}');
     // Inform firmware of max packet size if needed
   });
   ```

---

## 8. Recommendations for BleHAL

### 8.1 Priority Improvements

Based on all research, here are the top improvements for your existing `BleHAL`:

#### P0 — Critical

1. **Add MTU awareness**: After connect, read the negotiated MTU. If MTU-3 < 84 (your framed packet size), log a warning and consider requesting a larger MTU on Android:
   ```dart
   final mtu = device.mtuNow;
   if (mtu - 3 < _framedPacketSize) {
     debugPrint('BLE HAL: ⚠️ MTU $mtu слишком мал для пакета $_framedPacketSize');
     if (Platform.isAndroid) {
       await device.requestMtu(512);
     }
   }
   ```

2. **Add CRC to framed packets**: Your `_isLikelyValidPacket` range-check is good but insufficient. A CRC16 catches bit-flip corruption that range checks miss.

#### P1 — Important

3. **Distinguish disconnect reasons**: Use `device.disconnectReason` to decide reconnection strategy:
   ```dart
   device.connectionState.listen((state) {
     if (state == BluetoothConnectionState.disconnected) {
       final reason = _device?.disconnectReason;
       if (reason?.code == 0x08) { // CONNECTION_TIMEOUT / link loss
         _scheduleReconnect(aggressive: true);
       } else if (reason?.code == 0x13) { // REMOTE_USER_TERMINATED
         _scheduleReconnect(aggressive: false);
       } else {
         // Unknown error — cautious reconnect
         _scheduleReconnect(aggressive: false);
       }
     }
   });
   ```

4. **Request CONNECTION_PRIORITY_HIGH during measurement**:
   ```dart
   Future<void> startMeasurement() async {
     if (Platform.isAndroid) {
       await _device?.requestConnectionPriority(
         connectionPriorityRequest: ConnectionPriority.high);
     }
     await _sendCommand(BleCommand.start);
   }
   
   Future<void> stopMeasurement() async {
     await _sendCommand(BleCommand.stop);
     if (Platform.isAndroid) {
       await _device?.requestConnectionPriority(
         connectionPriorityRequest: ConnectionPriority.balanced);
     }
   }
   ```

5. **Add cancelWhenDisconnected for subscriptions**:
   ```dart
   // flutter_blue_plus provides automatic cleanup:
   device.cancelWhenDisconnected(_dataSub!, delayed: true, next: false);
   ```

#### P2 — Nice to Have

6. **Add sequence numbers to packets** for dropped-packet detection
7. **Use `BytesBuilder`** instead of `List<int>` for `_notifyBuffer`
8. **Add a "park" state** for brief disconnections (suppress UI flicker for disconnections < 3 seconds)
9. **Firmware: check `os_msys_num_free()`** before every notification send
10. **Firmware: set optimal connection parameters**:
    ```c
    // In ble_server.cpp after connection:
    struct ble_gap_upd_params params = {
        .itvl_min = 6,   // 7.5ms
        .itvl_max = 24,  // 30ms (balance between throughput and power)
        .latency = 0,
        .supervision_timeout = 400,  // 4 seconds
    };
    ble_gap_update_params(conn_handle, &params);
    ```

### 8.2 Architecture Summary

```
┌─────────────────────────────────────────────────────┐
│                  Flutter App (BleHAL)                │
├─────────────────────────────────────────────────────┤
│                                                     │
│  ┌─────────────┐    ┌──────────────┐                │
│  │ State Machine│    │ MTU Manager  │                │
│  │             │    │              │                │
│  │ disconnected│    │ negotiate()  │                │
│  │ connecting  │    │ mtuNow → int │                │
│  │ initializing│    │ validate()   │                │
│  │ connected   │    └──────────────┘                │
│  │ reconnecting│                                    │
│  │ error       │    ┌──────────────┐                │
│  └─────────────┘    │ Packet Parser│                │
│                     │              │                │
│  ┌─────────────┐    │ buffer       │                │
│  │ Reconnector │    │ resync       │                │
│  │             │    │ CRC verify   │                │
│  │ exp.backoff │    │ seq check    │                │
│  │ reason-aware│    └──────────────┘                │
│  │ jitter      │                                    │
│  │ park state  │    ┌──────────────┐                │
│  └─────────────┘    │ Watchdog     │                │
│                     │              │                │
│                     │ data stall   │                │
│                     │ soft recover │                │
│                     └──────────────┘                │
└──────────────────────────┬──────────────────────────┘
                           │ BLE 5.0 (Notify)
                           │ MTU 512, payload 509
                           │ Conn interval 7.5-30ms
┌──────────────────────────┴──────────────────────────┐
│              ESP32-S3 Firmware (NimBLE)              │
├─────────────────────────────────────────────────────┤
│                                                     │
│  ┌─────────────┐    ┌──────────────┐                │
│  │ GATT Server │    │ Notification │                │
│  │             │    │ Sender       │                │
│  │ MTU handler │    │              │                │
│  │ Subscribe   │    │ mbuf check   │                │
│  │ handler     │    │ burst send   │                │
│  └─────────────┘    │ backoff      │                │
│                     └──────────────┘                │
│  ┌─────────────┐                                    │
│  │ Conn Params │                                    │
│  │             │                                    │
│  │ itvl: 7.5ms│                                    │
│  │ latency: 0 │                                    │
│  │ timeout: 4s│                                    │
│  └─────────────┘                                    │
└─────────────────────────────────────────────────────┘
```

---

## Sources

| Repository | Stars | Key Contribution |
|-----------|-------|-----------------|
| [chipweinberger/flutter_blue_plus](https://github.com/chipweinberger/flutter_blue_plus) | 700+ | Dart BLE API, autoConnect, MTU, disconnect reasons, Windows support |
| [polarofficial/polar-ble-sdk](https://github.com/polarofficial/polar-ble-sdk) | 500+ | 5-state connection model, RFC76 framing, flow control |
| [NordicSemiconductor/Android-BLE-Library](https://github.com/NordicSemiconductor/Android-BLE-Library) | 1900+ | Retry logic, error 133 handling, MTU details, PacketSplitter |
| [adafruit/Adafruit_CircuitPython_BLE](https://github.com/adafruit/Adafruit_CircuitPython_BLE) | 100+ | Characteristic patterns, PacketBuffer, UART service |
| [espressif/esp-idf](https://github.com/espressif/esp-idf) | 12000+ | NimBLE internals, throughput benchmarks, mbuf management |
