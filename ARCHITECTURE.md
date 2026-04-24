# Цифровая Лаборатория по Физике — Архитектура системы

> **Версия**: 1.0  
> **Дата**: Январь 2026  
> **Цель**: Превзойти Releon и L-micro по всем параметрам

---

## 1. Обзор системы

Цифровая лаборатория состоит из двух основных компонентов:

```
┌─────────────────────────────────────────────────────────────┐
│                      FLUTTER APP                            │
│        (Astra Linux / Windows / Android)                    │
└─────────────────────────────────────────────────────────────┘
                          │
                          │ BLE 5.0 / USB-C
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                   МУЛЬТИДАТЧИК                              │
│                    (ESP32-S3)                               │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. Технологический стек

### 2.1 Мобильное/Десктопное приложение

| Компонент | Технология | Обоснование |
|-----------|------------|-------------|
| Framework | **Flutter 3.x (Dart)** | Одна кодовая база для всех платформ |
| State Management | **Riverpod** или **BLoC** | Строгое разделение UI и логики |
| Local Database | **Drift (SQLite)** | Оффлайн-режим, быстрые запросы |
| BLE | `flutter_blue_plus` | Стабильная работа с BLE 5.0 |
| USB | `usb_serial` + FFI | Для проводного подключения |
| Графики | **FL Chart** + LTTB | Производительность на старых ПК |
| PDF Export | `pdf`, `printing` | Генерация отчётов |
| Локализация | `intl` | Русский язык интерфейса |

### 2.2 Прошивка датчика

| Компонент | Технология | Обоснование |
|-----------|------------|-------------|
| MCU | **ESP32-S3-WROOM-1** | BLE 5.0, USB OTG, 2 ядра, PSRAM |
| Framework | **ESP-IDF 5.x** / PlatformIO | Полный контроль над железом |
| BLE Stack | **NimBLE** | Легче и быстрее Bluedroid |
| Web Server | **ESPAsyncWebServer** | Fallback UI без приложения |
| OTA | ESP-IDF OTA | Обновление прошивки по воздуху |
| Протокол | **Framed binary packet v1** (runtime BLE) + protobuf schema (логическая модель) | Минимальный overhead для realtime BLE и предсказуемый фиксированный размер пакета |

### 2.3 Backend (опционально)

| Компонент | Технология | Назначение |
|-----------|------------|------------|
| API | **FastAPI (Python)** | Облачная аналитика, AI |
| Database | PostgreSQL | Хранение данных классов |
| Auth | Keycloak / Простой JWT | Авторизация учителей |

---

## 3. Архитектура Flutter-приложения (Clean Architecture)

```
lib/
├── main.dart
├── core/
│   ├── constants/          # Константы, темы
│   ├── errors/             # Классы ошибок
│   ├── utils/              # Утилиты (LTTB, форматирование)
│   └── di/                 # Dependency Injection (GetIt/Riverpod)
│
├── data/
│   ├── hal/                # Hardware Abstraction Layer
│   │   ├── ble_hal.dart          # BLE реализация
│   │   ├── usb_hal_windows.dart  # USB реализация desktop  
│   │   ├── mock_hal.dart         # Симуляция для тестов
│   │   └── hal_interface.dart    # Абстрактный интерфейс
│   │
│   ├── datasources/
│   │   ├── local/          # SQLite (Drift)
│   │   └── remote/         # REST API (опционально)
│   │
│   ├── models/             # DTO, JSON-сериализация
│   └── repositories/       # Реализация репозиториев
│
├── domain/
│   ├── entities/           # Бизнес-объекты
│   │   ├── measurement.dart
│   │   ├── sensor.dart
│   │   ├── experiment.dart
│   │   └── lab_work.dart
│   │
│   ├── repositories/       # Абстрактные репозитории
│   ├── usecases/           # Бизнес-логика
│   │   ├── start_experiment.dart
│   │   ├── stop_experiment.dart
│   │   ├── export_to_pdf.dart
│   │   ├── calculate_approximation.dart
│   │   └── calibrate_sensor.dart
│   │
│   └── math/               # Математическая обработка
│       ├── lttb.dart             # Downsampling графиков
│       ├── kalman_filter.dart    # Фильтрация шумов
│       ├── approximation.dart    # y=kx+b, полиномы
│       ├── statistics.dart       # Среднее, погрешность
│       └── integral.dart         # Численное интегрирование
│
└── presentation/
    ├── blocs/              # или providers/ для Riverpod
    │   ├── connection/     # Состояние подключения
    │   ├── experiment/     # Текущий эксперимент
    │   └── settings/       # Настройки приложения
    │
    ├── pages/
    │   ├── home/           # Главный экран
    │   ├── experiment/     # Экран эксперимента
    │   ├── lab_works/      # Список лабораторных
    │   ├── reports/        # История и экспорт
    │   └── settings/       # Настройки
    │
    ├── widgets/            # Переиспользуемые виджеты
    │   ├── chart/          # Графики
    │   ├── sensor_card/    # Карточка датчика
    │   ├── big_value/      # Крупное число (для проектора)
    │   └── connection_status/
    │
    └── themes/             # Тёмная тема по умолчанию
```

---

## 4. Архитектура прошивки ESP32-S3

```
firmware/
├── platformio.ini
├── src/
│   ├── main.cpp
│   │
│   ├── core/
│   │   ├── config.h              # Пины, константы
│   │   ├── ring_buffer.h         # Кольцевой буфер (PSRAM)
│   │   └── binary_protocol.h     # Структуры пакетов
│   │
│   ├── connectivity/             # Core 0
│   │   ├── ble_server.cpp        # NimBLE GATT
│   │   ├── wifi_ap.cpp           # Точка доступа
│   │   ├── web_server.cpp        # AsyncWebServer
│   │   └── ota_handler.cpp       # OTA обновления
│   │
│   ├── sensors/                  # Core 1
│   │   ├── sensor_manager.cpp    # Общий менеджер
│   │   ├── ina226_driver.cpp     # Вольтметр/Амперметр
│   │   ├── bme280_driver.cpp     # Температура/Давление/Влажность
│   │   ├── lsm6ds3_driver.cpp    # Акселерометр/Гироскоп
│   │   ├── max31855_driver.cpp   # Термопара
│   │   └── vl53l1x_driver.cpp    # Лазерный дальномер
│   │
│   ├── dsp/                      # Цифровая обработка
│   │   ├── mahony_filter.cpp     # Фильтр ориентации
│   │   ├── kalman_filter.cpp     # Фильтр Калмана
│   │   └── moving_average.cpp    # Скользящее среднее
│   │
│   └── storage/
│       └── nvs_config.cpp        # Сохранение калибровки
│
├── data/                         # Web UI (SPIFFS)
│   ├── index.html
│   ├── app.js
│   └── style.css
│
└── proto/
    └── sensor_data.proto         # Protobuf схема
```

---

## 5. Протокол обмена данными

### 5.1 BLE GATT Structure

```
Service: Physics Lab (UUID: 0x1820)
├── Characteristic: Sensor Data (UUID: 0x2A00)
│   ├── Properties: Notify
│   └── Format: Framed binary packet v1 (fixed-size packet + protocol header)
│
├── Characteristic: Command (UUID: 0x2A01)
│   ├── Properties: Write
│   └── Commands: START, STOP, CALIBRATE, GET_INFO
│
├── Characteristic: Config (UUID: 0x2A02)
│   ├── Properties: Read/Write
│   └── Data: Sample rate, enabled sensors
│
└── Characteristic: Firmware (UUID: 0x2A03)
    ├── Properties: Read
    └── Data: Version, battery level
```

### 5.2 Protobuf Schema

`sensor_data.proto` описывает **логическую модель полей** и используется как схема
для совместимости, документации и возможного будущего nanopb-слоя. Текущий runtime BLE
обмен не сериализуется через Protobuf: на устройстве используется framed fixed-size binary packet.

```protobuf
syntax = "proto3";

message SensorPacket {
  uint32 timestamp_ms = 1;
  
  // Электричество
  float voltage_v = 2;
  float current_a = 3;
  float power_w = 4;
  
  // Окружающая среда
  float temperature_c = 5;
  float pressure_pa = 6;
  float humidity_pct = 7;
  
  // Движение
  float accel_x = 8;
  float accel_y = 9;
  float accel_z = 10;
  float gyro_x = 11;
  float gyro_y = 12;
  float gyro_z = 13;
  
  // Внешние датчики
  float thermocouple_c = 14;
  float distance_mm = 15;
}

message DeviceInfo {
  string firmware_version = 1;
  uint32 battery_percent = 2;
  repeated string enabled_sensors = 3;
}
```

---

## 6. Критические требования к производительности

### 6.1 Оптимизация графиков (LTTB)

```dart
/// Алгоритм Largest-Triangle-Three-Buckets
/// Уменьшает 100,000 точек до 1,000 без потери формы
List<Point> downsample(List<Point> data, int threshold) {
  if (data.length <= threshold) return data;
  
  final sampled = <Point>[data.first];
  final bucketSize = (data.length - 2) / (threshold - 2);
  
  for (int i = 0; i < threshold - 2; i++) {
    final avgRangeStart = ((i + 1) * bucketSize).floor() + 1;
    final avgRangeEnd = ((i + 2) * bucketSize).floor() + 1;
    
    // Найти точку с максимальной площадью треугольника
    // ... реализация алгоритма
  }
  
  sampled.add(data.last);
  return sampled;
}
```

### 6.2 Изоляты для параллельной обработки

```dart
/// Чтение данных в отдельном изоляте
class SensorIsolate {
  late Isolate _isolate;
  late ReceivePort _receivePort;
  
  Future<void> start(HALInterface hal) async {
    _receivePort = ReceivePort();
    _isolate = await Isolate.spawn(
      _isolateEntry,
      _IsolateParams(hal, _receivePort.sendPort),
    );
  }
  
  static void _isolateEntry(_IsolateParams params) {
    // Бесконечный цикл чтения данных
    // Парсинг framed binary packet v1 / текстового serial потока
    // Применение фильтра Калмана
    // Отправка готовых данных в UI
  }
}
```

---

## 7. Встроенный Web-интерфейс датчика (Killer Feature)

Когда приложение недоступно, учитель подключается к Wi-Fi датчика и открывает браузер:

```
SSID: PhysicsLab
Password: Lab_XXXXXXXX
URL: http://192.168.4.1
```

### Функции Web UI:
- ✅ Просмотр текущих показаний в реальном времени
- ✅ Простой график (Chart.js)
- ✅ Экспорт данных в CSV
- ✅ Информация о батарее и версии прошивки
- ✅ Обновление прошивки (OTA)

---

## 8. Оффлайн-режим и синхронизация

### 8.1 Локальное хранение (Drift/SQLite)

```dart
@DriftDatabase(tables: [Experiments, Measurements, LabWorks])
class AppDatabase extends _$AppDatabase {
  // Все данные сохраняются локально
  // При появлении сети — синхронизация с облаком (опционально)
}
```

### 8.2 Очередь синхронизации

```dart
class SyncQueue {
  /// Добавляет эксперимент в очередь на синхронизацию
  Future<void> enqueue(Experiment exp);
  
  /// Вызывается при появлении интернета
  Future<void> processQueue();
}
```

---

## 9. OTA-обновления прошивки

### 9.1 Процесс обновления

1. Приложение проверяет версию прошивки датчика
2. Если есть новая версия — скачивает `.bin` с сервера
3. Передаёт файл на датчик через BLE (chunked transfer)
4. ESP32 записывает в OTA-раздел и перезагружается

### 9.2 Безопасность

- Прошивка подписывается (Secure Boot)
- Проверка CRC32 перед применением
- Откат на предыдущую версию при ошибке

---

## 10. Тестирование и CI/CD

### 10.1 Структура тестов (Flutter)

```
test/
├── unit/
│   ├── math/               # Тесты LTTB, Калман
│   ├── usecases/           # Бизнес-логика
│   └── repositories/       # Репозитории
│
├── widget/
│   ├── chart_test.dart
│   └── sensor_card_test.dart
│
└── integration/
    └── experiment_flow_test.dart
```

### 10.2 GitHub Actions

```yaml
# .github/workflows/build.yml
name: Build & Test

on: [push, pull_request]

jobs:
  flutter:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
      - run: flutter pub get
      - run: flutter analyze
      - run: flutter test
      - run: flutter build linux --release
      - run: flutter build apk --release
      
  firmware:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/cache@v3
        with:
          path: ~/.platformio
          key: pio-${{ hashFiles('**/platformio.ini') }}
      - run: pip install platformio
      - run: pio run -e esp32s3
```

---

## 11. Требования к UI/UX

### 11.1 Принципы дизайна

- **Тёмная тема по умолчанию** — экономия батареи, забота о зрении
- **Крупные элементы** — для сенсорных экранов и проекторов
- **Минимум шагов** — запуск эксперимента в 2 касания
- **Русский язык** — все надписи на русском, понятные ошибки

### 11.2 Режимы отображения

| Режим | Описание | Использование |
|-------|----------|---------------|
| **Табло** | Одно большое число | Демонстрация с проектора |
| **График** | Y(t) в реальном времени | Основной режим |
| **Таблица** | Числовые данные | Для записи в тетрадь |
| **Лаборатория** | График + инструкция | Пошаговая лаба |

### 11.3 Цветовая схема

```dart
class AppColors {
  // Основные
  static const background = Color(0xFF121212);
  static const surface = Color(0xFF1E1E1E);
  static const primary = Color(0xFF4CAF50);  // Зелёный — наука
  
  // Датчики
  static const voltage = Color(0xFFFFEB3B);   // Жёлтый
  static const current = Color(0xFF2196F3);   // Синий
  static const temperature = Color(0xFFF44336); // Красный
  static const pressure = Color(0xFF9C27B0);  // Фиолетовый
  static const motion = Color(0xFF00BCD4);    // Голубой
}
```

---

## 12. Соответствие нормативам

### 12.1 Приказ Минпросвещения № 804/838

- ✅ Поддержка Astra Linux, РЕД ОС
- ✅ Bluetooth 5.0
- ✅ Автономная работа от аккумулятора (6+ часов)
- ✅ Встроенные методические материалы
- ✅ Экспорт в CSV/XLSX/PDF

### 12.2 Реестры

- [ ] Регистрация в Реестре российского ПО (Минцифры)
- [ ] Регистрация в Реестре Минпромторга (для железа)
- [ ] Сертификат совместимости с Astra Linux

---

## 13. Roadmap разработки

### Этап 1: MVP (3 месяца)
- [ ] Прошивка ESP32-S3 с базовыми датчиками (V/A/T/P)
- [ ] Протокол BLE + framed binary packet v1
- [ ] Flutter-приложение (Android + Windows)
- [ ] Базовые функции: подключение, график, таблица, экспорт CSV

### Этап 2: Beta (6 месяцев)
- [ ] Сборка под Astra Linux
- [ ] Математическая обработка (аппроксимация, интегралы)
- [ ] Встроенные лабораторные работы (10 штук)
- [ ] Web UI в датчике
- [ ] OTA-обновления

### Этап 3: Release (9 месяцев)
- [ ] Облачный кабинет учителя
- [ ] Полный набор лабораторных (30+ работ)
- [ ] Регистрация в реестрах
- [ ] Сертификация

### Этап 4: Масштабирование (12+ месяцев)
- [ ] Мультидатчики для химии, биологии
- [ ] AI-ассистент (анализ ошибок ученика)
- [ ] Интеграция с МЭШ/Сферум

---

## 14. Конкурентные преимущества

| Функция | Мы | Releon | L-micro |
|---------|----|----|---------|
| Web UI без приложения | ✅ | ❌ | ❌ |
| OTA-обновления | ✅ | ⚠️ | ❌ |
| Оффлайн-режим | ✅ | ⚠️ | ✅ |
| LTTB (быстрые графики) | ✅ | ❌ | ❌ |
| Astra Linux (нативно) | ✅ | ⚠️ | ❌ |
| Открытый протокол | ✅ | ❌ | ❌ |
| Мультиплеер (2+ устройства) | ✅ | ❌ | ❌ |

---

## 15. Команда и компетенции

### Необходимые специалисты:

| Роль | Стек | Приоритет |
|------|------|-----------|
| Flutter Developer | Dart, BLoC/Riverpod, BLE | 🔴 Критично |
| Embedded Developer | C++, ESP-IDF, BLE | 🔴 Критично |
| Hardware Engineer | Схемотехника, PCB | 🔴 Критично |
| UI/UX Designer | Figma, тёмные темы | 🟡 Важно |
| QA Engineer | Flutter tests, hardware | 🟡 Важно |
| DevOps | GitHub Actions, Linux | 🟢 Желательно |

---

*Документ является основой для разработки. Обновляется по мере развития проекта.*
