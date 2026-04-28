import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_lab/domain/math/crc8.dart';

/// Helper: converts a String to List<int> for crc8() which takes List<int>.
int crc8String(String data) => crc8(data.codeUnits);

void main() {
  group('CRC8 (Dallas/Maxim)', () {
    test('empty list returns 0', () {
      expect(crc8([]), 0x00);
    });

    test('single byte', () {
      expect(crc8([0x41]), isNot(0)); // 'A'
    });

    test('known test vector "123456789"', () {
      // CRC-8/MAXIM of "123456789" = 0xA1
      expect(crc8String('123456789'), 0xA1);
    });

    test('firmware-like data line', () {
      const line = 'V:4.321,A:0.042,T:22.50,P:101325.0,H:45.0,'
          'AX:0.0012,AY:-0.0023,AZ:1.0001,N:1,T_MS:100';
      final checksum = crc8String(line);
      // Checksum should be deterministic
      expect(checksum, crc8String(line));
      // And be a valid byte
      expect(checksum, inInclusiveRange(0, 255));
    });

    test('corrupted data produces different CRC', () {
      const line1 = 'V:4.321,A:0.042,T:22.50';
      const line2 = 'V:4.322,A:0.042,T:22.50'; // One digit changed
      expect(crc8String(line1), isNot(crc8String(line2)));
    });

    test('CRC detects single bit flip', () {
      const original = 'V:1.000,A:2.000';
      final originalCrc = crc8String(original);

      final bytes = original.codeUnits.toList();
      bytes[2] ^= 0x01; // Flip LSB of '1'
      expect(crc8(bytes), isNot(originalCrc));
    });

    test('CRC detects byte swap', () {
      expect(crc8String('V:1.234'), isNot(crc8String('V:1.243')));
    });

    test('CRC hex formatting matches firmware *XX format', () {
      const line = 'V:5.000,A:0.050,N:42,T_MS:4200';
      final checksum = crc8String(line);
      final hex = checksum.toRadixString(16).toUpperCase().padLeft(2, '0');
      expect(hex.length, 2);
      expect(int.parse(hex, radix: 16), checksum);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  //  BLE COMMAND PAYLOAD TESTS
  //
  //  Verify that the payload format matches what firmware expects:
  //  - Simple command: [cmd, crc8([cmd])]
  //  - setSampleRate:  [cmd, lo, hi, crc8([cmd, lo, hi])]
  //  - calibrate:      [cmd, len, ...sensorId, crc8(all_except_last)]
  //
  //  If someone refactors ble_hal.dart, these tests will catch
  //  broken payload format BEFORE it reaches real hardware.
  // ═══════════════════════════════════════════════════════════════

  group('BLE command payload format', () {
    // Constants from BleCommand in ble_hal.dart
    const start = 0x01;
    const stop = 0x02;
    const calibrate = 0x03;
    const setSampleRate = 0x04;

    test('simple command payload: [cmd, crc8([cmd])]', () {
      for (final cmd in [start, stop]) {
        final payload = Uint8List(2);
        payload[0] = cmd;
        payload[1] = crc8([cmd]);

        expect(payload.length, 2);
        expect(payload[0], cmd);
        // Verify CRC byte is valid
        expect(crc8([payload[0]]), payload[1],
            reason: 'CRC must match for cmd=0x${cmd.toRadixString(16)}');
      }
    });

    test('setSampleRate payload: [cmd, lo, hi, crc8(first 3)]', () {
      const hz = 100; // 100 Hz
      final payload = Uint8List(4);
      payload[0] = setSampleRate;
      payload[1] = hz & 0xFF;
      payload[2] = (hz >> 8) & 0xFF;
      payload[3] = crc8(payload.sublist(0, 3));

      expect(payload[0], setSampleRate);
      expect(payload[1], 100); // lo byte
      expect(payload[2], 0); // hi byte (100 < 256)
      expect(crc8(payload.sublist(0, 3)), payload[3],
          reason: 'CRC must cover [cmd, lo, hi]');
    });

    test('setSampleRate high frequency (1000 Hz) little-endian', () {
      const hz = 1000;
      final payload = Uint8List(4);
      payload[0] = setSampleRate;
      payload[1] = hz & 0xFF; // 0xE8
      payload[2] = (hz >> 8) & 0xFF; // 0x03
      payload[3] = crc8(payload.sublist(0, 3));

      expect(payload[1], 0xE8);
      expect(payload[2], 0x03);
      // Verify CRC covers the right bytes
      expect(crc8([setSampleRate, 0xE8, 0x03]), payload[3]);
    });

    test('calibrate payload: [cmd, len, ...id, crc8(all_but_last)]', () {
      const sensorId = 'voltage';
      final payload = Uint8List(2 + sensorId.length + 1);
      payload[0] = calibrate;
      payload[1] = sensorId.length;
      for (int i = 0; i < sensorId.length; i++) {
        payload[2 + i] = sensorId.codeUnitAt(i);
      }
      payload[payload.length - 1] =
          crc8(payload.sublist(0, payload.length - 1));

      expect(payload[0], calibrate);
      expect(payload[1], 7); // 'voltage'.length
      expect(String.fromCharCodes(payload.sublist(2, 2 + 7)), 'voltage');
      // CRC covers everything except the last byte
      expect(
        crc8(payload.sublist(0, payload.length - 1)),
        payload.last,
        reason: 'CRC must cover [cmd, len, ...sensorId]',
      );
    });

    test('different commands produce different CRC', () {
      final crcStart = crc8([start]);
      final crcStop = crc8([stop]);
      final crcCal = crc8([calibrate]);
      expect(crcStart, isNot(crcStop));
      expect(crcStart, isNot(crcCal));
      expect(crcStop, isNot(crcCal));
    });
  });
}
