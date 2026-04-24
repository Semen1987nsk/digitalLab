# Senior Code Audit — 2026-03-07

## Executive Summary

Проект уже выглядит как сильный инженерный MVP, а не как учебный прототип:

- Flutter-часть структурирована лучше среднего по рынку для ранней стадии.
- Есть хороший фокус на слабые школьные ПК: оконный буфер, LTTB, isolate-обработка, защита от зависших COM-портов.
- USB/HAL и BLE написаны с явной ориентацией на реальную нестабильную среду.
- Прошивка уже думает про watchdog, деградацию по отсутствующим датчикам, буферизацию и fallback Web UI.

Но до уровня «надёжный школьный продукт, который предсказуемо работает на разных компьютерах без неприятных сюрпризов» ещё есть зазор.

Главный вывод этого обновлённого аудита:

- базовая стабильность у проекта уже есть;
- анализатор и текущие тесты зелёные;
- часть замечаний из прошлого аудита уже исправлена;
- но остаются несколько архитектурно неприятных рисков, которые могут проявляться редко, зато очень болезненно в эксплуатации.

## Что именно проверено

Проверка делалась не только по документам, но и по живому коду.

### Верификация

- `flutter analyze` — без ошибок
- `flutter test` — все тесты проходят
- просмотрены ключевые Flutter-модули:
	- [../lib/main.dart](../lib/main.dart)
	- [../lib/presentation/blocs/experiment/experiment_provider.dart](../lib/presentation/blocs/experiment/experiment_provider.dart)
	- [../lib/data/hal/usb_hal_windows.dart](../lib/data/hal/usb_hal_windows.dart)
	- [../lib/data/hal/sensor_hub.dart](../lib/data/hal/sensor_hub.dart)
	- [../lib/data/hal/data_isolate.dart](../lib/data/hal/data_isolate.dart)
	- [../lib/data/hal/ble_hal.dart](../lib/data/hal/ble_hal.dart)
	- [../lib/data/datasources/local/experiment_autosave_service.dart](../lib/data/datasources/local/experiment_autosave_service.dart)
	- [../lib/data/datasources/local/app_database.dart](../lib/data/datasources/local/app_database.dart)
- просмотрены ключевые firmware-модули:
	- [../firmware/src/main.cpp](../firmware/src/main.cpp)
	- [../firmware/src/core/ring_buffer.h](../firmware/src/core/ring_buffer.h)
	- [../firmware/src/core/config.h](../firmware/src/core/config.h)

## Обновлённая оценка

- Архитектура: **8/10**
- Runtime reliability: **7/10**
- Производительность на слабых ПК: **8.5/10**
- Тестовая зрелость: **6.5/10**
- Готовность к школьной эксплуатации: **6.5/10**

## Что стало лучше с прошлого аудита

Ниже — вещи, которые я специально перепроверил как антигипотезы.

### Антигипотеза 1: старт приложения всё ещё хрупкий

**Не подтвердилась.**

Раньше риск был в раннем доступе к DI через widget context. Сейчас старт выглядит заметно чище:

- recovery запускается через `ref.read(autosaveServiceProvider)` в [../lib/main.dart](../lib/main.dart)
- раннего вызова `ProviderScope.containerOf(context)` больше нет

Это правильное улучшение.

### Антигипотеза 2: recovery существует только на бумаге

**Не подтвердилась полностью.**

Сейчас сценарий реально встроен:

- startup recovery детектится в [../lib/data/datasources/local/experiment_autosave_service.dart](../lib/data/datasources/local/experiment_autosave_service.dart)
- prompt пользователю показывается в [../lib/presentation/pages/shell/app_shell.dart](../lib/presentation/pages/shell/app_shell.dart)
- восстановленные пакеты реально загружаются в [../lib/presentation/blocs/experiment/experiment_provider.dart](../lib/presentation/blocs/experiment/experiment_provider.dart)

Но один важный defect в этом потоке всё же остался — он вынесен ниже как критическое замечание.

### Антигипотеза 3: кодовая база сейчас в красной зоне по качеству

**Не подтвердилась.**

Формально состояние репозитория сейчас хорошее:

- diagnostics чистые
- unit-тесты зелёные
- явного развала зависимостей или сломанной сборки по Flutter-части нет

Проблемы здесь не уровня «всё падает уже сейчас», а уровня «несколько сценариев эксплуатации ещё недостаточно добиты до production-grade».

## Сильные стороны проекта

### 1. Сильный reliability focus в USB/HAL

Особенно хорошо выглядят:

- защита от зависания COM-драйверов в [../lib/data/hal/usb_hal_windows.dart](../lib/data/hal/usb_hal_windows.dart)
- topology/hot-plug/backoff логика в [../lib/data/hal/sensor_hub.dart](../lib/data/hal/sensor_hub.dart)
- isolate-обработка данных в [../lib/data/hal/data_isolate.dart](../lib/data/hal/data_isolate.dart)

Это уже код, который писал человек с опытом реального Windows-железа, а не только happy-path разработки.

### 2. Хороший performance baseline для школьных ПК

Позитивные решения:

- `CircularSampleBuffer` и оконная публикация данных в [../lib/presentation/blocs/experiment/experiment_provider.dart](../lib/presentation/blocs/experiment/experiment_provider.dart)
- отдельная реализация LTTB в [../lib/domain/math/lttb.dart](../lib/domain/math/lttb.dart)
- адаптивный UI tick вместо наивного rebuild на каждый пакет

Это правильная инженерная база под слабые машины.

### 3. Прошивка ориентирована на деградацию, а не на идеальные условия

Плюсы:

- watchdog в sensor task
- I2C mutex
- graceful degradation по отсутствующим датчикам
- PSRAM ring buffer
- fallback Web UI

Для школьной эксплуатации это правильный mindset.

## Критические замечания

### Статус обновления после исправлений от 2026-03-07

Ниже перечислены замечания, актуальные **на момент аудита**. Часть из них уже была закрыта
в этом же цикле доработки:

- бывший `CR-1` по firmware buffer semantics — **исправлен**: transport queue BLE и history buffer разделены;
- бывший `CR-2` по recovery lifecycle — **исправлен**: interrupted session теперь помечается обработанной после решения пользователя;
- бывший `HR-1` по autosave shutdown — **исправлен**: добавлен безопасный shutdown path контроллера;
- бывший `HR-2` по пустому widget-layer — **частично исправлен**: добавлены реальные widget tests на recovery UI.

Оставшиеся пункты ниже стоит читать как архитектурные рекомендации и snapshot рисков на дату аудита.

### CR-1. В прошивке один ring buffer выполняет две несовместимые роли

Файлы:

- [../firmware/src/main.cpp](../firmware/src/main.cpp)
- [../firmware/src/core/ring_buffer.h](../firmware/src/core/ring_buffer.h)

Суть проблемы:

- `taskSensorPolling()` складывает измерения в `g_sensorBuffer`
- `taskBleServer()` отправляет данные через `while (g_sensorBuffer.pop(packet))`, то есть **выгребает буфер**
- Web API при этом использует тот же буфер для:
	- `/api/data` через `peekLast()`
	- `/api/csv` через `peekAt()`

Почему это опасно:

- при активном BLE-клиенте Web UI и CSV-экспорт начинают видеть непредсказуемо урезанную историю;
- fallback Web UI фактически перестаёт быть надёжным fallback, если BLE уже потребляет данные;
- архитектурно смешаны две разные сущности: **transport queue** и **measurement history**.

Это не cosmetic issue, а реальная ошибка модели данных прошивки.

Что рекомендую:

- разделить буферы на `txQueue` и `historyBuffer`;
- либо сделать BLE-отправку по отдельному курсору чтения без destructive `pop()`;
- отдельно определить retention policy для Web/CSV.

Приоритет: **P0**

Статус: **исправлено**

---

### CR-2. Восстановленный эксперимент не меняет статус в БД и может всплывать снова

Файлы:

- [../lib/data/datasources/local/app_database.dart](../lib/data/datasources/local/app_database.dart)
- [../lib/data/datasources/local/experiment_autosave_service.dart](../lib/data/datasources/local/experiment_autosave_service.dart)
- [../lib/presentation/pages/shell/app_shell.dart](../lib/presentation/pages/shell/app_shell.dart)
- [../lib/presentation/blocs/experiment/experiment_provider.dart](../lib/presentation/blocs/experiment/experiment_provider.dart)

Суть проблемы:

- при старте `running` эксперименты переводятся в `interrupted`
- затем загружается `latestInterruptedExperiment()`
- пользователь может нажать «Восстановить»
- но после восстановления сам experiment record не переводится ни в `completed`, ни в `restored`, ни в `dismissed`

Почему это опасно:

- один и тот же interrupted session может снова и снова предлагаться после следующих запусков приложения;
- у пользователя появится ощущение «приложение помнит уже закрытую аварию и не умеет её завершать»;
- история статусов в БД становится неоднозначной.

Что рекомендую:

- добавить явный lifecycle для recovery:
	- `interrupted`
	- `recovery_offered`
	- `restored`
	- `discarded`
	либо хотя бы переводить запись в `completed`/`dismissed` после пользовательского решения;
- не оставлять interrupted-запись в подвешенном состоянии после prompt.

Приоритет: **P0**

Статус: **исправлено**

## Высокие риски

### HR-1. `ExperimentController.dispose()` не завершает autosave session

Файл:

- [../lib/presentation/blocs/experiment/experiment_provider.dart](../lib/presentation/blocs/experiment/experiment_provider.dart)

Суть:

- при `dispose()` контроллер останавливает HAL fire-and-forget,
- но не вызывает `_autosave?.endSession()`.

Почему это риск:

- при пересоздании провайдера, смене HAL-режима или другом lifecycle invalidation можно оставить активную сессию autosave в неопределённом состоянии;
- это повышает шанс лишних `interrupted` записей и неполного flush.

Да, часть сценариев потом будет восстановлена на следующем запуске, но это уже repair path вместо корректного lifecycle.

Что рекомендую:

- сделать явный async shutdown path контроллера;
- при invalidation безопасно завершать сессию и только потом отпускать HAL.

Приоритет: **P1**

Статус: **исправлено**

---

### HR-2. Widget/integration слой всё ещё почти пустой

Файлы:

- [../test/widget_test.dart](../test/widget_test.dart)
- [../test/unit](../test/unit)

Факт:

- unit-тесты хорошие и полезные;
- но `widget_test.dart` сейчас остаётся smoke-заглушкой `1 + 1 == 2`.

Почему это риск:

- основные регрессии этого продукта будут не в математике, а в lifecycle/UI/Riverpod/navigation/recovery;
- именно эти сценарии сильнее всего страдают на школьных ПК и нестабильном железе.

Минимум, который нужен:

- startup → splash → shell;
- prompt восстановления эксперимента;
- старт/стоп эксперимента;
- поведение при отсутствии устройства;
- USB/mock переключение режима.

Приоритет: **P1**

Статус: **частично исправлено**

---

### HR-3. Web command API в прошивке рассчитан на single-chunk body

Файл:

- [../firmware/src/main.cpp](../firmware/src/main.cpp)

Суть:

- обработчик `POST /api/command` парсит body только в момент `index + len >= total`;
- но строка строится из текущего `data`/`len`, без накопления предыдущих chunks.

Почему это риск:

- короткие тела обычно пройдут, поэтому баг будет редким и коварным;
- при chunked/fragmented доставке команда может быть распознана некорректно.

Что рекомендую:

- либо копить body полностью до `total`;
- либо использовать нормальный парсер JSON/command envelope.

Приоритет: **P1**

---

### HR-4. Production observability пока недостаточна

Файлы:

- [../lib/main.dart](../lib/main.dart)
- [../lib/core/logging.dart](../lib/core/logging.dart)
- [../lib/data/hal](../lib/data/hal)

Факт:

- ошибок и событий логируется много,
- но почти всё уходит в `debugPrint`/console.

Почему это риск:

- на школьном ПК учитель не сможет прислать полезный crash-report;
- редкие COM/BLE сбои будут «не воспроизводятся», потому что нет локального артефакта;
- release-режим сейчас не даёт эксплуатационной телеметрии.

Что рекомендую:

- rolling log file;
- экран или экспорт diagnostics bundle;
- хранение последних ошибок HAL/BLE/USB и параметров окружения.

Приоритет: **P1**

## Средние риски

### MR-1. Документация ещё не полностью догнала код

Файлы:

- [../README.md](../README.md)
- [../ARCHITECTURE.md](../ARCHITECTURE.md)
- [../firmware/src/core/config.h](../firmware/src/core/config.h)

Что увидел:

- на момент аудита в `README` ещё фигурировал старый путь `usb_hal.dart`, хотя фактический файл — `usb_hal_windows.dart`;
- на момент аудита в `ARCHITECTURE.md` верхняя часть уже говорила про `framed binary packet v1`, но раздел BLE GATT всё ещё содержал формулировку `Format: Protobuf binary`;
- на момент аудита комментарий в `config.h` ещё описывал старый формат пароля `Lab_XXXX`, тогда как `main.cpp` уже генерировал `Lab_XXXXXXXX`.

Это не ломает runtime, но ломает доверие к документации и усложняет onboarding.

Текущее состояние: базовые расхождения устранены, core docs синхронизированы с реальной реализацией.

Приоритет: **P2**

Статус: **исправлено**

---

### MR-2. Файл `experiment_provider.dart` по-прежнему слишком крупный

Файл:

- [../lib/presentation/blocs/experiment/experiment_provider.dart](../lib/presentation/blocs/experiment/experiment_provider.dart)

Факт:

- там сосредоточены orchestration подключения, live buffer, autosave hooks, adaptive UI ticking, recovery load, calibration hooks и lifecycle эксперимента.

Это ещё не авария, но уже точка будущей хрупкости.

Приоритет: **P2**

---

### MR-3. Silent recovery есть, но не хватает formalized state machine

Файлы:

- [../lib/data/datasources/local/experiment_autosave_service.dart](../lib/data/datasources/local/experiment_autosave_service.dart)
- [../lib/presentation/blocs/experiment/experiment_provider.dart](../lib/presentation/blocs/experiment/experiment_provider.dart)

Сейчас flow рабочий, но он ещё не выглядит как законченная state machine уровня production.

Для долгой поддержки лучше явно формализовать состояния:

- idle
- connecting
- connected
- starting
- running
- stopping
- recovering
- recovered
- failed

Приоритет: **P2**

## Итог по прошивке

### Что хорошо

- верный вектор на realtime и degradation;
- watchdog и mutex внедрены не для красоты;
- BLE-протокол и runtime-пакет уже достаточно прагматичны;
- fallback Web UI реально есть, а не только заявлен в документах.

### Что критично добить

- разделить queue/history semantics в буферах;
- сделать безопасный command parsing;
- формально описать transport contract и retention behavior.

## Итог по Flutter-приложению

### Что хорошо

- чистый старт и recovery bootstrap стали лучше;
- `SensorHub` и `UsbHALWindows` — сильная часть проекта;
- базовая производительность для старых ПК уже продумана;
- unit test layer полезен и не пустой.

### Что критично добить

- recovery status lifecycle;
- widget/integration coverage;
- graceful shutdown autosave/session lifecycle;
- эксплуатационную диагностику.

## Рекомендуемый remediation plan

### За 1–3 дня

- исправить recovery status flow;
- исправить документационные расхождения;
- завести минимум 3 widget-теста на startup/recovery/start-stop.

### За 1 неделю

- разделить firmware queue/history buffer semantics;
- починить `POST /api/command` на multi-chunk body;
- добавить diagnostics export из приложения.

### За 2–3 недели

- декомпозировать `experiment_provider.dart`;
- добавить integration tests на ключевые пользовательские сценарии;
- ввести формальную state machine для experiment lifecycle.

## Финальный вердикт

Если говорить как сеньер прямо: проект **хороший, живой и инженерно зрелее большинства MVP**, но ещё не дошёл до точки, где его можно без опасений раскатывать как «железобетонный школьный продукт».

Сейчас это уже не история про «переписать всё», а история про:

- закрыть 2 действительно важных дефекта архитектурного уровня;
- усилить lifecycle и recovery semantics;
- добавить тесты и observability там, где у пользователей реально болит.

После этого проект можно поднять примерно до **8/10 по эксплуатационной зрелости** без радикальной переработки архитектуры.


