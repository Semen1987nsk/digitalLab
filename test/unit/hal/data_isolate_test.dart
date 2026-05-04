import 'dart:async';
import 'dart:typed_data';

import 'package:digital_lab/data/hal/data_isolate.dart';
import 'package:digital_lab/data/hal/packet_parsers.dart';
import 'package:digital_lab/domain/entities/sensor_data.dart';
import 'package:flutter_test/flutter_test.dart';

/// Собирает корректный обрамлённый BLE-пакет для тестов парсинга
/// через реальный Isolate.
Uint8List _buildBleFrame({
  int timestampMs = 1000,
  double voltage = 3.30,
  int validFlags = 1 << 1, // bit для voltage
}) {
  final payload = ByteData(PacketParsers.bleLegacyPacketSize);
  payload.setUint32(0, timestampMs, Endian.little);
  payload.setFloat32(8, voltage, Endian.little);
  payload.setUint32(76, validFlags, Endian.little);

  final frame = BytesBuilder();
  frame.addByte(0x50);
  frame.addByte(0x4C);
  frame.addByte(PacketParsers.bleProtocolVersion);
  frame.addByte(PacketParsers.bleLegacyPacketSize);
  frame.add(payload.buffer.asUint8List());

  return frame.toBytes();
}

void main() {
  group('DataProcessingIsolate lifecycle', () {
    test('start() returns only after Isolate handshake', () async {
      final isolate = DataProcessingIsolate();
      expect(isolate.isRunning, isFalse);

      await isolate.start(deviceType: IsolateDeviceType.bleMultisensor);

      expect(isolate.isRunning, isTrue,
          reason: 'после await start() Isolate готов принимать команды');

      await isolate.dispose();
    });

    test('start() is idempotent — second call is a no-op', () async {
      final isolate = DataProcessingIsolate();
      await isolate.start(deviceType: IsolateDeviceType.bleMultisensor);
      // Второй вызов — Logger.warning, не должен породить второй Isolate.
      await isolate.start(deviceType: IsolateDeviceType.bleMultisensor);

      expect(isolate.isRunning, isTrue);
      await isolate.dispose();
    });

    test('processRawData before start() does not throw', () async {
      final isolate = DataProcessingIsolate();
      // До start() данные дропаются с warning'ом, без exception.
      expect(
        () => isolate.processRawData(Uint8List.fromList([0xAA, 0xBB])),
        returnsNormally,
      );

      await isolate.dispose();
    });

    test('stop() shuts the Isolate down cleanly', () async {
      final isolate = DataProcessingIsolate();
      await isolate.start(deviceType: IsolateDeviceType.bleMultisensor);
      expect(isolate.isRunning, isTrue);

      await isolate.stop();
      expect(isolate.isRunning, isFalse,
          reason: 'после stop() флаг должен сброситься');

      await isolate.dispose();
    });

    test('dispose() closes the broadcast data stream', () async {
      final isolate = DataProcessingIsolate();
      await isolate.start(deviceType: IsolateDeviceType.bleMultisensor);

      var doneFired = false;
      isolate.dataStream.listen(
        (_) {},
        onDone: () => doneFired = true,
      );

      await isolate.dispose();
      // Даём микротаскам пройти, чтобы onDone успел сработать.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(doneFired, isTrue);
    });
  });

  group('DataProcessingIsolate parsing through real Isolate', () {
    test('valid BLE frame is parsed and emitted via dataStream', () async {
      final isolate = DataProcessingIsolate();
      await isolate.start(deviceType: IsolateDeviceType.bleMultisensor);

      final completer = Completer<SensorPacket>();
      late StreamSubscription<SensorPacket> sub;
      sub = isolate.dataStream.listen((packet) {
        if (!completer.isCompleted) {
          completer.complete(packet);
        }
      });

      final frame = _buildBleFrame(timestampMs: 4242, voltage: 5.0);
      isolate.processRawData(frame);

      final packet = await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException(
            'Isolate не вернул пакет за 5 секунд — handshake/парсинг сломан'),
      );

      expect(packet.timestampMs, 4242);
      expect(packet.voltageV, closeTo(5.0, 1e-3));

      await sub.cancel();
      await isolate.dispose();
    });

    test('garbage input does not produce a packet', () async {
      final isolate = DataProcessingIsolate();
      await isolate.start(deviceType: IsolateDeviceType.bleMultisensor);

      var packetsReceived = 0;
      final sub = isolate.dataStream.listen((_) => packetsReceived++);

      // Случайные байты — без magic, парсер должен их сжать до 1 байта.
      isolate.processRawData(Uint8List.fromList([0x11, 0x22, 0x33]));

      // Даём Isolate время отработать. Точно нет packet.
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(packetsReceived, 0);

      await sub.cancel();
      await isolate.dispose();
    });

    test('two back-to-back BLE frames yield two packets', () async {
      final isolate = DataProcessingIsolate();
      await isolate.start(deviceType: IsolateDeviceType.bleMultisensor);

      final received = <SensorPacket>[];
      final sub = isolate.dataStream.listen(received.add);

      final f1 = _buildBleFrame(timestampMs: 100, voltage: 1.0);
      final f2 = _buildBleFrame(timestampMs: 200, voltage: 2.0);
      // Передаём оба пакета в одном чанке (как BLE notify иногда склеивает).
      final combined = Uint8List.fromList([...f1, ...f2]);
      isolate.processRawData(combined);

      // Ждём пока придут оба пакета (с разумным таймаутом).
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (received.length < 2 && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      expect(received, hasLength(2));
      expect(received[0].voltageV, closeTo(1.0, 1e-3));
      expect(received[1].voltageV, closeTo(2.0, 1e-3));

      await sub.cancel();
      await isolate.dispose();
    });

    test('Arduino multisensor CSV line is parsed via Isolate', () async {
      final isolate = DataProcessingIsolate();
      await isolate.start(
        deviceType: IsolateDeviceType.arduinoMultisensor,
        enableFiltering: false,
      );

      final completer = Completer<SensorPacket>();
      final sub = isolate.dataStream.listen((p) {
        if (!completer.isCompleted) completer.complete(p);
      });

      // Реальная строка от прошивки (с CRC8). Этот же CRC проверяется парсером.
      // Используем парсер вне Isolate чтобы вычислить корректный CRC и
      // отправить готовую строку (включая `\n` для завершения).
      const data = 'V:7.5,A:1.5,T:42.0';
      // CRC рассчитан тем же алгоритмом, что внутри парсера (Dallas/Maxim).
      // Для 'V:7.5,A:1.5,T:42.0' — пересчитываем тут же:
      int crc = 0;
      for (final code in data.codeUnits) {
        int b = code & 0xFF;
        for (int bit = 0; bit < 8; bit++) {
          if ((crc ^ b) & 0x01 != 0) {
            crc = (crc >> 1) ^ 0x8C;
          } else {
            crc >>= 1;
          }
          b >>= 1;
        }
      }
      final hex = (crc & 0xFF).toRadixString(16).toUpperCase().padLeft(2, '0');
      final line = '$data*$hex\n';

      isolate.processRawData(Uint8List.fromList(line.codeUnits));

      final packet = await completer.future.timeout(
        const Duration(seconds: 5),
      );

      expect(packet.voltageV, closeTo(7.5, 1e-6));
      expect(packet.currentA, closeTo(1.5, 1e-6));
      expect(packet.temperatureC, closeTo(42.0, 1e-6));

      await sub.cancel();
      await isolate.dispose();
    });
  });
}
