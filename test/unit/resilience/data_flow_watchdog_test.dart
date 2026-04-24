import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_lab/data/hal/sensor_hub.dart';
import 'package:digital_lab/domain/entities/sensor_data.dart';
import 'package:digital_lab/domain/repositories/hal_interface.dart';

// ═══════════════════════════════════════════════════════════════
//  Resilience tests: Data-Flow Watchdog & Recovery UX
//
//  Гипотеза H2 Principal Engineer аудита:
//  "Дешёвый USB-кабель с частичным контактом → порт остаётся открытым
//   но данные перестают приходить → бесконечное молчание."
//
//  Data-flow watchdog реализован в UsbHALWindows (_checkDataFlowWatchdog).
//  Здесь тестируем SensorHub-уровень: isRecovering и агрегированный статус.
// ═══════════════════════════════════════════════════════════════

class FakeHAL implements HALInterface {
  final _statusController = StreamController<ConnectionStatus>.broadcast();
  final _dataController = StreamController<SensorPacket>.broadcast();
  bool shouldFailConnect = false;

  @override
  Stream<ConnectionStatus> get connectionStatus => _statusController.stream;
  @override
  Stream<SensorPacket> get sensorData => _dataController.stream;

  @override
  DeviceInfo? get deviceInfo => const DeviceInfo(
        name: 'FakeDevice',
        firmwareVersion: '1.0',
        batteryPercent: 100,
        enabledSensors: ['voltage'],
        connectionType: ConnectionType.usb,
      );
  @override
  bool get isCalibrated => false;

  @override
  Future<bool> connect() async {
    if (shouldFailConnect) return false;
    _statusController.add(ConnectionStatus.connected);
    return true;
  }

  @override
  Future<void> disconnect() async {
    _statusController.add(ConnectionStatus.disconnected);
  }

  @override
  Future<void> startMeasurement() async {}
  @override
  Future<void> stopMeasurement() async {}
  @override
  Future<void> calibrate(String sensorId) async {}
  @override
  Future<void> setSampleRate(int hz) async {}
  @override
  Future<void> dispose() async {}

  void emitStatus(ConnectionStatus status) => _statusController.add(status);
  void emitPacket(SensorPacket packet) => _dataController.add(packet);

  void close() {
    _statusController.close();
    _dataController.close();
  }
}

void main() {
  group('SensorHub isRecovering', () {
    late SensorHub hub;
    late FakeHAL fakeHal;

    setUp(() {
      hub = SensorHub();
      fakeHal = FakeHAL();
      hub.addDevice(HubDevice(id: 'COM3', name: 'Test', hal: fakeHal));
    });

    tearDown(() async {
      await hub.dispose();
      fakeHal.close();
    });

    test('isRecovering is false initially', () {
      expect(hub.isRecovering, isFalse);
    });

    test('isRecovering is false when connected', () async {
      await hub.connect();
      expect(hub.currentStatus, ConnectionStatus.connected);
      expect(hub.isRecovering, isFalse);
    });

    test('SensorHub status is disconnected after device disconnects', () async {
      await hub.connect();
      expect(hub.currentStatus, ConnectionStatus.connected);

      fakeHal.emitStatus(ConnectionStatus.disconnected);
      // Give the async listener a tick to process
      await Future.delayed(Duration.zero);

      expect(hub.currentStatus, ConnectionStatus.disconnected);
    });

    test('SensorHub merges sensor data from device', () async {
      final packets = <SensorPacket>[];
      hub.sensorData.listen(packets.add);

      await hub.connect();
      fakeHal.emitPacket(const SensorPacket(timestampMs: 100, voltageV: 5.0));
      await Future.delayed(Duration.zero);

      expect(packets, hasLength(1));
      expect(packets.first.voltageV, 5.0);
    });

    test('HubDevice tracks packet rate', () async {
      await hub.connect();
      final device = hub.devices.first;

      expect(device.packetsReceived, 0);
      expect(device.packetsPerSecond, 0.0);

      fakeHal.emitPacket(const SensorPacket(timestampMs: 100));
      fakeHal.emitPacket(const SensorPacket(timestampMs: 200));
      fakeHal.emitPacket(const SensorPacket(timestampMs: 300));
      await Future.delayed(Duration.zero);

      expect(device.packetsReceived, 3);
      // packetsPerSecond > 0 because all 3 are within the 3s window
      expect(device.packetsPerSecond, greaterThan(0));
    });
  });

  group('SensorHub aggregate status with multiple devices', () {
    late SensorHub hub;
    late FakeHAL hal1;
    late FakeHAL hal2;

    setUp(() {
      hub = SensorHub();
      hal1 = FakeHAL();
      hal2 = FakeHAL();
      hub.addDevice(HubDevice(id: 'COM3', name: 'Arduino', hal: hal1));
      hub.addDevice(HubDevice(id: 'COM4', name: 'FTDI', hal: hal2));
    });

    tearDown(() async {
      await hub.dispose();
      hal1.close();
      hal2.close();
    });

    test('connected if ANY device is connected', () async {
      await hub.connect();
      expect(hub.connectedCount, 2);

      hal1.emitStatus(ConnectionStatus.disconnected);
      await Future.delayed(Duration.zero);

      // COM4 still connected → hub = connected
      expect(hub.currentStatus, ConnectionStatus.connected);
      expect(hub.connectedCount, 1);
    });

    test('disconnected only when ALL devices disconnected', () async {
      await hub.connect();

      hal1.emitStatus(ConnectionStatus.disconnected);
      hal2.emitStatus(ConnectionStatus.disconnected);
      await Future.delayed(Duration.zero);

      expect(hub.currentStatus, ConnectionStatus.disconnected);
      expect(hub.connectedCount, 0);
    });
  });
}
