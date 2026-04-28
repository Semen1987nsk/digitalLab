import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_lab/data/hal/sensor_hub.dart';
import 'package:digital_lab/domain/entities/sensor_data.dart';
import 'package:digital_lab/domain/repositories/hal_interface.dart';

// ═══════════════════════════════════════════════════════════════
//  Fake HAL for testing SensorHub
// ═══════════════════════════════════════════════════════════════

class FakeHAL implements HALInterface {
  final _statusController = StreamController<ConnectionStatus>.broadcast();
  final _dataController = StreamController<SensorPacket>.broadcast();

  bool connectCalled = false;
  bool disconnectCalled = false;
  bool startCalled = false;
  bool stopCalled = false;
  bool disposeCalled = false;
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
    connectCalled = true;
    if (shouldFailConnect) return false;
    _statusController.add(ConnectionStatus.connected);
    return true;
  }

  @override
  Future<void> disconnect() async {
    disconnectCalled = true;
    _statusController.add(ConnectionStatus.disconnected);
  }

  @override
  Future<void> startMeasurement() async {
    startCalled = true;
  }

  @override
  Future<void> stopMeasurement() async {
    stopCalled = true;
  }

  @override
  Future<void> calibrate(String sensorId) async {}

  @override
  Future<void> setSampleRate(int hz) async {}

  @override
  Future<void> dispose() async {
    disposeCalled = true;
  }

  /// Emit a sensor packet (for testing)
  void emitPacket(SensorPacket packet) {
    _dataController.add(packet);
  }

  void close() {
    _statusController.close();
    _dataController.close();
  }
}

// ═══════════════════════════════════════════════════════════════
//  Tests
// ═══════════════════════════════════════════════════════════════

void main() {
  group('SensorHub', () {
    late SensorHub hub;

    setUp(() {
      hub = SensorHub();
    });

    tearDown(() async {
      await hub.dispose();
    });

    test('starts with empty device list', () {
      expect(hub.devices, isEmpty);
      expect(hub.connectedCount, 0);
      expect(hub.currentStatus, ConnectionStatus.disconnected);
    });

    test('addDevice registers a device', () {
      final hal = FakeHAL();
      hub.addDevice(HubDevice(id: 'COM3', name: 'Test', hal: hal));

      expect(hub.devices.length, 1);
      expect(hub.devices.first.id, 'COM3');
    });

    test('addDevice ignores duplicate id', () {
      final hal1 = FakeHAL();
      final hal2 = FakeHAL();
      hub.addDevice(HubDevice(id: 'COM3', name: 'Dev1', hal: hal1));
      hub.addDevice(HubDevice(id: 'COM3', name: 'Dev2', hal: hal2));

      expect(hub.devices.length, 1);
    });

    test('connect() calls connect on all devices', () async {
      final hal1 = FakeHAL();
      final hal2 = FakeHAL();
      hub.addDevice(HubDevice(id: 'COM3', name: 'Dev1', hal: hal1));
      hub.addDevice(HubDevice(id: 'COM4', name: 'Dev2', hal: hal2));

      final result = await hub.connect();

      expect(result, isTrue);
      expect(hal1.connectCalled, isTrue);
      expect(hal2.connectCalled, isTrue);
    });

    test('connect() returns true if at least one device connects', () async {
      final hal1 = FakeHAL();
      final hal2 = FakeHAL()..shouldFailConnect = true;
      hub.addDevice(HubDevice(id: 'COM3', name: 'Dev1', hal: hal1));
      hub.addDevice(HubDevice(id: 'COM4', name: 'Dev2', hal: hal2));

      final result = await hub.connect();

      expect(result, isTrue);
    });

    test('connect() returns false if all devices fail', () async {
      final hal1 = FakeHAL()..shouldFailConnect = true;
      final hal2 = FakeHAL()..shouldFailConnect = true;
      hub.addDevice(HubDevice(id: 'COM3', name: 'Dev1', hal: hal1));
      hub.addDevice(HubDevice(id: 'COM4', name: 'Dev2', hal: hal2));

      final result = await hub.connect();

      expect(result, isFalse);
    });

    test('disconnect() calls disconnect on all devices', () async {
      final hal1 = FakeHAL();
      final hal2 = FakeHAL();
      hub.addDevice(HubDevice(id: 'COM3', name: 'Dev1', hal: hal1));
      hub.addDevice(HubDevice(id: 'COM4', name: 'Dev2', hal: hal2));

      await hub.disconnect();

      expect(hal1.disconnectCalled, isTrue);
      expect(hal2.disconnectCalled, isTrue);
    });

    test('merges sensor data from multiple devices', () async {
      final hal1 = FakeHAL();
      final hal2 = FakeHAL();
      hub.addDevice(HubDevice(id: 'COM3', name: 'Arduino', hal: hal1));
      hub.addDevice(HubDevice(id: 'COM4', name: 'FTDI', hal: hal2));

      final packets = <SensorPacket>[];
      hub.sensorData.listen(packets.add);

      // Yield to let stream subscriptions set up
      await Future.delayed(Duration.zero);

      // Device 1 sends voltage
      hal1.emitPacket(const SensorPacket(
        timestampMs: 100,
        voltageV: 5.0,
        temperatureC: 25.0,
      ));

      // Device 2 sends distance
      hal2.emitPacket(const SensorPacket(
        timestampMs: 100,
        distanceMm: 1500.0,
      ));

      await Future.delayed(const Duration(milliseconds: 50));

      expect(packets.length, 2);
      expect(packets[0].voltageV, 5.0);
      expect(packets[0].temperatureC, 25.0);
      expect(packets[1].distanceMm, 1500.0);
    });

    test('startMeasurement/stopMeasurement calls all devices', () async {
      final hal1 = FakeHAL();
      final hal2 = FakeHAL();
      hub.addDevice(HubDevice(id: 'COM3', name: 'Dev1', hal: hal1));
      hub.addDevice(HubDevice(id: 'COM4', name: 'Dev2', hal: hal2));

      await hub.connect();
      await hub.startMeasurement();

      expect(hal1.startCalled, isTrue);
      expect(hal2.startCalled, isTrue);

      await hub.stopMeasurement();

      expect(hal1.stopCalled, isTrue);
      expect(hal2.stopCalled, isTrue);
    });

    test('deviceInfo merges sensors from all devices', () async {
      final hal1 = FakeHAL();
      final hal2 = FakeHAL();
      hub.addDevice(HubDevice(id: 'COM3', name: 'Dev1', hal: hal1));
      hub.addDevice(HubDevice(id: 'COM4', name: 'Dev2', hal: hal2));

      await hub.connect();
      // Wait for status to propagate
      await Future.delayed(const Duration(milliseconds: 50));

      final info = hub.deviceInfo;
      expect(info, isNotNull);
      expect(info!.name, contains('2 устройства'));
    });

    test('removeDevice disposes and removes device', () async {
      final hal = FakeHAL();
      hub.addDevice(HubDevice(id: 'COM3', name: 'Dev1', hal: hal));

      expect(hub.devices.length, 1);

      await hub.removeDevice('COM3');

      expect(hub.devices.length, 0);
      expect(hal.disconnectCalled, isTrue);
      expect(hal.disposeCalled, isTrue);
    });

    test('dispose cleans up all devices', () async {
      final hal1 = FakeHAL();
      final hal2 = FakeHAL();
      hub.addDevice(HubDevice(id: 'COM3', name: 'Dev1', hal: hal1));
      hub.addDevice(HubDevice(id: 'COM4', name: 'Dev2', hal: hal2));

      await hub.dispose();

      expect(hal1.disposeCalled, isTrue);
      expect(hal2.disposeCalled, isTrue);
    });
  });
}
