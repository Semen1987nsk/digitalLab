# Digital Physics Laboratory - AI Coding Agent Instructions

You are assisting with the development of a high-performance Digital Physics Laboratory ("Цифровая Лаборатория") designed for Russian schools. This project consists of a Flutter desktop/mobile application and ESP32-based hardware firmware.

> **Full architecture documentation**: See [ARCHITECTURE.md](../ARCHITECTURE.md)

## Project Architecture & Tech Stack

### Mobile/Desktop Application (Flutter)
- **Framework**: Flutter 3.x (Dart). Target: Astra Linux (priority), Windows, Android.
- **Architecture**: Clean Architecture with layers: `data/` → `domain/` → `presentation/`
  - `data/hal/`: Hardware Abstraction Layer (BLE/USB/Mock). MUST use **Isolates** for data ingestion.
  - `data/datasources/`: Local (Drift/SQLite) and Remote (REST API).
  - `domain/math/`: LTTB downsampling, Kalman filter, approximation, statistics.
  - `presentation/`: BLoC or Riverpod. Dark theme, large touch-friendly controls.
- **Performance Constraints**: 
  - Target: Celeron N4000, 4GB RAM, HDD.
  - **Graphing**: NEVER render raw points. Use **LTTB** to reduce 100K→1K points.
  - **Concurrency**: Sensor reading + DSP in separate **Isolates**.

### Firmware (ESP32-S3)
- **MCU**: ESP32-S3-WROOM-1 (BLE 5.0, USB OTG, PSRAM).
- **Framework**: ESP-IDF 5.x / PlatformIO. BLE via **NimBLE**.
- **Sensors**: INA226 (V/A), BME280 (T/P/H), LSM6DS3 (IMU), MAX31855 (thermocouple), VL53L1X (ToF).
- **Core Assignment**:
  - **Core 0**: Wi-Fi AP, BLE GATT, AsyncWebServer, OTA handler.
  - **Core 1**: Sensor polling (high-freq), ring buffer (PSRAM), DSP (Mahony/Kalman).
- **Protocol**: Protobuf (nanopb) over BLE. NO JSON for sensor streams.
- **Web UI**: Built-in fallback at `192.168.4.1` when app unavailable.

## Critical Developer Workflows

- **Building**: `flutter build linux`, `flutter build apk`, `pio run -e esp32s3`
- **Testing**: `flutter test`, unit tests for `domain/math/`, integration tests for experiment flow.
- **Hardware Simulation**: Use `MockHAL` generating realistic noisy physics data.
- **OTA Updates**: Firmware updates via BLE chunked transfer with CRC32 validation.
- **Offline Mode**: All data persisted in SQLite (Drift). Sync queue for cloud upload.

## Coding Conventions

- **Language**: Code/comments in English. **UI strings strictly in Russian**.
- **UI/UX**: Dark theme default. Large buttons (48dp+). Modes: Табло, График, Таблица, Лаборатория.
- **Errors**: Russian user-friendly messages (e.g., "Проверьте подключение датчика").
- **State**: Strict separation via BLoC/Riverpod. No business logic in widgets.
- **Firmware**: FreeRTOS tasks pinned to cores. Avoid blocking calls on Core 0.

## Key Integration Points

- **HAL Interface**: Uniform `Stream<SensorPacket>` regardless of BLE/USB/Mock transport.
- **Protobuf Schema**: `proto/sensor_data.proto` defines all data structures.
- **Web Fallback**: ESP32 serves SPA from SPIFFS at `192.168.4.1`.
- **Cloud (optional)**: FastAPI backend for AI analysis and teacher dashboard.
- **Regulatory**: Compliance with Russian Order No. 804/838. Target: Реестр российского ПО.

## File Structure Reference

```
lib/                          # Flutter app
├── data/hal/                 # BLE, USB, Mock implementations
├── domain/math/              # LTTB, Kalman, approximation
└── presentation/pages/       # Home, Experiment, LabWorks, Reports

firmware/                     # ESP32-S3
├── src/connectivity/         # BLE, Wi-Fi, WebServer, OTA
├── src/sensors/              # Driver for each sensor chip
└── data/                     # Web UI (SPIFFS)
```
