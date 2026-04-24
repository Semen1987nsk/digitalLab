/*
 * ╔══════════════════════════════════════════════════════════════════╗
 * ║  LABOSFERA — Мультидатчик по Физике                            ║
 * ║  Firmware v0.4 | Arduino UNO R3 + BME280 + MPU6050             ║
 * ╠══════════════════════════════════════════════════════════════════╣
 * ║  Соответствие: ТЗ Labosfera v2.2, ФГОС ООО/СОО,               ║
 * ║  Приказ Минпросвещения №838, Письмо №ТВ-2356/02                ║
 * ╠══════════════════════════════════════════════════════════════════╣
 * ║  РЕАЛЬНЫЕ ДАТЧИКИ (подтверждено I2C сканированием):            ║
 * ║    BME280 @ 0x76 — Температура + Давление + Влажность          ║
 * ║    MPU6050 @ 0x68 — Акселерометр 3-оси + Гироскоп              ║
 * ║    A0 (аналог) — Напряжение, A1 — Ток (шунт)                  ║
 * ╠══════════════════════════════════════════════════════════════════╣
 * ║  v0.4 CHANGES (reliability):                                   ║
 * ║    + Watchdog Timer (WDT) — auto-reset on freeze               ║
 * ║    + I2C bus recovery (SDA unstick on lockup)                   ║
 * ║    + CRC8 checksum on every data line                          ║
 * ║    + Non-blocking serial command read                          ║
 * ║    + Periodic sensor health check with auto-reinit             ║
 * ║    + Drift-free timing via accumulator pattern                 ║
 * ║    + Serial timeout (no infinite hang on !Serial)              ║
 * ║    + Sensor error counters for diagnostics                     ║
 * ║    + I2C read return-value checking throughout                 ║
 * ║    + Sanity checks on sensor readings                          ║
 * ╚══════════════════════════════════════════════════════════════════╝
 *
 * КАНАЛЫ ВЫВОДА (10 Гц):
 *   V:±X.XXX   — Напряжение (В), A0, 16x oversampling
 *   A:X.XXX    — Ток (А), A1 через шунт
 *   T:XX.XX    — Температура (°C), BME280 I2C
 *   P:XXXXX.X  — Давление (Па), BME280 I2C
 *   H:XX.X     — Влажность (%), BME280 I2C
 *   AX:±X.XXX  — Ускорение X (g), MPU6050
 *   AY:±X.XXX  — Ускорение Y (g), MPU6050
 *   AZ:±X.XXX  — Ускорение Z (g), MPU6050
 *   *XX        — CRC8 контрольная сумма (hex)
 */

#include <Wire.h>
#include <math.h>
#include <avr/wdt.h>

// ═══════════════════════════════════════════════════════════
//  КОНФИГУРАЦИЯ
// ═══════════════════════════════════════════════════════════

// Напряжение (A0)
const float V_DIVIDER_RATIO  = 1.0;   // 1.0=прямое, 3.0=делитель

// Ток (A1)
const float SHUNT_RESISTANCE = 1.0;   // Ом (прототип)

// АЦП
const float V_REF            = 5.0;
const int   ADC_MAX          = 1023;
const int   OVERSAMPLE       = 16;
const int   SEND_INTERVAL_MS = 100;   // 10 Гц

// I2C адреса
const uint8_t BME280_ADDR    = 0x76;
const uint8_t MPU6050_ADDR   = 0x68;
const uint8_t HMC5883L_ADDR  = 0x1E;
const uint8_t QMC5883L_ADDR  = 0x0D;

// MPU6050 шкала: 0=±2g, 1=±4g, 2=±8g, 3=±16g
const uint8_t MPU_ACCEL_RANGE = 0;    // ±2g → 16384 LSB/g
const float   MPU_ACCEL_SCALE = 16384.0;

// I2C Recovery pins (AVR hardware I2C)
const int I2C_SDA_PIN_RECOVERY = A4;
const int I2C_SCL_PIN_RECOVERY = A5;

// Sensor health check interval (every N packets)
const int HEALTH_CHECK_INTERVAL = 100;  // ~10 секунд при 10 Гц

// Serial wait timeout at startup (ms)
const unsigned long SERIAL_WAIT_TIMEOUT_MS = 3000;

// ═══════════════════════════════════════════════════════════
//  FORWARD STRUCT DECLARATIONS
//  (Arduino IDE auto-generates function prototypes at top;
//   structs used as return types must be declared before them)
// ═══════════════════════════════════════════════════════════

struct AdcResult { float mean; float variance; };

// ═══════════════════════════════════════════════════════════
//  CRC8 (Dallas/Maxim, polynomial 0x31)
//  Used for data integrity between Arduino ↔ Flutter app
// ═══════════════════════════════════════════════════════════

uint8_t crc8(const char* data, uint16_t len) {
  uint8_t crc = 0x00;
  for (uint16_t i = 0; i < len; i++) {
    uint8_t b = (uint8_t)data[i];
    for (uint8_t bit = 0; bit < 8; bit++) {
      if ((crc ^ b) & 0x01) {
        crc = (crc >> 1) ^ 0x8C;  // Reflected 0x31
      } else {
        crc >>= 1;
      }
      b >>= 1;
    }
  }
  return crc;
}

// ═══════════════════════════════════════════════════════════
//  BME280 КАЛИБРОВОЧНЫЕ ДАННЫЕ
// ═══════════════════════════════════════════════════════════

struct BME280Cal {
  uint16_t dig_T1;
  int16_t  dig_T2, dig_T3;
  uint16_t dig_P1;
  int16_t  dig_P2, dig_P3, dig_P4, dig_P5;
  int16_t  dig_P6, dig_P7, dig_P8, dig_P9;
  uint8_t  dig_H1, dig_H3;
  int16_t  dig_H2, dig_H4, dig_H5;
  int8_t   dig_H6;
  int32_t  t_fine;
};

BME280Cal bme;
bool g_bmeOk          = false;
bool g_mpuOk          = false;
bool g_magOk          = false;

enum MagChipType : uint8_t {
  MAG_NONE = 0,
  MAG_HMC5883L = 1,
  MAG_QMC5883L = 2,
};

MagChipType g_magChip = MAG_NONE;
float g_magFieldMt    = 0;

unsigned long g_nextSendMs  = 0;      // Drift-free timing target
unsigned long g_packetCount = 0;

// Error counters for diagnostics
uint16_t g_bmeErrors   = 0;
uint16_t g_mpuErrors   = 0;
uint16_t g_magErrors   = 0;
uint16_t g_i2cRecovers = 0;

// Non-blocking serial command buffer
char g_cmdBuf[32];
uint8_t g_cmdLen = 0;

// ═══════════════════════════════════════════════════════════
//  I2C BUS RECOVERY
// ═══════════════════════════════════════════════════════════

/// Attempts to recover a stuck I2C bus by bit-banging SCL.
///
/// If a slave holds SDA low (e.g. due to incomplete transaction after
/// Arduino reset), the bus is deadlocked. Wire.begin() won't fix it.
/// Solution: toggle SCL up to 9 times to let the slave release SDA.
///
/// MUST be called BEFORE Wire.begin() or after TWCR=0.
void i2cBusRecovery() {
  pinMode(I2C_SDA_PIN_RECOVERY, INPUT_PULLUP);
  pinMode(I2C_SCL_PIN_RECOVERY, OUTPUT);

  // Generate up to 9 clock pulses — a stuck slave will release SDA
  // after its current byte completes (max 8 bits + ACK = 9 clocks)
  for (int i = 0; i < 9; i++) {
    digitalWrite(I2C_SCL_PIN_RECOVERY, LOW);
    delayMicroseconds(5);
    digitalWrite(I2C_SCL_PIN_RECOVERY, HIGH);
    delayMicroseconds(5);
    if (digitalRead(I2C_SDA_PIN_RECOVERY) == HIGH) break;
  }

  // Generate STOP condition: SDA low→high while SCL is high
  pinMode(I2C_SDA_PIN_RECOVERY, OUTPUT);
  digitalWrite(I2C_SDA_PIN_RECOVERY, LOW);
  delayMicroseconds(5);
  digitalWrite(I2C_SCL_PIN_RECOVERY, HIGH);
  delayMicroseconds(5);
  digitalWrite(I2C_SDA_PIN_RECOVERY, HIGH);
  delayMicroseconds(5);

  // Release pins back for Wire library
  pinMode(I2C_SDA_PIN_RECOVERY, INPUT);
  pinMode(I2C_SCL_PIN_RECOVERY, INPUT);
}

// Forward declarations
bool bmeInit();
bool mpuInit();
bool magInit();

/// Full I2C reinit: bus recovery + Wire restart + sensor reinit
void i2cFullRecovery() {
  Serial.println(F("# I2C_RECOVERY: starting..."));
  g_i2cRecovers++;

  // Shut down TWI hardware
  TWCR = 0;
  delay(10);

  // Bit-bang recovery
  i2cBusRecovery();

  // Restart Wire
  Wire.begin();
  Wire.setClock(400000);
  delay(10);

  // Reinit sensors
  bool bmeWas = g_bmeOk;
  bool mpuWas = g_mpuOk;
  bool magWas = g_magOk;

  g_bmeOk = bmeInit();
  g_mpuOk = mpuInit();
  g_magOk = magInit();

  Serial.print(F("# I2C_RECOVERY: BME "));
  Serial.print(bmeWas ? F("OK") : F("ERR"));
  Serial.print(F("->"));
  Serial.println(g_bmeOk ? F("OK") : F("FAIL"));

  Serial.print(F("# I2C_RECOVERY: MPU "));
  Serial.print(mpuWas ? F("OK") : F("ERR"));
  Serial.print(F("->"));
  Serial.println(g_mpuOk ? F("OK") : F("FAIL"));

  Serial.print(F("# I2C_RECOVERY: MAG "));
  Serial.print(magWas ? F("OK") : F("ERR"));
  Serial.print(F("->"));
  Serial.println(g_magOk ? F("OK") : F("FAIL"));
}

// ═══════════════════════════════════════════════════════════
//  I2C УТИЛИТЫ (with error checking)
// ═══════════════════════════════════════════════════════════

uint8_t i2cRead8(uint8_t addr, uint8_t reg) {
  Wire.beginTransmission(addr);
  Wire.write(reg);
  uint8_t err = Wire.endTransmission(false);
  if (err != 0) return 0xFF;
  uint8_t count = Wire.requestFrom(addr, (uint8_t)1);
  if (count == 0) return 0xFF;
  return Wire.available() ? Wire.read() : 0xFF;
}

void i2cWrite8(uint8_t addr, uint8_t reg, uint8_t val) {
  Wire.beginTransmission(addr);
  Wire.write(reg);
  Wire.write(val);
  Wire.endTransmission();
}

/// Reads multiple bytes via I2C. Returns number of bytes actually read.
uint8_t i2cReadBuf(uint8_t addr, uint8_t reg, uint8_t* buf, uint8_t len) {
  Wire.beginTransmission(addr);
  Wire.write(reg);
  uint8_t err = Wire.endTransmission(false);
  if (err != 0) {
    memset(buf, 0, len);
    return 0;
  }
  uint8_t count = Wire.requestFrom(addr, len);
  uint8_t i = 0;
  for (; i < len && Wire.available(); i++) {
    buf[i] = Wire.read();
  }
  for (; i < len; i++) {
    buf[i] = 0;
  }
  return count;
}

// ═══════════════════════════════════════════════════════════
//  BME280: ИНИЦИАЛИЗАЦИЯ И ЧТЕНИЕ
//  Datasheet: Bosch BME280, Section 4.2.2
// ═══════════════════════════════════════════════════════════

bool bmeInit() {
  uint8_t id = i2cRead8(BME280_ADDR, 0xD0);
  if (id != 0x60 && id != 0x58) return false;

  // Soft reset
  i2cWrite8(BME280_ADDR, 0xE0, 0xB6);
  delay(10);

  // Read calibration (0x88..0x9F, 26 bytes)
  uint8_t cal[26];
  if (i2cReadBuf(BME280_ADDR, 0x88, cal, 26) < 26) return false;

  bme.dig_T1 = (uint16_t)(cal[0] | (cal[1] << 8));
  bme.dig_T2 = (int16_t)(cal[2] | (cal[3] << 8));
  bme.dig_T3 = (int16_t)(cal[4] | (cal[5] << 8));
  bme.dig_P1 = (uint16_t)(cal[6] | (cal[7] << 8));
  bme.dig_P2 = (int16_t)(cal[8] | (cal[9] << 8));
  bme.dig_P3 = (int16_t)(cal[10] | (cal[11] << 8));
  bme.dig_P4 = (int16_t)(cal[12] | (cal[13] << 8));
  bme.dig_P5 = (int16_t)(cal[14] | (cal[15] << 8));
  bme.dig_P6 = (int16_t)(cal[16] | (cal[17] << 8));
  bme.dig_P7 = (int16_t)(cal[18] | (cal[19] << 8));
  bme.dig_P8 = (int16_t)(cal[20] | (cal[21] << 8));
  bme.dig_P9 = (int16_t)(cal[22] | (cal[23] << 8));

  // Humidity calibration
  if (id == 0x60) {
    bme.dig_H1 = i2cRead8(BME280_ADDR, 0xA1);

    uint8_t hcal[7];
    if (i2cReadBuf(BME280_ADDR, 0xE1, hcal, 7) < 7) return false;
    bme.dig_H2 = (int16_t)(hcal[0] | (hcal[1] << 8));
    bme.dig_H3 = hcal[2];
    bme.dig_H4 = (int16_t)((hcal[3] << 4) | (hcal[4] & 0x0F));
    bme.dig_H5 = (int16_t)(((hcal[4] >> 4) & 0x0F) | (hcal[5] << 4));
    bme.dig_H6 = (int8_t)hcal[6];

    i2cWrite8(BME280_ADDR, 0xF2, 0x01);  // osrs_h = x1
  }

  // T x2, P x16, Normal mode
  i2cWrite8(BME280_ADDR, 0xF5, 0x00);  // standby=0.5ms, filter=off
  i2cWrite8(BME280_ADDR, 0xF4, 0x57);  // ctrl_meas
  return true;
}

int32_t bmeCompensateT(int32_t adc_T) {
  int32_t var1 = ((((adc_T >> 3) - ((int32_t)bme.dig_T1 << 1)))
                  * (int32_t)bme.dig_T2) >> 11;
  int32_t var2 = (((((adc_T >> 4) - (int32_t)bme.dig_T1)
                  * ((adc_T >> 4) - (int32_t)bme.dig_T1)) >> 12)
                  * (int32_t)bme.dig_T3) >> 14;
  bme.t_fine = var1 + var2;
  return (bme.t_fine * 5 + 128) >> 8;
}

uint32_t bmeCompensateP(int32_t adc_P) {
  int64_t var1 = (int64_t)bme.t_fine - 128000;
  int64_t var2 = var1 * var1 * (int64_t)bme.dig_P6;
  var2 = var2 + ((var1 * (int64_t)bme.dig_P5) << 17);
  var2 = var2 + (((int64_t)bme.dig_P4) << 35);
  var1 = ((var1 * var1 * (int64_t)bme.dig_P3) >> 8)
       + ((var1 * (int64_t)bme.dig_P2) << 12);
  var1 = (((((int64_t)1) << 47) + var1)) * ((int64_t)bme.dig_P1) >> 33;
  if (var1 == 0) return 0;

  int64_t p = 1048576 - adc_P;
  p = (((p << 31) - var2) * 3125) / var1;
  var1 = ((int64_t)bme.dig_P9 * (p >> 13) * (p >> 13)) >> 25;
  var2 = ((int64_t)bme.dig_P8 * p) >> 19;
  p = ((p + var1 + var2) >> 8) + (((int64_t)bme.dig_P7) << 4);
  return (uint32_t)p;
}

uint32_t bmeCompensateH(int32_t adc_H) {
  int32_t v = bme.t_fine - 76800;
  v = (((((adc_H << 14) - (((int32_t)bme.dig_H4) << 20)
      - (((int32_t)bme.dig_H5) * v)) + 16384) >> 15)
      * (((((((v * ((int32_t)bme.dig_H6)) >> 10)
      * (((v * ((int32_t)bme.dig_H3)) >> 11) + 32768)) >> 10)
      + 2097152) * ((int32_t)bme.dig_H2) + 8192) >> 14));
  v = v - (((((v >> 15) * (v >> 15)) >> 7) * ((int32_t)bme.dig_H1)) >> 4);
  v = (v < 0) ? 0 : v;
  v = (v > 419430400) ? 419430400 : v;
  return (uint32_t)(v >> 12);
}

float g_bmeTemp = 0, g_bmePres = 0, g_bmeHum = 0;

/// Reads BME280. Returns false if I2C read failed or data invalid.
bool bmeRead() {
  uint8_t data[8];
  if (i2cReadBuf(BME280_ADDR, 0xF7, data, 8) < 8) {
    g_bmeErrors++;
    return false;
  }

  int32_t adc_P = ((int32_t)data[0] << 12) | ((int32_t)data[1] << 4) | (data[2] >> 4);
  int32_t adc_T = ((int32_t)data[3] << 12) | ((int32_t)data[4] << 4) | (data[5] >> 4);
  int32_t adc_H = ((int32_t)data[6] << 8)  | data[7];

  // Sanity: all 0xFFFFF = sensor not responding
  if (adc_T == 0xFFFFF && adc_P == 0xFFFFF) {
    g_bmeErrors++;
    return false;
  }

  int32_t tRaw = bmeCompensateT(adc_T);
  g_bmeTemp = (float)tRaw / 100.0f;

  // Sanity: -50..+85°C
  if (g_bmeTemp < -50.0f || g_bmeTemp > 85.0f) {
    g_bmeErrors++;
    return false;
  }

  uint32_t pRaw = bmeCompensateP(adc_P);
  g_bmePres = (float)pRaw / 256.0f;

  uint32_t hRaw = bmeCompensateH(adc_H);
  g_bmeHum = (float)hRaw / 1024.0f;
  return true;
}

// ═══════════════════════════════════════════════════════════
//  MPU6050: ИНИЦИАЛИЗАЦИЯ И ЧТЕНИЕ
// ═══════════════════════════════════════════════════════════

float g_accelX = 0, g_accelY = 0, g_accelZ = 0;
float g_mpuTemp = 0;

bool mpuInit() {
  uint8_t id = i2cRead8(MPU6050_ADDR, 0x75);
  if (id != 0x68 && id != 0x71 && id != 0x70) return false;

  i2cWrite8(MPU6050_ADDR, 0x6B, 0x80);  // DEVICE_RESET
  delay(100);
  i2cWrite8(MPU6050_ADDR, 0x6B, 0x01);  // CLKSEL=PLL_X
  delay(10);

  // Verify wakeup
  uint8_t pwr = i2cRead8(MPU6050_ADDR, 0x6B);
  if (pwr & 0x40) {
    i2cWrite8(MPU6050_ADDR, 0x6B, 0x01);
    delay(50);
  }

  i2cWrite8(MPU6050_ADDR, 0x1C, MPU_ACCEL_RANGE << 3);  // ±2g
  i2cWrite8(MPU6050_ADDR, 0x1B, 0x00);                   // ±250°/s
  i2cWrite8(MPU6050_ADDR, 0x1A, 0x04);                   // DLPF ~21 Hz
  i2cWrite8(MPU6050_ADDR, 0x19, 0x09);                   // 100 Hz
  delay(50);
  return true;
}

/// Reads MPU6050. Returns false if I2C failed or data invalid.
bool mpuRead() {
  uint8_t buf[14];
  if (i2cReadBuf(MPU6050_ADDR, 0x3B, buf, 14) < 14) {
    g_mpuErrors++;
    return false;
  }

  int16_t ax = (int16_t)((buf[0] << 8) | buf[1]);
  int16_t ay = (int16_t)((buf[2] << 8) | buf[3]);
  int16_t az = (int16_t)((buf[4] << 8) | buf[5]);
  int16_t rawT = (int16_t)((buf[6] << 8) | buf[7]);

  // Sanity: all zeros or all 0xFF = bus error
  if ((ax == 0 && ay == 0 && az == 0) ||
      (ax == -1 && ay == -1 && az == -1)) {
    g_mpuErrors++;
    return false;
  }

  g_accelX = (float)ax / MPU_ACCEL_SCALE;
  g_accelY = (float)ay / MPU_ACCEL_SCALE;
  g_accelZ = (float)az / MPU_ACCEL_SCALE;
  g_mpuTemp = (float)rawT / 340.0f + 36.53f;
  return true;
}

// ═══════════════════════════════════════════════════════════
//  MAGNETOMETER: HMC5883L / QMC5883L
// ═══════════════════════════════════════════════════════════

bool magInit() {
  // Try HMC5883L
  uint8_t ida = i2cRead8(HMC5883L_ADDR, 0x0A);
  uint8_t idb = i2cRead8(HMC5883L_ADDR, 0x0B);
  uint8_t idc = i2cRead8(HMC5883L_ADDR, 0x0C);

  if (ida == 'H' && idb == '4' && idc == '3') {
    i2cWrite8(HMC5883L_ADDR, 0x00, 0x70); // 8-average, 15Hz
    i2cWrite8(HMC5883L_ADDR, 0x01, 0x20); // Gain 1.3Ga
    i2cWrite8(HMC5883L_ADDR, 0x02, 0x00); // Continuous mode
    delay(10);
    g_magChip = MAG_HMC5883L;
    return true;
  }

  // Try QMC5883L
  i2cWrite8(QMC5883L_ADDR, 0x0B, 0x01); // soft reset
  delay(5);
  i2cWrite8(QMC5883L_ADDR, 0x09, 0x1D); // OSR512,RNG8G,ODR200,Continuous
  delay(10);
  uint8_t st = i2cRead8(QMC5883L_ADDR, 0x06);
  if (st != 0xFF) {
    g_magChip = MAG_QMC5883L;
    return true;
  }

  g_magChip = MAG_NONE;
  return false;
}

bool magRead() {
  if (g_magChip == MAG_NONE) return false;

  int16_t mx = 0, my = 0, mz = 0;

  if (g_magChip == MAG_HMC5883L) {
    uint8_t buf[6];
    if (i2cReadBuf(HMC5883L_ADDR, 0x03, buf, 6) < 6) {
      g_magErrors++;
      return false;
    }
    // HMC order: X, Z, Y
    mx = (int16_t)((buf[0] << 8) | buf[1]);
    mz = (int16_t)((buf[2] << 8) | buf[3]);
    my = (int16_t)((buf[4] << 8) | buf[5]);

    if ((mx == 0 && my == 0 && mz == 0) ||
        (mx == -1 && my == -1 && mz == -1)) {
      g_magErrors++;
      return false;
    }

    // 0.92 mG/LSB = 0.000092 mT/LSB
    float fx = (float)mx * 0.000092f;
    float fy = (float)my * 0.000092f;
    float fz = (float)mz * 0.000092f;
    g_magFieldMt = sqrt(fx * fx + fy * fy + fz * fz);
    return true;
  }

  if (g_magChip == MAG_QMC5883L) {
    uint8_t buf[6];
    if (i2cReadBuf(QMC5883L_ADDR, 0x00, buf, 6) < 6) {
      g_magErrors++;
      return false;
    }
    // QMC order: X, Y, Z (little-endian)
    mx = (int16_t)(buf[0] | (buf[1] << 8));
    my = (int16_t)(buf[2] | (buf[3] << 8));
    mz = (int16_t)(buf[4] | (buf[5] << 8));

    if ((mx == 0 && my == 0 && mz == 0) ||
        (mx == -1 && my == -1 && mz == -1)) {
      g_magErrors++;
      return false;
    }

    const float qmcScaleMt = 0.0001f;
    float fx = (float)mx * qmcScaleMt;
    float fy = (float)my * qmcScaleMt;
    float fz = (float)mz * qmcScaleMt;
    g_magFieldMt = sqrt(fx * fx + fy * fy + fz * fz);
    return true;
  }

  return false;
}

// ═══════════════════════════════════════════════════════════
//  АНАЛОГОВЫЕ КАНАЛЫ
// ═══════════════════════════════════════════════════════════

AdcResult readAdc(int pin) {
  analogRead(pin);
  delayMicroseconds(100);
  long sum = 0, sumSq = 0;
  for (int i = 0; i < OVERSAMPLE; i++) {
    int val = analogRead(pin);
    sum   += val;
    sumSq += (long)val * val;
  }
  float mean = (float)sum / OVERSAMPLE;
  float var  = (float)sumSq / OVERSAMPLE - mean * mean;
  return { mean, var };
}

float measureVoltage(float adcMean) {
  return (adcMean / (float)ADC_MAX) * V_REF * V_DIVIDER_RATIO;
}

float measureCurrent(float adcMean) {
  float vShunt = (adcMean / (float)ADC_MAX) * V_REF;
  return vShunt / SHUNT_RESISTANCE;
}

// ═══════════════════════════════════════════════════════════
//  ДИАГНОСТИКА
// ═══════════════════════════════════════════════════════════

int freeRam() {
  extern int __heap_start, *__brkval;
  int v;
  return (int)&v - (__brkval == 0
    ? (int)&__heap_start : (int)__brkval);
}

// ═══════════════════════════════════════════════════════════
//  PERIODIC SENSOR HEALTH CHECK
// ═══════════════════════════════════════════════════════════

void sensorHealthCheck() {
  bool needRecovery = false;

  // Check BME280
  if (g_bmeOk) {
    uint8_t id = i2cRead8(BME280_ADDR, 0xD0);
    if (id != 0x60 && id != 0x58) {
      Serial.println(F("# HEALTH: BME280 lost!"));
      g_bmeOk = false;
      needRecovery = true;
    }
  } else {
    // Try to rediscover (maybe user plugged it back in)
    uint8_t id = i2cRead8(BME280_ADDR, 0xD0);
    if (id == 0x60 || id == 0x58) {
      Serial.println(F("# HEALTH: BME280 found! Reinit..."));
      g_bmeOk = bmeInit();
    }
  }

  // Check MPU6050
  if (g_mpuOk) {
    uint8_t id = i2cRead8(MPU6050_ADDR, 0x75);
    if (id != 0x68 && id != 0x71 && id != 0x70) {
      Serial.println(F("# HEALTH: MPU6050 lost!"));
      g_mpuOk = false;
      needRecovery = true;
    }
  } else {
    uint8_t id = i2cRead8(MPU6050_ADDR, 0x75);
    if (id == 0x68 || id == 0x71 || id == 0x70) {
      Serial.println(F("# HEALTH: MPU6050 found! Reinit..."));
      g_mpuOk = mpuInit();
    }
  }

  // Check Magnetometer
  if (g_magOk) {
    bool magOk = magRead();
    if (!magOk) {
      Serial.println(F("# HEALTH: MAG lost!"));
      g_magOk = false;
      needRecovery = true;
    }
  } else {
    if (magInit()) {
      Serial.println(F("# HEALTH: MAG found! Reinit..."));
      g_magOk = true;
    }
  }

  // If consecutive errors high or sensor lost → full I2C recovery
  if (g_bmeErrors > 10 || g_mpuErrors > 10 || g_magErrors > 10 || needRecovery) {
    i2cFullRecovery();
    g_bmeErrors = 0;
    g_mpuErrors = 0;
    g_magErrors = 0;
  }
}

// ═══════════════════════════════════════════════════════════
//  NON-BLOCKING SERIAL COMMAND READER
// ═══════════════════════════════════════════════════════════

/// Reads serial one byte at a time (non-blocking).
/// Returns true when a complete line is ready in g_cmdBuf.
bool readSerialCommand() {
  while (Serial.available()) {
    char c = Serial.read();
    if (c == '\n' || c == '\r') {
      if (g_cmdLen > 0) {
        g_cmdBuf[g_cmdLen] = '\0';
        g_cmdLen = 0;
        return true;
      }
      continue;
    }
    if (g_cmdLen < sizeof(g_cmdBuf) - 1) {
      g_cmdBuf[g_cmdLen++] = c;
    }
  }
  return false;
}

// ═══════════════════════════════════════════════════════════
//  ОБРАБОТКА КОМАНД
// ═══════════════════════════════════════════════════════════

void processCommand(const char* cmd) {
  if (strcmp_P(cmd, PSTR("GET_INFO")) == 0) {
    Serial.println(F("# INFO: LABOSFERA Multisensor v0.4"));
    Serial.print(F("# UPTIME: "));
    Serial.print(millis() / 1000);
    Serial.println(F(" s"));
    Serial.print(F("# PACKETS: "));
    Serial.println(g_packetCount);
    Serial.print(F("# FREE_RAM: "));
    Serial.print(freeRam());
    Serial.println(F(" bytes"));
    Serial.print(F("# ERRORS: BME="));
    Serial.print(g_bmeErrors);
    Serial.print(F(" MPU="));
    Serial.print(g_mpuErrors);
    Serial.print(F(" MAG="));
    Serial.print(g_magErrors);
    Serial.print(F(" I2C_RECOVER="));
    Serial.println(g_i2cRecovers);
  } else if (strcmp_P(cmd, PSTR("PING")) == 0) {
    Serial.println(F("# PONG"));
  } else if (strcmp_P(cmd, PSTR("GET_SENSORS")) == 0) {
    Serial.print(F("# SENSORS: V,A"));
    if (g_bmeOk) Serial.print(F(",T,P,H"));
    if (g_mpuOk) Serial.print(F(",ACC"));
    if (g_magOk) Serial.print(F(",MAG"));
    Serial.println();
  } else if (strcmp_P(cmd, PSTR("RESET_ERRORS")) == 0) {
    g_bmeErrors = 0;
    g_mpuErrors = 0;
    g_magErrors = 0;
    g_i2cRecovers = 0;
    Serial.println(F("# ERRORS_RESET"));
  } else if (strcmp_P(cmd, PSTR("I2C_RECOVER")) == 0) {
    i2cFullRecovery();
  }
}

// ═══════════════════════════════════════════════════════════
//  SETUP
// ═══════════════════════════════════════════════════════════

void setup() {
  // Disable WDT left over from a previous reset
  wdt_disable();

  Serial.begin(115200);

  // Wait for Serial WITH TIMEOUT — don't hang if USB not connected
  {
    unsigned long t0 = millis();
    while (!Serial && (millis() - t0 < SERIAL_WAIT_TIMEOUT_MS)) { ; }
  }

  // I2C Bus Recovery BEFORE Wire.begin() — unstick SDA if held low
  i2cBusRecovery();

  Wire.begin();
  Wire.setClock(400000);
  // Wire timeout to prevent infinite hang if slave holds bus
  // (requires Arduino AVR core >= 2.0.0)
#if defined(WIRE_HAS_TIMEOUT) || (ARDUINO >= 10800)
  Wire.setWireTimeout(3000, true);  // 3ms, reset on timeout
#endif

  analogReference(DEFAULT);

  // Warm up ADC
  for (int i = 0; i < 10; i++) {
    analogRead(A0);
    analogRead(A1);
  }

  // ── Init I2C sensors ──
  g_bmeOk = bmeInit();
  g_mpuOk = mpuInit();
  g_magOk = magInit();

  // ── Protocol header ──
  Serial.println(F("=== LABOSFERA Multisensor v0.4 ==="));

#if defined(ARDUINO_AVR_UNO)
  Serial.println(F("Board: Arduino UNO R3"));
#elif defined(ARDUINO_AVR_MEGA2560)
  Serial.println(F("Board: Arduino Mega 2560"));
#else
  Serial.println(F("Board: Arduino Compatible"));
#endif

  Serial.print(F("BME280: "));
  Serial.println(g_bmeOk ? F("OK (T+P+H)") : F("NOT FOUND"));
  Serial.print(F("MPU6050: "));
  Serial.println(g_mpuOk ? F("OK (Acc+Gyro)") : F("NOT FOUND"));
  Serial.print(F("MAG: "));
  if (g_magOk) {
    if (g_magChip == MAG_HMC5883L) {
      Serial.println(F("OK (HMC5883L)"));
    } else if (g_magChip == MAG_QMC5883L) {
      Serial.println(F("OK (QMC5883L)"));
    } else {
      Serial.println(F("OK"));
    }
  } else {
    Serial.println(F("NOT FOUND"));
  }

  Serial.print(F("# SENSORS: V,A"));
  if (g_bmeOk) Serial.print(F(",T,P,H"));
  if (g_mpuOk) Serial.print(F(",ACC"));
  if (g_magOk) Serial.print(F(",MAG"));
  Serial.println();

  Serial.print(F("# V_RANGE: 0-"));
  Serial.print(V_REF * V_DIVIDER_RATIO, 1);
  Serial.println(F(" V"));

  float vRes = V_REF * V_DIVIDER_RATIO / ADC_MAX / sqrt((float)OVERSAMPLE) * 1000.0;
  Serial.print(F("# V_RESOLUTION: "));
  Serial.print(vRes, 2);
  Serial.println(F(" mV"));

  if (g_bmeOk) {
    Serial.println(F("# T_RANGE: -40..+85 C (BME280)"));
    Serial.println(F("# P_RANGE: 30000..110000 Pa"));
    Serial.println(F("# H_RANGE: 0..100 %RH"));
  }
  if (g_mpuOk) {
    Serial.println(F("# ACC_RANGE: +/-2 g"));
  }
  if (g_magOk) {
    Serial.println(F("# MAG_RANGE: auto (mT), output=M"));
  }

  Serial.println(F("# CRC: CRC8_MAXIM"));

  Serial.print(F("Rate: "));
  Serial.print(1000 / SEND_INTERVAL_MS);
  Serial.println(F(" Hz"));
  Serial.print(F("Free RAM: "));
  Serial.print(freeRam());
  Serial.println(F(" bytes"));

  Serial.println(F("================================"));
  Serial.println(F("DATA_START"));

  g_nextSendMs = millis() + SEND_INTERVAL_MS;

  // === Enable Watchdog Timer ===
  // 2s timeout. If loop() freezes, WDT resets the MCU.
  wdt_enable(WDTO_2S);
}

// ═══════════════════════════════════════════════════════════
//  MAIN LOOP
// ═══════════════════════════════════════════════════════════

char g_lineBuf[200];

void loop() {
  // === Feed watchdog — we're alive ===
  wdt_reset();

  unsigned long now = millis();

  // Drift-free timing
  if ((long)(now - g_nextSendMs) < 0) {
    if (readSerialCommand()) processCommand(g_cmdBuf);
    return;
  }

  // Skip missed cycles (don't burst)
  while ((long)(now - g_nextSendMs) >= 0) {
    g_nextSendMs += SEND_INTERVAL_MS;
  }

  g_packetCount++;

  // ── Read ADC ──
  AdcResult adcV = readAdc(A0);
  AdcResult adcA = readAdc(A1);
  float voltage = measureVoltage(adcV.mean);
  float current = measureCurrent(adcA.mean);

  // ── Read I2C sensors ──
  bool bmeReadOk = g_bmeOk ? bmeRead() : false;
  bool mpuReadOk = g_mpuOk ? mpuRead() : false;
  bool magReadOk = g_magOk ? magRead() : false;

  // ── Build CSV line in buffer (for CRC calculation) ──
  int pos = 0;

  // V
  pos += snprintf(g_lineBuf + pos, sizeof(g_lineBuf) - pos, "V:");
  dtostrf(voltage, 1, 3, g_lineBuf + pos);
  pos = strlen(g_lineBuf);

  // A
  pos += snprintf(g_lineBuf + pos, sizeof(g_lineBuf) - pos, ",A:");
  dtostrf(current, 1, 3, g_lineBuf + pos);
  pos = strlen(g_lineBuf);

  // T
  pos += snprintf(g_lineBuf + pos, sizeof(g_lineBuf) - pos, ",T:");
  if (bmeReadOk) {
    dtostrf(g_bmeTemp, 1, 2, g_lineBuf + pos);
  } else {
    strncpy(g_lineBuf + pos, "---", 4);
  }
  pos = strlen(g_lineBuf);

  // P
  pos += snprintf(g_lineBuf + pos, sizeof(g_lineBuf) - pos, ",P:");
  if (bmeReadOk) {
    dtostrf(g_bmePres, 1, 1, g_lineBuf + pos);
  } else {
    strncpy(g_lineBuf + pos, "---", 4);
  }
  pos = strlen(g_lineBuf);

  // H
  pos += snprintf(g_lineBuf + pos, sizeof(g_lineBuf) - pos, ",H:");
  if (bmeReadOk) {
    dtostrf(g_bmeHum, 1, 1, g_lineBuf + pos);
  } else {
    strncpy(g_lineBuf + pos, "---", 4);
  }
  pos = strlen(g_lineBuf);

  // AX
  pos += snprintf(g_lineBuf + pos, sizeof(g_lineBuf) - pos, ",AX:");
  if (mpuReadOk) {
    dtostrf(g_accelX, 1, 4, g_lineBuf + pos);
  } else {
    strncpy(g_lineBuf + pos, "---", 4);
  }
  pos = strlen(g_lineBuf);

  // AY
  pos += snprintf(g_lineBuf + pos, sizeof(g_lineBuf) - pos, ",AY:");
  if (mpuReadOk) {
    dtostrf(g_accelY, 1, 4, g_lineBuf + pos);
  } else {
    strncpy(g_lineBuf + pos, "---", 4);
  }
  pos = strlen(g_lineBuf);

  // AZ
  pos += snprintf(g_lineBuf + pos, sizeof(g_lineBuf) - pos, ",AZ:");
  if (mpuReadOk) {
    dtostrf(g_accelZ, 1, 4, g_lineBuf + pos);
  } else {
    strncpy(g_lineBuf + pos, "---", 4);
  }
  pos = strlen(g_lineBuf);

  // M (magnetic field magnitude, mT)
  if (g_magOk) {
    pos += snprintf(g_lineBuf + pos, sizeof(g_lineBuf) - pos, ",M:");
    if (magReadOk) {
      dtostrf(g_magFieldMt, 1, 4, g_lineBuf + pos);
    } else {
      strncpy(g_lineBuf + pos, "---", 4);
    }
    pos = strlen(g_lineBuf);
  }

  // Metadata
  pos += snprintf(g_lineBuf + pos, sizeof(g_lineBuf) - pos,
                  ",N:%lu,T_MS:%lu", g_packetCount, now);

  // === CRC8 checksum ===
  uint8_t checksum = crc8(g_lineBuf, pos);
  snprintf(g_lineBuf + pos, sizeof(g_lineBuf) - pos, "*%02X", checksum);

  Serial.println(g_lineBuf);

  // ── Health check every ~10 seconds ──
  if (g_packetCount % HEALTH_CHECK_INTERVAL == 0) {
    sensorHealthCheck();
  }

  // ── Diagnostics every 5 seconds ──
  if (g_packetCount % 50 == 0) {
    Serial.print(F("# STATUS: BME="));
    Serial.print(g_bmeOk ? F("OK") : F("ERR"));
    Serial.print(F(" MPU="));
    Serial.print(g_mpuOk ? F("OK") : F("ERR"));
    Serial.print(F(" MAG="));
    Serial.print(g_magOk ? F("OK") : F("ERR"));
    Serial.print(F(" |g|="));
    float mag = sqrt(g_accelX*g_accelX + g_accelY*g_accelY + g_accelZ*g_accelZ);
    Serial.println(mag, 3);

    if (g_magOk) {
      Serial.print(F("# MAG: "));
      Serial.print(g_magFieldMt, 4);
      Serial.println(F(" mT"));
    }

    Serial.print(F("# ADC: Vm="));
    Serial.print(adcV.mean, 1);
    Serial.print(F(" Vv="));
    Serial.print(adcV.variance, 1);
    Serial.print(F(" Am="));
    Serial.print(adcA.mean, 1);
    Serial.print(F(" Av="));
    Serial.println(adcA.variance, 1);

    Serial.print(F("# ERR: B="));
    Serial.print(g_bmeErrors);
    Serial.print(F(" M="));
    Serial.print(g_mpuErrors);
    Serial.print(F(" G="));
    Serial.print(g_magErrors);
    Serial.print(F(" R="));
    Serial.println(g_i2cRecovers);

    Serial.print(F("# RAM: "));
    Serial.print(freeRam());
    Serial.println(F(" B"));
  }

  // ── Commands (non-blocking) ──
  if (readSerialCommand()) processCommand(g_cmdBuf);
}
