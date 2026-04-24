# Цифровая Лаборатория по Физике

> Цифровая лаборатория нового поколения для российских школ

## 🚀 Быстрый старт

### Flutter-приложение (ПК/Планшет)

```bash
# Установка зависимостей
flutter pub get

# Запуск в режиме разработки (Mock-датчик)
flutter run -d linux   # или windows, android

# Сборка релиза
flutter build linux --release
flutter build apk --release
```

### Прошивка ESP32-S3

```bash
cd firmware

# Надёжная подготовка toolchain (Windows PowerShell)
powershell -ExecutionPolicy Bypass -File ..\tools\bootstrap_firmware_env.ps1

# Сборка (через pinned PlatformIO)
powershell -ExecutionPolicy Bypass -File ..\tools\build_firmware.ps1

# Прошивка
pio run -e esp32s3 -t upload

# Мониторинг Serial
pio device monitor
```

Если `pio` не найден, используйте bootstrap-скрипт выше: он автоматически
устанавливает PlatformIO CLI в изолированное окружение и проверяет доступность
команды.

## � Поддерживаемые датчики

### V802 (HC-SR04 + FT232RL)
| Параметр | Значение |
|----------|----------|
| Чип USB | FT232RL (VID: 0x0403, PID: 0x6001) |
| Скорость порта | 9600 бод |
| Формат данных | `173 cm` (число + "cm") |
| Единица измерения | Сантиметры → конвертируется в мм |

### ESP32-S3 Мультидатчик
- VL53L1X — Лазерный дальномер (0-4000 мм)
- INA226 — Вольтметр/Амперметр
- BME280 — Температура/Давление/Влажность
- LSM6DS3 — Акселерометр/Гироскоп

## 📁 Структура проекта

```
lib/                          # Flutter-приложение
├── data/hal/                 # Hardware Abstraction Layer
│   ├── mock_hal.dart         # Симуляция для разработки
│   ├── usb_hal_windows.dart  # USB подключение и recovery логика для desktop
│   └── ble_hal.dart          # BLE подключение (framed binary packet v1)
├── domain/
│   ├── entities/             # Модели данных
│   └── math/                 # LTTB, статистика
└── presentation/
    ├── pages/                # Экраны
    └── widgets/              # UI-компоненты

firmware/                     # Прошивка ESP32-S3
├── src/
│   ├── core/                 # Конфигурация, буферы
│   ├── sensors/              # Драйверы датчиков
│   └── connectivity/         # BLE, Wi-Fi, Web
├── data/                     # Web UI (SPIFFS)
└── proto/                    # Protobuf схемы

tools/
└── sensor-debug.html         # Отладка USB-датчиков в браузере
```

## 🔐 Статус протокола

- USB/Serial legacy-датчики работают через текстовый поток, совместимый с текущими HAL-парсерами.
- ESP32-S3 мультидатчик по BLE сейчас использует **framed binary packet v1**.
- [firmware/proto/sensor_data.proto](firmware/proto/sensor_data.proto) сохраняется как логическая схема полей и база для дальнейшего расширения протокола.
- В прошивке transport queue BLE и history buffer для Web UI/CSV разделены: Web fallback не теряет историю при активном BLE-клиенте.

## 🎯 Режимы работы

| Режим | Описание |
|-------|----------|
| **Табло** | Крупное число для проектора |
| **График** | Y(t) в реальном времени |
| **Таблица** | Числовые данные |

## 🔧 Режимы подключения

В приложении есть переключатель режима HAL (иконка в AppBar):

| Режим | Иконка | Описание |
|-------|--------|----------|
| Симуляция | 🛠️ | Генерирует тестовые данные |
| USB (V802) | 🔌 | Датчик V802 через USB |
| Bluetooth | 📶 | ESP32-S3 через BLE |

## 🧪 Тестирование

```bash
# Unit-тесты
flutter test

# Конкретный тест
flutter test test/unit/math/lttb_test.dart
```

## 📄 Документация

- [ARCHITECTURE.md](ARCHITECTURE.md) — Полная архитектура системы
- [.github/copilot-instructions.md](.github/copilot-instructions.md) — Инструкции для AI-агентов

## 📝 Лицензия

Proprietary © 2026
