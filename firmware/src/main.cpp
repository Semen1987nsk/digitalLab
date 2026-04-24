/**
 * Цифровая Лаборатория - Прошивка ESP32-S3
 * 
 * Архитектура:
 * - Core 0: BLE, Wi-Fi, WebServer, OTA
 * - Core 1: Опрос датчиков, DSP, буферизация
 * 
 * Датчики:
 * - VL53L1X: Лазерный дальномер (I2C)
 * - INA226: Вольтметр/Амперметр (I2C)
 * - BME280: Температура/Давление/Влажность (I2C)
 * - LSM6DS3: Акселерометр/Гироскоп (I2C)
 * - MAX31855: Термопара (SPI)
 */

#include <Arduino.h>
#include <Wire.h>
#include <SPI.h>
#include <NimBLEDevice.h>
#include <esp_task_wdt.h>
#include <esp_wifi.h>
#include <WiFi.h>
#include <ESPAsyncWebServer.h>
#include <SPIFFS.h>
#include <nvs_flash.h>
#include <cstdio>
#include <cstring>
#include <atomic>

#include "core/config.h"
#include "core/ring_buffer.h"
#include "sensors/sensor_drivers.h"

// Глобальные объекты
RingBuffer<SensorPacket, BLE_TX_BUFFER_SIZE> g_bleTxBuffer;
RingBuffer<SensorPacket, HISTORY_BUFFER_SIZE> g_historyBuffer;
SemaphoreHandle_t g_i2cMutex = nullptr;

// Драйверы датчиков (глобальные — инициализируются в initSensors())
static BME280Driver   g_bme280;
static INA226Driver   g_ina226;
static LSM6DS3Driver  g_lsm6ds3;
static VL53L1XDriver  g_vl53l1x;
static MAX31855Driver g_max31855;

// Web-сервер (ESPAsyncWebServer — async, no FreeRTOS task needed)
static AsyncWebServer g_webServer(80);

// Состояние системы (std::atomic для безопасного доступа между ядрами)
std::atomic<bool> g_measuring{false};
std::atomic<uint32_t> g_sampleRateHz{DEFAULT_SAMPLE_RATE_HZ};
std::atomic<uint32_t> g_startTimeMs{0};

// ── Deferred command queue (connectivity → sensor task) ──────
// Commands that require I2C (CALIBRATE) are enqueued here
// and executed by sensor task on Core 1, not in BLE/Web callbacks.
enum class SensorCommand : uint8_t {
    CALIBRATE_INA226 = 1,
};
static QueueHandle_t g_sensorCmdQueue = nullptr;

// ── BLE send health counters ─────────────────────────────────
static std::atomic<uint32_t> g_bleNotifyDrops{0};
static std::atomic<uint32_t> g_bleNotifyOk{0};

// Прототипы функций
void taskSensorPolling(void* param);
void taskBleServer(void* param);
void taskWebServer(void* param);
void initSensors();
void initBle();
void initWifi();
void updateBleStatusCharacteristics();

/// CRC8 (Dallas/Maxim, polynomial 0x31 reflected).
/// Must match crc8() in Flutter app (usb_hal_windows.dart, ble_hal.dart).
static uint8_t crc8(const uint8_t* data, size_t len) {
    uint8_t crc = 0x00;
    for (size_t i = 0; i < len; i++) {
        uint8_t b = data[i];
        for (int bit = 0; bit < 8; bit++) {
            if ((crc ^ b) & 0x01) {
                crc = (crc >> 1) ^ 0x8C;
            } else {
                crc >>= 1;
            }
            b >>= 1;
        }
    }
    return crc;
}

/// Generates a unique Wi-Fi password from the full ESP32 MAC address.
/// Format: "Lab_XXXXXXXX" — 8 hex chars from MAC[2..5] = 4 billion combos.
/// Previous "Lab_XXXX" (16-bit) had only 65K combos — trivially brute-forced.
/// Printed on device label for teacher convenience.
static String generateWifiPassword() {
    uint8_t mac[6];
    esp_read_mac(mac, ESP_MAC_WIFI_SOFTAP);
    char pwd[16];
    snprintf(pwd, sizeof(pwd), "Lab_%02X%02X%02X%02X", mac[2], mac[3], mac[4], mac[5]);
    return String(pwd);
}

/// Watchdog timeout for sensor task (seconds).
/// If I2C bus hangs (common with cheap Chinese sensors), ESP32
/// will auto-reboot instead of sending stale data forever.
static constexpr uint32_t kWatchdogTimeoutSec = 10;

// ─────────────────────────────────────────────────────────────
//  Battery ADC
// ─────────────────────────────────────────────────────────────

/// Reads battery voltage via ADC and returns percentage (0–100).
///
/// Hardware: voltage divider (BATTERY_DIVIDER) feeds BATTERY_ADC_PIN.
/// ESP32-S3 ADC: 12-bit (0–4095), reference ~3.3V (with attenuation).
/// LiPo profile: 4.2V = 100%, 3.0V = 0% (linear approximation).
///
/// Smoothing: 16-sample average to filter ADC noise.
static uint8_t readBatteryPercent() {
    static constexpr float kVref = 3.3f;
    static constexpr int   kAdcMax = 4095;
    static constexpr float kBattFull = 4.2f;   // LiPo fully charged
    static constexpr float kBattEmpty = 3.0f;  // LiPo cutoff
    static constexpr int   kSamples = 16;

    uint32_t sum = 0;
    for (int i = 0; i < kSamples; i++) {
        sum += analogRead(BATTERY_ADC_PIN);
    }
    float adcAvg = static_cast<float>(sum) / kSamples;

    // ADC voltage → real battery voltage (through divider)
    float vBatt = (adcAvg / kAdcMax) * kVref * BATTERY_DIVIDER;

    // Clamp and convert to 0–100%
    float pct = (vBatt - kBattEmpty) / (kBattFull - kBattEmpty) * 100.0f;
    if (pct > 100.0f) pct = 100.0f;
    if (pct < 0.0f) pct = 0.0f;

    return static_cast<uint8_t>(pct);
}

extern "C" {
    void startMeasurement();
    void stopMeasurement();
    void setSampleRate(uint32_t hz);
}

// BLE runtime
NimBLEServer* g_bleServer = nullptr;
NimBLEService* g_bleService = nullptr;
NimBLECharacteristic* g_dataChar = nullptr;
NimBLECharacteristic* g_commandChar = nullptr;
NimBLECharacteristic* g_configChar = nullptr;
NimBLECharacteristic* g_firmwareChar = nullptr;
std::atomic<bool> g_bleClientConnected{false};

constexpr uint16_t kPacketMagic = 0x4C50;  // "LP" (Labosfera Protocol)
constexpr uint8_t kPacketProtocolVersion = 1;
constexpr uint8_t kPayloadSize = sizeof(SensorPacket); // 80 bytes

struct __attribute__((packed)) FramedSensorPacket {
    uint16_t magic;           // kPacketMagic (0x4C50)
    uint8_t protocolVersion;  // kPacketProtocolVersion (1)
    uint8_t payloadSize;      // kPayloadSize (80)
    SensorPacket payload;
};

static_assert(sizeof(SensorPacket) == 80, "SensorPacket size must be 80 bytes");
static_assert(sizeof(FramedSensorPacket) == 84, "FramedSensorPacket size must be 84 bytes");

class PhysicsLabServerCallbacks : public NimBLEServerCallbacks {
public:
    void onConnect(NimBLEServer* server) {
        g_bleClientConnected = true;
        Serial.println("[BLE] Client connected");
        (void)server;
    }

    void onDisconnect(NimBLEServer* server) {
        g_bleClientConnected = false;
        Serial.println("[BLE] Client disconnected, advertising restart");
        NimBLEDevice::startAdvertising();
        (void)server;
    }
};

class PhysicsLabCommandCallbacks : public NimBLECharacteristicCallbacks {
public:
    void onWrite(NimBLECharacteristic* characteristic) {
        const std::string value = characteristic->getValue();
        if (value.empty()) {
            return;
        }

        const uint8_t* data = reinterpret_cast<const uint8_t*>(value.data());
        const size_t len = value.size();

        // ── CRC8 VALIDATION for incoming commands ──────────────
        // Protocol: [cmd_byte, ...params, crc8_byte]
        // Minimum: 2 bytes (command + CRC). Without CRC = legacy client.
        // Prevents corrupted BLE packets from triggering false START/STOP.
        if (len >= 2) {
            const uint8_t receivedCrc = data[len - 1];
            const uint8_t computedCrc = crc8(data, len - 1);
            if (receivedCrc != computedCrc) {
                Serial.printf("[BLE] CRC MISMATCH: received=0x%02X computed=0x%02X (len=%d)\n",
                    receivedCrc, computedCrc, (int)len);
                return; // REJECT corrupted command
            }
        }

        // First byte = command ID (CRC-validated)
        const uint8_t cmd = data[0];

        switch (cmd) {
            case 0x01:  // START
                startMeasurement();
                break;
            case 0x02:  // STOP
                stopMeasurement();
                break;
            case 0x03: { // CALIBRATE
                // Defer to sensor task (Core 1) via queue — never do I2C in BLE callback
                SensorCommand cmd = SensorCommand::CALIBRATE_INA226;
                if (g_sensorCmdQueue != nullptr) {
                    if (xQueueSend(g_sensorCmdQueue, &cmd, 0) == pdTRUE) {
                        Serial.println("[BLE] CALIBRATE queued for sensor task");
                    } else {
                        Serial.println("[BLE] CALIBRATE queue full — ignored");
                    }
                }
                break;
            }
            case 0x04:  // SET_SAMPLE_RATE (LE uint16 in bytes [1..2])
                if (len >= 4) {  // cmd + 2 bytes rate + CRC
                    const uint16_t hz = static_cast<uint16_t>(data[1]) |
                                        (static_cast<uint16_t>(data[2]) << 8);
                    setSampleRate(hz);
                }
                break;
            case 0x05:  // GET_INFO
                updateBleStatusCharacteristics();
                break;
            case 0x06:  // CLEAR_BUFFER
                g_bleTxBuffer.clear();
                g_historyBuffer.clear();
                Serial.println("[BLE] Buffers cleared");
                break;
            default:
                Serial.printf("[BLE] Unknown command: 0x%02X\n", cmd);
                break;
        }
    }
};

// =============================================================================
// Setup
// =============================================================================
void setup() {
    // Инициализация Serial для отладки
    Serial.begin(115200);
    delay(1000);
    
    Serial.println("=====================================");
    Serial.println("  Цифровая Лаборатория по Физике");
    Serial.printf("  Firmware: %s\n", FIRMWARE_VERSION);
    Serial.printf("  Build: %s\n", FIRMWARE_BUILD_DATE);
    Serial.println("=====================================");
    
    // Настройка ADC для батареи (12-bit, 11dB attenuation → до ~3.3V)
    analogReadResolution(12);
    analogSetAttenuation(ADC_11db);
    
    // Инициализация NVS (Non-Volatile Storage) — для калибровки датчиков
    esp_err_t nvsErr = nvs_flash_init();
    if (nvsErr == ESP_ERR_NVS_NO_FREE_PAGES || nvsErr == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        nvs_flash_erase();
        nvs_flash_init();
    }
    Serial.println("[OK] NVS initialized");

    // Deferred command queue (BLE/Web → sensor task)
    g_sensorCmdQueue = xQueueCreate(4, sizeof(SensorCommand));
    configASSERT(g_sensorCmdQueue != nullptr);
    Serial.println("[OK] Sensor command queue created");

    // Инициализация I2C
    g_i2cMutex = xSemaphoreCreateMutex();
    Wire.begin(I2C_SDA_PIN, I2C_SCL_PIN);
    Wire.setClock(I2C_FREQUENCY);
    Wire.setTimeOut(20); // Таймаут 20мс для предотвращения зависания шины
    Serial.println("[OK] I2C initialized");
    
    // Инициализация SPI (для термопары)
    SPI.begin(SPI_SCK_PIN, SPI_MISO_PIN, SPI_MOSI_PIN);
    Serial.println("[OK] SPI initialized");
    
    // Инициализация датчиков
    initSensors();
    
    // Инициализация BLE
    initBle();
    
    // Инициализация Wi-Fi AP
    initWifi();
    
    // Создание задачи опроса датчиков (Core 1)
    xTaskCreatePinnedToCore(
        taskSensorPolling,
        "SensorTask",
        8192,
        NULL,
        TASK_PRIORITY_SENSORS,
        NULL,
        CORE_SENSORS
    );
    Serial.println("[OK] Sensor task started on Core 1");
    
    // Создание задачи BLE (Core 0)
    xTaskCreatePinnedToCore(
        taskBleServer,
        "BleTask",
        8192,           // P0 FIX: was 4096, NimBLE needs ≥6144 for notify()
        NULL,
        TASK_PRIORITY_BLE,
        NULL,
        CORE_CONNECTIVITY
    );
    Serial.println("[OK] BLE task started on Core 0 (stack=8192)");
    
    // Создание задачи Web-сервера (Core 0)
    xTaskCreatePinnedToCore(
        taskWebServer,
        "WebTask",
        8192,
        NULL,
        TASK_PRIORITY_WEBSERVER,
        NULL,
        CORE_CONNECTIVITY
    );
    Serial.println("[OK] Web server task started on Core 0");
    
    Serial.println("\n[READY] System initialized");
    Serial.printf("Web UI: http://192.168.4.1\n");
    Serial.printf("BLE Name: %s\n", BLE_DEVICE_NAME);
}

// =============================================================================
// Loop (не используется - всё в FreeRTOS задачах)
// =============================================================================
void loop() {
    // Основной цикл пуст - вся работа в задачах FreeRTOS
    vTaskDelay(pdMS_TO_TICKS(1000));
}

// =============================================================================
// Задача опроса датчиков (Core 1)
// =============================================================================
void taskSensorPolling(void* param) {
    TickType_t lastWakeTime = xTaskGetTickCount();
    uint32_t droppedBleSamples = 0;
    uint32_t droppedHistorySamples = 0;
    uint32_t i2cMutexMisses = 0;
    
    // ── TASK WATCHDOG ─────────────────────────────────────────
    // If I2C bus hangs (common with cheap Chinese sensors),
    // the watchdog will auto-reboot ESP32 after kWatchdogTimeoutSec.
    // Without this, a frozen sensor task sends stale data forever.
    esp_task_wdt_init(kWatchdogTimeoutSec, true);  // true = panic on timeout
    esp_task_wdt_add(NULL);  // Add current task to WDT
    
    while (true) {
        // Feed watchdog every cycle — proves task is alive
        esp_task_wdt_reset();
        
        // ── Process deferred commands from BLE/Web (non-blocking) ──
        SensorCommand pendingCmd;
        while (xQueueReceive(g_sensorCmdQueue, &pendingCmd, 0) == pdTRUE) {
            if (pendingCmd == SensorCommand::CALIBRATE_INA226) {
                if (xSemaphoreTake(g_i2cMutex, pdMS_TO_TICKS(100)) == pdTRUE) {
                    if (g_ina226.available()) {
                        auto ina = g_ina226.read();
                        if (ina.valid) {
                            g_ina226.setZeroOffset(ina.voltage_v, ina.current_a);
                            Serial.printf("[SENSOR] CALIBRATE: INA226 zero set (V=%.4f, A=%.4f)\n",
                                ina.voltage_v, ina.current_a);
                        } else {
                            Serial.println("[SENSOR] CALIBRATE: INA226 read invalid, skipped");
                        }
                    }
                    xSemaphoreGive(g_i2cMutex);
                } else {
                    Serial.println("[SENSOR] CALIBRATE: I2C mutex busy, retrying next cycle");
                    // Re-enqueue for retry
                    xQueueSendToFront(g_sensorCmdQueue, &pendingCmd, 0);
                    break;  // Don't spin — try again next cycle
                }
            }
        }

        if (g_measuring) {
            SensorPacket packet = {};
            packet.timestamp_ms = millis() - g_startTimeMs;
            
            // --- Чтение датчиков по I2C (с защитой Mutex) ---
            if (xSemaphoreTake(g_i2cMutex, pdMS_TO_TICKS(10)) == pdTRUE) {

                // --- BME280: Температура / Давление / Влажность ---
                if (g_bme280.available()) {
                    auto bme = g_bme280.read();
                    if (bme.valid) {
                        packet.temperature_c = bme.temperature_c;
                        packet.pressure_pa   = bme.pressure_pa;
                        packet.humidity_pct   = bme.humidity_pct;
                        packet.setValid(FIELD_TEMPERATURE);
                        packet.setValid(FIELD_PRESSURE);
                        packet.setValid(FIELD_HUMIDITY);
                    }
                }

                // --- INA226: Напряжение / Ток / Мощность ---
                if (g_ina226.available()) {
                    auto ina = g_ina226.read();
                    if (ina.valid) {
                        packet.voltage_v = ina.voltage_v;
                        packet.current_a = ina.current_a;
                        packet.power_w   = ina.power_w;
                        packet.setValid(FIELD_VOLTAGE);
                        packet.setValid(FIELD_CURRENT);
                        packet.setValid(FIELD_POWER);
                    }
                }

                // --- LSM6DS3: Акселерометр + Гироскоп ---
                if (g_lsm6ds3.available()) {
                    auto imu = g_lsm6ds3.read();
                    if (imu.valid) {
                        packet.accel_x = imu.accel_x;
                        packet.accel_y = imu.accel_y;
                        packet.accel_z = imu.accel_z;
                        packet.gyro_x  = imu.gyro_x;
                        packet.gyro_y  = imu.gyro_y;
                        packet.gyro_z  = imu.gyro_z;
                        packet.setValid(FIELD_ACCEL_X);
                        packet.setValid(FIELD_ACCEL_Y);
                        packet.setValid(FIELD_ACCEL_Z);
                        packet.setValid(FIELD_GYRO_X);
                        packet.setValid(FIELD_GYRO_Y);
                        packet.setValid(FIELD_GYRO_Z);
                    }
                }

                // --- VL53L1X: Лазерный дальномер ---
                if (g_vl53l1x.available()) {
                    auto tof = g_vl53l1x.read();
                    if (tof.valid) {
                        packet.distance_mm = tof.distance_mm;
                        packet.setValid(FIELD_DISTANCE);
                    }
                }

                xSemaphoreGive(g_i2cMutex);
            } else {
                // Не удалось захватить шину I2C вовремя
                i2cMutexMisses++;
                continue;
            }

            // --- MAX31855: Термопара (SPI — отдельная шина, mutex не нужен) ---
            if (g_max31855.available()) {
                auto tc = g_max31855.read();
                if (tc.valid) {
                    packet.thermocouple_c = tc.thermocouple_c;
                    packet.setValid(FIELD_THERMOCOUPLE);
                }
            }
            
            // Добавляем в буфер
            if (!g_bleTxBuffer.push(packet)) {
                droppedBleSamples++;
            }
            if (!g_historyBuffer.push(packet)) {
                droppedHistorySamples++;
            }
            
            // Отладочный вывод каждую секунду
            static uint32_t lastDebugMs = 0;
            if (millis() - lastDebugMs > 1000) {
                Serial.printf("[SENSOR] t=%ums V=%.2fV A=%.3fA T=%.1f°C P=%.0fPa d=%.0fmm az=%.2f hist=%d tx=%d drop_hist=%lu drop_tx=%lu i2c_miss=%lu\n",
                    packet.timestamp_ms,
                    packet.isValid(FIELD_VOLTAGE)     ? packet.voltage_v     : 0.0f,
                    packet.isValid(FIELD_CURRENT)     ? packet.current_a     : 0.0f,
                    packet.isValid(FIELD_TEMPERATURE) ? packet.temperature_c : 0.0f,
                    packet.isValid(FIELD_PRESSURE)    ? packet.pressure_pa   : 0.0f,
                    packet.isValid(FIELD_DISTANCE)    ? packet.distance_mm   : 0.0f,
                    packet.isValid(FIELD_ACCEL_Z)     ? packet.accel_z       : 0.0f,
                    g_historyBuffer.count(),
                    g_bleTxBuffer.count(),
                    static_cast<unsigned long>(droppedHistorySamples),
                    static_cast<unsigned long>(droppedBleSamples),
                    static_cast<unsigned long>(i2cMutexMisses)
                );
                lastDebugMs = millis();
            }
        }
        
        // Ждём следующий цикл (частота зависит от g_sampleRateHz)
        uint32_t rateHz = g_sampleRateHz;
        if (rateHz == 0) {
            rateHz = DEFAULT_SAMPLE_RATE_HZ;
        }
        uint32_t delayMs = 1000 / rateHz;
        if (delayMs == 0) {
            delayMs = 1;
        }
        vTaskDelayUntil(&lastWakeTime, pdMS_TO_TICKS(delayMs));
    }
}

// =============================================================================
// Инициализация датчиков
// =============================================================================
void initSensors() {
    Serial.println("[INIT] Scanning I2C bus...");
    
    uint8_t foundDevices = 0;
    for (uint8_t addr = 1; addr < 127; addr++) {
        if (xSemaphoreTake(g_i2cMutex, pdMS_TO_TICKS(100)) == pdTRUE) {
            Wire.beginTransmission(addr);
            uint8_t error = Wire.endTransmission();
            xSemaphoreGive(g_i2cMutex);
            
            if (error == 0) {
                Serial.printf("  Found device at 0x%02X", addr);
                
                if (addr == VL53L1X_ADDR) Serial.print(" (VL53L1X - Distance)");
                else if (addr == INA226_ADDR) Serial.print(" (INA226 - V/A)");
                else if (addr == BME280_ADDR) Serial.print(" (BME280 - T/P/H)");
                else if (addr == LSM6DS3_ADDR) Serial.print(" (LSM6DS3 - IMU)");
                
                Serial.println();
                foundDevices++;
            }
        }
    }
    
    if (foundDevices == 0) {
        Serial.println("  No I2C devices found (check wiring!)");
    } else {
        Serial.printf("[OK] Found %d I2C devices\n", foundDevices);
    }

    // ── Инициализация драйверов ────────────────────────────────
    // Каждый драйвер проверяет WHO_AM_I / Chip ID. Если чип не
    // ответил, available() == false → read() возвращает {valid=false}.
    // Прошивка продолжает работу с теми датчиками, которые есть.

    if (xSemaphoreTake(g_i2cMutex, pdMS_TO_TICKS(500)) == pdTRUE) {
        if (g_bme280.begin(Wire, BME280_ADDR)) {
            Serial.println("[OK] BME280 initialized (T/P/H)");
        } else {
            Serial.println("[--] BME280 not found");
        }

        if (g_ina226.begin(Wire, INA226_ADDR, 0.1f)) {
            Serial.println("[OK] INA226 initialized (V/A, Rshunt=0.1Ω)");
            g_ina226.loadCalibrationFromNVS();  // Restore saved zero-offsets
        } else {
            Serial.println("[--] INA226 not found");
        }

        if (g_lsm6ds3.begin(Wire, LSM6DS3_ADDR)) {
            Serial.println("[OK] LSM6DS3 initialized (Accel/Gyro)");
        } else {
            Serial.println("[--] LSM6DS3 not found");
        }

        if (g_vl53l1x.begin(Wire, VL53L1X_ADDR)) {
            Serial.println("[OK] VL53L1X initialized (ToF laser)");
        } else {
            Serial.println("[--] VL53L1X not found");
        }

        xSemaphoreGive(g_i2cMutex);
    }

    // MAX31855 — SPI (no mutex needed, separate bus)
    if (g_max31855.begin(SPI_CS_THERMO_PIN)) {
        Serial.println("[OK] MAX31855 initialized (thermocouple)");
    } else {
        Serial.println("[--] MAX31855 not found");
    }
}

// =============================================================================
// BLE
// =============================================================================
void initBle() {
    Serial.println("[INIT] BLE...");

    NimBLEDevice::init(BLE_DEVICE_NAME);
    NimBLEDevice::setPower(ESP_PWR_LVL_P9);

    g_bleServer = NimBLEDevice::createServer();
    g_bleServer->setCallbacks(new PhysicsLabServerCallbacks());

    g_bleService = g_bleServer->createService(BLE_SERVICE_UUID);

    g_dataChar = g_bleService->createCharacteristic(
        BLE_CHAR_DATA_UUID,
        NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY
    );

    g_commandChar = g_bleService->createCharacteristic(
        BLE_CHAR_COMMAND_UUID,
        NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR
    );
    g_commandChar->setCallbacks(new PhysicsLabCommandCallbacks());

    g_configChar = g_bleService->createCharacteristic(
        BLE_CHAR_CONFIG_UUID,
        NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::WRITE
    );

    g_firmwareChar = g_bleService->createCharacteristic(
        BLE_CHAR_FIRMWARE_UUID,
        NIMBLE_PROPERTY::READ
    );

    updateBleStatusCharacteristics();
    g_bleService->start();

    NimBLEAdvertising* advertising = NimBLEDevice::getAdvertising();
    advertising->addServiceUUID(BLE_SERVICE_UUID);
    advertising->setScanResponse(true);
    advertising->start();

    Serial.println("[OK] BLE ready");
}

void taskBleServer(void* param) {
    TickType_t lastWakeTime = xTaskGetTickCount();
    uint32_t sentPackets = 0;
    uint32_t sendErrors = 0;

    while (true) {
        if (g_bleClientConnected && g_dataChar != nullptr && g_measuring) {
            SensorPacket packet = {};
            uint8_t packetsSentThisCycle = 0;
            
            while (g_bleTxBuffer.pop(packet)) {
                if (!g_bleClientConnected) {
                    // Если клиент отключился во время выгребания буфера, прерываем отправку
                    break;
                }

                const FramedSensorPacket framed = {
                    .magic = kPacketMagic,
                    .protocolVersion = kPacketProtocolVersion,
                    .payloadSize = kPayloadSize,
                    .payload = packet,
                };

                const uint8_t* bytes = reinterpret_cast<const uint8_t*>(&framed);
                constexpr size_t totalSize = sizeof(FramedSensorPacket);

                // Отправляем весь пакет целиком. NimBLE сам разобьет его на L2CAP-фрагменты,
                // если MTU клиента меньше 84 байт. Это в 5 раз снижает нагрузку на стек
                // по сравнению с ручной отправкой по 20 байт.
                g_dataChar->setValue(bytes, totalSize);
                bool notifyOk = g_dataChar->notify();

                if (notifyOk) {
                    sentPackets++;
                    g_bleNotifyOk++;
                } else {
                    sendErrors++;
                    g_bleNotifyDrops++;
                    // Back off: client congested. Stop sending this cycle.
                    break;
                }
                packetsSentThisCycle++;
                
                // Защита от переполнения очереди NimBLE при выгребании большого буфера
                if (packetsSentThisCycle >= 10) {
                    vTaskDelay(pdMS_TO_TICKS(5));
                    packetsSentThisCycle = 0;
                }
            }
        }

        static uint32_t lastStatusMs = 0;
        if (millis() - lastStatusMs > 1000) {
            updateBleStatusCharacteristics();
            if (g_bleClientConnected) {
                Serial.printf("[BLE] sent=%lu drops=%lu errs=%lu buf=%d i2c(ok=%lu nack=%lu short=%lu)\n",
                    static_cast<unsigned long>(sentPackets),
                    static_cast<unsigned long>(g_bleNotifyDrops.load()),
                    static_cast<unsigned long>(sendErrors),
                    g_bleTxBuffer.count(),
                    static_cast<unsigned long>(g_i2cHealth.successfulReads),
                    static_cast<unsigned long>(g_i2cHealth.nackErrors),
                    static_cast<unsigned long>(g_i2cHealth.shortReads)
                );
            }
            lastStatusMs = millis();
        }

        vTaskDelayUntil(&lastWakeTime, pdMS_TO_TICKS(10));
    }
}

void updateBleStatusCharacteristics() {
    if (g_firmwareChar != nullptr) {
        int major = 1;
        int minor = 1;
        int patch = 0;
        sscanf(FIRMWARE_VERSION, "%d.%d.%d", &major, &minor, &patch);

        const uint8_t firmwarePayload[4] = {
            static_cast<uint8_t>(major),
            static_cast<uint8_t>(minor),
            static_cast<uint8_t>(patch),
            readBatteryPercent(),
        };
        g_firmwareChar->setValue(firmwarePayload, sizeof(firmwarePayload));
    }

    if (g_configChar != nullptr) {
        // Dynamic mask — only advertise sensors that actually initialized
        uint32_t enabledMask = 0;

        if (g_bme280.available()) {
            enabledMask |= (1UL << FIELD_TEMPERATURE);
            enabledMask |= (1UL << FIELD_PRESSURE);
            enabledMask |= (1UL << FIELD_HUMIDITY);
        }
        if (g_ina226.available()) {
            enabledMask |= (1UL << FIELD_VOLTAGE);
            enabledMask |= (1UL << FIELD_CURRENT);
            enabledMask |= (1UL << FIELD_POWER);
        }
        if (g_lsm6ds3.available()) {
            enabledMask |= (1UL << FIELD_ACCEL_X);
            enabledMask |= (1UL << FIELD_ACCEL_Y);
            enabledMask |= (1UL << FIELD_ACCEL_Z);
            enabledMask |= (1UL << FIELD_GYRO_X);
            enabledMask |= (1UL << FIELD_GYRO_Y);
            enabledMask |= (1UL << FIELD_GYRO_Z);
        }
        if (g_vl53l1x.available()) {
            enabledMask |= (1UL << FIELD_DISTANCE);
        }
        if (g_max31855.available()) {
            enabledMask |= (1UL << FIELD_THERMOCOUPLE);
        }

        uint8_t configPayload[8] = {};
        memcpy(&configPayload[0], &enabledMask, sizeof(enabledMask));

        const uint16_t rate = static_cast<uint16_t>(g_sampleRateHz);
        memcpy(&configPayload[4], &rate, sizeof(rate));
        configPayload[6] = g_measuring ? 1 : 0;
        configPayload[7] = 0;

        g_configChar->setValue(configPayload, sizeof(configPayload));
    }
}

// =============================================================================
// Wi-Fi Access Point + Web Server (ESPAsyncWebServer)
// =============================================================================
void initWifi() {
    Serial.println("[INIT] Wi-Fi AP...");

    // ── Dynamic password from MAC address ─────────────────────
    const String password = generateWifiPassword();
    WiFi.softAP(WIFI_AP_SSID, password.c_str(), WIFI_AP_CHANNEL, 0, WIFI_AP_MAX_CONNECTIONS);
    
    Serial.printf("[OK] Wi-Fi AP ready: SSID=%s Password=%s\n",
        WIFI_AP_SSID, password.c_str());
    Serial.printf("     IP: %s\n", WiFi.softAPIP().toString().c_str());

    // ── SPIFFS for serving index.html ─────────────────────────
    if (!SPIFFS.begin(true)) {
        Serial.println("[WARN] SPIFFS mount failed — Web UI unavailable");
    } else {
        Serial.printf("[OK] SPIFFS mounted (%d bytes used)\n", SPIFFS.usedBytes());
    }

    // ── Web Server Routes ─────────────────────────────────────

    // GET / — serve index.html from SPIFFS (fallback Web UI)
    g_webServer.on("/", HTTP_GET, [](AsyncWebServerRequest* request) {
        if (SPIFFS.exists("/index.html")) {
            request->send(SPIFFS, "/index.html", "text/html");
        } else {
            request->send(200, "text/html",
                "<html><body style='background:#121212;color:#fff;font-family:sans-serif;text-align:center;padding:40px'>"
                "<h1>&#128300; Labosfera</h1>"
                "<p>Web UI not uploaded to SPIFFS yet.</p>"
                "<p>Use <code>pio run -t uploadfs</code> to upload.</p>"
                "</body></html>");
        }
    });

    // GET /api/status — device status (JSON)
    g_webServer.on("/api/status", HTTP_GET, [](AsyncWebServerRequest* request) {
        char json[384];
        snprintf(json, sizeof(json),
            "{\"firmware\":\"%s\",\"battery\":%d,\"measuring\":%s,"
            "\"sample_rate\":%lu,\"buffer_count\":%d,\"tx_buffer_count\":%d,"
            "\"ble_connected\":%s,\"uptime_ms\":%lu,"
            "\"free_heap\":%lu,\"max_alloc_heap\":%lu}",
            FIRMWARE_VERSION,
            readBatteryPercent(),
            g_measuring ? "true" : "false",
            static_cast<unsigned long>(g_sampleRateHz),
            g_historyBuffer.count(),
            g_bleTxBuffer.count(),
            g_bleClientConnected ? "true" : "false",
            static_cast<unsigned long>(millis()),
            static_cast<unsigned long>(ESP.getFreeHeap()),
            static_cast<unsigned long>(ESP.getMaxAllocHeap()));
        request->send(200, "application/json", json);
    });

    // GET /api/data — last sensor reading (JSON)
    // Used by Web UI for live display (polled at 100ms interval)
    g_webServer.on("/api/data", HTTP_GET, [](AsyncWebServerRequest* request) {
        SensorPacket pkt = {};
        bool hasData = g_historyBuffer.peekLast(pkt);

        char json[512];
        if (hasData) {
            snprintf(json, sizeof(json),
                "{\"timestamp_ms\":%lu,"
                "\"voltage_v\":%.3f,\"current_a\":%.4f,\"power_w\":%.3f,"
                "\"temperature_c\":%.2f,\"pressure_pa\":%.1f,\"humidity_pct\":%.1f,"
                "\"accel_x\":%.3f,\"accel_y\":%.3f,\"accel_z\":%.3f,"
                "\"gyro_x\":%.2f,\"gyro_y\":%.2f,\"gyro_z\":%.2f,"
                "\"thermocouple_c\":%.2f,\"distance_mm\":%.1f,"
                "\"valid_flags\":%lu,\"buffer_count\":%d}",
                static_cast<unsigned long>(pkt.timestamp_ms),
                pkt.voltage_v, pkt.current_a, pkt.power_w,
                pkt.temperature_c, pkt.pressure_pa, pkt.humidity_pct,
                pkt.accel_x, pkt.accel_y, pkt.accel_z,
                pkt.gyro_x, pkt.gyro_y, pkt.gyro_z,
                pkt.thermocouple_c, pkt.distance_mm,
                static_cast<unsigned long>(pkt.valid_flags),
                g_historyBuffer.count());
        } else {
            snprintf(json, sizeof(json),
                "{\"timestamp_ms\":0,\"distance_mm\":0,\"temperature_c\":0,"
                "\"buffer_count\":0,\"valid_flags\":0}");
        }
        request->send(200, "application/json", json);
    });

    // GET /api/csv — export buffer as CSV (P0 FIX: chunked response)
    // Teachers can save data without the app.
    //
    // Previous implementation used AsyncResponseStream which buffers the
    // ENTIRE response in heap RAM before sending. With 10K samples × 140B
    // = 1.4MB this caused OOM on ESP32 (~300KB heap).
    //
    // New approach: AsyncWebServerResponse with chunked transfer encoding.
    // Each chunk reads a small batch from the ring buffer, formats CSV lines,
    // and streams them directly to the TCP socket. Peak RAM: ~4KB.
    g_webServer.on("/api/csv", HTTP_GET, [](AsyncWebServerRequest* request) {
        // Snapshot count at request time (buffer may grow during export)
        const int snapshotCount = g_historyBuffer.count();
        if (snapshotCount == 0) {
            request->send(200, "text/csv", "timestamp_ms,voltage_v,current_a,power_w,"
                "temperature_c,pressure_pa,humidity_pct,accel_x,accel_y,accel_z,"
                "gyro_x,gyro_y,gyro_z,thermocouple_c,distance_mm\r\n");
            return;
        }

        // State for chunked callback: current index and total count
        struct CsvState {
            int index;
            int total;
        };
        auto* state = new CsvState{0, snapshotCount};

        AsyncWebServerResponse* response = request->beginChunkedResponse(
            "text/csv",
            [state](uint8_t* buffer, size_t maxLen, size_t sentSoFar) -> size_t {
                if (state->index >= state->total) {
                    delete state;
                    return 0;  // Signal end of response
                }

                size_t written = 0;

                // Write CSV header as first chunk
                if (sentSoFar == 0) {
                    const char* header = "timestamp_ms,voltage_v,current_a,power_w,"
                        "temperature_c,pressure_pa,humidity_pct,accel_x,accel_y,accel_z,"
                        "gyro_x,gyro_y,gyro_z,thermocouple_c,distance_mm\r\n";
                    size_t hLen = strlen(header);
                    if (hLen <= maxLen) {
                        memcpy(buffer, header, hLen);
                        written = hLen;
                    }
                }

                // Fill remainder of buffer with CSV lines (batch of ~20 rows per chunk)
                // Each row is max ~150 bytes. We leave 256B margin.
                while (state->index < state->total && (written + 256) < maxLen) {
                    SensorPacket pkt = {};
                    if (g_historyBuffer.peekAt(state->index, pkt)) {
                        int n = snprintf(
                            reinterpret_cast<char*>(buffer + written),
                            maxLen - written,
                            "%lu,%.3f,%.4f,%.3f,%.2f,%.1f,%.1f,%.3f,%.3f,%.3f,%.2f,%.2f,%.2f,%.2f,%.1f\r\n",
                            static_cast<unsigned long>(pkt.timestamp_ms),
                            pkt.voltage_v, pkt.current_a, pkt.power_w,
                            pkt.temperature_c, pkt.pressure_pa, pkt.humidity_pct,
                            pkt.accel_x, pkt.accel_y, pkt.accel_z,
                            pkt.gyro_x, pkt.gyro_y, pkt.gyro_z,
                            pkt.thermocouple_c, pkt.distance_mm);
                        if (n > 0 && (written + n) <= maxLen) {
                            written += n;
                        }
                    }
                    state->index++;
                }

                return written;
            }
        );
        response->addHeader("Content-Disposition", "attachment; filename=\"labosfera_data.csv\"");
        request->send(response);
    });

    // POST /api/command — start/stop/calibrate/set_rate
    // Body: JSON {"command":"start"} or {"command":"calibrate"} etc.
    //
    // Chunk-safe implementation:
    // - body can arrive fragmented across multiple onBody invocations
    // - we accumulate all chunks into request->_tempObject
    // - parse only after the full payload is received
    //
    // This removes a subtle bug where the previous implementation parsed only
    // the LAST chunk and silently lost earlier bytes.
    g_webServer.on("/api/command", HTTP_POST,
        // onRequest handler (invoked after body is parsed)
        [](AsyncWebServerRequest* request) {},
        // onUpload (not used)
        NULL,
        // onBody — may receive body in multiple chunks
        [](AsyncWebServerRequest* request, uint8_t* data, size_t len, size_t index, size_t total) {
            static constexpr size_t kMaxCommandBodyBytes = 256;

            if (index == 0) {
                if (total == 0 || total > kMaxCommandBodyBytes) {
                    request->send(413, "application/json", "{\"error\":\"body too large\"}");
                    return;
                }

                request->_tempObject = calloc(total + 1, sizeof(uint8_t));
                if (request->_tempObject == nullptr) {
                    request->send(500, "application/json", "{\"error\":\"oom\"}");
                    return;
                }
            }

            if (request->_tempObject == nullptr) {
                return;
            }

            memcpy(reinterpret_cast<uint8_t*>(request->_tempObject) + index, data, len);

            if (index + len < total) {
                return;  // wait for remaining chunks
            }

            String body(reinterpret_cast<char*>(request->_tempObject));
            body.trim();

            String cmd = "";
            int cmdKeyIdx = body.indexOf("\"command\"");
            if (cmdKeyIdx >= 0) {
                int colonIdx = body.indexOf(':', cmdKeyIdx);
                if (colonIdx >= 0) {
                    int valStart = body.indexOf('"', colonIdx + 1);
                    if (valStart >= 0) {
                        int valEnd = body.indexOf('"', valStart + 1);
                        if (valEnd > valStart) {
                            cmd = body.substring(valStart + 1, valEnd);
                        }
                    }
                }
            }

            if (cmd == "start") {
                startMeasurement();
                request->send(200, "application/json", "{\"ok\":true,\"action\":\"start\"}");
            } else if (cmd == "stop") {
                stopMeasurement();
                request->send(200, "application/json", "{\"ok\":true,\"action\":\"stop\"}");
            } else if (cmd == "calibrate") {
                // Defer to sensor task (Core 1) via queue — never do I2C in Web callback
                SensorCommand sensorCmd = SensorCommand::CALIBRATE_INA226;
                if (g_sensorCmdQueue != nullptr) {
                    xQueueSend(g_sensorCmdQueue, &sensorCmd, 0);
                }
                request->send(200, "application/json", "{\"ok\":true,\"action\":\"calibrate\"}");
            } else if (cmd == "set_rate") {
                int valIdx = body.indexOf("\"value\"");
                if (valIdx >= 0) {
                    int colonIdx = body.indexOf(':', valIdx);
                    if (colonIdx >= 0) {
                        uint32_t hz = body.substring(colonIdx + 1).toInt();
                        setSampleRate(hz);
                    }
                }
                request->send(200, "application/json", "{\"ok\":true,\"action\":\"set_rate\"}");
            } else {
                request->send(400, "application/json", "{\"error\":\"unknown command\"}");
            }
        }
    );

    // Catch-all: serve SPIFFS files (style.css, app.js if uploaded)
    g_webServer.serveStatic("/", SPIFFS, "/").setDefaultFile("index.html");

    // Start the async web server
    g_webServer.begin();
    Serial.println("[OK] Web server started on port 80");
}

/// taskWebServer — lightweight heartbeat logger.
/// ESPAsyncWebServer is async (runs in lwIP/WiFi task context),
/// so this task only logs periodic diagnostics.
void taskWebServer(void* param) {
    TickType_t lastWakeTime = xTaskGetTickCount();

    while (true) {
        static uint32_t lastHeartbeatMs = 0;
        if (millis() - lastHeartbeatMs > 30000) {  // Every 30s (not spammy)
            Serial.printf("[WEB] clients=%d measuring=%d buf=%d uptime=%lus heap=%lu/%lu\n",
                WiFi.softAPgetStationNum(),
                g_measuring ? 1 : 0,
                g_historyBuffer.count(),
                static_cast<unsigned long>(millis() / 1000),
                static_cast<unsigned long>(ESP.getFreeHeap()),
                static_cast<unsigned long>(ESP.getMaxAllocHeap())
            );
            // Warn if heap fragmentation is dangerous (< 16KB largest block)
            if (ESP.getMaxAllocHeap() < 16384) {
                Serial.println("[WARN] Heap fragmentation critical! Largest free block < 16KB");
            }
            lastHeartbeatMs = millis();
        }

        vTaskDelayUntil(&lastWakeTime, pdMS_TO_TICKS(1000));
    }
}

// =============================================================================
// API для управления измерениями (вызывается из BLE/Web)
// =============================================================================
extern "C" {
    void startMeasurement() {
        g_bleTxBuffer.clear();
        g_historyBuffer.clear();
        g_startTimeMs = millis();
        g_measuring = true;
        Serial.println("[CMD] Measurement started");
    }
    
    void stopMeasurement() {
        g_measuring = false;
        Serial.printf("[CMD] Measurement stopped. Collected %d history samples (%d pending BLE)\n", 
            g_historyBuffer.count(),
            g_bleTxBuffer.count());
    }
    
    void setSampleRate(uint32_t hz) {
        g_sampleRateHz = constrain(hz, 1, MAX_SAMPLE_RATE_HZ);
        Serial.printf("[CMD] Sample rate set to %lu Hz\n",
            static_cast<unsigned long>(g_sampleRateHz.load()));
    }
    
    bool getLastPacket(SensorPacket* packet) {
        return g_historyBuffer.peekLast(*packet);
    }
}
