#pragma once
/**
 * sensor_drivers.h — Драйверы I2C/SPI датчиков для Цифровой Лаборатории
 *
 * Все драйверы работают через Wire (I2C) и SPI напрямую, без тяжёлых
 * Arduino-библиотек. Это экономит ~40 KB Flash и убирает лишние зависимости.
 *
 * Каждый драйвер:
 *   1. begin()     — инициализация + проверка WHO_AM_I / chip ID
 *   2. read(...)   — одно чтение (вызывается из taskSensorPolling)
 *   3. available() — true если чип ответил при begin()
 *
 * I2C Mutex НЕ захватывается внутри драйверов — вызывающий код
 * (taskSensorPolling) держит мьютекс на весь цикл опроса.
 *
 * SAFE I2C LAYER (P0 hardening):
 *   All low-level _readReg/_readRegs/_readReg16 validate:
 *   - endTransmission() return (0 = success, else NACK/bus error)
 *   - requestFrom() actual byte count vs. requested
 *   - On partial/failed read → return 0x00/0xFF sentinel + caller checks .valid
 *   Philosophy: better a temporary "no data" than silent garbage.
 */

#include <nvs_flash.h>
#include <nvs.h>

#include <Arduino.h>
#include <Wire.h>
#include <SPI.h>
#include "core/config.h"

// ═══════════════════════════════════════════════════════════════
//  Global I2C bus health counters (readable via Serial / Web API)
// ═══════════════════════════════════════════════════════════════
struct I2CBusHealth {
    uint32_t nackErrors = 0;       // endTransmission returned non-zero
    uint32_t shortReads = 0;       // requestFrom returned fewer bytes
    uint32_t successfulReads = 0;  // full clean transactions
};
static I2CBusHealth g_i2cHealth;

// ═══════════════════════════════════════════════════════════════
//  BME280 — Температура / Давление / Влажность
//  Datasheet: Bosch Sensortec BST-BME280-DS002
//  I2C Address: 0x76 (SDO=GND) or 0x77 (SDO=VCC)
// ═══════════════════════════════════════════════════════════════

class BME280Driver {
public:
    struct Reading {
        float temperature_c;   // °C, resolution 0.01
        float pressure_pa;     // Pa, resolution 0.18
        float humidity_pct;    // %RH, resolution 0.008
        bool valid;
    };

    bool begin(TwoWire& wire = Wire, uint8_t addr = BME280_ADDR) {
        _wire = &wire;
        _addr = addr;

        // Check chip ID (should be 0x60 for BME280, 0x58 for BMP280)
        uint8_t chipId = _readReg(0xD0);
        if (chipId != 0x60 && chipId != 0x58) {
            Serial.printf("[BME280] Chip ID mismatch: 0x%02X (expected 0x60)\n", chipId);
            _available = false;
            return false;
        }
        Serial.printf("[BME280] Found chip ID=0x%02X at 0x%02X\n", chipId, _addr);
        _isBME = (chipId == 0x60);  // BME280 has humidity, BMP280 does not

        // Soft reset
        _writeReg(0xE0, 0xB6);
        delay(10);

        // Read calibration data
        _readCalibration();

        // Configure: forced mode, oversampling x1 for T/P/H
        // ctrl_hum (0xF2): osrs_h = 001 (x1)
        if (_isBME) {
            _writeReg(0xF2, 0x01);
        }
        // config (0xF5): t_sb=000 (0.5ms), filter=010 (x4), spi3w_en=0
        _writeReg(0xF5, 0x08);
        // ctrl_meas (0xF4): osrs_t=001 (x1), osrs_p=001 (x1), mode=00 (sleep)
        // We use forced mode — trigger measurement each read()
        _writeReg(0xF4, 0x25);  // Will be overwritten in read()

        _available = true;
        return true;
    }

    bool available() const { return _available; }

    Reading read() {
        Reading r = {0, 0, 0, false};
        if (!_available) return r;

        // Trigger forced measurement
        // ctrl_meas: osrs_t=001 (x1), osrs_p=001 (x1), mode=01 (forced)
        _writeReg(0xF4, 0x25);

        // Wait for measurement (typical: 8ms for T+P+H at x1 oversampling)
        delay(10);

        // Check status — bit 3 (measuring) should be 0
        uint8_t status = _readReg(0xF3);
        if (status & 0x08) {
            delay(5);  // Extra wait
        }

        // Read raw data: press[0xF7..0xF9], temp[0xFA..0xFC], hum[0xFD..0xFE]
        uint8_t buf[8];
        uint8_t bytesRead = _readRegs(0xF7, buf, 8);
        if (bytesRead < 8) {
            // I2C bus error — return invalid rather than garbage
            return r;
        }

        int32_t rawP = ((int32_t)buf[0] << 12) | ((int32_t)buf[1] << 4) | (buf[2] >> 4);
        int32_t rawT = ((int32_t)buf[3] << 12) | ((int32_t)buf[4] << 4) | (buf[5] >> 4);
        int32_t rawH = ((int32_t)buf[6] << 8) | buf[7];

        // Compensate temperature (from datasheet, integer math)
        int32_t t_fine = _compensateT(rawT);
        r.temperature_c = (float)((t_fine * 5 + 128) >> 8) / 100.0f;

        // Compensate pressure
        r.pressure_pa = _compensateP(rawP, t_fine);

        // Compensate humidity (BME280 only)
        if (_isBME) {
            r.humidity_pct = _compensateH(rawH, t_fine);
        }

        // Sanity check
        if (r.temperature_c > -40 && r.temperature_c < 85 &&
            r.pressure_pa > 30000 && r.pressure_pa < 110000) {
            r.valid = true;
        }

        return r;
    }

private:
    TwoWire* _wire = nullptr;
    uint8_t _addr = BME280_ADDR;
    bool _available = false;
    bool _isBME = false;

    // Calibration data (from registers 0x88..0xA1, 0xE1..0xE7)
    uint16_t _dig_T1; int16_t _dig_T2, _dig_T3;
    uint16_t _dig_P1; int16_t _dig_P2, _dig_P3, _dig_P4, _dig_P5;
    int16_t _dig_P6, _dig_P7, _dig_P8, _dig_P9;
    uint8_t _dig_H1, _dig_H3; int16_t _dig_H2, _dig_H4, _dig_H5; int8_t _dig_H6;

    void _readCalibration() {
        uint8_t buf[26];
        _readRegs(0x88, buf, 26);  // T1..P9

        _dig_T1 = (uint16_t)(buf[1] << 8 | buf[0]);
        _dig_T2 = (int16_t)(buf[3] << 8 | buf[2]);
        _dig_T3 = (int16_t)(buf[5] << 8 | buf[4]);
        _dig_P1 = (uint16_t)(buf[7] << 8 | buf[6]);
        _dig_P2 = (int16_t)(buf[9] << 8 | buf[8]);
        _dig_P3 = (int16_t)(buf[11] << 8 | buf[10]);
        _dig_P4 = (int16_t)(buf[13] << 8 | buf[12]);
        _dig_P5 = (int16_t)(buf[15] << 8 | buf[14]);
        _dig_P6 = (int16_t)(buf[17] << 8 | buf[16]);
        _dig_P7 = (int16_t)(buf[19] << 8 | buf[18]);
        _dig_P8 = (int16_t)(buf[21] << 8 | buf[20]);
        _dig_P9 = (int16_t)(buf[23] << 8 | buf[22]);

        _dig_H1 = _readReg(0xA1);

        if (_isBME) {
            uint8_t hbuf[7];
            _readRegs(0xE1, hbuf, 7);
            _dig_H2 = (int16_t)(hbuf[1] << 8 | hbuf[0]);
            _dig_H3 = hbuf[2];
            _dig_H4 = (int16_t)((hbuf[3] << 4) | (hbuf[4] & 0x0F));
            _dig_H5 = (int16_t)((hbuf[5] << 4) | (hbuf[4] >> 4));
            _dig_H6 = (int8_t)hbuf[6];
        }
    }

    int32_t _compensateT(int32_t adc_T) {
        int32_t var1 = ((((adc_T >> 3) - ((int32_t)_dig_T1 << 1))) * ((int32_t)_dig_T2)) >> 11;
        int32_t var2 = (((((adc_T >> 4) - ((int32_t)_dig_T1)) * ((adc_T >> 4) - ((int32_t)_dig_T1))) >> 12) * ((int32_t)_dig_T3)) >> 14;
        return var1 + var2;  // t_fine
    }

    float _compensateP(int32_t adc_P, int32_t t_fine) {
        int64_t var1 = (int64_t)t_fine - 128000;
        int64_t var2 = var1 * var1 * (int64_t)_dig_P6;
        var2 = var2 + ((var1 * (int64_t)_dig_P5) << 17);
        var2 = var2 + (((int64_t)_dig_P4) << 35);
        var1 = ((var1 * var1 * (int64_t)_dig_P3) >> 8) + ((var1 * (int64_t)_dig_P2) << 12);
        var1 = (((((int64_t)1) << 47) + var1)) * ((int64_t)_dig_P1) >> 33;
        if (var1 == 0) return 0;
        int64_t p = 1048576 - adc_P;
        p = (((p << 31) - var2) * 3125) / var1;
        var1 = (((int64_t)_dig_P9) * (p >> 13) * (p >> 13)) >> 25;
        var2 = (((int64_t)_dig_P8) * p) >> 19;
        p = ((p + var1 + var2) >> 8) + (((int64_t)_dig_P7) << 4);
        return (float)p / 256.0f;
    }

    float _compensateH(int32_t adc_H, int32_t t_fine) {
        int32_t v = t_fine - 76800;
        v = (((((adc_H << 14) - (((int32_t)_dig_H4) << 20) - (((int32_t)_dig_H5) * v)) + 16384) >> 15) *
             (((((((v * ((int32_t)_dig_H6)) >> 10) * (((v * ((int32_t)_dig_H3)) >> 11) + 32768)) >> 10) + 2097152) * ((int32_t)_dig_H2) + 8192) >> 14));
        v = v - (((((v >> 15) * (v >> 15)) >> 7) * ((int32_t)_dig_H1)) >> 4);
        v = (v < 0) ? 0 : v;
        v = (v > 419430400) ? 419430400 : v;
        return (float)(v >> 12) / 1024.0f;
    }

    uint8_t _readReg(uint8_t reg) {
        _wire->beginTransmission(_addr);
        _wire->write(reg);
        uint8_t err = _wire->endTransmission(false);
        if (err != 0) { g_i2cHealth.nackErrors++; return 0x00; }
        uint8_t received = _wire->requestFrom(_addr, (uint8_t)1);
        if (received < 1) { g_i2cHealth.shortReads++; return 0x00; }
        g_i2cHealth.successfulReads++;
        return _wire->read();
    }

    /// Returns actual bytes read. Caller MUST check return == len.
    uint8_t _readRegs(uint8_t reg, uint8_t* buf, uint8_t len) {
        memset(buf, 0, len);
        _wire->beginTransmission(_addr);
        _wire->write(reg);
        uint8_t err = _wire->endTransmission(false);
        if (err != 0) { g_i2cHealth.nackErrors++; return 0; }
        uint8_t received = _wire->requestFrom(_addr, len);
        if (received < len) { g_i2cHealth.shortReads++; }
        uint8_t actual = 0;
        for (uint8_t i = 0; i < received && _wire->available(); i++) {
            buf[i] = _wire->read();
            actual++;
        }
        if (actual == len) g_i2cHealth.successfulReads++;
        return actual;
    }

    bool _writeReg(uint8_t reg, uint8_t val) {
        _wire->beginTransmission(_addr);
        _wire->write(reg);
        _wire->write(val);
        uint8_t err = _wire->endTransmission();
        if (err != 0) { g_i2cHealth.nackErrors++; return false; }
        return true;
    }
};


// ═══════════════════════════════════════════════════════════════
//  INA226 — Вольтметр / Амперметр / Ваттметр
//  Datasheet: Texas Instruments SBOS547A
//  I2C Address: 0x40 (default, A0=A1=GND)
//  Shunt resistor: 0.1 Ω (assumed)
// ═══════════════════════════════════════════════════════════════

class INA226Driver {
public:
    struct Reading {
        float voltage_v;    // Bus voltage, V (LSB = 1.25 mV)
        float current_a;    // Current through shunt, A
        float power_w;      // Calculated power, W
        bool valid;
    };

    bool begin(TwoWire& wire = Wire, uint8_t addr = INA226_ADDR,
               float shuntResistorOhm = 0.1f) {
        _wire = &wire;
        _addr = addr;
        _shuntR = shuntResistorOhm;

        // Read Manufacturer ID (0xFE) — should be 0x5449 ("TI")
        uint16_t mfgId = _readReg16(0xFE);
        if (mfgId != 0x5449) {
            Serial.printf("[INA226] Manufacturer ID mismatch: 0x%04X (expected 0x5449)\n", mfgId);
            _available = false;
            return false;
        }

        // Die ID (0xFF) — should be 0x2260
        uint16_t dieId = _readReg16(0xFF);
        Serial.printf("[INA226] Found MfgID=0x%04X DieID=0x%04X at 0x%02X\n", mfgId, dieId, _addr);

        // Reset
        _writeReg16(0x00, 0x8000);
        delay(5);

        // Configuration register (0x00):
        // AVG=010 (16 samples), VBUSCT=100 (1.1ms), VSHCT=100 (1.1ms),
        // MODE=111 (continuous shunt+bus)
        // = 0b0100_010_100_100_111 = 0x4527
        _writeReg16(0x00, 0x4527);

        // Calibration register (0x05):
        // CAL = 0.00512 / (CurrentLSB * Rshunt)
        // Choose CurrentLSB = 0.001 A (1 mA) → CAL = 0.00512 / (0.001 * 0.1) = 51.2 → 51
        _currentLSB = 0.001f;  // 1 mA per bit
        uint16_t cal = (uint16_t)(0.00512f / (_currentLSB * _shuntR));
        _writeReg16(0x05, cal);

        _available = true;
        return true;
    }

    bool available() const { return _available; }

    /// Store zero-offsets for voltage and current.
    /// Call with current reading when probes are shorted / open.
    /// Persists to NVS so offsets survive power cycles.
    void setZeroOffset(float offsetV, float offsetA) {
        _offsetV = offsetV;
        _offsetA = offsetA;
        Serial.printf("[INA226] Zero offset set: V=%.4f A=%.4f\n", offsetV, offsetA);

        // Persist to NVS (Non-Volatile Storage)
        nvs_handle_t nvs;
        if (nvs_open("ina226_cal", NVS_READWRITE, &nvs) == ESP_OK) {
            // NVS doesn't support float directly — store as raw bytes
            nvs_set_blob(nvs, "off_v", &_offsetV, sizeof(_offsetV));
            nvs_set_blob(nvs, "off_a", &_offsetA, sizeof(_offsetA));
            nvs_commit(nvs);
            nvs_close(nvs);
            Serial.println("[INA226] Offsets saved to NVS");
        }
    }

    /// Clear calibration offsets (also erases NVS)
    void clearZeroOffset() {
        _offsetV = 0;
        _offsetA = 0;
        nvs_handle_t nvs;
        if (nvs_open("ina226_cal", NVS_READWRITE, &nvs) == ESP_OK) {
            nvs_erase_all(nvs);
            nvs_commit(nvs);
            nvs_close(nvs);
        }
    }

    /// Load calibration offsets from NVS (call after begin())
    void loadCalibrationFromNVS() {
        nvs_handle_t nvs;
        if (nvs_open("ina226_cal", NVS_READONLY, &nvs) == ESP_OK) {
            size_t sz = sizeof(float);
            float v = 0, a = 0;
            bool loaded = false;
            if (nvs_get_blob(nvs, "off_v", &v, &sz) == ESP_OK &&
                nvs_get_blob(nvs, "off_a", &a, &sz) == ESP_OK) {
                _offsetV = v;
                _offsetA = a;
                loaded = true;
            }
            nvs_close(nvs);
            if (loaded) {
                Serial.printf("[INA226] Loaded NVS offsets: V=%.4f A=%.4f\n", _offsetV, _offsetA);
            }
        }
    }

    Reading read() {
        Reading r = {0, 0, 0, false};
        if (!_available) return r;

        // Bus voltage (reg 0x02): LSB = 1.25 mV
        uint16_t rawBusU = _readReg16(0x02);
        if (rawBusU == 0xFFFF) return r;  // I2C bus error
        int16_t rawBus = (int16_t)rawBusU;
        r.voltage_v = rawBus * 1.25e-3f - _offsetV;

        // Current (reg 0x04): LSB = _currentLSB (set by calibration)
        uint16_t rawCurrentU = _readReg16(0x04);
        if (rawCurrentU == 0xFFFF) return r;  // I2C bus error
        int16_t rawCurrent = (int16_t)rawCurrentU;
        r.current_a = rawCurrent * _currentLSB - _offsetA;

        // Power = V * I (recalculated after offset)
        r.power_w = r.voltage_v * r.current_a;

        // Sanity: bus voltage -1..36V, current -10..+10A (allow slight negative after offset)
        if (r.voltage_v >= -1.0f && r.voltage_v <= 36.0f &&
            r.current_a >= -10.0f && r.current_a <= 10.0f) {
            r.valid = true;
        }

        return r;
    }

private:
    TwoWire* _wire = nullptr;
    uint8_t _addr = INA226_ADDR;
    bool _available = false;
    float _shuntR = 0.1f;
    float _currentLSB = 0.001f;
    float _offsetV = 0.0f;
    float _offsetA = 0.0f;

    /// Read 16-bit register. Returns 0xFFFF on bus error (invalid sentinel).
    uint16_t _readReg16(uint8_t reg) {
        _wire->beginTransmission(_addr);
        _wire->write(reg);
        uint8_t err = _wire->endTransmission(false);
        if (err != 0) { g_i2cHealth.nackErrors++; return 0xFFFF; }
        uint8_t received = _wire->requestFrom(_addr, (uint8_t)2);
        if (received < 2) { g_i2cHealth.shortReads++; return 0xFFFF; }
        g_i2cHealth.successfulReads++;
        uint8_t hi = _wire->read();
        uint8_t lo = _wire->read();
        return (uint16_t)(hi << 8 | lo);
    }

    bool _writeReg16(uint8_t reg, uint16_t val) {
        _wire->beginTransmission(_addr);
        _wire->write(reg);
        _wire->write((uint8_t)(val >> 8));
        _wire->write((uint8_t)(val & 0xFF));
        uint8_t err = _wire->endTransmission();
        if (err != 0) { g_i2cHealth.nackErrors++; return false; }
        return true;
    }
};


// ═══════════════════════════════════════════════════════════════
//  LSM6DS3 — Акселерометр + Гироскоп (6-axis IMU)
//  Datasheet: STMicroelectronics DocID026899
//  I2C Address: 0x6A (SDO=GND) or 0x6B (SDO=VCC)
// ═══════════════════════════════════════════════════════════════

class LSM6DS3Driver {
public:
    struct Reading {
        float accel_x, accel_y, accel_z;   // m/s²
        float gyro_x, gyro_y, gyro_z;      // °/s (dps)
        bool valid;
    };

    bool begin(TwoWire& wire = Wire, uint8_t addr = LSM6DS3_ADDR) {
        _wire = &wire;
        _addr = addr;

        // WHO_AM_I (0x0F) — should be 0x69 (LSM6DS3) or 0x6A (LSM6DS3TR-C)
        uint8_t whoAmI = _readReg(0x0F);
        if (whoAmI != 0x69 && whoAmI != 0x6A) {
            Serial.printf("[LSM6DS3] WHO_AM_I mismatch: 0x%02X (expected 0x69/0x6A)\n", whoAmI);
            _available = false;
            return false;
        }
        Serial.printf("[LSM6DS3] Found WHO_AM_I=0x%02X at 0x%02X\n", whoAmI, _addr);

        // Software reset
        _writeReg(0x12, 0x01);  // CTRL3_C: SW_RESET
        delay(20);

        // CTRL1_XL (0x10): ODR_XL=0100 (104 Hz), FS_XL=00 (±2g), BW_XL=00
        _writeReg(0x10, 0x40);
        _accelScale = 2.0f * 9.80665f / 32768.0f;  // ±2g → m/s²

        // CTRL2_G (0x11): ODR_G=0100 (104 Hz), FS_G=01 (±500 dps)
        _writeReg(0x11, 0x44);
        _gyroScale = 500.0f / 32768.0f;  // ±500 dps

        // CTRL3_C (0x12): BDU=1 (block data update), IF_INC=1 (auto-increment)
        _writeReg(0x12, 0x44);

        _available = true;
        return true;
    }

    bool available() const { return _available; }

    Reading read() {
        Reading r = {0, 0, 0, 0, 0, 0, false};
        if (!_available) return r;

        // Check STATUS_REG (0x1E): bit 0 = XLDA (accel), bit 1 = GDA (gyro)
        uint8_t status = _readReg(0x1E);
        if (!(status & 0x01)) {
            return r;  // No new data yet
        }

        // Read all 12 bytes at once: OUTX_L_G(0x22)..OUTZ_H_XL(0x2D)
        uint8_t buf[12];
        uint8_t bytesRead = _readRegs(0x22, buf, 12);
        if (bytesRead < 12) {
            // I2C bus error — return invalid rather than garbage
            return r;
        }

        // Gyroscope (first 6 bytes)
        int16_t rawGX = (int16_t)(buf[1] << 8 | buf[0]);
        int16_t rawGY = (int16_t)(buf[3] << 8 | buf[2]);
        int16_t rawGZ = (int16_t)(buf[5] << 8 | buf[4]);
        r.gyro_x = rawGX * _gyroScale;
        r.gyro_y = rawGY * _gyroScale;
        r.gyro_z = rawGZ * _gyroScale;

        // Accelerometer (next 6 bytes)
        int16_t rawAX = (int16_t)(buf[7] << 8 | buf[6]);
        int16_t rawAY = (int16_t)(buf[9] << 8 | buf[8]);
        int16_t rawAZ = (int16_t)(buf[11] << 8 | buf[10]);
        r.accel_x = rawAX * _accelScale;
        r.accel_y = rawAY * _accelScale;
        r.accel_z = rawAZ * _accelScale;

        // Sanity check: reject physically impossible values
        // ±2g = ±19.6 m/s², allow 25 m/s² for margin; ±500 dps
        const float kMaxAccel = 25.0f;   // m/s² (slightly above ±2g range)
        const float kMaxGyro  = 550.0f;  // dps (slightly above ±500 range)
        if (fabsf(r.accel_x) < kMaxAccel && fabsf(r.accel_y) < kMaxAccel &&
            fabsf(r.accel_z) < kMaxAccel && fabsf(r.gyro_x) < kMaxGyro &&
            fabsf(r.gyro_y) < kMaxGyro && fabsf(r.gyro_z) < kMaxGyro) {
            r.valid = true;
        }

        return r;
    }

private:
    TwoWire* _wire = nullptr;
    uint8_t _addr = LSM6DS3_ADDR;
    bool _available = false;
    float _accelScale = 0;
    float _gyroScale = 0;

    uint8_t _readReg(uint8_t reg) {
        _wire->beginTransmission(_addr);
        _wire->write(reg);
        uint8_t err = _wire->endTransmission(false);
        if (err != 0) { g_i2cHealth.nackErrors++; return 0x00; }
        uint8_t received = _wire->requestFrom(_addr, (uint8_t)1);
        if (received < 1) { g_i2cHealth.shortReads++; return 0x00; }
        g_i2cHealth.successfulReads++;
        return _wire->read();
    }

    /// Returns actual bytes read. Caller MUST check return == len.
    uint8_t _readRegs(uint8_t reg, uint8_t* buf, uint8_t len) {
        memset(buf, 0, len);
        _wire->beginTransmission(_addr);
        _wire->write(reg);
        uint8_t err = _wire->endTransmission(false);
        if (err != 0) { g_i2cHealth.nackErrors++; return 0; }
        uint8_t received = _wire->requestFrom(_addr, len);
        if (received < len) { g_i2cHealth.shortReads++; }
        uint8_t actual = 0;
        for (uint8_t i = 0; i < received && _wire->available(); i++) {
            buf[i] = _wire->read();
            actual++;
        }
        if (actual == len) g_i2cHealth.successfulReads++;
        return actual;
    }

    bool _writeReg(uint8_t reg, uint8_t val) {
        _wire->beginTransmission(_addr);
        _wire->write(reg);
        _wire->write(val);
        uint8_t err = _wire->endTransmission();
        if (err != 0) { g_i2cHealth.nackErrors++; return false; }
        return true;
    }
};


// ═══════════════════════════════════════════════════════════════
//  VL53L1X — Лазерный дальномер (Time-of-Flight)
//  Datasheet: STMicroelectronics DocID031065
//  I2C Address: 0x29 (default)
//  Range: 40–4000 mm (dark), up to 1300 mm (strong ambient light)
//
//  NOTE: VL53L1X requires a complex firmware blob upload on init.
//  This driver uses the "ultra lite" approach — minimal registers
//  from ST's VL53L1X ULD (Ultra Lite Driver) application note.
// ═══════════════════════════════════════════════════════════════

class VL53L1XDriver {
public:
    struct Reading {
        float distance_mm;     // Distance in mm
        uint8_t rangeStatus;   // 0=valid, other=error
        bool valid;
    };

    bool begin(TwoWire& wire = Wire, uint8_t addr = VL53L1X_ADDR) {
        _wire = &wire;
        _addr = addr;

        // Check model ID (0x010F) — should be 0xEA, 0xCC
        uint8_t modelId = _readReg16Addr(0x010F);
        if (modelId != 0xEA) {
            Serial.printf("[VL53L1X] Model ID mismatch: 0x%02X (expected 0xEA)\n", modelId);
            _available = false;
            return false;
        }
        Serial.printf("[VL53L1X] Found Model ID=0x%02X at 0x%02X\n", modelId, _addr);

        // Wait for device boot (register 0x00E5 == 0x03)
        uint32_t startMs = millis();
        while (_readReg16Addr(0x00E5) != 0x03) {
            if (millis() - startMs > 1000) {
                Serial.println("[VL53L1X] Boot timeout");
                _available = false;
                return false;
            }
            delay(10);
        }

        // ── Init sequence (from ST VL53L1X ULD) ──
        // This is the minimal configuration for short-range mode
        _writeReg16Addr(static_cast<uint16_t>(0x002D), static_cast<uint8_t>(0x06));  // timing budget, etc.
        _writeReg16Addr(static_cast<uint16_t>(0x0051), static_cast<uint16_t>(0x0104));  // IntermeasurementPeriod (approximated)
        // Short range mode: 1.4m max, but more robust
        _writeReg16Addr(static_cast<uint16_t>(0x0060), static_cast<uint8_t>(0x0f));   // Range config
        _writeReg16Addr(static_cast<uint16_t>(0x0063), static_cast<uint8_t>(0x0d));
        _writeReg16Addr(static_cast<uint16_t>(0x0069), static_cast<uint8_t>(0x12));

        // Start continuous ranging
        _writeReg16Addr(static_cast<uint16_t>(0x0087), static_cast<uint8_t>(0x40));  // Start command

        _available = true;
        return true;
    }

    bool available() const { return _available; }

    Reading read() {
        Reading r = {0, 0xFF, false};
        if (!_available) return r;

        // Check if new data is ready (GPIO__TIO_HV_STATUS, bit 0)
        uint8_t status = _readReg16Addr(0x0031);
        if (!(status & 0x01)) {
            return r;  // No new data
        }

        // Read range result (2 bytes at 0x0096)
        uint8_t hi = _readReg16Addr(0x0096);
        uint8_t lo = _readReg16Addr(0x0097);
        uint16_t rawDist = (uint16_t)(hi << 8 | lo);

        // Range status (0x0089)
        r.rangeStatus = _readReg16Addr(0x0089) & 0x1F;

        // Clear interrupt
        _writeReg16Addr(static_cast<uint16_t>(0x0086), static_cast<uint8_t>(0x01));

        r.distance_mm = (float)rawDist;

        // Valid if status == 0 (range valid) and distance is reasonable
        if (r.rangeStatus == 0 && rawDist > 0 && rawDist < 4100) {
            r.valid = true;
        }

        return r;
    }

private:
    TwoWire* _wire = nullptr;
    uint8_t _addr = VL53L1X_ADDR;
    bool _available = false;

    // VL53L1X uses 16-bit register addresses
    uint8_t _readReg16Addr(uint16_t reg) {
        _wire->beginTransmission(_addr);
        _wire->write((uint8_t)(reg >> 8));
        _wire->write((uint8_t)(reg & 0xFF));
        uint8_t err = _wire->endTransmission(false);
        if (err != 0) { g_i2cHealth.nackErrors++; return 0x00; }
        uint8_t received = _wire->requestFrom(_addr, (uint8_t)1);
        if (received < 1) { g_i2cHealth.shortReads++; return 0x00; }
        g_i2cHealth.successfulReads++;
        return _wire->read();
    }

    bool _writeReg16Addr(uint16_t reg, uint8_t val) {
        _wire->beginTransmission(_addr);
        _wire->write((uint8_t)(reg >> 8));
        _wire->write((uint8_t)(reg & 0xFF));
        _wire->write(val);
        uint8_t err = _wire->endTransmission();
        if (err != 0) { g_i2cHealth.nackErrors++; return false; }
        return true;
    }

    bool _writeReg16Addr(uint16_t reg, uint16_t val) {
        _wire->beginTransmission(_addr);
        _wire->write((uint8_t)(reg >> 8));
        _wire->write((uint8_t)(reg & 0xFF));
        _wire->write((uint8_t)(val >> 8));
        _wire->write((uint8_t)(val & 0xFF));
        uint8_t err = _wire->endTransmission();
        if (err != 0) { g_i2cHealth.nackErrors++; return false; }
        return true;
    }
};


// ═══════════════════════════════════════════════════════════════
//  MAX31855 — Термопара (SPI)
//  Datasheet: Maxim Integrated 19-0545
//  SPI: CPOL=0, CPHA=0, MSB first, read-only
// ═══════════════════════════════════════════════════════════════

class MAX31855Driver {
public:
    struct Reading {
        float thermocouple_c;   // Hot junction (thermocouple), °C
        float internal_c;       // Cold junction (internal), °C
        uint8_t fault;          // 0=OK, bit0=OC, bit1=SCG, bit2=SCV
        bool valid;
    };

    bool begin(int csPin = SPI_CS_THERMO_PIN) {
        _csPin = csPin;
        pinMode(_csPin, OUTPUT);
        digitalWrite(_csPin, HIGH);

        // Probe: read SPI and check if chip responds
        _available = true;  // temporarily allow read()
        Reading r = read();

        // All fault bits set (0x07) = no chip / open circuit on all pins.
        // All zeros = SPI MISO floating low (not connected).
        if (r.fault == 0x07) {
            _available = false;
            Serial.printf("[MAX31855] No chip detected (CS=%d, fault=0x%02X)\n",
                _csPin, r.fault);
            return false;
        }

        Serial.printf("[MAX31855] OK: tc=%.1f°C, internal=%.1f°C, CS=%d\n",
            r.thermocouple_c, r.internal_c, _csPin);
        return true;
    }

    bool available() const { return _available; }

    Reading read() {
        Reading r = {0, 0, 0x07, false};
        if (!_available) return r;

        // Read 32 bits from MAX31855
        digitalWrite(_csPin, LOW);
        delayMicroseconds(1);

        uint32_t raw = 0;
        raw |= (uint32_t)SPI.transfer(0) << 24;
        raw |= (uint32_t)SPI.transfer(0) << 16;
        raw |= (uint32_t)SPI.transfer(0) << 8;
        raw |= (uint32_t)SPI.transfer(0);

        digitalWrite(_csPin, HIGH);

        // Check fault bit (bit 16)
        if (raw & 0x00010000) {
            r.fault = raw & 0x07;  // bits 2:0 = SCV, SCG, OC
            return r;
        }

        // Thermocouple temperature: bits 31:18, 14-bit signed, LSB = 0.25°C
        int16_t tcRaw = (int16_t)((raw >> 18) & 0x3FFF);
        if (tcRaw & 0x2000) tcRaw |= 0xC000;  // Sign extend
        r.thermocouple_c = tcRaw * 0.25f;

        // Internal (cold junction): bits 15:4, 12-bit signed, LSB = 0.0625°C
        int16_t intRaw = (int16_t)((raw >> 4) & 0x0FFF);
        if (intRaw & 0x0800) intRaw |= 0xF000;
        r.internal_c = intRaw * 0.0625f;

        r.fault = 0;

        // Sanity check
        if (r.thermocouple_c > -200 && r.thermocouple_c < 1400) {
            r.valid = true;
        }

        return r;
    }

private:
    int _csPin = SPI_CS_THERMO_PIN;
    bool _available = false;
};
