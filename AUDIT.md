# Аудит проекта digitalLab — актуальный

> **Дата:** 2026-05-01 (обновлён после Sprint 4)
> **Объём проверки:** ~25 200 строк Dart (66 файлов в `lib/`), прошивка ESP32-S3 (~1 900 строк C++), 21 тестовый файл (~3 700 строк)
> **Статика:** `flutter analyze --fatal-infos` — **0 issues**
> **Тесты:** `flutter test` — **269/269 ✅** (+63 за Sprint 4)
> **CI:** GitHub Actions поднят, jobs `flutter` (analyze + test) и `build-windows` (release artifact) запускаются на push/PR
> **Метод:** свежее чтение кода без опоры на предыдущие аудиты + интеграция исторического контекста из завершённых спринтов.

Этот документ заменяет ранее существовавшие `SENIOR_AUDIT_REPORT.md`, `AUDIT_V2.md`, `SPRINT1_COMPLETED.md`, `SPRINT2_COMPLETED.md`, `SUMMARY.md`, `INDEX.md` — они устарели или дублировали друг друга.

---

## Итоговая оценка: 8.3 / 10

| # | Метрика | Оценка | Что хорошо | Что слабо |
|---|---------|:------:|------------|-----------|
| 1 | Дизайн | **8** | Полная design system на 8px-grid в [design_tokens.dart](lib/presentation/themes/design_tokens.dart), две Material-3 темы (тёмная по умолчанию + светлая «для проекторов») с полным `ColorScheme`, `AppPalette` + extension `context.palette`, Inter bundled, семантичные цвета, классическая палитра осциллографа | Нет визуальной документации/Figma; нет описанных empty/loading/error макетов |
| 2 | Архитектура | **9.5** | Clean Architecture (`core/data/domain/presentation`); HAL-интерфейс со Stream'ами в [hal_interface.dart](lib/domain/repositories/hal_interface.dart); Composite в [SensorHub](lib/data/hal/sensor_hub.dart) для N устройств одновременно; парсинг в Isolate с handshake через Completer; **парсеры пакетов выделены в [packet_parsers.dart](lib/data/hal/packet_parsers.dart) как чистые функции** (отдельно от Isolate, покрыты тестами); Riverpod DI с `onDispose`; CancellationToken; платформенный fallback BLE→USB на Windows; `HalSettingsNotifier` блокирует смену режима во время записи | Местами оправданно сложно (autodetect через FFI-Isolate) |
| 3 | Интерфейс | **8** | Три ViewMode (display/chart/table) — как у Vernier/PASCO; IndexedStack-навигация в AppShell; Keyboard Shortcuts/Actions — пробел/Esc/Ctrl+E для desktop. **Главный экран разрезан на 6 публичных компонентов** ([experiment_page.dart](lib/presentation/pages/experiment/experiment_page.dart) 559 строк вместо 2709): `ChartView`, `ControlBar`+`ActionButton`+`SessionStatusPill`+`ExperimentSummary`, `ExperimentTimer`, `BigDisplay`, `DataTableView`, `ViewModeSelector`, `TimelineNavigator` | Тестами не покрыты только сложные интеракции графика (zoom/pan/select) |
| 4 | UX | **8** | Защита данных: `_confirmStopOnBack` при выходе во время записи, `_confirmStartNewRecording` при перезаписи, autosave + recovery prompt при запуске; `runZonedGuarded` + `ErrorWidget` (приложение не падает в красный экран); русское «Перезапустите или обратитесь к учителю»; флаг `isRecovering` показывает «Восстановление связи…» вместо «Отключён» | Главный экран перегружен; нет онбординга/туториала первого запуска |
| 5 | Качество кода | **9** | Senior-level lint (`strict-casts`, `strict-raw-types`, `cancel_subscriptions`, `close_sinks`, `prefer_final_fields`); `flutter analyze --fatal-infos` — 0 issues; комментарии объясняют **WHY** — пример [usb_hal_windows.dart:181-195](lib/data/hal/usb_hal_windows.dart#L181-L195) (зачем закрывать порт в Isolate: `CloseHandle()` на отвалившемся CDC ACM блокирует поток на 10–20 секунд из-за `IRP_MJ_CLOSE`); логгер с ротацией 2 МБ, fire-and-forget I/O, буферизация до init | Локально остаются `debugPrint` там, где должен быть `Logger.info`; единичные `// ignore:` комментарии |
| 6 | Производительность | **9** | LTTB на `Float64List` interleaved (минимум GC); парсинг в Isolate; `Timer.periodic` + `sp_nonblocking_read` вместо `SerialPortReader` — документированно избегает heap corruption на Windows ([usb_hal_windows.dart:132-200](lib/data/hal/usb_hal_windows.dart#L132-L200)); lazy scan вместо FFI в теле провайдера; watchdog 2 с / 5 с per device; scrolling-window pkt/s | Нет бенчмарков на школьном Celeron — только архитектурные решения |
| 7 | Тесты | **8** | **269 тестов проходят** (было 206). За Sprint 4 добавлено: 28 тестов на парсеры BLE/USB ([packet_parsers_test.dart](test/unit/hal/packet_parsers_test.dart) — битовые флипы CRC, malformed CSV, BLE buffer reconstruction, диапазоны валидации), 9 тестов на data_isolate lifecycle ([data_isolate_test.dart](test/unit/hal/data_isolate_test.dart) — handshake, idempotent start, end-to-end парсинг через реальный Isolate), 25 widget-тестов на experiment-компоненты ([experiment_components_test.dart](test/widget/experiment_components_test.dart) — Timer/ViewModeSelector/BigDisplay/DataTable/ControlBar/ActionButton/SessionStatusPill/ChartView smoke). FakeHAL для интеграции; Drift in-memory для DB | Логика подключения USB ([usb_hal_windows.dart](lib/data/hal/usb_hal_windows.dart) 1324 стр.) и реального BLE-handshake (FlutterBluePlus) косвенно покрыта только через FakeHAL; нет golden-тестов |
| 8 | Документация | **7** | Doсstrings на публичных API (`KalmanFilter`, `LTTB`, `SensorHub`, `BleHAL`, `Logger`); комментарии в коде объясняют технические решения (Windows IRP_MJ_CLOSE, race conditions, exponential backoff cap); полный набор техдоков (ARCHITECTURE, HARDWARE, PROTOCOL, GETTING_STARTED) | Нет методички учителю и user-guide школьнику |
| 9 | Кросс-платформа + железо | **8** | Прошивка работает с реальными датчиками (5 шт., I2C/SPI, WHO_AM_I, калибровка в NVS, SAFE I2C LAYER); BLE-протокол с CRC8 (`BleCommand` 0x01..0x06), проверка минимальной версии firmware, buffer reconstruction для фрагментированных notify (защита от unbounded роста — 1280 байт max); USB CRC8 на каждой data line; правильный fallback BLE→USB на Windows | Android USB не реализован — на мобильных только BLE+Mock; iOS не упоминается; Astra Linux не проверено в CI |
| 10 | Готовность к продакшену | **8** | Crash-recovery работает: autosave-сервис + recovery prompt при старте ([main.dart:120-131](lib/main.dart#L120-L131)); `runZonedGuarded` + `ErrorWidget` + `PlatformDispatcher.onError`; экспорт CSV/PDF/printing; Drift offline БД; intl подключён; shared_preferences для настроек; **CI в [.github/workflows/ci.yml](.github/workflows/ci.yml)** — analyze+test на Linux, release-сборка под Windows как artifact | Локализация только русская (intl без переводов); нет телеметрии (для школы это скорее плюс) |

**Среднее по 10 метрикам: 8.3 / 10** — продукт уровня выше отраслевой нормы для школьного ПО, готов к пилотному запуску в школах после доводки прошивки и написания методички.

---

## Сильные стороны (что объективно сделано хорошо)

1. **Архитектура и паттерны уровня индустриального инструмента** (комментарии в коде явно ссылаются на Vernier LabQuest / PASCO Capstone). Composite HAL, Isolate-handshake, CancellationToken, lazy scan без FFI в провайдере.
2. **Прошивка работает с реальным железом** — настоящие I2C/SPI драйверы для 5 датчиков (BME280, INA226, LSM6DS3, VL53L1X, MAX31855) с проверкой WHO_AM_I/Chip ID, калибровкой по даташиту, SAFE I2C LAYER, NVS persist для калибровки, CRC8 на BLE-командах, Task Watchdog 10 с.
3. **Четыре независимых уровня защиты данных:** autosave каждые 30 с в Drift → recovery prompt при старте → диалоги подтверждения при выходе во время записи и при перезаписи → `ErrorWidget` вместо краша.
4. **Документация технических решений в коде** — комментарии объясняют конкретные Windows USB-баги (`IRP_MJ_CLOSE`), причины ограничений (`flutter_blue_plus` на Windows), экспоненциальный backoff. Это редкость и сильно облегчает поддержку.
5. **Производительность системно проработана:** LTTB на `Float64List` interleaved, Isolate для парсинга, Timer-polling вместо `SerialPortReader`, lazy scan, скользящие окна, кольцевой буфер на `Queue` с O(1) eviction.
6. **Качество кода:** `flutter analyze` чист при senior-level правилах (`strict-casts`, `strict-raw-types`, `cancel_subscriptions`, `close_sinks`).

---

## Открытые пункты (приоритизированы)

### Критические (P0) — блокируют пилот в школе
*Нет.* Все ранее идентифицированные критические баги закрыты в Sprint 1/2 (см. историю ниже).

### Высокий приоритет (P1) — закрыть до релиза
| # | Файл / место | Проблема | Объём |
|---|--------------|----------|-------|
| ~~P1-1~~ | ~~experiment_page.dart 2709 строк~~ | ~~Монолит~~ | **закрыто в Sprint 4** — разрезано на 6 файлов компонентов, главный сократился до 559 строк |
| ~~P1-2~~ | ~~UI-тесты~~ | ~~0 widget-тестов для Pages~~ | **закрыто в Sprint 4** — 25 widget-тестов в [experiment_components_test.dart](test/widget/experiment_components_test.dart), плюс 6 ранее в `widget_test.dart` и `stopped_review_widgets_test.dart` |
| ~~P1-3~~ | ~~`.github/workflows/`~~ | ~~CI~~ | **закрыто в Sprint 3** — см. [.github/workflows/ci.yml](.github/workflows/ci.yml) |
| P1-4 | Методичка учителю | Нет user-guide для школы. Без неё пилот не поедет, какой бы крутой ни был код. | ~2 дня (вне кода) |

### Средний приоритет (P2) — улучшит качество, не блокирует
| # | Файл / место | Проблема | Объём |
|---|--------------|----------|-------|
| ~~P2-1~~ | ~~halProvider при isRunning~~ | ~~Смена HAL во время записи~~ | **закрыто в Sprint 3** — введён `HalSettingsNotifier` с проверкой `isRunning`, UI показывает SnackBar |
| ~~P2-2~~ | ~~export_utils.dart в domain/~~ | ~~Clean Architecture violation~~ | **закрыто в Sprint 3** — перенесён в [data/utils/export_utils.dart](lib/data/utils/export_utils.dart) |
| ~~P2-3~~ | ~~`_recoverFromDataStall`~~ | ~~Бесконечный watchdog-цикл~~ | **закрыто в Sprint 3** — введён `_stallRecoveryCount` с лимитом 3, сброс при поступлении данных |
| ~~P2-4~~ | ~~port_connection_manager Windows-only~~ | ~~Нет platform guard~~ | **закрыто в Sprint 3** — `if (!Platform.isWindows) return []` в `scanPorts()` и `enumeratePortsAsync()` |
| ~~P2-5~~ | ~~HAL unit-тесты~~ | ~~0 тестов на парсеры/Isolate~~ | **закрыто в Sprint 4** — 28 тестов парсеров + 9 тестов data_isolate (включая end-to-end парсинг через реальный Isolate). Полные FFI-тесты `usb_hal_windows`/`ble_hal` остаются как long-tail работа |
| P2-6 | Прошивка: BME280 `delay(15ms)` внутри I2C-мьютекса | Блокирует все остальные I2C-датчики на 15 мс. Перейти в continuous mode либо отпускать мьютекс на время `delay`. | 2 ч (требует железо) |
| P2-7 | Прошивка: `/api/csv` без snapshot-lock | Параллельная запись в кольцевой буфер во время CSV-экспорта может дать рваные данные. Snapshot API или `pause g_measuring` на время экспорта. | 3 ч (требует железо) |

### Низкий приоритет (P3) — техдолг
- Локализация подключена (`intl`), но фактически только русский — добавить переводы по мере необходимости.
- ~~Hardcoded версия в sidebar~~ — уже использует `package_info_plus` ([app_shell.dart:399](lib/presentation/pages/shell/app_shell.dart#L399)).
- ~~Неиспользуемая зависимость `protobuf`~~ — отсутствует в текущем `pubspec.yaml`.
- `avoid_print` в `tools/` (не в `lib/`) — заменить на Logger или исключить из анализа.
- Кэшировать `readBatteryPercent()` (вызывается часто) — задача в прошивке.

---

## История крупных правок

### Sprint 4 (май 2026 — после Sprint 3 в той же сессии)
**Закрыты P1-1, P1-2, P2-5 — крупные структурные пункты, разблокирован пилот:**
- Декомпозиция [experiment_page.dart](lib/presentation/pages/experiment/experiment_page.dart): 2709 → 559 строк (×4.8). Выделено 6 публичных компонентов:
  - [view_mode_selector.dart](lib/presentation/pages/experiment/view_mode_selector.dart) (`ViewMode`, `ViewModeSelector`)
  - [experiment_big_display.dart](lib/presentation/pages/experiment/experiment_big_display.dart) (`BigDisplay`)
  - [experiment_timer.dart](lib/presentation/pages/experiment/experiment_timer.dart) (`ExperimentTimer`)
  - [experiment_control_bar.dart](lib/presentation/pages/experiment/experiment_control_bar.dart) (`ControlBar`, `SessionStatusPill`, `ExperimentSummary`, `ActionButton`)
  - [experiment_data_table_view.dart](lib/presentation/pages/experiment/experiment_data_table_view.dart) (`DataTableView`)
  - [experiment_chart_view.dart](lib/presentation/pages/experiment/experiment_chart_view.dart) (`ChartView`, `TimelineNavigator`, `ChartData`, `ChartInteractionMode`)

  В главном файле остались точка входа, диалоги, шорткаты, баннеры состояния (вынесены в `_StatusBanners` + `_Banner` для устранения дубликации) и единый метод `_exportExperiment` (был дублирован в `onExport` и `_runExportFromShortcut`).
- Парсеры протоколов вынесены в [packet_parsers.dart](lib/data/hal/packet_parsers.dart) как чистые публичные функции (`PacketParsers.parseMultisensorLine`, `parseDistanceLine`, `parseBleSensorPacket`, `tryExtractBlePacket`). Раньше они были приватными `static` методами внутри `data_isolate.dart` — нельзя было покрыть unit-тестами без поднятия Isolate. CRC8 строки делегирован в общий [domain/math/crc8.dart](lib/domain/math/crc8.dart).
- Тесты: +28 на парсеры (битовые флипы CRC, malformed CSV, BLE buffer reconstruction, диапазоны валидации), +9 на data_isolate (handshake, idempotent start, end-to-end парсинг через реальный Isolate с CSV/BLE), +25 widget-тестов на experiment-компоненты. Итого `flutter test` — **269/269 passed**.
- 4 info `prefer_const_constructors`/`prefer_final_locals` в новых тестах закрыты `dart fix --apply`.

### Sprint 3 (май 2026)
**Закрыты средние замечания и поднят CI:**
- `HalSettingsNotifier` ([experiment_provider.dart](lib/presentation/blocs/experiment/experiment_provider.dart)): объединил `halModeProvider` и `selectedPortProvider` под одной моделью `HalSettings`, изменения идут только через `setMode`/`setSelectedPort` с проверкой `experimentControllerProvider.isRunning`. Старые имена сохранены как read-only `Provider<...>` обёртки для совместимости с `ref.watch`. UI (settings_page, home_page, ble_device_page) показывает SnackBar «Сначала остановите запись» при попытке сменить режим во время эксперимента.
- `_stallRecoveryCount` в [ble_hal.dart](lib/data/hal/ble_hal.dart): отдельный счётчик watchdog-recover'ов с лимитом 3, сброс при поступлении новых данных. Без него `_recoverFromDataStall` бесконечно реконнектил без получения данных, потому что `connect()` сбрасывал `_reconnectAttempts`.
- Platform guard в [port_connection_manager.dart](lib/data/hal/port_connection_manager.dart) — `scanPorts()` и `enumeratePortsAsync()` возвращают пустой список на не-Windows, не запуская `reg.exe`.
- `export_utils.dart` перенесён из [domain/utils/](lib/domain/utils/) в [data/utils/](lib/data/utils/export_utils.dart) — устранено нарушение Clean Architecture (`dart:io` в `domain/`).
- 23 info-замечания `curly_braces_in_flow_control_structures` устранены через `dart fix --apply` (data_isolate.dart, sensor_data.dart, usb_hal_windows.dart, experiment_page.dart). Теперь `flutter analyze --fatal-infos` — 0 issues.
- CI поднят: [.github/workflows/ci.yml](.github/workflows/ci.yml) — analyze+test на Ubuntu, release-сборка под Windows как artifact, кэширование pub-cache, concurrency-cancel предыдущих run'ов.

### Sprint 1 (февраль 2026, версия v2.2 → v2.3)
**Закрыты критические/высокие пункты:**
- Race condition в `connect()` USB HAL (флаг `_isConnecting` ставится **до** первого `await`).
- O(N) зависание буфера эксперимента — введён `CircularSampleBuffer<T>` на `Queue` с O(1) add/evict, callback `onWarningThreshold` при 80%.
- BLE reconnect: лимит 5→10, сброс счётчика при ручном `connect()`, `clamp(2, 30)` на backoff.
- FFI-блокировка UI: `openReadWrite()` теперь в `Isolate.run()` с таймаутом 6 с.
- Валидация монотонности `timestampMs` в ExperimentController.
- Дублирование `port_scanner.dart` ↔ `port_connection_manager.dart` устранено через общий `port_types.dart`.
- Прошивка: CRC8 на входящих BLE-командах, Task Watchdog 10 с, динамический Wi-Fi пароль из MAC, именованные константы.

### Sprint 2 (июль 2026)
**Закрыт главный блокер релиза:**
- **Реальные I2C/SPI драйверы датчиков** в новом файле `firmware/src/sensors/sensor_drivers.h` (~450 строк): `BME280Driver`, `INA226Driver`, `LSM6DS3Driver`, `VL53L1XDriver`, `MAX31855Driver`. Каждый с `begin()` (проверка Chip ID/WHO_AM_I), `read()` (возвращает структуру с `.valid`), `available()`. Прошивка работает с любым подмножеством подключённых датчиков. Калибровка INA226 хранится в NVS.
- Удалён мёртвый код `lib/data/hal/usb_hal.dart` (старый Android HAL через `usb_serial`) и зависимость `usb_serial` из `pubspec.yaml`.
- Реализовано автосохранение в SQLite через Drift: таблицы `Experiments` и `Measurements`, `ExperimentAutosaveService` с `beginSession`/`addPacket`/`flush`/`endSession`/`recoverInterrupted`. Интеграция в [main.dart](lib/main.dart): при старте `db.markInterruptedExperiments()`.
- Исправления `SensorConnectionState.copyWith` (терял `errorMessage`), `AppShell` (уничтожал страницы при переключении табов — заменено на `IndexedStack`), CSV-экспорт без UTF-8 BOM (Excel показывал кракозябры), `volatile` → `std::atomic` в прошивке для межъядерных переменных, data race в `ring_buffer::count()`.

---

## Заключение и рекомендации

Проект готов к **пилотному запуску в школах**. Все технические блокеры закрыты, кода-уровень код-базы — **8.3 / 10**. Остающиеся открытые пункты — либо вне кода (методичка учителю, P1-4), либо требуют физического тестирования на железе (P2-6/P2-7 в прошивке).

**Что осталось (по приоритетам):**

1. **Методичка учителю (P1-4, ≈ 2 дня, вне кода)** — единственный пункт, без которого школа не примет продукт. Должна включать 1 опыт-эталон с пошаговым описанием подключения, запуска и интерпретации данных. Задача методиста, не разработчика.

2. **Нагрузочное тестирование на целевом ПК (Celeron N4000, 4 ГБ RAM, HDD)** — провести 45-минутный реальный эксперимент, измерить пиковую RAM, средний FPS графика, поведение autosave при выключении из розетки. Включить `PRAGMA journal_mode=WAL` в Drift для HDD-оптимизации.

3. **Прошивка (P2-6, P2-7)** — точечные доводки требуют физического оборудования. Не блокирует пилот в режиме работы 1 датчик на класс.

После выполнения первых двух пунктов реалистичная итоговая оценка — **8.7 / 10**, продукт можно выставлять на тендеры в нацпроектах «Точка роста».

---

*Документ ведётся по состоянию на дату в шапке. При следующем крупном спринте — обновить таблицу метрик и историю правок, не плодить отдельные SPRINT_N.md файлы.*
