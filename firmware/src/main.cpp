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

#include "core/config.h"
#include "core/ring_buffer.h"

// Глобальные объекты
RingBuffer<SensorPacket, RING_BUFFER_SIZE> g_sensorBuffer;

// Состояние системы
volatile bool g_measuring = false;
volatile uint32_t g_sampleRateHz = DEFAULT_SAMPLE_RATE_HZ;
volatile uint32_t g_startTimeMs = 0;

// Прототипы функций
void taskSensorPolling(void* param);
void taskBleServer(void* param);
void taskWebServer(void* param);
void initSensors();
void initBle();
void initWifi();

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
    
    // Инициализация I2C
    Wire.begin(I2C_SDA_PIN, I2C_SCL_PIN);
    Wire.setClock(I2C_FREQUENCY);
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
        4096,
        NULL,
        TASK_PRIORITY_BLE,
        NULL,
        CORE_CONNECTIVITY
    );
    Serial.println("[OK] BLE task started on Core 0");
    
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
    
    while (true) {
        if (g_measuring) {
            SensorPacket packet = {};
            packet.timestamp_ms = millis() - g_startTimeMs;
            
            // --- Чтение VL53L1X (расстояние) ---
            // TODO: Реализовать драйвер
            // Временная симуляция:
            static float simDistance = 500.0f;
            simDistance += (random(-50, 50) / 10.0f);
            simDistance = constrain(simDistance, 50, 2000);
            packet.distance_mm = simDistance;
            packet.setValid(FIELD_DISTANCE);
            
            // --- Чтение BME280 (температура) ---
            // TODO: Реализовать драйвер
            packet.temperature_c = 22.5f + (random(-10, 10) / 10.0f);
            packet.setValid(FIELD_TEMPERATURE);
            
            // --- Чтение LSM6DS3 (ускорение) ---
            // TODO: Реализовать драйвер
            packet.accel_x = (random(-10, 10) / 100.0f);
            packet.accel_y = (random(-10, 10) / 100.0f);
            packet.accel_z = 9.81f + (random(-5, 5) / 100.0f);
            packet.setValid(FIELD_ACCEL_X);
            packet.setValid(FIELD_ACCEL_Y);
            packet.setValid(FIELD_ACCEL_Z);
            
            // Добавляем в буфер
            g_sensorBuffer.push(packet);
            
            // Отладочный вывод каждую секунду
            static uint32_t lastDebugMs = 0;
            if (millis() - lastDebugMs > 1000) {
                Serial.printf("[SENSOR] t=%ums, d=%.1fmm, T=%.1f°C, az=%.2fm/s², buf=%d\n",
                    packet.timestamp_ms,
                    packet.distance_mm,
                    packet.temperature_c,
                    packet.accel_z,
                    g_sensorBuffer.count()
                );
                lastDebugMs = millis();
            }
        }
        
        // Ждём следующий цикл (частота зависит от g_sampleRateHz)
        uint32_t delayMs = 1000 / g_sampleRateHz;
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
        Wire.beginTransmission(addr);
        if (Wire.endTransmission() == 0) {
            Serial.printf("  Found device at 0x%02X", addr);
            
            if (addr == VL53L1X_ADDR) Serial.print(" (VL53L1X - Distance)");
            else if (addr == INA226_ADDR) Serial.print(" (INA226 - V/A)");
            else if (addr == BME280_ADDR) Serial.print(" (BME280 - T/P/H)");
            else if (addr == LSM6DS3_ADDR) Serial.print(" (LSM6DS3 - IMU)");
            
            Serial.println();
            foundDevices++;
        }
    }
    
    if (foundDevices == 0) {
        Serial.println("  No I2C devices found (simulation mode)");
    } else {
        Serial.printf("[OK] Found %d I2C devices\n", foundDevices);
    }
}

// =============================================================================
// Заглушка BLE (будет реализована в ble_server.cpp)
// =============================================================================
void initBle() {
    Serial.println("[INIT] BLE...");
    // TODO: NimBLE инициализация
    Serial.println("[OK] BLE ready (stub)");
}

void taskBleServer(void* param) {
    while (true) {
        // TODO: BLE notify loop
        vTaskDelay(pdMS_TO_TICKS(100));
    }
}

// =============================================================================
// Заглушка Wi-Fi (будет реализована в wifi_ap.cpp)
// =============================================================================
void initWifi() {
    Serial.println("[INIT] Wi-Fi AP...");
    // TODO: AsyncWebServer
    Serial.println("[OK] Wi-Fi AP ready (stub)");
}

void taskWebServer(void* param) {
    while (true) {
        // TODO: Web server loop
        vTaskDelay(pdMS_TO_TICKS(100));
    }
}

// =============================================================================
// API для управления измерениями (вызывается из BLE/Web)
// =============================================================================
extern "C" {
    void startMeasurement() {
        g_sensorBuffer.clear();
        g_startTimeMs = millis();
        g_measuring = true;
        Serial.println("[CMD] Measurement started");
    }
    
    void stopMeasurement() {
        g_measuring = false;
        Serial.printf("[CMD] Measurement stopped. Collected %d samples\n", 
            g_sensorBuffer.count());
    }
    
    void setSampleRate(uint32_t hz) {
        g_sampleRateHz = constrain(hz, 1, MAX_SAMPLE_RATE_HZ);
        Serial.printf("[CMD] Sample rate set to %d Hz\n", g_sampleRateHz);
    }
    
    bool getLastPacket(SensorPacket* packet) {
        return g_sensorBuffer.peekLast(*packet);
    }
}
