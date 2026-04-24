# Sprint 2 — Завершённые задачи

> **Дата**: Июль 2026  
> **Результат**: `flutter analyze` — 0 ошибок, 0 предупреждений | `flutter test` — 151/151 ✅

---

## C1. CRITICAL — Реальные I2C/SPI драйверы датчиков (прошивка ESP32)

**Проблема**: `taskSensorPolling()` генерировал **fake данные** через `random()`. Прошивка не взаимодействовала с реальным железом.

**Решение**: Создана полноценная система драйверов датчиков.

### Новый файл: `firmware/src/sensors/sensor_drivers.h` (~450 строк)

5 production-ready драйверов, каждый с:
- `begin()` — инициализация + проверка Chip ID / WHO_AM_I
- `read()` — чтение данных, возвращает структуру с `.valid`
- `available()` — доступен ли датчик

| Класс | Датчик | Интерфейс | Данные | Особенности |
|-------|--------|-----------|--------|-------------|
| `BME280Driver` | BME280 (0x76) | I2C | T/P/H | Полные алгоритмы компенсации Bosch, forced mode |
| `INA226Driver` | INA226 (0x40) | I2C | V/A/W | Калибровочный регистр, 16-sample averaging |
| `LSM6DS3Driver` | LSM6DS3 (0x6A) | I2C | 6-axis IMU | ±2g / ±500 dps, 104 Hz ODR |
| `VL53L1XDriver` | VL53L1X (0x29) | I2C | ToF laser | Short-range mode, continuous ranging |
| `MAX31855Driver` | MAX31855 | SPI | Thermocouple | 32-bit read, fault detection |

### Изменения в `firmware/src/main.cpp`

1. **`initSensors()`** — полная переработка:
   - I2C bus scan (как раньше) + вызов `begin()` на каждом драйвере
   - Каждый датчик проверяется независимо → прошивка работает с любым подмножеством
   - MAX31855 инициализируется отдельно (SPI шина)
   - Чёткий лог: `[OK] BME280 initialized` или `[--] BME280 not found`

2. **`taskSensorPolling()`** — fake `random()` заменён на реальные вызовы:
   - BME280 → `temperature_c`, `pressure_pa`, `humidity_pct`
   - INA226 → `voltage_v`, `current_a`, `power_w`
   - LSM6DS3 → `accel_x/y/z`, `gyro_x/y/z`
   - VL53L1X → `distance_mm`
   - MAX31855 → `thermocouple_c` (вне I2C mutex — SPI)
   - Каждое чтение проверяется через `.valid` + `setValid(FIELD_*)`

3. **`updateBleStatusCharacteristics()`** — `enabledMask` теперь **динамический**:
   - Ранее: хардкод `DISTANCE | TEMPERATURE | ACCEL_XYZ`
   - Теперь: проверяет `g_*.available()` для каждого датчика
   - Flutter-приложение знает, какие датчики реально подключены

4. **Debug output** — расширен до V/A/T/P/d/az для полного мониторинга

---

## M2. Удалён мёртвый код `usb_hal.dart`

**Проблема**: `lib/data/hal/usb_hal.dart` (242 строки) — старый Android USB HAL через пакет `usb_serial`. На Windows не работает (используется `usb_hal_windows.dart` через `flutter_libserialport`). Импортировался в `experiment_provider.dart`, но никогда не инстанцировался на десктопе.

**Решение**:
1. **Удалён** файл `lib/data/hal/usb_hal.dart`
2. **Удалён** пакет `usb_serial: ^0.5.0` из `pubspec.yaml`
3. **Обновлён** `experiment_provider.dart`:
   - Убран `import usb_hal.dart`
   - Fallback для мобильных платформ: `MockHAL()` с информативным логом вместо `UsbHAL()`

---

## M5. Автосохранение в SQLite (Drift)

**Проблема**: Все данные эксперимента только в RAM (`CircularSampleBuffer`). При краше приложения / потере питания — **потеря всех данных**.

**Решение**: Полная реализация Drift ORM с автосохранением.

### Новые файлы:

#### `lib/data/datasources/local/app_database.dart`
- **Таблица `Experiments`**: id, startTime, endTime, sampleRateHz, status (running/completed/interrupted), title, measurementCount
- **Таблица `Measurements`**: id, experimentId (FK), timestampMs, 13 nullable полей (все поля SensorPacket)
- **Unique constraint**: `(experimentId, timestampMs)` — защита от дублей
- **TypeConverter**: `ExperimentStatusConverter` для enum ↔ int
- **CRUD**: `createExperiment`, `completeExperiment`, `markInterruptedExperiments`, `deleteExperiment`, `insertMeasurements` (batch), `measurementsFor`, `measurementCountFor`
- **Тестируемость**: конструктор `AppDatabase.forTesting(e)` для in-memory БД

#### `lib/data/datasources/local/experiment_autosave_service.dart`
- **`beginSession()`** — INSERT experiment (status=running), запуск Timer(30s)
- **`addPacket()`** — буферизация в RAM-очередь (O(1))
- **`flush()`** — batch INSERT в БД (каждые 30 секунд по таймеру)
- **`endSession()`** — финальный flush + UPDATE status=completed
- **`recoverInterrupted()`** — восстановление данных прерванного эксперимента

#### `lib/core/di/providers.dart`
- **`appDatabaseProvider`** — singleton AppDatabase
- **`autosaveServiceProvider`** — привязан к AppDatabase

### Интеграция в ExperimentController:
- `start()` → `autosave.beginSession()` (создание записи в БД)
- Каждый пакет → `autosave.addPacket()` (буферизация)
- `stop()` → `autosave.endSession()` (финальный flush)
- При краше: данные уже в SQLite, при следующем запуске — `markInterruptedExperiments()`

### Инициализация в `main.dart`:
- При старте приложения: `db.markInterruptedExperiments()` — помечает незавершённые сессии

---

## Валидация

| Проверка | Результат |
|----------|-----------|
| `flutter analyze` | 0 ошибок, 0 предупреждений, 23 info |
| `flutter test` | **151/151 passed** ✅ |
| `build_runner` | 93 outputs generated (Drift codegen) |
| Dead imports | 0 (verified via grep) |
| Dead packages | `usb_serial` removed |

---

## Файлы изменённые/созданные

| Файл | Действие | Строк |
|------|----------|-------|
| `firmware/src/sensors/sensor_drivers.h` | **СОЗДАН** | ~450 |
| `firmware/src/main.cpp` | Изменён | ~680 |
| `lib/data/datasources/local/app_database.dart` | **СОЗДАН** | ~220 |
| `lib/data/datasources/local/app_database.g.dart` | **Сгенерирован** (Drift) | ~1800 |
| `lib/data/datasources/local/experiment_autosave_service.dart` | **СОЗДАН** | ~200 |
| `lib/core/di/providers.dart` | **СОЗДАН** | ~25 |
| `lib/presentation/blocs/experiment/experiment_provider.dart` | Изменён | ~710 |
| `lib/main.dart` | Изменён | ~140 |
| `lib/data/hal/usb_hal.dart` | **УДАЛЁН** | -242 |
| `pubspec.yaml` | Изменён (убран usb_serial) | 58 |

---

## Что осталось на Sprint 3

1. **Тесты для Drift** — unit-тесты AppDatabase с in-memory БД
2. **UI восстановления** — диалог «Восстановить прерванный эксперимент?»
3. **История экспериментов** — страница просмотра/экспорта сохранённых данных
4. **OTA firmware update** — BLE chunked transfer с CRC32
5. **Web UI** — реализация fallback SPA на ESP32 (SPIFFS)
