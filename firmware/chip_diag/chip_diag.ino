/*
 * LABOSFERA — Full Chip Diagnostic
 * Reads WHO_AM_I and actual data from detected I2C sensors
 */

#include <Wire.h>

uint8_t readReg(uint8_t addr, uint8_t reg) {
  Wire.beginTransmission(addr);
  Wire.write(reg);
  Wire.endTransmission(false);
  Wire.requestFrom(addr, (uint8_t)1);
  return Wire.available() ? Wire.read() : 0xFF;
}

void writeReg(uint8_t addr, uint8_t reg, uint8_t val) {
  Wire.beginTransmission(addr);
  Wire.write(reg);
  Wire.write(val);
  Wire.endTransmission();
}

void readRegs(uint8_t addr, uint8_t reg, uint8_t* buf, uint8_t len) {
  Wire.beginTransmission(addr);
  Wire.write(reg);
  Wire.endTransmission(false);
  Wire.requestFrom(addr, len);
  for (uint8_t i = 0; i < len && Wire.available(); i++) {
    buf[i] = Wire.read();
  }
}

void setup() {
  Serial.begin(115200);
  while (!Serial) { ; }
  Wire.begin();
  delay(100);

  Serial.println(F("=== LABOSFERA Chip Diagnostic ==="));
  Serial.println();

  // ── MPU at 0x68 ──
  Serial.println(F("--- Chip at 0x68 (MPU) ---"));
  uint8_t whoAmI = readReg(0x68, 0x75);  // WHO_AM_I register
  Serial.print(F("WHO_AM_I (0x75): 0x"));
  Serial.println(whoAmI, HEX);

  if (whoAmI == 0x68) {
    Serial.println(F("-> MPU6050 confirmed (no magnetometer)"));
  } else if (whoAmI == 0x71) {
    Serial.println(F("-> MPU9250 confirmed (HAS magnetometer AK8963!)"));
  } else if (whoAmI == 0x70) {
    Serial.println(F("-> MPU6500 confirmed (no magnetometer)"));
  } else if (whoAmI == 0x19) {
    Serial.println(F("-> MPU6886 confirmed"));
  } else if (whoAmI == 0x98) {
    Serial.println(F("-> ICM-20948 confirmed (HAS magnetometer!)"));
  } else {
    Serial.print(F("-> Unknown MPU variant: 0x"));
    Serial.println(whoAmI, HEX);
  }

  // Wake up MPU
  writeReg(0x68, 0x6B, 0x00);  // PWR_MGMT_1 = 0 (wake up)
  delay(100);

  // Read raw accel
  uint8_t accelBuf[6];
  readRegs(0x68, 0x3B, accelBuf, 6);
  int16_t ax = (int16_t)((accelBuf[0] << 8) | accelBuf[1]);
  int16_t ay = (int16_t)((accelBuf[2] << 8) | accelBuf[3]);
  int16_t az = (int16_t)((accelBuf[4] << 8) | accelBuf[5]);

  // Default scale: ±2g, sensitivity 16384 LSB/g
  Serial.print(F("Accel RAW: X="));
  Serial.print(ax);
  Serial.print(F(" Y="));
  Serial.print(ay);
  Serial.print(F(" Z="));
  Serial.println(az);

  float gx = ax / 16384.0;
  float gy = ay / 16384.0;
  float gz = az / 16384.0;
  Serial.print(F("Accel (g): X="));
  Serial.print(gx, 3);
  Serial.print(F(" Y="));
  Serial.print(gy, 3);
  Serial.print(F(" Z="));
  Serial.println(gz, 3);

  float totalG = sqrt(gx*gx + gy*gy + gz*gz);
  Serial.print(F("|g| = "));
  Serial.print(totalG, 3);
  Serial.println(F(" (should be ~1.0 if stationary)"));

  // Read gyro
  uint8_t gyroBuf[6];
  readRegs(0x68, 0x43, gyroBuf, 6);
  int16_t gxr = (int16_t)((gyroBuf[0] << 8) | gyroBuf[1]);
  int16_t gyr = (int16_t)((gyroBuf[2] << 8) | gyroBuf[3]);
  int16_t gzr = (int16_t)((gyroBuf[4] << 8) | gyroBuf[5]);
  Serial.print(F("Gyro RAW:  X="));
  Serial.print(gxr);
  Serial.print(F(" Y="));
  Serial.print(gyr);
  Serial.print(F(" Z="));
  Serial.println(gzr);

  // Read MPU temperature
  uint8_t tempBuf[2];
  readRegs(0x68, 0x41, tempBuf, 2);
  int16_t rawT = (int16_t)((tempBuf[0] << 8) | tempBuf[1]);
  float mpuTempC = rawT / 340.0 + 36.53;
  Serial.print(F("MPU Temp: "));
  Serial.print(mpuTempC, 1);
  Serial.println(F(" C (chip internal, not ambient)"));

  // If MPU9250, try to access AK8963 magnetometer
  if (whoAmI == 0x71) {
    // Enable I2C bypass to directly access AK8963
    writeReg(0x68, 0x37, 0x02);  // INT_PIN_CFG: I2C_BYPASS_EN
    delay(10);

    // AK8963 should appear at 0x0C
    Wire.beginTransmission(0x0C);
    uint8_t akErr = Wire.endTransmission();
    if (akErr == 0) {
      uint8_t akId = readReg(0x0C, 0x00);  // WIA
      Serial.print(F("AK8963 WHO_AM_I: 0x"));
      Serial.println(akId, HEX);
      if (akId == 0x48) {
        Serial.println(F("-> AK8963 magnetometer CONFIRMED!"));
      }
    } else {
      Serial.println(F("AK8963 not accessible"));
    }
  }

  Serial.println();

  // ── BMP at 0x76 ──
  Serial.println(F("--- Chip at 0x76 (BMP) ---"));
  uint8_t chipId = readReg(0x76, 0xD0);
  Serial.print(F("Chip ID (0xD0): 0x"));
  Serial.println(chipId, HEX);

  if (chipId == 0x58) {
    Serial.println(F("-> BMP280 confirmed (Pressure + Temperature)"));
  } else if (chipId == 0x60) {
    Serial.println(F("-> BME280 confirmed (Pressure + Temperature + Humidity!)"));
  } else if (chipId == 0x50) {
    Serial.println(F("-> BMP390 confirmed (High-precision P + T)"));
  } else {
    Serial.print(F("-> Unknown BMP variant: 0x"));
    Serial.println(chipId, HEX);
  }

  // Read BMP280 calibration (trimming) and temperature
  if (chipId == 0x58 || chipId == 0x60) {
    // Force measurement mode
    writeReg(0x76, 0xF4, 0x27);  // ctrl_meas: osrs_t=001, osrs_p=001, mode=normal
    writeReg(0x76, 0xF5, 0x00);  // config: filter off
    delay(100);

    // Read calibration
    uint8_t cal[26];
    readRegs(0x76, 0x88, cal, 26);

    uint16_t dig_T1 = cal[0] | (cal[1] << 8);
    int16_t dig_T2  = cal[2] | (cal[3] << 8);
    int16_t dig_T3  = cal[4] | (cal[5] << 8);
    uint16_t dig_P1 = cal[6] | (cal[7] << 8);
    int16_t dig_P2  = cal[8] | (cal[9] << 8);
    int16_t dig_P3  = cal[10] | (cal[11] << 8);
    int16_t dig_P4  = cal[12] | (cal[13] << 8);
    int16_t dig_P5  = cal[14] | (cal[15] << 8);
    int16_t dig_P6  = cal[16] | (cal[17] << 8);
    int16_t dig_P7  = cal[18] | (cal[19] << 8);
    int16_t dig_P8  = cal[20] | (cal[21] << 8);
    int16_t dig_P9  = cal[22] | (cal[23] << 8);

    Serial.print(F("Cal T1="));
    Serial.print(dig_T1);
    Serial.print(F(" T2="));
    Serial.print(dig_T2);
    Serial.print(F(" T3="));
    Serial.println(dig_T3);

    delay(50);

    // Read raw data
    uint8_t data[6];
    readRegs(0x76, 0xF7, data, 6);
    int32_t adc_P = ((int32_t)data[0] << 12) | ((int32_t)data[1] << 4) | (data[2] >> 4);
    int32_t adc_T = ((int32_t)data[3] << 12) | ((int32_t)data[4] << 4) | (data[5] >> 4);

    Serial.print(F("Raw T ADC: "));
    Serial.println(adc_T);
    Serial.print(F("Raw P ADC: "));
    Serial.println(adc_P);

    // BMP280 compensation (from datasheet)
    int32_t var1t = ((((adc_T >> 3) - ((int32_t)dig_T1 << 1))) * (int32_t)dig_T2) >> 11;
    int32_t var2t = (((((adc_T >> 4) - (int32_t)dig_T1) * ((adc_T >> 4) - (int32_t)dig_T1)) >> 12) * (int32_t)dig_T3) >> 14;
    int32_t t_fine = var1t + var2t;
    float tempC = (t_fine * 5 + 128) >> 8;
    tempC /= 100.0;

    Serial.print(F("BMP Temperature: "));
    Serial.print(tempC, 2);
    Serial.println(F(" C"));

    // Pressure compensation
    int64_t var1p = (int64_t)t_fine - 128000;
    int64_t var2p = var1p * var1p * (int64_t)dig_P6;
    var2p = var2p + ((var1p * (int64_t)dig_P5) << 17);
    var2p = var2p + (((int64_t)dig_P4) << 35);
    var1p = ((var1p * var1p * (int64_t)dig_P3) >> 8) + ((var1p * (int64_t)dig_P2) << 12);
    var1p = (((((int64_t)1) << 47) + var1p)) * ((int64_t)dig_P1) >> 33;

    if (var1p != 0) {
      int64_t p = 1048576 - adc_P;
      p = (((p << 31) - var2p) * 3125) / var1p;
      var1p = ((int64_t)dig_P9 * (p >> 13) * (p >> 13)) >> 25;
      var2p = ((int64_t)dig_P8 * p) >> 19;
      p = ((p + var1p + var2p) >> 8) + (((int64_t)dig_P7) << 4);

      float pressurePa = (float)p / 256.0;
      float pressureKPa = pressurePa / 1000.0;
      float pressureHPa = pressurePa / 100.0;

      Serial.print(F("BMP Pressure: "));
      Serial.print(pressurePa, 1);
      Serial.print(F(" Pa = "));
      Serial.print(pressureKPa, 2);
      Serial.print(F(" kPa = "));
      Serial.print(pressureHPa, 2);
      Serial.println(F(" hPa"));
    }

    // If BME280, also read humidity
    if (chipId == 0x60) {
      writeReg(0x76, 0xF2, 0x01);  // ctrl_hum: osrs_h = 1x
      writeReg(0x76, 0xF4, 0x27);  // re-trigger
      delay(50);
      uint8_t hdata[2];
      readRegs(0x76, 0xFD, hdata, 2);
      int32_t adc_H = ((int32_t)hdata[0] << 8) | hdata[1];
      Serial.print(F("Humidity raw ADC: "));
      Serial.println(adc_H);
    }
  }

  Serial.println();

  // ── Analog pins ──
  Serial.println(F("--- Analog Pins Detail ---"));
  for (int p = 0; p <= 5; p++) {
    int pin = A0 + p;
    analogRead(pin);
    delayMicroseconds(200);

    long sum = 0;
    long sumSq = 0;
    for (int i = 0; i < 32; i++) {
      int v = analogRead(pin);
      sum += v;
      sumSq += (long)v * v;
    }
    float mean = (float)sum / 32.0;
    float var = (float)sumSq / 32.0 - mean * mean;
    float voltage = mean / 1023.0 * 5.0;

    Serial.print(F("A"));
    Serial.print(p);
    Serial.print(F(": mean="));
    Serial.print(mean, 1);
    Serial.print(F(" var="));
    Serial.print(var, 1);
    Serial.print(F(" V="));
    Serial.print(voltage, 3);
    Serial.print(F("V "));

    if (mean < 2) Serial.println(F("[GND/sensor-to-GND]"));
    else if (mean > 1020) Serial.println(F("[VCC/pulled-HIGH]"));
    else if (var > 50) Serial.println(F("[FLOATING - noise]"));
    else if (var < 5) Serial.println(F("[STABLE - connected]"));
    else Serial.println(F("[MODERATE noise]"));
  }

  // Check if A3 could be a Hall sensor
  Serial.println();
  Serial.println(F("--- A3 Hall Sensor Test ---"));
  Serial.println(F("Reading A3 x 10 at 100ms intervals:"));
  for (int i = 0; i < 10; i++) {
    analogRead(A3);
    delayMicroseconds(100);
    long s = 0;
    for (int j = 0; j < 16; j++) s += analogRead(A3);
    float m = (float)s / 16.0;
    float v = m / 1023.0 * 5.0;
    Serial.print(F("  A3["));
    Serial.print(i);
    Serial.print(F("]: "));
    Serial.print(v, 3);
    Serial.println(F(" V"));
    delay(100);
  }
  Serial.println(F("(Hall @ 0 field = ~2.5V, linear with field)"));
  Serial.println(F("(If ~0.5V constant = likely NOT a Hall sensor)"));

  Serial.println();
  Serial.println(F("=== Diagnostic Complete ==="));
}

void loop() {
  delay(10000);
}
