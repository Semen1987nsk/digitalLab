import 'dart:typed_data';

import 'package:digital_lab/data/hal/packet_parsers.dart';
import 'package:digital_lab/domain/entities/sensor_type.dart';
import 'package:digital_lab/domain/math/crc8.dart';
import 'package:digital_lab/domain/math/signal_processor.dart';
import 'package:flutter_test/flutter_test.dart';

/// Helper: рассчитывает CRC8 для данных и возвращает hex-строку (как
/// прошивка отдаёт). Использует общий [crc8] из domain/math.
String _crcHex(String data) {
  final bytes =
      List<int>.generate(data.length, (i) => data.codeUnitAt(i) & 0xFF);
  return crc8(bytes).toRadixString(16).toUpperCase().padLeft(2, '0');
}

/// Helper: собирает байтовый буфер из BLE-фрейма (header + payload).
Uint8List _buildBleFrame({
  int timestampMs = 1000,
  double voltage = 3.30,
  double current = 0.50,
  double temperature = 25.0,
  double pressure = 101325.0,
  double humidity = 45.0,
  double accelX = 0.1,
  double accelY = 0.2,
  double accelZ = 9.81,
  double magneticField = 25.0,
  double force = 0.0,
  double lux = 500.0,
  double radiation = 12.0,
  double distance = 1500.0,
  int validFlags = 0xFFFFFFFF,
}) {
  final payload = ByteData(PacketParsers.bleLegacyPacketSize);
  payload.setUint32(0, timestampMs, Endian.little);
  payload.setFloat32(4, distance, Endian.little);
  payload.setFloat32(8, voltage, Endian.little);
  payload.setFloat32(12, current, Endian.little);
  payload.setFloat32(20, temperature, Endian.little);
  payload.setFloat32(24, pressure, Endian.little);
  payload.setFloat32(28, humidity, Endian.little);
  payload.setFloat32(32, accelX, Endian.little);
  payload.setFloat32(36, accelY, Endian.little);
  payload.setFloat32(40, accelZ, Endian.little);
  payload.setFloat32(60, magneticField, Endian.little);
  payload.setFloat32(64, force, Endian.little);
  payload.setFloat32(68, lux, Endian.little);
  payload.setFloat32(72, radiation, Endian.little);
  payload.setUint32(76, validFlags, Endian.little);

  // Header: magic 0x4C50 LE + version + payload_size
  final frame = BytesBuilder();
  frame.addByte(0x50); // 'P' — младший байт magic
  frame.addByte(0x4C); // 'L' — старший байт magic
  frame.addByte(PacketParsers.bleProtocolVersion);
  frame.addByte(PacketParsers.bleLegacyPacketSize);
  frame.add(payload.buffer.asUint8List());

  return frame.toBytes();
}

void main() {
  group('parseMultisensorLine', () {
    test('correct CSV with valid CRC8 parses all fields', () {
      const data = 'V:3.30,A:0.50,T:23.4,N:1234';
      final line = '$data*${_crcHex(data)}';

      final packet = PacketParsers.parseMultisensorLine(line, {}, false);

      expect(packet, isNotNull);
      expect(packet!.voltageV, closeTo(3.30, 1e-6));
      expect(packet.currentA, closeTo(0.50, 1e-6));
      expect(packet.temperatureC, closeTo(23.4, 1e-6));
      // 'N' (sequence) намеренно не сохраняется в SensorPacket
    });

    test('returns null when CRC mismatches (bit-flip on the wire)', () {
      const data = 'V:3.30,A:0.50,T:23.4';
      // Берём правильный CRC и инвертируем последний бит.
      final correctCrc = int.parse(_crcHex(data), radix: 16);
      final brokenCrc = (correctCrc ^ 0x01).toRadixString(16).padLeft(2, '0');
      final line = '$data*$brokenCrc';

      expect(
        PacketParsers.parseMultisensorLine(line, {}, false),
        isNull,
      );
    });

    test('returns null when star delimiter is missing', () {
      expect(
        PacketParsers.parseMultisensorLine('V:1.0,A:0.5', {}, false),
        isNull,
      );
    });

    test('returns null on multiple stars (corrupted format)', () {
      expect(
        PacketParsers.parseMultisensorLine('V:1.0*AB*CD', {}, false),
        isNull,
      );
    });

    test('TS field is parsed into timestampMs', () {
      const data = 'TS:5000,V:1.5';
      final line = '$data*${_crcHex(data)}';

      final packet = PacketParsers.parseMultisensorLine(line, {}, false);

      expect(packet, isNotNull);
      expect(packet!.timestampMs, 5000);
      expect(packet.voltageV, closeTo(1.5, 1e-6));
    });

    test('unknown keys are silently ignored', () {
      const data = 'V:1.0,XYZ:42,QQ:foo,A:0.1';
      final line = '$data*${_crcHex(data)}';

      final packet = PacketParsers.parseMultisensorLine(line, {}, false);

      expect(packet, isNotNull);
      expect(packet!.voltageV, closeTo(1.0, 1e-6));
      expect(packet.currentA, closeTo(0.1, 1e-6));
    });

    test('non-numeric value of known key is skipped, not error', () {
      const data = 'V:abc,A:0.5';
      final line = '$data*${_crcHex(data)}';

      final packet = PacketParsers.parseMultisensorLine(line, {}, false);

      expect(packet, isNotNull);
      expect(packet!.voltageV, isNull);
      expect(packet.currentA, closeTo(0.5, 1e-6));
    });

    test('M and MAG aliases both map to magneticField', () {
      const dataM = 'M:25.5';
      const dataMag = 'MAG:25.5';

      final pktM = PacketParsers.parseMultisensorLine(
          '$dataM*${_crcHex(dataM)}', {}, false);
      final pktMag = PacketParsers.parseMultisensorLine(
          '$dataMag*${_crcHex(dataMag)}', {}, false);

      expect(pktM!.magneticFieldMt, closeTo(25.5, 1e-6));
      expect(pktMag!.magneticFieldMt, closeTo(25.5, 1e-6));
    });

    test('SignalProcessor is invoked when enableFiltering=true', () {
      const data = 'V:5.0,A:0.5,T:25.0';
      final line = '$data*${_crcHex(data)}';

      final processors = <SensorType, SignalProcessor>{
        SensorType.voltage: SignalProcessor(sensorType: SensorType.voltage),
      };
      final packet = PacketParsers.parseMultisensorLine(line, processors, true);

      expect(packet, isNotNull);
      // SignalProcessor — Калман+1€, после первого сэмпла фильтр
      // инициализируется значением и возвращает его (или близкое).
      // Главное — фильтр был задействован и не вернул null.
      expect(packet!.voltageV, isNotNull);
      expect(packet.voltageV!.isFinite, isTrue);
    });
  });

  group('parseDistanceLine', () {
    test('"173 cm" → 1730 mm', () {
      final packet = PacketParsers.parseDistanceLine('173 cm', null, false);
      expect(packet, isNotNull);
      expect(packet!.distanceMm, closeTo(1730.0, 1e-6));
    });

    test('"1234 mm" → 1234 mm', () {
      final packet = PacketParsers.parseDistanceLine('1234 mm', null, false);
      expect(packet, isNotNull);
      expect(packet!.distanceMm, closeTo(1234.0, 1e-6));
    });

    test('garbage text → null', () {
      expect(
        PacketParsers.parseDistanceLine('hello world', null, false),
        isNull,
      );
    });

    test('value without unit → null', () {
      expect(
        PacketParsers.parseDistanceLine('173', null, false),
        isNull,
      );
    });

    test('embedded value in larger string parses', () {
      // Регекс ловит первое вхождение `\d+\s*(cm|mm)` — это полезно для
      // строк с префиксом "DIST: 173 cm".
      final packet =
          PacketParsers.parseDistanceLine('DIST: 173 cm OK', null, false);
      expect(packet, isNotNull);
      expect(packet!.distanceMm, closeTo(1730.0, 1e-6));
    });
  });

  group('parseBleSensorPacket', () {
    test('all fields valid → packet decoded', () {
      final frame = _buildBleFrame(
        timestampMs: 1000,
        voltage: 3.30,
        current: 0.50,
        temperature: 25.0,
        // validFlags разрешает: distance|voltage|current|temperature|pressure|humidity|aXYZ|mag|force|lux|radiation
        validFlags: (1 << 0) |
            (1 << 1) |
            (1 << 2) |
            (1 << 4) |
            (1 << 5) |
            (1 << 6) |
            (1 << 7) |
            (1 << 8) |
            (1 << 9) |
            (1 << 14) |
            (1 << 15) |
            (1 << 16) |
            (1 << 17),
      );
      final payload = frame.sublist(PacketParsers.bleFrameHeaderSize);

      final packet = PacketParsers.parseBleSensorPacket(payload);

      expect(packet, isNotNull);
      expect(packet!.timestampMs, 1000);
      expect(packet.voltageV, closeTo(3.30, 1e-3));
      expect(packet.currentA, closeTo(0.50, 1e-3));
      expect(packet.temperatureC, closeTo(25.0, 1e-3));
    });

    test('validFlags=0 → null (empty packet)', () {
      final frame = _buildBleFrame(validFlags: 0);
      final payload = frame.sublist(PacketParsers.bleFrameHeaderSize);

      expect(PacketParsers.parseBleSensorPacket(payload), isNull);
    });

    test('voltage out of physical range → null (corrupted)', () {
      final frame = _buildBleFrame(
        voltage: 9999.0, // вне -500..500
        validFlags: (1 << 1), // помечено как валидное
      );
      final payload = frame.sublist(PacketParsers.bleFrameHeaderSize);

      expect(PacketParsers.parseBleSensorPacket(payload), isNull);
    });

    test('NaN value with its bit set → null', () {
      final frame = _buildBleFrame(
        temperature: double.nan,
        validFlags: (1 << 4),
      );
      final payload = frame.sublist(PacketParsers.bleFrameHeaderSize);

      expect(PacketParsers.parseBleSensorPacket(payload), isNull);
    });

    test('field with no valid bit is null in the packet', () {
      // Только voltage помечен валидным; current не помечен — должен быть null.
      final frame = _buildBleFrame(validFlags: (1 << 1));
      final payload = frame.sublist(PacketParsers.bleFrameHeaderSize);

      final packet = PacketParsers.parseBleSensorPacket(payload);

      expect(packet, isNotNull);
      expect(packet!.voltageV, isNotNull);
      expect(packet.currentA, isNull);
      expect(packet.temperatureC, isNull);
    });

    test('payload shorter than 80 bytes → null', () {
      final shortPayload = Uint8List(50);
      expect(PacketParsers.parseBleSensorPacket(shortPayload), isNull);
    });
  });

  group('tryExtractBlePacket — buffer reconstruction', () {
    test('clean frame at buffer start is consumed', () {
      final frame = _buildBleFrame(validFlags: (1 << 1), voltage: 5.0);
      final buffer = <int>[...frame];

      final packet = PacketParsers.tryExtractBlePacket(buffer);

      expect(packet, isNotNull);
      expect(packet!.voltageV, closeTo(5.0, 1e-3));
      expect(buffer, isEmpty,
          reason: 'весь обработанный фрейм удалён из буфера');
    });

    test('garbage prefix before magic is dropped', () {
      final frame = _buildBleFrame(validFlags: (1 << 1));
      final buffer = <int>[0xAA, 0xBB, 0xCC, ...frame];

      final packet = PacketParsers.tryExtractBlePacket(buffer);

      expect(packet, isNotNull);
      expect(buffer, isEmpty);
    });

    test('partial frame returns null and keeps buffer for next notify', () {
      final frame = _buildBleFrame(validFlags: (1 << 1));
      // Только половина пакета (≥4 байта чтобы header прошёл проверку).
      final buffer = <int>[...frame.sublist(0, 40)];

      final packet = PacketParsers.tryExtractBlePacket(buffer);

      expect(packet, isNull);
      expect(buffer.length, 40,
          reason: 'буфер сохранён до прихода остальных байт');
    });

    test('two frames back-to-back are extracted in two calls', () {
      final f1 = _buildBleFrame(validFlags: (1 << 1), voltage: 1.0);
      final f2 = _buildBleFrame(validFlags: (1 << 1), voltage: 2.0);
      final buffer = <int>[...f1, ...f2];

      final p1 = PacketParsers.tryExtractBlePacket(buffer);
      final p2 = PacketParsers.tryExtractBlePacket(buffer);

      expect(p1, isNotNull);
      expect(p1!.voltageV, closeTo(1.0, 1e-3));
      expect(p2, isNotNull);
      expect(p2!.voltageV, closeTo(2.0, 1e-3));
      expect(buffer, isEmpty);
    });

    test('empty buffer → null, buffer stays empty', () {
      final buffer = <int>[];
      expect(PacketParsers.tryExtractBlePacket(buffer), isNull);
      expect(buffer, isEmpty);
    });

    test(
        'invalid header (wrong protocol version) drops 1 byte and returns null',
        () {
      // magic OK, но version=99 → 1 байт сдвига и ждём другой magic.
      final buffer = <int>[
        0x50, 0x4C, // magic
        99, // version (invalid)
        80, // payload size
        ...List.filled(80, 0),
      ];
      final initialLen = buffer.length;

      final packet = PacketParsers.tryExtractBlePacket(buffer);

      expect(packet, isNull);
      expect(buffer.length, initialLen - 1,
          reason: 'удалён ровно 1 байт, чтобы продолжить поиск magic дальше');
    });

    test('no magic in buffer → length is compressed to last byte', () {
      final buffer = <int>[
        0x11,
        0x22,
        0x33,
        0x44,
        0x55,
      ];

      final packet = PacketParsers.tryExtractBlePacket(buffer);

      expect(packet, isNull);
      expect(buffer.length, 1,
          reason: 'все байты кроме последнего отброшены — magic 2-байтный, '
              'надо хранить только хвост на случай склейки с следующим notify');
    });
  });

  group('CRC integration with domain/math/crc8', () {
    test('multisensor parser uses the SAME crc8 as domain/math', () {
      // Если бы parseMultisensorLine использовал свой алгоритм CRC,
      // а тестовый _crcHex — другой, тесты бы не проходили.
      const data = 'V:1.234,A:0.567';
      final hex = _crcHex(data);
      final line = '$data*$hex';

      expect(
        PacketParsers.parseMultisensorLine(line, {}, false),
        isNotNull,
      );
    });
  });
}
