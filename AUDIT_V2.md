# 🔬 ЛАБОСФЕРА — Аудит v2 (Senior Developer Level)

> **Дата**: Январь 2026 (обновлённый)  
> **Объём**: ~25 файлов Flutter/Dart (~8 500 строк), 4 файла прошивки (~1 900 строк), 13 тестовых файлов (194 теста)  
> **Статус после аудита**: `flutter analyze` — 0 issues, `flutter test` — 194/194 ✅

---

## 📊 Сводка

| Категория | Найдено | Исправлено | Осталось |
|-----------|---------|------------|----------|
| 🔴 Критические баги | 8 | 7 | 1 |
| 🟠 Серьёзные проблемы | 9 | 4 | 5 |
| 🟡 Средние | 12 | 2 | 10 |
| 🟢 Рекомендации | 15+ | 0 | 15+ |

**Общая оценка: 7.5/10** — профессиональная архитектура, качественная документация, но накоплен технический долг в edge cases (race conditions, утечки ресурсов, пограничные сценарии).

---

## ✅ Исправлено в этом аудите

### 1. 🔴 `SensorConnectionState.copyWith` терял `errorMessage` (experiment_provider.dart)

**Проблема**: `copyWith()` всегда перезаписывал `errorMessage` переданным значением (включая `null`). При вызове `copyWith(status: connected)` без `errorMessage` — ошибка исчезала из UI, хотя никто не просил её убрать. Пользователь мог видеть мигающее сообщение об ошибке на долю секунды.

**Решение**: Добавлен `clearErrorMessage: bool = false` по аналогии с существующим паттерном `clearStartTime`/`clearEndTime` в `ExperimentState.copyWith()`. Теперь `errorMessage` сохраняется между обновлениями состояния, если явно не очищен. `connect()` и `disconnect()` используют `clearErrorMessage: true`.

---

### 2. 🔴 `AppShell` уничтожал страницы при переключении табов (app_shell.dart)

**Проблема**: `_buildPage()` создавал новый виджет при каждом переключении таба через `switch`. Данные эксперимента, позиция скролла, состояние HistoryPage — всё терялось. Учитель мог случайно нажать на вкладку «Настройки» и потерять данные незавершённого эксперимента.

**Решение**: Заменён `_buildPage()` switch на `IndexedStack` — все 5 страниц живут одновременно, переключение мгновенное, состояние сохраняется. Удалён ненужный метод `_buildPage()`.

---

### 3. 🟠 Debug-логирование в release-сборке (experiment_provider.dart)

**Проблема**: FPS-счётчик и per-50-packet лог выполнялись в release-сборке. `debugPrint` пустой в release, но `DateTime.now()`, `_fpsFrameCount++`, интерполяция строк — нет. На Celeron N4000 это заметные микро-аллокации каждые 33мс.

**Решение**: Обёрнуто в `if (kDebugMode)` — компилятор tree-shakes весь блок в release.

---

### 4. 🔴 `ExperimentAutosaveService` — тройная проблема

**4a. OOM при сбое flush()**: Если `_db.insertMeasurements()` постоянно бросало исключение (диск полный, БД залочена), `_pendingPackets` рос бесконечно (100 Гц × 30с = 3000 пакетов/цикл). За 10 минут → OOM на 4GB Celeron.

**Решение**: Лимит `_maxPendingPackets = 12000` (~1.5 МБ). При переполнении дропаются 10% старейших пакетов с warning.

**4b. `dispose()` не вызывал `endSession()`**: При уничтожении провайдера данные в RAM-очереди терялись, эксперимент оставался со статусом `running` в БД навсегда.

**Решение**: `dispose()` теперь `async`, вызывает `endSession()` (финальный flush + status=completed).

**4c. `recoverInterrupted()` бросал `StateError`**: `firstWhere(..., orElse: () => throw StateError(...))` — гарантированный краш при race condition (markInterrupted отработал, но другой поток уже обработал interrupted эксперименты).

**Решение**: Замена на `indexWhere()` + safe `null` return.

---

### 5. 🟡 CSV-экспорт без UTF-8 BOM (export_utils.dart)

**Проблема**: Excel на Windows открывает CSV без BOM как Windows-1252. Кириллические заголовки (`Время (с)`, `Напряжение (В)`) отображались как кракозябры.

**Решение**: Добавлен `\uFEFF` (UTF-8 BOM) в начало файла.

---

### 6. 🔴 Firmware: `\\n` литерал в BLE printf (main.cpp)

**Проблема**: `Serial.printf("... buf=%d\\n", ...)` — обратный слэш заэкранирован, вместо переноса строки печатались символы `\n`. Логи BLE-сервера шли одной строкой в Serial Monitor.

**Решение**: Исправлено на `\n`.

---

### 7. 🔴 Firmware: `volatile` вместо `std::atomic` для межъядерных переменных (main.cpp)

**Проблема**: `volatile bool g_measuring`, `volatile uint32_t g_sampleRateHz/g_startTimeMs/g_bleClientConnected` — `volatile` не гарантирует атомарность на двухъядерном ESP32-S3. Стандарт C++ это UB для межпоточного доступа.

**Решение**: Заменено на `std::atomic<bool>`, `std::atomic<uint32_t>`.

---

### 8. 🔴 Firmware: Data race в `ring_buffer.h count()` (ring_buffer.h)

**Проблема**: Fallback при `xSemaphoreTake` failure возвращал `count_` без мьютекса — data race при записи с Core 1.

**Решение**: Fallback возвращает `0` вместо чтения без синхронизации.

---

### 9. 🟡 Dead code — `_maybeAdaptUiRate` (experiment_provider.dart)

**Проблема**: Ветки `pps > 200` и `else` обе устанавливали `targetMs = 33`.

**Решение**: Упрощено до двух веток.

---

### 10. 🟡 `ExperimentStatusConverter.fromSql` — потенциальный RangeError (app_database.dart)

**Решение**: Bounds check, fallback → `interrupted`.

---

### 11. 🟢 Мёртвое поле `_lastPacketTimestamp` в BleHAL (ble_hal.dart)

**Решение**: Удалено из класса и из `_cleanup()`.

---

### 12. 🟢 Отсутствие `MigrationStrategy` в AppDatabase (app_database.dart)

**Решение**: Добавлен `MigrationStrategy` с `onCreate` и заготовкой `onUpgrade`.

---

## ⚠️ Обнаружено, НЕ исправлено (требует дискуссии)

### 🔴 Переключение HAL-режима во время записи уничтожает эксперимент

**Файл**: experiment_provider.dart, `halProvider`  
**Проблема**: `halProvider` пересоздаётся при `ref.watch(halModeProvider)`. Если пользователь переключит USB→BLE во время записи — старый HAL уничтожится, `ExperimentController` останется с мёртвой ссылкой.

**Рекомендация**: Заблокировать UI-переключение HAL пока `experiment.isRunning`.

---

### 🟠 `closePort()` в `PortConnectionManager` — утечка native handle

**Рекомендация**: `try/finally { port.dispose(); }` в изоляте.

---

### 🟠 `export_utils.dart` в `domain/` импортирует `dart:io` — Clean Architecture violation

**Рекомендация**: Перенести в `data/` или `presentation/`.

---

### 🟠 `_recoverFromDataStall` в BleHAL — бесконечный цикл reconnect

**Рекомендация**: Отдельный `_stallRecoveryCount`, не сбрасывать `_reconnectAttempts` при watchdog reconnect.

---

### 🟠 `PortConnectionManager` — Windows-only без platform guard

**Рекомендация**: Добавить `if (!Platform.isWindows) return [];`.

---

### 🟠 `CircularSampleBuffer.takeLast()` — O(N) на Queue

**Рекомендация**: Заменить `Queue` на `List` с circular index для O(1) `takeLast()`.

---

### 🟡 BME280 `delay(15ms)` внутри I2C мьютекса блокирует все датчики

**Рекомендация**: Continuous mode или release мьютекса на время delay.

---

### 🟡 `/api/csv` — нет snapshot lock при экспорте буфера

**Рекомендация**: Snapshot API или `pause g_measuring` на время экспорта.

---

### 🟡 `experiment_page.dart` — 1451 строк

**Рекомендация**: Разделить на компоненты.

---

### 🟡 Hardcoded версия 'v2.0' в sidebar

**Рекомендация**: `package_info_plus`.

---

### 🟢 Неиспользуемая зависимость `protobuf` в pubspec.yaml

**Рекомендация**: Удалить.

---

## 💪 Сильные стороны проекта

1. **Clean Architecture** — чёткое разделение domain/data/presentation
2. **Dual-core FreeRTOS** — Core 0 (connectivity) / Core 1 (sensors)
3. **CircularSampleBuffer** с O(1) add/evict
4. **CRC8 end-to-end** data integrity (firmware ↔ USB ↔ BLE ↔ app)
5. **Adaptive UI 30 FPS** с wall-clock elapsed для плавных графиков
6. **Exponential backoff** в SensorHub, BleHAL, UsbHAL
7. **Hot-plug monitoring** через Windows Registry (zero FFI in UI thread)
8. **Heckbert nice-number** axis ticks
9. **194 теста**, покрытие math, HAL, core, utils
10. **Watchdog на sensor task** — auto-reboot при зависании I2C
11. **NVS-persisted calibration** — переживает перезагрузку
12. **Monotonicity validation** — фильтрация пакетов с откатом timestamp
13. **PopScope protection** — предотвращение потери данных
14. **Документация** — отличная архитектурная документация (ARCHITECTURE.md)

---

## 📋 Приоритеты дальнейшей работы

### Немедленно (до релиза)
1. ⛔ Заблокировать переключение HAL во время эксперимента
2. 🔧 Заменить `Queue` → `List` в CircularSampleBuffer
3. 🔧 Platform guard в PortConnectionManager

### Краткосрочно (1-2 спринта)
4. Разделить experiment_page.dart
5. Перенести export_utils.dart из domain
6. BME280 → continuous mode
7. Snapshot API в ring_buffer

### Техдолг
8. Удалить `protobuf` из pubspec.yaml
9. Кэшировать readBatteryPercent()
10. package_info_plus для версии в UI
11. `.select()` в home_page

---

*Аудит: полное чтение каждого файла + статический анализ + 194 теста.*
