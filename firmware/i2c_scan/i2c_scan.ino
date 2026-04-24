/*
 * I2C Scanner — обнаружение всех устройств на шине I2C
 * Пины: A4 (SDA), A5 (SCL) на Arduino UNO
 *
 * Известные адреса:
 *   0x18 — LIS3DH (акселерометр)
 *   0x19 — LIS3DH (альтернативный, SDO=HIGH)
 *   0x1E — HMC5883L (магнитометр)
 *   0x0C — MLX90393 (магнитометр)
 *   0x0F — MLX90393 (альтернативный)
 *   0x48 — ADS1115 (16-bit АЦП)
 *   0x40 — INA226 (вольтметр/амперметр)
 *   0x76 — BMP280 / BMP390 (давление)
 *   0x77 — BMP280 / BMP390 (альтернативный)
 *   0x23 — BH1750 (люксметр)
 *   0x5C — BH1750 (альтернативный)
 *   0x68 — MPU6050 (акселерометр/гироскоп)
 *   0x69 — MPU6050 (альтернативный)
 *   0x6A — LSM6DS3 (акселерометр/гироскоп)
 *   0x6B — LSM6DS3 (альтернативный)
 *   0x1C — LIS2MDL (магнитометр)
 *   0x3C — SSD1306 (OLED дисплей)
 */

#include <Wire.h>

struct KnownDevice {
  uint8_t addr;
  const char* name;
};

const KnownDevice knownDevices[] = {
  {0x0C, "MLX90393 (Magnetometer)"},
  {0x0F, "MLX90393 (alt addr)"},
  {0x18, "LIS3DH (Accelerometer, SDO=LOW)"},
  {0x19, "LIS3DH (Accelerometer, SDO=HIGH)"},
  {0x1C, "LIS2MDL (Magnetometer)"},
  {0x1E, "HMC5883L (Magnetometer)"},
  {0x23, "BH1750 (Lux sensor, ADDR=LOW)"},
  {0x3C, "SSD1306 (OLED display)"},
  {0x40, "INA226 (V/A sensor)"},
  {0x44, "SHT30 (Temp/Humidity)"},
  {0x48, "ADS1115 (16-bit ADC)"},
  {0x5C, "BH1750 (Lux sensor, ADDR=HIGH)"},
  {0x68, "MPU6050 (Accel/Gyro, AD0=LOW)"},
  {0x69, "MPU6050 (Accel/Gyro, AD0=HIGH)"},
  {0x6A, "LSM6DS3 (Accel/Gyro, SDO=LOW)"},
  {0x6B, "LSM6DS3 (Accel/Gyro, SDO=HIGH)"},
  {0x76, "BMP280/BMP390 (Pressure, SDO=LOW)"},
  {0x77, "BMP280/BMP390 (Pressure, SDO=HIGH)"},
};

const int numKnown = sizeof(knownDevices) / sizeof(knownDevices[0]);

const char* identifyDevice(uint8_t addr) {
  for (int i = 0; i < numKnown; i++) {
    if (knownDevices[i].addr == addr) return knownDevices[i].name;
  }
  return "Unknown device";
}

void setup() {
  Serial.begin(115200);
  while (!Serial) { ; }

  Wire.begin();

  Serial.println(F("=== LABOSFERA I2C Bus Scanner ==="));
  Serial.println(F("Scanning I2C bus (A4=SDA, A5=SCL)..."));
  Serial.println(F("Address range: 0x01 - 0x7F"));
  Serial.println();

  int found = 0;

  for (uint8_t addr = 1; addr < 128; addr++) {
    Wire.beginTransmission(addr);
    uint8_t error = Wire.endTransmission();

    if (error == 0) {
      found++;
      Serial.print(F("FOUND: 0x"));
      if (addr < 16) Serial.print('0');
      Serial.print(addr, HEX);
      Serial.print(F(" ("));
      Serial.print(addr);
      Serial.print(F(") -> "));
      Serial.println(identifyDevice(addr));
    } else if (error == 4) {
      Serial.print(F("ERROR at 0x"));
      if (addr < 16) Serial.print('0');
      Serial.println(addr, HEX);
    }
  }

  Serial.println();
  Serial.println(F("================================"));
  Serial.print(F("Total devices found: "));
  Serial.println(found);

  if (found == 0) {
    Serial.println(F(""));
    Serial.println(F("NO I2C DEVICES DETECTED!"));
    Serial.println(F(""));
    Serial.println(F("Check wiring:"));
    Serial.println(F("  SDA -> A4 (pin 18)"));
    Serial.println(F("  SCL -> A5 (pin 19)"));
    Serial.println(F("  VCC -> 3.3V or 5V"));
    Serial.println(F("  GND -> GND"));
    Serial.println(F(""));
    Serial.println(F("For FGOS 'Klassika' 6-sensor set you need:"));
    Serial.println(F("  1. Voltage    -> A0 (analog) [OK - built in]"));
    Serial.println(F("  2. Current    -> A1 + shunt  [OK - wires present]"));
    Serial.println(F("  3. Temp NTC   -> A2 + 10k pullup [NEED NTC]"));
    Serial.println(F("  4. Pressure   -> BMP280/BMP390 on I2C [NEED CHIP]"));
    Serial.println(F("  5. Accel 3-ax -> LIS3DH/MPU6050 on I2C [NEED CHIP]"));
    Serial.println(F("  6. Mag field  -> MLX90393/HMC5883L on I2C [NEED CHIP]"));
  }

  // Also check analog pins
  Serial.println();
  Serial.println(F("=== Analog Pin Check ==="));
  
  for (int pin = A0; pin <= A5; pin++) {
    analogRead(pin); // throwaway
    delayMicroseconds(100);
    
    long sum = 0;
    for (int i = 0; i < 16; i++) {
      sum += analogRead(pin);
    }
    float mean = (float)sum / 16.0;
    float voltage = mean / 1023.0 * 5.0;
    
    Serial.print(F("A"));
    Serial.print(pin - A0);
    Serial.print(F(": ADC="));
    Serial.print(mean, 1);
    Serial.print(F("  V="));
    Serial.print(voltage, 3);
    Serial.print(F(" V"));
    
    // Interpretation
    if (mean < 5) {
      Serial.println(F("  -> PULLED LOW (sensor/GND connected)"));
    } else if (mean > 1018) {
      Serial.println(F("  -> PULLED HIGH (sensor/VCC connected)"));
    } else if (pin - A0 == 2 && mean > 100 && mean < 900) {
      Serial.println(F("  -> POSSIBLE NTC THERMISTOR"));
    } else {
      // Check noise (floating?)
      float var = 0;
      for (int i = 0; i < 16; i++) {
        int v = analogRead(pin);
        float d = v - mean;
        var += d * d;
      }
      var /= 16.0;
      if (var > 50) {
        Serial.println(F("  -> FLOATING (no connection, high noise)"));
      } else {
        Serial.println(F("  -> CONNECTED (stable signal)"));
      }
    }
  }

  Serial.println();
  Serial.println(F("=== Scan Complete ==="));
}

void loop() {
  // Nothing - one-shot scan
  delay(10000);
}
