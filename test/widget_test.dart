import 'dart:async';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:digital_lab/data/datasources/local/app_database.dart';
import 'package:digital_lab/data/datasources/local/experiment_autosave_service.dart';
import 'package:digital_lab/domain/entities/sensor_data.dart';
import 'package:digital_lab/domain/repositories/hal_interface.dart';
import 'package:digital_lab/core/di/providers.dart';
import 'package:digital_lab/presentation/blocs/experiment/experiment_provider.dart';
import 'package:digital_lab/presentation/pages/shell/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeHal implements HALInterface {
  final _statusController = StreamController<ConnectionStatus>.broadcast();
  final _dataController = StreamController<SensorPacket>.broadcast();

  @override
  Stream<ConnectionStatus> get connectionStatus => _statusController.stream;

  @override
  Stream<SensorPacket> get sensorData => _dataController.stream;

  @override
  DeviceInfo? get deviceInfo => null;

  @override
  bool get isCalibrated => false;

  @override
  Future<void> calibrate(String sensorId) async {}

  @override
  Future<bool> connect() async => true;

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> dispose() async {
    await _statusController.close();
    await _dataController.close();
  }

  @override
  Future<void> setSampleRate(int hz) async {}

  @override
  Future<void> startMeasurement() async {}

  @override
  Future<void> stopMeasurement() async {}
}

class _TrackingExperimentController extends ExperimentController {
  int restoreCalls = 0;
  RecoveredExperimentSession? lastSession;

  _TrackingExperimentController(super.hal);

  @override
  void restoreRecoveredSession(RecoveredExperimentSession session) {
    restoreCalls++;
    lastSession = session;
    super.restoreRecoveredSession(session);
  }
}

Future<RecoveredExperimentSession> _createInterruptedSession(
  AppDatabase db,
  ExperimentAutosaveService service,
) async {
  final experimentId = await db.createExperiment(
    startTime: DateTime.utc(2026, 3, 7, 12, 0, 0),
    sampleRateHz: 25,
    title: 'Widget recovery',
  );

  await db.insertMeasurements(experimentId, [
    MeasurementsCompanion.insert(
      experimentId: experimentId,
      timestampMs: 100,
      voltageV: const Value(5.0),
      currentA: const Value(0.2),
    ),
    MeasurementsCompanion.insert(
      experimentId: experimentId,
      timestampMs: 200,
      voltageV: const Value(5.1),
      currentA: const Value(0.21),
    ),
  ]);
  await db.updateMeasurementCount(experimentId, 2);
  await db.markInterruptedExperiments();

  return (await service.loadLatestInterruptedSession())!;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('RecoveryPromptPresenter stays idle without pending session',
      (tester) async {
    final fakeHal = _FakeHal();
    final controller = _TrackingExperimentController(fakeHal);

    addTearDown(() async {
      await fakeHal.dispose();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          experimentControllerProvider.overrideWith((ref) => controller),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: RecoveryPromptPresenter(
              pendingRecovery: null,
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('Восстановить эксперимент?'), findsNothing);
  });

  testWidgets('RecoveryPromptPresenter restores session and resolves recovery',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final service = ExperimentAutosaveService(db);
    final session = await _createInterruptedSession(db, service);
    final fakeHal = _FakeHal();
    final controller = _TrackingExperimentController(fakeHal);
    var handled = 0;

    addTearDown(() async {
      await fakeHal.dispose();
      await service.dispose();
      await db.close();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          autosaveServiceProvider.overrideWith((ref) => service),
          experimentControllerProvider.overrideWith((ref) => controller),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: RecoveryPromptPresenter(
              pendingRecovery: session,
              onRecoveryHandled: () => handled++,
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('Восстановить эксперимент?'), findsOneWidget);
    expect(find.textContaining('Widget recovery'), findsOneWidget);

    await tester.tap(find.text('Восстановить'));
    await tester.pumpAndSettle();

    expect(controller.restoreCalls, 1);
    expect(controller.lastSession?.experimentId, session.experimentId);
    expect(handled, 1);
    expect(await service.loadLatestInterruptedSession(), isNull);
  });

  testWidgets('RecoveryPromptPresenter skips session and does not re-offer it',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final service = ExperimentAutosaveService(db);
    final session = await _createInterruptedSession(db, service);
    final fakeHal = _FakeHal();
    final controller = _TrackingExperimentController(fakeHal);
    var handled = 0;

    addTearDown(() async {
      await fakeHal.dispose();
      await service.dispose();
      await db.close();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          autosaveServiceProvider.overrideWith((ref) => service),
          experimentControllerProvider.overrideWith((ref) => controller),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: RecoveryPromptPresenter(
              pendingRecovery: session,
              onRecoveryHandled: () => handled++,
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('Восстановить эксперимент?'), findsOneWidget);

    await tester.tap(find.text('Пропустить'));
    await tester.pumpAndSettle();

    expect(controller.restoreCalls, 0);
    expect(handled, 1);
    expect(await service.loadLatestInterruptedSession(), isNull);
  });
}
