# Senior UI Audit — 2026-03-08

## Executive Summary

Если оценивать Flutter UI строго и по-взрослому, то текущий интерфейс проекта **уже сильнее типичного инженерного MVP**, но **пока не дотягивает до world-class senior product design**.

Главный вывод:

- у проекта есть хорошая основа для научного desktop/mobile UI;
- экран эксперимента за последние правки заметно вырос в качестве;
- тема, цветовая палитра и фокус на слабые школьные ПК выбраны правильно;
- но продуктовый UX ещё не собран в единую систему;
- несколько экранов всё ещё ощущаются как смесь сильных локальных решений, stub-страниц и «инженерного» UI.

Текущая оценка UI/UX зрелости:

- Visual system: **7/10**
- Screen consistency: **6/10**
- School usability: **7.5/10**
- Projector/readability readiness: **7/10**
- World-class polish: **5.5/10**

## Что проверено

Проанализированы ключевые UI-поверхности Flutter-приложения:

- [../lib/presentation/themes/app_theme.dart](../lib/presentation/themes/app_theme.dart)
- [../lib/presentation/pages/shell/app_shell.dart](../lib/presentation/pages/shell/app_shell.dart)
- [../lib/presentation/pages/splash/splash_screen.dart](../lib/presentation/pages/splash/splash_screen.dart)
- [../lib/presentation/pages/home/home_page.dart](../lib/presentation/pages/home/home_page.dart)
- [../lib/presentation/widgets/device_panel.dart](../lib/presentation/widgets/device_panel.dart)
- [../lib/presentation/pages/experiment/experiment_page.dart](../lib/presentation/pages/experiment/experiment_page.dart)
- [../lib/presentation/pages/experiment/stopped_review_widgets.dart](../lib/presentation/pages/experiment/stopped_review_widgets.dart)
- [../lib/presentation/pages/calibration/calibration_page.dart](../lib/presentation/pages/calibration/calibration_page.dart)
- [../lib/presentation/pages/port_selection/port_selection_page.dart](../lib/presentation/pages/port_selection/port_selection_page.dart)
- [../lib/presentation/pages/ble/ble_device_page.dart](../lib/presentation/pages/ble/ble_device_page.dart)
- [../lib/presentation/pages/history/history_page.dart](../lib/presentation/pages/history/history_page.dart)
- [../lib/presentation/pages/settings/settings_page.dart](../lib/presentation/pages/settings/settings_page.dart)
- [../lib/presentation/pages/linking/sensor_linking_page.dart](../lib/presentation/pages/linking/sensor_linking_page.dart)
- [../lib/presentation/pages/oscilloscope/oscilloscope_page.dart](../lib/presentation/pages/oscilloscope/oscilloscope_page.dart)

## Сильные стороны

### 1. Правильный общий вектор продукта

Сильная сторона проекта — не «красивости», а правильный вектор:

- тёмная тема действительно подходит для лабораторного сценария;
- крупные контролы и читаемые цифры ориентированы на проектор и старые ПК;
- продукт думает о графиках как о главном контенте, а не как о второстепенном элементе;
- UI местами уже учитывает реальную эксплуатацию, а не только демо-сценарий.

Это уже senior-подход.

### 2. Сильный экран эксперимента

Самый зрелый экран сейчас — эксперимент:

- [../lib/presentation/pages/experiment/experiment_page.dart](../lib/presentation/pages/experiment/experiment_page.dart)
- [../lib/presentation/pages/experiment/stopped_review_widgets.dart](../lib/presentation/pages/experiment/stopped_review_widgets.dart)

Что хорошо:

- хороший приоритет на данные и график;
- post-stop review стал значительно проще и взрослее;
- убран лишний режимный шум;
- действия анализа теперь ближе к реальным задачам школьника;
- график получает больше площади, а не уступает её постоянным подсказкам.

Это уже уровень, который можно развивать дальше без переделки с нуля.

### 3. Home screen выглядит живее многих научных приложений

На [../lib/presentation/pages/home/home_page.dart](../lib/presentation/pages/home/home_page.dart) и [../lib/presentation/widgets/device_panel.dart](../lib/presentation/widgets/device_panel.dart) видно хорошее product thinking:

- есть ощущение «живой панели приборов»;
- карточки датчиков умеют показывать статус, ценность и доступность функций;
- `DevicePanel` выглядит полезным, а не декоративным;
- цветовое кодирование сенсоров помогает, а не мешает.

Для учебного продукта это сильная база.

## Критические замечания

### CR-1. Нет единой продуктовой дизайн-системы уровня whole-app

Файл-источник проблемы — не один файл, а всё сочетание:

- [../lib/presentation/themes/app_theme.dart](../lib/presentation/themes/app_theme.dart)
- [../lib/presentation/pages/home/home_page.dart](../lib/presentation/pages/home/home_page.dart)
- [../lib/presentation/pages/shell/app_shell.dart](../lib/presentation/pages/shell/app_shell.dart)
- [../lib/presentation/pages/calibration/calibration_page.dart](../lib/presentation/pages/calibration/calibration_page.dart)
- [../lib/presentation/pages/experiment/experiment_page.dart](../lib/presentation/pages/experiment/experiment_page.dart)

Суть:

- тема задаёт хорошую палитру и базовые стили;
- но экраны всё ещё проектируются локально, а не как части одной системы;
- карточки, панели, headers, badge-элементы и навигация ощущаются как разные мини-системы.

Почему это серьёзно:

- приложение не складывается в единый визуальный язык;
- продукт выглядит как «сильная инженерная сборка экранов», а не как законченная design system;
- ощущение senior-level polish теряется не в деталях, а в общей несобранности.

Что нужно:

- формализовать component library: page header, section header, status badge, primary panel, secondary panel, action chip, empty state;
- задать 2–3 уровня плотности интерфейса и не смешивать их случайно;
- унифицировать radii, icon sizes, panel heights, badge logic, page paddings.

Приоритет: **P0**

---

### CR-2. Sidebar shell слишком «дизайнерский», но недостаточно продуктовый

Файл:

- [../lib/presentation/pages/shell/app_shell.dart](../lib/presentation/pages/shell/app_shell.dart)

Что вижу:

- sidebar вложил много усилий в glow, gradient, custom accent bar, halo, premium-эффекты;
- при этом сам layout shell остаётся довольно узким и визуально доминирующим относительно контента;
- на фоне остальных экранов он выглядит как отдельный дизайнерский стиль.

Почему это плохо:

- world-class senior UI не просто делает «красиво», он держит баланс между identity и тишиной;
- sidebar сейчас слишком старается быть премиальным;
- из-за этого ощущается некоторое несоответствие между shell и более прагматичными рабочими экранами.

Вердикт:

- решение не плохое;
- но это скорее strong custom implementation, чем зрелое product navigation решение.

Что бы я сделал:

- упростил визуальные эффекты на 20–30%;
- усилил читаемость и информационную роль, а не декоративность;
- проверил, не выигрывает ли приложение от более спокойственного rail/navigation shell.

Приоритет: **P0**

## Высокие риски

### HR-1. Splash screen слишком демонстрационный для школьного продукта

Файл:

- [../lib/presentation/pages/splash/splash_screen.dart](../lib/presentation/pages/splash/splash_screen.dart)

Проблема:

- splash явно сделан как showcase-анимация;
- частицы, пульсации, градиенты и staged animation создают ощущение «вау-экрана»;
- но для школьного продукта важнее быстрый, спокойный, уверенный вход.

Почему это не senior-level:

- настоящий senior UI для такого приложения не тратит лишнее внимание и GPU/CPU-бюджет на декоративную заставку;
- splash должен поддерживать trust и speed, а не конкурировать с основным приложением;
- на слабых машинах этот экран скорее ухудшает первое впечатление.

Что рекомендую:

- сделать splash проще, короче и спокойнее;
- оставить бренд, но убрать лишнюю “showroom” анимацию;
- фокус сместить на быстрый переход и clean loading state.

Приоритет: **P1**

---

### HR-2. Stub-страницы резко сбивают уровень восприятия продукта

Файлы:

- [../lib/presentation/pages/history/history_page.dart](../lib/presentation/pages/history/history_page.dart)
- [../lib/presentation/pages/settings/settings_page.dart](../lib/presentation/pages/settings/settings_page.dart)
- [../lib/presentation/pages/linking/sensor_linking_page.dart](../lib/presentation/pages/linking/sensor_linking_page.dart)

Проблема:

- экраны честно оформлены как «в разработке»;
- но они слишком похожи на placeholder screens;
- если пользователь попадает туда из премиально оформленного shell/home, ощущение зрелости продукта резко падает.

Почему это важно:

- UX оценивается по худшему экрану, а не по лучшему;
- world-class продукт не должен иметь важные разделы, выглядящие как временный stub;
- лучше иметь меньше доступных разделов, чем много недозрелых поверхностей.

Что рекомендую:

- либо скрыть/ограничить stub-экраны до готовности;
- либо быстро перевести их в “structured preview” формат: реальные секции, будущая информация, dummy content, consistent layout, а не просто badge “В разработке”.

Приоритет: **P1**

---

### HR-3. Port selection screen визуально выпадает из остального приложения

Файл:

- [../lib/presentation/pages/port_selection/port_selection_page.dart](../lib/presentation/pages/port_selection/port_selection_page.dart)

Проблема:

- этот экран использует локальные цвета и визуальные решения, которые не опираются на [../lib/presentation/themes/app_theme.dart](../lib/presentation/themes/app_theme.dart);
- много utility/debug визуала прямо в основном пользовательском потоке;
- лог-панель и диагностика полезны инженеру, но не оформлены как продуктовый UX.

Почему это проблема:

- UX продукта ломается именно на сложных системных экранах;
- если пользователь попадает в подключение и видит debug-style UI, доверие к продукту падает;
- это особенно критично для школы, где сценарий “не подключается” должен быть максимально понятным и спокойным.

Что нужно:

- привести страницу к общей дизайн-системе;
- разделить teacher-friendly flow и engineering diagnostics;
- минимизировать ощущение «служебного окна».

Приоритет: **P1**

---

### HR-4. Calibration page сильная, но слишком dense и “профессиональная”

Файл:

- [../lib/presentation/pages/calibration/calibration_page.dart](../lib/presentation/pages/calibration/calibration_page.dart)

Проблема:

- экран хороший по качеству и глубине;
- но по плотности и количеству смысловых блоков он ближе к pro tool, чем к школьному продукту;
- есть риск перегруза для учителя и тем более для ученика.

Почему это не world-class yet:

- senior UX умеет скрывать сложность по слоям;
- здесь сложность оформлена красиво, но всё ещё довольно фронтально;
- продукт выглядит more technical than educational.

Что рекомендую:

- сделать progressive disclosure;
- оставить quick actions на первом экране;
- двухточечную калибровку и детальную info-панель сделать более пошаговыми.

Приоритет: **P1**

## Средние замечания

### MR-1. Home screen местами перегружен продуктовыми амбициями

Файл:

- [../lib/presentation/pages/home/home_page.dart](../lib/presentation/pages/home/home_page.dart)

Что хорошо:

- сильное первое впечатление;
- понятная сетка датчиков;
- хороший live-feel.

Что спорно:

- app bar содержит много действий и режимов;
- рядом живут teacher-facing flow, debugging, HAL-mode, port selection и version segmentation;
- для первого экрана это уже почти command center.

Риск:

- продукт хочет быть и школьным, и инженерным, и демонстрационным одновременно;
- это ослабляет простоту.

Приоритет: **P2**

---

### MR-2. DevicePanel качественный, но может стать слишком “операторским”

Файл:

- [../lib/presentation/widgets/device_panel.dart](../lib/presentation/widgets/device_panel.dart)

Панель сильная и полезная, но есть риск, что со временем она превратится в mini dashboard с избыточной плотностью.

Сейчас она ещё в хорошем состоянии, но для долгой жизни важно:

- не добавлять туда много метрик «на всякий случай»;
- держать teacher readability выше инженерной информативности;
- не дублировать статус одновременно в трёх местах.

Приоритет: **P2**

---

### MR-3. BLE page лучше, чем COM page, но всё ещё ближе к utility flow

Файл:

- [../lib/presentation/pages/ble/ble_device_page.dart](../lib/presentation/pages/ble/ble_device_page.dart)

Плюсы:

- лучше встроена в общую тему;
- хороший empty state;
- читаемая структура.

Минусы:

- ощущение всё ещё больше “device picker utility”, чем части цельного продукта;
- не хватает мягкого onboarding-контекста для не-технического пользователя.

Приоритет: **P2**

---

### MR-4. Oscilloscope page интересный, но stylistically отдельный продукт внутри продукта

Файл:

- [../lib/presentation/pages/oscilloscope/oscilloscope_page.dart](../lib/presentation/pages/oscilloscope/oscilloscope_page.dart)

Экран выглядит как отдельное приложение/инструмент, а не как естественная часть Labosfera.

Это нормально для профессионального инструмента, но для общей UI-консистентности есть риск:

- слишком другой цветовой мир;
- слишком другой interaction language;
- слишком другой semantic density.

Если оставлять осциллограф как premium/specialized mode — ок.
Если позиционировать как обычную часть продукта — нужна более мягкая интеграция в общий визуальный язык.

Приоритет: **P2**

## Что уже близко к senior-level

### Experiment flow

Наиболее зрелая зона продукта:

- хороший chart-first подход;
- сильный data-centric UX;
- stop/review flow после последних правок стал гораздо взрослее;
- хороший потенциал для projector mode.

### Theme foundation

[../lib/presentation/themes/app_theme.dart](../lib/presentation/themes/app_theme.dart) — хорошая основа:

- разумная палитра;
- правильный dark baseline;
- адекватная типографическая база;
- неплохие базовые button/card/chip decisions.

Проблема не в основе темы, а в том, что экраны пока применяют её не как единую систему.

## Что мешает выйти на мировой уровень

Чтобы интерфейс стал действительно senior/world-class, нужно не столько «улучшать красоту», сколько сделать 5 системных шагов.

### 1. Ввести page architecture

Каждый основной экран должен иметь одну и ту же структуру:

- page header;
- primary action zone;
- primary content area;
- secondary/meta area;
- empty/error/loading states одного семейства.

### 2. Ограничить количество визуальных приёмов

Сейчас в продукте одновременно живут:

- gradients;
- glow;
- badges;
- decorative separators;
- colored overlays;
- dense cards;
- instrumentation UI.

Все по отдельности неплохи, но вместе создают ощущение «много сильных идей сразу».

Senior-level polish требует дисциплины:

- меньше разных эффектов;
- больше единого поведения и ритма.

### 3. Развести teacher UX и engineering UX

Это один из главных архитектурных UX-вопросов проекта.

Сейчас продукт частично пытается быть:

- школьным UI для урока;
- инженерным tool для диагностики железа;
- premium demo app.

Нужно жёстче отделить:

- normal school flow;
- advanced diagnostics;
- developer/debug tooling.

### 4. Скрыть незрелые разделы до их готовности

Лучше 3 сильных экрана, чем 6 экранов, из которых 3 выглядят как placeholder.

### 5. Сделать полноценный UI kit / audit trail

Нужны не только цвета и текстовые стили, но и:

- единый scale отступов;
- компоненты page sections;
- правила использования chips vs buttons;
- правила для banner/error/info blocks;
- шаблоны list/detail/empty/stub states.

## Практический roadmap

### За 2–3 дня

- упростить sidebar shell;
- привести `port_selection_page.dart` к общей дизайн-системе;
- убрать лишнюю «showcase» составляющую из splash;
- сделать stub-экраны менее placeholder-like.

### За 1 неделю

- собрать UI kit первого уровня;
- унифицировать page headers и section blocks;
- переработать home app bar и отладочные entry points;
- отделить user-facing и diagnostic-facing маршруты.

### За 2 недели

- привести history/settings/linking к реальному content-first UX;
- harmonize oscilloscpe/calibration with app-wide language;
- сделать адаптивные правила для проекторов и слабых экранов.

## Финальный вердикт

Если говорить честно и жёстко:

- **нет**, сейчас UI ещё не на максимальном senior/world-class уровне;
- **да**, у проекта уже есть сильная база и правильное направление;
- strongest part — экран эксперимента и общий scientific/product mindset;
- weakest part — whole-app consistency и разделение product UX vs engineering UX.

То есть проблема уже не в том, что интерфейс «плохой».
Проблема в том, что он ещё **не собран в единую зрелую систему**.

Это хорошая новость: такой продукт можно довести до очень сильного уровня без полного редизайна, если работать системно, а не точечно.
