import 'dart:typed_data';

import '../../domain/entities/sensor_data.dart';
import '../../domain/entities/sensor_type.dart';
import '../../domain/math/crc8.dart' as math;
import '../../domain/math/signal_processor.dart';

/// Чистые функции парсинга пакетов от датчиков.
///
/// Раньше жили внутри `data_isolate.dart` как приватные `_static` методы —
/// нельзя было покрыть unit-тестами без поднятия Isolate. Вынесены сюда:
/// - publicly testable
/// - не зависят от Isolate / Flutter
/// - покрыты тестами в `test/unit/hal/packet_parsers_test.dart`
class PacketParsers {
  PacketParsers._();

  // ── BLE constants (must match firmware) ──────────────────

  /// Размер «голого» (без рамки) BLE-пакета, в байтах.
  static const int bleLegacyPacketSize = 80;

  /// Размер заголовка рамки: MAGIC(2) + VERSION(1) + PAYLOAD_SIZE(1).
  static const int bleFrameHeaderSize = 4;

  /// Полный размер обрамлённого пакета (header + payload).
  static const int bleFramedPacketSize =
      bleFrameHeaderSize + bleLegacyPacketSize;

  /// `'PL'` little-endian — magic-маркер начала фрейма.
  static const int bleFrameMagic = 0x4C50;

  /// Версия протокола BLE-пакета. Должна совпадать с прошивкой.
  static const int bleProtocolVersion = 1;

  // ═══════════════════════════════════════════════════════════
  //  Arduino мультидатчик (CSV-формат с CRC8)
  // ═══════════════════════════════════════════════════════════

  /// Формат строки: `"V:12.34,A:0.56,T:23.4,N:1234,*AB"` где `*AB` — CRC8 в hex.
  ///
  /// Возвращает `null` если:
  /// - нет `*` (некорректный формат)
  /// - CRC8 не совпадает (повреждённые данные → битовая ошибка в кабеле)
  /// - значение поля невалидное (не парсится как `double`)
  ///
  /// При [enableFiltering]=true применяет SignalProcessor к V/A/T (если
  /// процессоры заданы в [processors]).
  static SensorPacket? parseMultisensorLine(
    String line,
    Map<SensorType, SignalProcessor> processors,
    bool enableFiltering,
  ) {
    if (!line.contains('*')) return null;

    final parts = line.split('*');
    if (parts.length != 2) return null;

    final data = parts[0];
    final crcHex = parts[1];

    // Валидация CRC8 (Dallas/Maxim, reflected 0x8C)
    final expectedCrc = _crc8OfString(data);
    final receivedCrc = int.tryParse(crcHex, radix: 16);
    if (receivedCrc == null || receivedCrc != expectedCrc) {
      return null;
    }

    int timestampMs = 0;
    double? voltage, current, temperature, pressure, humidity;
    double? distance, acceleration, magneticField, force, lux, radiation;

    final fields = data.split(',');

    for (final field in fields) {
      if (!field.contains(':')) continue;

      final kv = field.split(':');
      if (kv.length != 2) continue;

      final key = kv[0].trim();
      final valueStr = kv[1].trim();
      final value = double.tryParse(valueStr);
      if (value == null) continue;

      switch (key) {
        case 'V':
          voltage = enableFiltering && processors[SensorType.voltage] != null
              ? processors[SensorType.voltage]!.process(value)
              : value;
          break;
        case 'A':
          current = enableFiltering && processors[SensorType.current] != null
              ? processors[SensorType.current]!.process(value)
              : value;
          break;
        case 'T':
          temperature =
              enableFiltering && processors[SensorType.temperature] != null
                  ? processors[SensorType.temperature]!.process(value)
                  : value;
          break;
        case 'P':
          pressure = value;
          break;
        case 'H':
          humidity = value;
          break;
        case 'DIST':
          distance = value;
          break;
        case 'ACC':
          acceleration = value;
          break;
        case 'MAG':
        case 'M':
          magneticField = value;
          break;
        case 'F':
          force = value;
          break;
        case 'LUX':
          lux = value;
          break;
        case 'RAD':
          radiation = value;
          break;
        case 'N':
          // Sequence number — диагностика, не сохраняем.
          break;
        case 'TS':
          timestampMs = value.toInt();
          break;
      }
    }

    return SensorPacket(
      timestampMs: timestampMs,
      voltageV: voltage,
      currentA: current,
      temperatureC: temperature,
      pressurePa: pressure,
      humidityPct: humidity,
      distanceMm: distance,
      accelX: acceleration,
      magneticFieldMt: magneticField,
      forceN: force,
      luxLx: lux,
      radiationCpm: radiation,
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  FTDI датчик расстояния V802 (CSV)
  // ═══════════════════════════════════════════════════════════

  /// Формат строки: `"173 cm"` или `"1234 mm"`. Возвращает `null` если строка
  /// не распознана. `cm` конвертирует в мм.
  static SensorPacket? parseDistanceLine(
    String line,
    SignalProcessor? processor,
    bool enableFiltering,
  ) {
    final match = RegExp(r'(\d+)\s*(cm|mm)').firstMatch(line);
    if (match == null) return null;

    final valueStr = match.group(1);
    final unit = match.group(2);
    if (valueStr == null || unit == null) return null;

    var value = double.tryParse(valueStr);
    if (value == null) return null;

    if (unit == 'cm') value *= 10;

    if (enableFiltering && processor != null) {
      value = processor.process(value);
    }

    return SensorPacket(
      timestampMs: 0,
      distanceMm: value,
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  BLE мультидатчик (binary frame)
  // ═══════════════════════════════════════════════════════════

  /// Пытается извлечь один обрамлённый BLE-пакет из [buffer].
  ///
  /// Алгоритм:
  /// 1. Ищет magic-маркер `0x4C50` ('PL').
  /// 2. Если magic не найден — оставляет в буфере последний байт (для
  ///    следующего notify) и возвращает `null`.
  /// 3. Если найден, но префикс до magic > 0 — отбрасывает префикс.
  /// 4. Проверяет header (version, payload size). Битый header → отбрасывает
  ///    1 байт и возвращает `null` (попробует снова на следующей итерации).
  /// 5. Если есть полный фрейм — парсит payload, удаляет фрейм из буфера.
  ///
  /// Мутирует [buffer]: удаляет из него обработанные/невалидные байты.
  static SensorPacket? tryExtractBlePacket(List<int> buffer) {
    if (buffer.isEmpty) return null;

    int magicIndex = -1;
    for (int i = 0; i + 1 < buffer.length; i++) {
      final candidate = buffer[i] | (buffer[i + 1] << 8);
      if (candidate == bleFrameMagic) {
        magicIndex = i;
        break;
      }
    }

    if (magicIndex > 0) {
      buffer.removeRange(0, magicIndex);
    }

    if (magicIndex == -1) {
      if (buffer.length > 1) {
        buffer.removeRange(0, buffer.length - 1);
      }
      return null;
    }

    if (buffer.length < bleFrameHeaderSize) return null;

    final protocolVersion = buffer[2];
    final payloadSize = buffer[3];
    if (protocolVersion != bleProtocolVersion ||
        payloadSize != bleLegacyPacketSize) {
      buffer.removeAt(0);
      return null;
    }

    if (buffer.length < bleFramedPacketSize) {
      return null;
    }

    final payload = Uint8List.fromList(
      buffer.sublist(bleFrameHeaderSize, bleFramedPacketSize),
    );
    final packet = parseBleSensorPacket(payload);

    if (packet != null) {
      buffer.removeRange(0, bleFramedPacketSize);
      return packet;
    }

    buffer.removeAt(0);
    return null;
  }

  /// Парсит «голый» (без рамки) BLE-пакет фиксированного размера 80 байт.
  ///
  /// Layout (Little-Endian):
  /// ```
  ///   0..3   uint32  timestamp_ms
  ///   4..7   float32 distance_mm
  ///   8..11  float32 voltage_v
  ///  12..15  float32 current_a
  ///  20..23  float32 temperature_c
  ///  24..27  float32 pressure_pa
  ///  28..31  float32 humidity_pct
  ///  32..35  float32 accel_x
  ///  36..39  float32 accel_y
  ///  40..43  float32 accel_z
  ///  60..63  float32 magnetic_field_mt
  ///  64..67  float32 force_n
  ///  68..71  float32 lux_lx
  ///  72..75  float32 radiation_cpm
  ///  76..79  uint32  valid_flags (битовая маска)
  /// ```
  ///
  /// Возвращает `null` если:
  /// - длина буфера меньше 80
  /// - `validFlags == 0` (пустой пакет, прошивка прислала «ничего нет»)
  /// - какое-то из valid-полей не вписывается в физический диапазон
  ///   (повреждение из-за помех на BLE).
  static SensorPacket? parseBleSensorPacket(Uint8List data) {
    if (data.length < bleLegacyPacketSize) return null;

    final byteData = ByteData.sublistView(data);

    final timestamp = byteData.getUint32(0, Endian.little);
    final distance = byteData.getFloat32(4, Endian.little);
    final voltage = byteData.getFloat32(8, Endian.little);
    final current = byteData.getFloat32(12, Endian.little);
    final temperature = byteData.getFloat32(20, Endian.little);
    final pressure = byteData.getFloat32(24, Endian.little);
    final humidity = byteData.getFloat32(28, Endian.little);
    final accelX = byteData.getFloat32(32, Endian.little);
    final accelY = byteData.getFloat32(36, Endian.little);
    final accelZ = byteData.getFloat32(40, Endian.little);
    final magneticField = byteData.getFloat32(60, Endian.little);
    final force = byteData.getFloat32(64, Endian.little);
    final lux = byteData.getFloat32(68, Endian.little);
    final radiation = byteData.getFloat32(72, Endian.little);
    final validFlags = byteData.getUint32(76, Endian.little);

    if (validFlags == 0) return null;

    if (!_isLikelyValidPacket(
      timestamp: timestamp,
      validFlags: validFlags,
      distance: distance,
      voltage: voltage,
      current: current,
      temperature: temperature,
      pressure: pressure,
      humidity: humidity,
      accelX: accelX,
      accelY: accelY,
      accelZ: accelZ,
      magneticField: magneticField,
      force: force,
      lux: lux,
      radiation: radiation,
    )) {
      return null;
    }

    return SensorPacket(
      timestampMs: timestamp,
      voltageV: _ifValid(validFlags, 1 << 1, voltage),
      currentA: _ifValid(validFlags, 1 << 2, current),
      pressurePa: _ifValid(validFlags, 1 << 5, pressure),
      temperatureC: _ifValid(validFlags, 1 << 4, temperature),
      humidityPct: _ifValid(validFlags, 1 << 6, humidity),
      accelX: _ifValid(validFlags, 1 << 7, accelX),
      accelY: _ifValid(validFlags, 1 << 8, accelY),
      accelZ: _ifValid(validFlags, 1 << 9, accelZ),
      magneticFieldMt: _ifValid(validFlags, 1 << 14, magneticField),
      distanceMm: _ifValid(validFlags, 1 << 0, distance),
      forceN: _ifValid(validFlags, 1 << 15, force),
      luxLx: _ifValid(validFlags, 1 << 16, lux),
      radiationCpm: _ifValid(validFlags, 1 << 17, radiation),
    );
  }

  static double? _ifValid(int flags, int bit, double value) {
    if (flags & bit != 0) return value;
    return null;
  }

  /// Проверка физических диапазонов для каждого помеченного валидным канала.
  /// Если хоть одно значение вне диапазона — вероятен битый пакет.
  static bool _isLikelyValidPacket({
    required int timestamp,
    required int validFlags,
    required double distance,
    required double voltage,
    required double current,
    required double temperature,
    required double pressure,
    required double humidity,
    required double accelX,
    required double accelY,
    required double accelZ,
    required double magneticField,
    required double force,
    required double lux,
    required double radiation,
  }) {
    if (validFlags == 0) return false;

    bool inRange(double v, double min, double max) =>
        v.isFinite && v >= min && v <= max;

    if ((validFlags & (1 << 0)) != 0 && !inRange(distance, 0, 100000)) {
      return false;
    }
    if ((validFlags & (1 << 1)) != 0 && !inRange(voltage, -500, 500)) {
      return false;
    }
    if ((validFlags & (1 << 2)) != 0 && !inRange(current, -100, 100)) {
      return false;
    }
    if ((validFlags & (1 << 4)) != 0 && !inRange(temperature, -100, 300)) {
      return false;
    }
    if ((validFlags & (1 << 5)) != 0 && !inRange(pressure, 1000, 500000)) {
      return false;
    }
    if ((validFlags & (1 << 6)) != 0 && !inRange(humidity, 0, 100)) {
      return false;
    }
    if ((validFlags & (1 << 7)) != 0 && !inRange(accelX, -500, 500)) {
      return false;
    }
    if ((validFlags & (1 << 8)) != 0 && !inRange(accelY, -500, 500)) {
      return false;
    }
    if ((validFlags & (1 << 9)) != 0 && !inRange(accelZ, -500, 500)) {
      return false;
    }
    if ((validFlags & (1 << 14)) != 0 &&
        !inRange(magneticField, -10000, 10000)) {
      return false;
    }
    if ((validFlags & (1 << 15)) != 0 && !inRange(force, -100000, 100000)) {
      return false;
    }
    if ((validFlags & (1 << 16)) != 0 && !inRange(lux, 0, 200000)) return false;
    if ((validFlags & (1 << 17)) != 0 && !inRange(radiation, 0, 1000000)) {
      return false;
    }

    return true;
  }

  // ═══════════════════════════════════════════════════════════
  //  Helpers
  // ═══════════════════════════════════════════════════════════

  /// CRC8 для строки. Использует общий [math.crc8] из `domain/math/crc8.dart`,
  /// преобразовывая каждый code unit в один байт. Подходит только для ASCII —
  /// формат мультидатчика этим и ограничен.
  static int _crc8OfString(String data) {
    final bytes = List<int>.generate(
        data.length, (i) => data.codeUnitAt(i) & 0xFF,
        growable: false);
    return math.crc8(bytes);
  }
}
