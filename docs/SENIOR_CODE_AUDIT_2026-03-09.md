# Сеньер-Аудит Кодовой Базы — Лабосфера

> **Дата**: 9 марта 2026  
> **Scope**: Flutter app (~15K LOC) + ESP32 firmware (~3K LOC)  
> **Тесты**: 202/202 ✅ | Анализатор: 0 issues ✅  
> **Методология**: Построчный обзор → автоматический анализ → верификация гипотез (3x anti-hypothesis check)

---

## Итоговая оценка

| Категория | Оценка | Комментарий |
|-----------|--------|-------------|
| **Архитектура** | ⭐⭐⭐⭐⭐ 9/10 | Clean Architecture, HAL паттерн, Composite (SensorHub) — на уровне Vernier/PASCO |
| **Надёжность** | ⭐⭐⭐⭐ 7/10 | Хорошая обработка ошибок, но есть race conditions при dispose и silent data loss |
| **Производительность** | ⭐⭐⭐⭐⭐ 9/10 | LTTB, CircularBuffer O(1), оконный снэпшот, адаптивный FPS — отлично |
| **Безопасность прошивки** | ⭐⭐⭐ 6/10 | I2C без проверки ошибок, CSV export OOM, нет Secure Boot/OTA |
| **Тестирование** | ⭐⭐⭐⭐ 8/10 | 202 теста, покрыты math, HAL, autosave, widget. Нет integration-тестов |
| **Code Quality** | ⭐⭐⭐⭐⭐ 9/10 | Чистый код, хорошие комментарии, defensive programming |

---

## Часть 1: Применённые Исправления (7 фиксов)

### ✅ FIX-1: SH-1 — ConcurrentModificationError в SensorHub

**Файл**: `lib/data/hal/sensor_hub.dart`  
**Severity**: 🔴 HIGH  

**Проблема**: `startMeasurement()`, `stopMeasurement()`, `calibrate()`, `setSampleRate()` итерировали `_devices` напрямую через `for (final device in _devices)`. При каждом `await` event loop мог исполнить callback hot-plug таймера, который вызывал `addDevice()`/`removeDevice()` → мутация списка во время итерации → `ConcurrentModificationError` → краш.

**Исправление**: Добавлен паттерн snapshot (`List<HubDevice>.of(_devices)`) перед итерацией + `_disposed` break guard — тот же подход, что уже был в `connect()`.

### ✅ FIX-2: SH-2 — Краш при dispose() SensorHub

**Файл**: `lib/data/hal/sensor_hub.dart`  
**Severity**: 🔴 CRITICAL  

**Проблема**: `dispose()` устанавливал `_disposed = true`, отменял таймеры, и **сразу** закрывал `_statusController` / `_dataController`. Если `_refreshTopology()` была в процессе (ожидала `await scanPorts()`), она возобновлялась после закрытия контроллеров и вызывала `_statusController.add()` → `StateError: Cannot add event after closing` → краш.

**Исправление**: Добавлено ожидание `_scanInProgress` (до 6с, тот же паттерн что в `disconnect()`) перед закрытием stream controllers.

### ✅ FIX-3: BLE-1 — Нежелательное переподключение BLE после disconnect

**Файл**: `lib/data/hal/ble_hal.dart`  
**Severity**: 🔴 HIGH  

**Проблема**: При потере BLE-соединения `_connectionSub` планировал `_reconnectTimer`. Если пользователь нажимал «Отключить», `disconnect()` НЕ отменял `_reconnectTimer`. Таймер срабатывал → BLE переподключался вопреки намерению пользователя.

**Исправление**: `_reconnectTimer?.cancel(); _reconnectTimer = null;` в начале `disconnect()`.

### ✅ FIX-4: Database Safety — Краш на заблокированных школьных ПК

**Файл**: `lib/data/datasources/local/app_database.dart`  
**Severity**: 🔴 CRITICAL  

**Проблема**: `_openConnection()` вызывал `getApplicationSupportDirectory()` без try/catch. На школьных ПК с GPO-ограничениями, повреждённым профилем или отсутствующим AppData это выбрасывало исключение → `appDatabaseProvider` навсегда сломан → автосохранение мертво → весь эксперимент потерян при краше.

**Исправление**: Трёхуровневый fallback:
1. AppData (стандартно)
2. `Directory.systemTemp` (если AppData недоступен)
3. In-memory БД (данные не сохранятся, но приложение не упадёт)

### ✅ FIX-5: Autosave Data Loss — Потеря данных при завершении эксперимента

**Файл**: `lib/data/datasources/local/experiment_autosave_service.dart`  
**Severity**: 🔴 HIGH  

**Проблема**: `endSession()` вызывал `flush()`, затем `_pendingPackets.clear()`. Если `flush()` падал (БД залочена, диск полон), пакеты возвращались в `_pendingPackets` внутри `flush()`, но затем `clear()` стирал их навсегда. Также `completeExperiment()` не был в try/catch — ошибка БД крашила весь flow.

**Исправление**: 
- Повторная попытка flush после 500мс паузы
- Предупреждение в лог если данные всё ещё не сохранены
- `completeExperiment()` обёрнут в try/catch

### ✅ FIX-6: EP-1 — Дублирование подписок в ExperimentController

**Файл**: `lib/presentation/blocs/experiment/experiment_provider.dart`  
**Severity**: 🟡 MEDIUM  

**Проблема**: `start()` не имел guard от повторного вызова. Если UI дважды вызывал `start()` до завершения первого (через `await` gap), создавалась вторая подписка на `sensorData` → данные дублировались в буфере, первая подписка становилась orphan (unreferenced, uncancellable).

**Исправление**: Добавлен `_isStarting` boolean guard с `try/finally` обёрткой.

### ✅ FIX-7: Статический анализ — 16 → 0 issues

**Файлы**: `home_page.dart`, `port_selection_page.dart`, `stopped_review_widgets.dart`, тесты  
**Severity**: ℹ️ INFO  

Все 16 `prefer_const_constructors` исправлены. `flutter analyze` → 0 issues.

---

## Часть 2: Аудит CRC8 и Бинарного Протокола

### ✅ CRC8 Consistency — Все реализации идентичны

| Свойство | Прошивка (C) | Dart (shared) | USB HAL | Data Isolate |
|----------|--------------|---------------|---------|--------------|
| Полином | 0x8C (reflected 0x31) | 0x8C | 0x8C | 0x8C |
| Init | 0x00 | 0x00 | 0x00 | 0x00 |
| Алгоритм | Bitwise LSB-first | Bitwise LSB-first | Bitwise LSB-first | Bitwise LSB-first |

### ✅ Binary Packet Layout — Совпадает

| Firmware struct (80 байт) | Flutter parser offsets |
|---|---|
| `timestamp_ms` @ 0 | `getUint32(0)` ✅ |
| `distance_mm` @ 4 | `getFloat32(4)` ✅ |
| `voltage_v` @ 8 | `getFloat32(8)` ✅ |
| `valid_flags` @ 76 | `getUint32(76)` ✅ |

Framed packet: magic `0x4C50`, proto v1, payload 80B, total 84B — совпадает.

### ⚠️ Замечание: 3 дублирующиеся реализации CRC8

`usb_hal_windows.dart` и `data_isolate.dart` имеют собственные приватные `_computeCRC8()`, идентичные `crc8.dart`. Рекомендуется вынести в единый import для облегчения поддержки.

---

## Часть 3: Thread Safety & Concurrency

### Исправлены (FIX-1, FIX-2, FIX-3, FIX-6):
- SH-1: ConcurrentModificationError → snapshot pattern
- SH-2: dispose() crash → scan wait
- BLE-1: unwanted reconnect → timer cancel
- EP-1: start() re-entrancy → boolean guard

### Остаточные (LOW-MEDIUM, мониторить):

| ID | Файл | Описание | Severity |
|----|------|----------|----------|
| SH-5 | sensor_hub.dart | `dispose()` во время `connect()` → orphan connections | MEDIUM |
| USB-1 | usb_hal_windows.dart | Timeout handler vs `_connectInternal()` → zombie connection | MEDIUM |
| USB-2 | usb_hal_windows.dart | `_isDisconnecting` force-reset → potential double port open | MEDIUM |
| DI-2 | data_isolate.dart | Нет `Isolate.addOnExitListener` → silent data loss on crash | MEDIUM |
| BLE-3 | ble_hal.dart | `_isolateSub` не отменяется при reconnect | LOW |
| BLE-5 | ble_hal.dart | `_notifyBuffer` — dead code | LOW |
| DI-1 | data_isolate.dart | `stop()` kills Isolate before `_StopCommand` processed | LOW |

---

## Часть 4: Error Handling & Resilience

### Исправлены (FIX-4, FIX-5):
- Database open crash → 3-level fallback
- Autosave data loss → retry + warning

### Остаточные:

| ID | Описание | Severity | Воздействие на пользователя |
|----|----------|----------|----------------------------|
| **B6** | BLE data stall recovery без retry loop → permanent freeze | HIGH | График замирает, нет сообщения об ошибке |
| **B8** | Несовместимая прошивка → generic error, нет русского сообщения | HIGH | Учитель не понимает что обновить прошивку |
| **E1** | `beginSession()` failure → 30 мин без автосохранения, нет UI-индикатора | HIGH | Данные потеряны при краше |
| **P1** | `reg query` заблокирован GPO → 0 устройств найдено, нет объяснения | HIGH | «USB-датчики не найдены» на рабочем ПК |
| **D2** | Autosave overflow дропает данные молча | MEDIUM | Потеря данных без уведомления |
| **B5** | После 10 BLE reconnect attempts, нет auto-recovery | MEDIUM | Лаб. работа прервана |
| **G7** | `debugPrint` → no-op в release. Нет телеметрии | MEDIUM | Невозможно диагностировать проблемы в школе |

---

## Часть 5: Firmware Safety

### 🔴 CRITICAL

| ID | Описание | Файл |
|----|----------|------|
| **F-3** | `/api/csv` — `beginResponseStream` буферизирует весь ответ в RAM. 10K samples × 120 chars ≈ 1.2MB → OOM на ESP32 (300KB heap). | main.cpp |

### 🟠 HIGH

| ID | Описание | Файл |
|----|----------|------|
| **A-1a** | BleTask stack 4096B — NimBLE рекомендует ≥6144 для `notify()` | main.cpp |
| **C-4** | `endTransmission()` return value не проверяется → garbage data при I2C NACK | sensor_drivers.h |
| **C-5** | `requestFrom()` return value не проверяется → чтение мусора | sensor_drivers.h |
| **A-3a** | BLE CALIBRATE handler делает I2C на Core 0 → блокирует NimBLE host task | main.cpp |
| **A-3b** | Web CALIBRATE handler делает I2C в lwIP callback → блокирует HTTP | main.cpp |
| **A-4a** | BleTask и WebTask НЕ зарегистрированы в watchdog | main.cpp |
| **B-3a** | `CONFIG_FREERTOS_CHECK_STACKOVERFLOW` не включён | platformio.ini |
| **E-3** | Secure Boot не настроен (физический доступ → прошивка любого кода) | — |
| **E-4** | OTA не реализован (описан в ARCHITECTURE.md как core feature) | — |
| **C-6** | BME280 `startForcedMeasurement()` блокирует I2C на 10мс | sensor_drivers.h |

### 🟡 MEDIUM

| ID | Описание |
|----|----------|
| **D-2b** | Single-byte BLE command (len==1) обходит CRC проверку |
| **D-3c** | `notify()` return value не проверяется → потеря пакета при disconnect |
| **B-1d** | Ring buffer mutex 10мс → drop samples во время CSV export |
| **F-4** | CSV export блокирует mutex 10000 раз → sensor drops |
| **F-5** | Slow client DoS: ESPAsyncWebServer single thread |

---

## Часть 6: Производительность (для Celeron N4000 + 4GB + HDD)

### ✅ Что сделано хорошо

| Механизм | Оценка | Детали |
|----------|--------|--------|
| **CircularSampleBuffer** | ⭐⭐⭐⭐⭐ | O(1) add/evict, Queue-backed, 500K capacity |
| **Оконный снэпшот** | ⭐⭐⭐⭐⭐ | `takeLast(windowSize)` — UI работает с ~3500 точками, не 500K |
| **LTTB downsampling** | ⭐⭐⭐⭐⭐ | Float64List interleaved, zero GC pressure, O(N) |
| **Адаптивный FPS** | ⭐⭐⭐⭐ | 33ms (30fps) / 40ms (25fps) по нагрузке |
| **Batch SQLite INSERT** | ⭐⭐⭐⭐⭐ | Drift `batch()` → single transaction, 30с интервал |
| **Timer-based polling** | ⭐⭐⭐⭐ | 10мс вместо SerialPortReader (избежание heap corruption) |
| **Isolate port close** | ⭐⭐⭐⭐ | Закрытие порта в Isolate — не блокирует UI |

### ⚠️ Что можно улучшить

| Проблема | Severity | Рекомендация |
|----------|----------|--------------|
| Recovery загружает ВСЕ измерения в RAM | HIGH | 1ч × 100Hz = 360K rows ≈ 80MB → OOM на 4GB. Использовать `LIMIT` + pagination |
| `SensorPacket` — 15 nullable doubles ≈ 150B × 500K = 75MB | MEDIUM | Допустимо, но на грани для 4GB. Мониторить |
| LTTB threshold 5000 → редко срабатывает при окне 3500 | LOW | Можно снизить до 2000 для доп. запаса |

---

## Часть 7: Рекомендации по приоритету

### 🔴 Немедленно (до релиза)

1. **Firmware: CSV export OOM** — заменить `beginResponseStream` на chunked response
2. **Firmware: I2C error checking** — проверять `endTransmission()` и `requestFrom()`
3. **Firmware: BleTask stack → 8192** и включить `CONFIG_FREERTOS_CHECK_STACKOVERFLOW=2`
4. **Flutter: Recovery pagination** — `LIMIT 10000` при загрузке прерванного эксперимента
5. **Flutter: P1 — fallback для заблокированного реестра** — пробовать `wmic` или `pnputil` если `reg query` не работает

### 🟡 Sprint 3 (после MVP)

6. **Firmware: Defer CALIBRATE to Core 1** — FreeRTOS queue вместо I2C на Core 0
7. **Firmware: Register all tasks with WDT**
8. **Flutter: Isolate crash detection** — `addOnExitListener` + auto-restart
9. **Flutter: BLE firmware version message** — русское сообщение «Обновите прошивку»
10. **Flutter: Autosave failure UI indicator** — предупреждение в экране эксперимента

### 🟢 Backlog

11. Unify 3 CRC8 implementations into single import
12. Remove dead code (`_notifyBuffer` in BLE HAL)
13. Add file-based logging for release builds (diagnosis in schools)
14. Firmware: Implement OTA + Secure Boot
15. Flutter: Integration tests for experiment flow

---

## Верификация

```
flutter analyze  → No issues found! ✅
flutter test     → 202/202 passed  ✅
```

Все 7 исправлений прошли полный цикл: код → анализатор → тесты → ручная проверка.
