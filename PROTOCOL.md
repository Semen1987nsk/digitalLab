# 🔌 ПРОТОКОЛ СВЯЗИ — Техническая спецификация

> Важно: этот документ содержит legacy-описание раннего USB/JSON протокола.
>
> Актуальный production runtime на March 2026:
> - legacy USB/Serial sensors: текстовый поток / строковый протокол
> - ESP32-S3 multisensor over BLE: **framed binary packet v1**
>
> Для актуального BLE-потока ориентируйтесь на [ARCHITECTURE.md](ARCHITECTURE.md), [firmware/proto/sensor_data.proto](firmware/proto/sensor_data.proto) и runtime-код в [lib/data/hal/ble_hal.dart](lib/data/hal/ble_hal.dart).

## 📋 Общие принципы

### Транспорт
- **Физический уровень:** USB (Serial)
- **Скорость:** 115200 baud (по умолчанию)
- **Формат:** JSON (текстовый)
- **Кодировка:** UTF-8
- **Разделитель сообщений:** `\n` (newline)

### Направления связи
```
PC ←→ Датчик
```
- **PC → Датчик:** Команды (start, stop, calibrate, etc.)
- **Датчик → PC:** Данные измерений, статусы, ошибки

---

## 📤 ФОРМАТ ДАННЫХ (Датчик → PC)

### 1. Данные измерений

```json
{
  "type": "measurement",
  "device": "distance-sensor",
  "id": "DS001",
  "version": "1.0.0",
  "timestamp": 1738000000,
  "data": {
    "value": 42.5,
    "unit": "cm",
    "quality": 95,
    "raw": 425
  },
  "status": "ok"
}
```

**Поля:**
- `type` — тип сообщения (`measurement`, `status`, `error`, `info`)
- `device` — тип датчика (`distance-sensor`, `temperature-sensor`, etc.)
- `id` — уникальный ID конкретного датчика (опционально)
- `version` — версия прошивки
- `timestamp` — время измерения (millis() или Unix timestamp)
- `data` — объект с данными:
  - `value` — значение в основных единицах
  - `unit` — единица измерения (`cm`, `°C`, `lux`, etc.)
  - `quality` — качество сигнала 0-100% (опционально)
  - `raw` — сырое значение с АЦП (опционально)
- `status` — состояние (`ok`, `warning`, `error`)

### 2. Статус устройства

```json
{
  "type": "status",
  "device": "distance-sensor",
  "id": "DS001",
  "status": "ready",
  "battery": 87,
  "temperature": 25.3,
  "uptime": 3600000
}
```

**Состояния:**
- `initializing` — инициализация
- `ready` — готов к работе
- `measuring` — идёт измерение
- `calibrating` — калибровка
- `error` — ошибка
- `sleep` — режим сна

### 3. Информация о датчике (при подключении)

```json
{
  "type": "device-info",
  "device": "distance-sensor",
  "id": "DS001",
  "name": "VL53L0X Distance Sensor",
  "version": "1.0.0",
  "firmware": "2026-01-26",
  "capabilities": ["distance", "ambient"],
  "parameters": {
    "minRange": 0,
    "maxRange": 200,
    "resolution": 0.1,
    "frequency": [1, 10, 50, 100]
  }
}
```

### 4. Ошибки

```json
{
  "type": "error",
  "device": "distance-sensor",
  "id": "DS001",
  "error": {
    "code": "SENSOR_TIMEOUT",
    "message": "Sensor not responding",
    "severity": "critical"
  },
  "timestamp": 1738000000
}
```

**Коды ошибок:**
- `SENSOR_NOT_FOUND` — датчик не найден
- `SENSOR_TIMEOUT` — таймаут датчика
- `CALIBRATION_FAILED` — ошибка калибровки
- `OUT_OF_RANGE` — значение вне диапазона
- `LOW_BATTERY` — низкий заряд батареи

---

## 📥 ФОРМАТ КОМАНД (PC → Датчик)

### 1. Начать измерения

```json
{
  "cmd": "start",
  "params": {
    "frequency": 10,
    "duration": 60,
    "mode": "continuous"
  }
}
```

**Параметры:**
- `frequency` — частота измерений (Hz)
- `duration` — длительность (секунды), 0 = бесконечно
- `mode` — режим:
  - `continuous` — непрерывно
  - `triggered` — по триггеру
  - `burst` — пакетами

### 2. Остановить измерения

```json
{
  "cmd": "stop"
}
```

### 3. Калибровка

```json
{
  "cmd": "calibrate",
  "params": {
    "reference": 50.0,
    "points": [
      {"reference": 10, "measured": 10.2},
      {"reference": 50, "measured": 50.1},
      {"reference": 100, "measured": 99.8}
    ]
  }
}
```

### 4. Получить информацию

```json
{
  "cmd": "get_info"
}
```

### 5. Настройка параметров

```json
{
  "cmd": "set_config",
  "params": {
    "sensitivity": "high",
    "filter": "median",
    "averaging": 5
  }
}
```

### 6. Сброс настроек

```json
{
  "cmd": "reset",
  "params": {
    "type": "soft"
  }
}
```

**Типы сброса:**
- `soft` — перезагрузка без сброса настроек
- `hard` — полный сброс к заводским настройкам

### 7. Режим сна

```json
{
  "cmd": "sleep",
  "params": {
    "duration": 300
  }
}
```

---

## 📊 ТИПЫ ДАТЧИКОВ И ИХ ДАННЫЕ

### 1. Датчик расстояния

```json
{
  "device": "distance-sensor",
  "data": {
    "value": 42.5,
    "unit": "cm",
    "ambient": 250
  }
}
```

### 2. Датчик температуры

```json
{
  "device": "temperature-sensor",
  "data": {
    "value": 23.4,
    "unit": "°C",
    "humidity": 45.2
  }
}
```

### 3. Датчик света

```json
{
  "device": "light-sensor",
  "data": {
    "value": 1234,
    "unit": "lux",
    "spectrum": {
      "visible": 1000,
      "ir": 234
    }
  }
}
```

### 4. Датчик давления

```json
{
  "device": "pressure-sensor",
  "data": {
    "value": 1013.25,
    "unit": "hPa",
    "altitude": 150,
    "temperature": 22.1
  }
}
```

### 5. Микрофон

```json
{
  "device": "sound-sensor",
  "data": {
    "value": 65,
    "unit": "dB",
    "frequency": 440,
    "peak": 72
  }
}
```

### 6. Акселерометр

```json
{
  "device": "motion-sensor",
  "data": {
    "x": 0.02,
    "y": 0.01,
    "z": 9.81,
    "unit": "m/s²"
  }
}
```

---

## ⚡ ОПТИМИЗАЦИЯ И ПРОИЗВОДИТЕЛЬНОСТЬ

### Batch-режим (пакетная отправка)

Для высокочастотных измерений (>50 Hz) отправлять пакетами:

```json
{
  "type": "batch",
  "device": "motion-sensor",
  "id": "MS001",
  "count": 100,
  "startTime": 1738000000,
  "interval": 10,
  "data": [
    {"x": 0.02, "y": 0.01, "z": 9.81},
    {"x": 0.03, "y": 0.02, "z": 9.80},
    ...
  ]
}
```

### Компактный формат (для low-bandwidth)

```json
{
  "d": "ds",
  "v": 42.5,
  "u": "cm",
  "t": 1738000000
}
```

Сокращения:
- `d` → `device`
- `v` → `value`
- `u` → `unit`
- `t` → `timestamp`

---

## 🔒 БЕЗОПАСНОСТЬ И ВАЛИДАЦИЯ

### Валидация на стороне датчика

```cpp
bool validateCommand(JsonObject cmd) {
  if (!cmd.containsKey("cmd")) return false;
  
  String cmdType = cmd["cmd"];
  if (cmdType != "start" && cmdType != "stop" && 
      cmdType != "calibrate" && cmdType != "get_info" &&
      cmdType != "set_config" && cmdType != "reset") {
    return false;
  }
  
  return true;
}
```

### Валидация на стороне PC

```typescript
interface Measurement {
  type: 'measurement';
  device: string;
  timestamp: number;
  data: {
    value: number;
    unit: string;
  };
  status: 'ok' | 'warning' | 'error';
}

function validateMeasurement(msg: unknown): msg is Measurement {
  const m = msg as Measurement;
  return (
    m.type === 'measurement' &&
    typeof m.device === 'string' &&
    typeof m.timestamp === 'number' &&
    typeof m.data?.value === 'number' &&
    typeof m.data?.unit === 'string' &&
    ['ok', 'warning', 'error'].includes(m.status)
  );
}
```

---

## 🧪 ПРИМЕРЫ ИСПОЛЬЗОВАНИЯ

### Arduino → PC (непрерывные измерения)

```cpp
void loop() {
  if (measuring) {
    float value = readSensor();
    sendMeasurement(value);
    delay(100); // 10 Hz
  }
  
  // Обработка команд
  if (Serial.available()) {
    String command = Serial.readStringUntil('\n');
    processCommand(command);
  }
}

void sendMeasurement(float value) {
  StaticJsonDocument<256> doc;
  doc["type"] = "measurement";
  doc["device"] = "distance-sensor";
  doc["timestamp"] = millis();
  doc["data"]["value"] = value;
  doc["data"]["unit"] = "cm";
  doc["status"] = "ok";
  
  serializeJson(doc, Serial);
  Serial.println();
}

void processCommand(String cmd) {
  StaticJsonDocument<256> doc;
  DeserializationError error = deserializeJson(doc, cmd);
  
  if (error) {
    sendError("Invalid JSON");
    return;
  }
  
  String cmdType = doc["cmd"];
  
  if (cmdType == "start") {
    measuring = true;
    frequency = doc["params"]["frequency"] | 10;
  } else if (cmdType == "stop") {
    measuring = false;
  } else if (cmdType == "calibrate") {
    float reference = doc["params"]["reference"];
    calibrate(reference);
  }
}
```

### PC → Arduino (отправка команды)

```typescript
async function startMeasurement(frequency: number = 10) {
  const command = {
    cmd: 'start',
    params: {
      frequency,
      mode: 'continuous'
    }
  };
  
  const writer = port.writable.getWriter();
  const encoder = new TextEncoder();
  const data = JSON.stringify(command) + '\n';
  
  await writer.write(encoder.encode(data));
  writer.releaseLock();
}
```

### PC (чтение данных)

```typescript
async function readData() {
  const reader = port.readable.getReader();
  const decoder = new TextDecoder();
  let buffer = '';
  
  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    
    buffer += decoder.decode(value);
    
    const lines = buffer.split('\n');
    buffer = lines.pop() || '';
    
    for (const line of lines) {
      if (!line.trim()) continue;
      
      try {
        const msg = JSON.parse(line);
        handleMessage(msg);
      } catch (e) {
        console.error('Parse error:', e);
      }
    }
  }
}

function handleMessage(msg: any) {
  switch (msg.type) {
    case 'measurement':
      updateChart(msg.data.value);
      break;
    case 'status':
      updateStatus(msg.status);
      break;
    case 'error':
      showError(msg.error.message);
      break;
  }
}
```

---

## 📡 ОБРАБОТКА ОШИБОК

### На стороне датчика

```cpp
void sendError(const char* code, const char* message) {
  StaticJsonDocument<256> doc;
  doc["type"] = "error";
  doc["device"] = DEVICE_TYPE;
  doc["error"]["code"] = code;
  doc["error"]["message"] = message;
  doc["error"]["severity"] = "critical";
  doc["timestamp"] = millis();
  
  serializeJson(doc, Serial);
  Serial.println();
}

// Примеры использования
if (!sensor.init()) {
  sendError("SENSOR_NOT_FOUND", "Could not initialize sensor");
}

if (sensor.timeoutOccurred()) {
  sendError("SENSOR_TIMEOUT", "Sensor did not respond");
}
```

### На стороне PC

```typescript
function handleError(error: ErrorMessage) {
  switch (error.error.code) {
    case 'SENSOR_NOT_FOUND':
      showToast('Датчик не найден. Проверьте подключение.', 'error');
      break;
    case 'SENSOR_TIMEOUT':
      showToast('Датчик не отвечает. Попробуйте переподключить.', 'error');
      break;
    case 'CALIBRATION_FAILED':
      showToast('Ошибка калибровки. Повторите процедуру.', 'warning');
      break;
    default:
      showToast(`Ошибка: ${error.error.message}`, 'error');
  }
  
  // Логирование
  console.error('[Device Error]', error);
  logToServer(error);
}
```

---

## 🚀 РАСШИРЕНИЯ ПРОТОКОЛА

### Версионирование

```json
{
  "protocol": "1.0",
  "type": "measurement",
  ...
}
```

### Мультидатчики (несколько на одном устройстве)

```json
{
  "type": "measurement",
  "device": "multi-sensor",
  "sensors": {
    "temperature": {"value": 23.4, "unit": "°C"},
    "humidity": {"value": 45, "unit": "%"},
    "pressure": {"value": 1013, "unit": "hPa"}
  }
}
```

### Streaming (для аудио/видео)

```json
{
  "type": "stream",
  "device": "microphone",
  "format": "pcm",
  "sampleRate": 44100,
  "channels": 1,
  "chunk": "base64_encoded_data"
}
```

---

## 🧪 ТЕСТИРОВАНИЕ ПРОТОКОЛА

### Скрипт для тестирования (Python)

```python
import serial
import json
import time

ser = serial.Serial('/dev/ttyUSB0', 115200, timeout=1)

# Отправка команды
def send_command(cmd, params=None):
    message = {'cmd': cmd}
    if params:
        message['params'] = params
    ser.write((json.dumps(message) + '\n').encode())

# Чтение данных
def read_data():
    line = ser.readline().decode().strip()
    if line:
        try:
            return json.loads(line)
        except:
            print(f"Parse error: {line}")
    return None

# Тест
send_command('start', {'frequency': 10})
time.sleep(5)

for _ in range(50):
    data = read_data()
    if data:
        print(f"Value: {data['data']['value']} {data['data']['unit']}")

send_command('stop')
```

---

**Версия протокола:** 1.0  
**Дата:** 26 января 2026  
**Статус:** Stable
