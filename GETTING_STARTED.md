# 🚀 С ЧЕГО НАЧАТЬ — Конкретные шаги

## 📌 НЕДЕЛЯ 1: Настройка инфраструктуры

### День 1-2: Инициализация проекта

```bash
# 1. Создать monorepo с Turborepo
npx create-turbo@latest digital-lab-workspace

# 2. Структура проекта
digital-lab-workspace/
├── apps/
│   └── student-app/          # React + TypeScript + Vite
├── packages/
│   ├── ui/                   # Компоненты UI
│   ├── core/                 # Ядро системы
│   └── sensors/              # Модули датчиков
└── firmware/                 # Прошивки Arduino

# 3. Установить зависимости
cd apps/student-app
npm install
npm install -D typescript @types/node @types/react @types/react-dom
npm install tailwindcss postcss autoprefixer
npm install zustand
npm install recharts
npm install lucide-react # иконки
```

### День 3: Настроить TailwindCSS + shadcn/ui

```bash
# Инициализация Tailwind
npx tailwindcss init -p

# Установка shadcn/ui
npx shadcn-ui@latest init

# Добавить первые компоненты
npx shadcn-ui@latest add button
npx shadcn-ui@latest add card
npx shadcn-ui@latest add tabs
npx shadcn-ui@latest add select
npx shadcn-ui@latest add dialog
```

### День 4-5: Создать базовую структуру

```
apps/student-app/src/
├── pages/
│   ├── Home.tsx
│   ├── Connect.tsx
│   └── Experiment.tsx
├── components/
│   ├── Layout/
│   │   ├── MainLayout.tsx
│   │   └── Sidebar.tsx
│   ├── Device/
│   │   ├── DeviceConnector.tsx
│   │   └── DeviceStatus.tsx
│   └── Chart/
│       └── RealtimeChart.tsx
├── lib/
│   ├── device-manager.ts
│   └── utils.ts
├── hooks/
│   ├── useDevice.ts
│   └── useSerialPort.ts
└── App.tsx
```

---

## 📌 НЕДЕЛЯ 2: Device Manager (Web Serial API)

### Создать `packages/core/device-manager/`

**1. SerialConnection.ts**
```typescript
export class SerialConnection {
  private port: SerialPort | null = null;
  private reader: ReadableStreamDefaultReader | null = null;
  
  async connect(baudRate: number = 115200) {
    // Запрос порта
    this.port = await navigator.serial.requestPort();
    
    // Открытие
    await this.port.open({
      baudRate,
      dataBits: 8,
      stopBits: 1,
      parity: 'none',
      flowControl: 'none'
    });
  }
  
  async disconnect() {
    // Закрытие порта
  }
  
  async read(): Promise<string> {
    // Чтение данных
  }
  
  async write(data: string) {
    // Запись данных
  }
}
```

**2. DeviceManager.ts**
```typescript
import { SerialConnection } from './SerialConnection';

export class DeviceManager {
  private connection: SerialConnection;
  private devices: Map<string, Device> = new Map();
  
  async connectDevice() {
    await this.connection.connect();
    // Определить тип устройства
    // Зарегистрировать в devices
  }
  
  async getDeviceData() {
    // Получить данные от устройства
  }
}
```

**3. Хук useDevice.ts**
```typescript
import { useState, useEffect } from 'react';
import { DeviceManager } from '@/lib/device-manager';

export function useDevice() {
  const [connected, setConnected] = useState(false);
  const [data, setData] = useState(null);
  const [manager] = useState(() => new DeviceManager());
  
  const connect = async () => {
    await manager.connectDevice();
    setConnected(true);
  };
  
  const disconnect = async () => {
    await manager.disconnect();
    setConnected(false);
  };
  
  return { connected, data, connect, disconnect };
}
```

---

## 📌 НЕДЕЛЯ 3: Первый датчик (Distance Sensor)

### Arduino прошивка

**distance-sensor.ino**
```cpp
#include <Wire.h>
#include <VL53L0X.h>
#include <ArduinoJson.h>

VL53L0X sensor;

void setup() {
  Serial.begin(115200);
  
  Wire.begin();
  sensor.init();
  sensor.setTimeout(500);
  
  // Отправить информацию о датчике
  sendDeviceInfo();
}

void loop() {
  uint16_t distance = sensor.readRangeSingleMillimeters();
  
  if (sensor.timeoutOccurred()) {
    sendError("Timeout");
  } else {
    sendData(distance);
  }
  
  delay(100); // 10 Hz
}

void sendData(uint16_t distance) {
  StaticJsonDocument<200> doc;
  
  doc["device"] = "distance-sensor";
  doc["id"] = "DS001";
  doc["version"] = "1.0.0";
  doc["timestamp"] = millis();
  
  JsonObject data = doc.createNestedObject("data");
  data["value"] = distance / 10.0; // мм -> см
  data["unit"] = "cm";
  data["raw"] = distance;
  
  doc["status"] = "ok";
  
  serializeJson(doc, Serial);
  Serial.println();
}

void sendDeviceInfo() {
  StaticJsonDocument<200> doc;
  
  doc["type"] = "device-info";
  doc["device"] = "distance-sensor";
  doc["name"] = "VL53L0X Distance Sensor";
  doc["version"] = "1.0.0";
  doc["capabilities"] = "distance";
  
  serializeJson(doc, Serial);
  Serial.println();
}

void sendError(const char* message) {
  StaticJsonDocument<200> doc;
  doc["status"] = "error";
  doc["message"] = message;
  serializeJson(doc, Serial);
  Serial.println();
}
```

### TypeScript модуль

**packages/sensors/distance/DistanceSensor.ts**
```typescript
import { Sensor } from '../sensor-base/Sensor';

export class DistanceSensor extends Sensor {
  name = 'Distance Sensor';
  unit = 'cm';
  minValue = 0;
  maxValue = 200;
  
  parseData(raw: string): number {
    const json = JSON.parse(raw);
    return json.data.value;
  }
  
  async calibrate(referenceDistance: number) {
    // Калибровка
  }
}
```

---

## 📌 НЕДЕЛЯ 4: UI и первый эксперимент

### Компонент подключения датчика

**DeviceConnector.tsx**
```typescript
import { Button } from '@/components/ui/button';
import { useDevice } from '@/hooks/useDevice';

export function DeviceConnector() {
  const { connected, connect, disconnect } = useDevice();
  
  return (
    <div className="p-4">
      {!connected ? (
        <Button onClick={connect}>
          📡 Подключить датчик
        </Button>
      ) : (
        <Button onClick={disconnect} variant="destructive">
          ⏹ Отключить
        </Button>
      )}
    </div>
  );
}
```

### График в реальном времени

**RealtimeChart.tsx**
```typescript
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip } from 'recharts';
import { useState, useEffect } from 'react';

export function RealtimeChart({ data }: { data: number[] }) {
  const chartData = data.map((value, index) => ({
    time: index,
    value
  }));
  
  return (
    <LineChart width={800} height={400} data={chartData}>
      <CartesianGrid strokeDasharray="3 3" />
      <XAxis dataKey="time" label={{ value: 'Время (с)', position: 'insideBottom', offset: -5 }} />
      <YAxis label={{ value: 'Расстояние (см)', angle: -90, position: 'insideLeft' }} />
      <Tooltip />
      <Line type="monotone" dataKey="value" stroke="#00d9ff" strokeWidth={2} dot={false} />
    </LineChart>
  );
}
```

### Первый эксперимент: Свободное падение

**FreeFall.tsx**
```typescript
import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { RealtimeChart } from '@/components/Chart/RealtimeChart';

export function FreeFallExperiment() {
  const [measuring, setMeasuring] = useState(false);
  const [data, setData] = useState<number[]>([]);
  const [result, setResult] = useState<number | null>(null);
  
  const startMeasurement = () => {
    setMeasuring(true);
    setData([]);
    // Начать запись данных
  };
  
  const stopMeasurement = () => {
    setMeasuring(false);
    // Рассчитать g
    const g = calculateG(data);
    setResult(g);
  };
  
  const calculateG = (distances: number[]): number => {
    // h = (1/2) * g * t^2
    // g = 2h / t^2
    // Используем линейную регрессию
    return 9.81; // упрощённо
  };
  
  return (
    <div className="p-8">
      <h1 className="text-3xl font-bold mb-4">Свободное падение</h1>
      
      <Card className="p-6 mb-4">
        <h2 className="text-xl mb-2">Инструкция:</h2>
        <ol className="list-decimal ml-6 space-y-2">
          <li>Установите датчик расстояния вертикально</li>
          <li>Подготовьте предмет для сброса</li>
          <li>Нажмите "Начать измерение"</li>
          <li>Отпустите предмет</li>
          <li>Нажмите "Остановить" после падения</li>
        </ol>
      </Card>
      
      <div className="flex gap-4 mb-6">
        {!measuring ? (
          <Button onClick={startMeasurement}>▶️ Начать измерение</Button>
        ) : (
          <Button onClick={stopMeasurement} variant="destructive">⏹ Остановить</Button>
        )}
      </div>
      
      <Card className="p-6 mb-4">
        <h3 className="text-lg mb-4">График расстояния от времени</h3>
        <RealtimeChart data={data} />
      </Card>
      
      {result && (
        <Card className="p-6 bg-green-50">
          <h3 className="text-xl font-bold mb-2">Результат:</h3>
          <p className="text-3xl">g = {result.toFixed(2)} м/с²</p>
          <p className="text-gray-600 mt-2">
            Теоретическое значение: 9.81 м/с²<br/>
            Погрешность: {((Math.abs(result - 9.81) / 9.81) * 100).toFixed(1)}%
          </p>
        </Card>
      )}
    </div>
  );
}
```

---

## 🎯 КРИТИЧНЫЕ ЗАДАЧИ ПЕРВЫХ 2 НЕДЕЛЬ

### ✅ Чек-лист Must-Do

**Техническое:**
- [ ] Monorepo настроен (Turborepo)
- [ ] React + TypeScript + Vite работает
- [ ] TailwindCSS + shadcn/ui установлены
- [ ] Web Serial API подключение работает
- [ ] Чтение данных от Arduino работает
- [ ] Парсинг JSON-сообщений работает

**Датчики:**
- [ ] VL53L0X датчик куплен/доставлен
- [ ] Arduino Nano настроен
- [ ] Прошивка залита и тестирована
- [ ] Датчик отправляет JSON

**UI:**
- [ ] Базовые компоненты (Button, Card, etc.)
- [ ] Страница подключения датчика
- [ ] График реал-тайм
- [ ] Отображение текущего значения

---

## 💡 БЫСТРЫЙ СТАРТ (За 1 день)

Если нужно ОЧЕНЬ быстро начать, вот минимальная версия:

### 1. Один HTML-файл (улучшенный)

```html
<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="UTF-8">
  <title>Digital Lab MVP</title>
  <script src="https://cdn.tailwindcss.com"></script>
  <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
</head>
<body class="bg-gray-900 text-white p-8">
  <div class="max-w-4xl mx-auto">
    <h1 class="text-4xl font-bold mb-8">🔬 Цифровая лаборатория MVP</h1>
    
    <div class="bg-gray-800 p-6 rounded-lg mb-6">
      <button id="connectBtn" class="bg-blue-500 px-6 py-3 rounded-lg font-bold hover:bg-blue-600">
        📡 Подключить датчик
      </button>
      <div id="status" class="mt-4 text-2xl">⏳ Не подключено</div>
    </div>
    
    <div class="bg-gray-800 p-6 rounded-lg mb-6">
      <h2 class="text-2xl mb-4">📊 Текущее значение</h2>
      <div id="value" class="text-6xl font-bold text-blue-400">--</div>
    </div>
    
    <div class="bg-gray-800 p-6 rounded-lg">
      <h2 class="text-2xl mb-4">📈 График</h2>
      <canvas id="chart"></canvas>
    </div>
  </div>
  
  <script>
    // Здесь ваш существующий код из sensor-test.html
    // + добавить Chart.js для красивых графиков
  </script>
</body>
</html>
```

### 2. Постепенная миграция

Затем постепенно:
- День 2-3: Разбить на компоненты
- День 4-5: Добавить TypeScript
- День 6-7: Переехать на React

---

## 📦 ЧТО КУПИТЬ (Оборудование для старта)

### Минимальный набор для MVP (~$50-70)
- 🔌 Arduino Nano x3 — $15 ($5 каждый)
- 📏 VL53L0X ToF датчик расстояния x2 — $10
- 🌡️ DS18B20 термометр x3 — $9
- 💡 BH1750 датчик света x2 — $6
- 🔗 USB кабели Mini-USB x3 — $6
- 📦 Breadboard + провода — $10
- 🧰 Корпуса 3D-printed — $15

### Для production (~$200-300)
- ESP32 модули (WiFi/BT)
- Качественные разъёмы
- PCB производство
- Профессиональные корпуса

---

## 🎓 ОБУЧЕНИЕ КОМАНДЫ

### Frontend разработчикам изучить:
- [ ] Web Serial API (MDN docs)
- [ ] React + TypeScript best practices
- [ ] TailwindCSS
- [ ] Chart.js / Recharts
- [ ] State management (Zustand)

### Hardware инженеру изучить:
- [ ] Arduino basics
- [ ] I2C/SPI протоколы
- [ ] JSON сериализация (ArduinoJson)
- [ ] Датчики (даташиты)

---

## 📚 ПОЛЕЗНЫЕ ССЫЛКИ

**Технологии:**
- Web Serial API: https://developer.mozilla.org/en-US/docs/Web/API/Web_Serial_API
- React: https://react.dev
- TailwindCSS: https://tailwindcss.com
- shadcn/ui: https://ui.shadcn.com
- Recharts: https://recharts.org

**Датчики:**
- VL53L0X: https://www.pololu.com/product/2490
- DS18B20: https://www.analog.com/en/products/ds18b20.html
- BH1750: https://www.mouser.com/datasheet/2/348/bh1750fvi-e-186247.pdf

**Конкуренты:**
- Releon: https://releon.ru
- L-микро: https://lmicro.ru
- Vernier: https://www.vernier.com
- PASCO: https://www.pasco.com

---

## ❓ FAQ — Частые вопросы

**Q: Почему Web Serial API, а не Electron?**
A: Проще, легче, кроссплатформенно. Electron можно добавить позже.

**Q: Почему React, а не Vue/Svelte?**
A: Больше библиотек, больше разработчиков, лучше ecosystem.

**Q: Почему Arduino, а не ESP32 сразу?**
A: Проще для прототипирования. ESP32 добавим в фазе 2.

**Q: Как хранить данные?**
A: Фаза 1 — IndexedDB (локально), Фаза 2 — PostgreSQL (облако).

**Q: Нужен ли backend?**
A: Не обязательно для MVP. Можно использовать Supabase/Firebase.

---

**Следующий шаг:** Выбрать один из подходов выше и начать! 🚀
