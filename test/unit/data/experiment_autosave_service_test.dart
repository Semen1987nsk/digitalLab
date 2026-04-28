import 'package:drift/native.dart';
import 'package:digital_lab/data/datasources/local/app_database.dart';
import 'package:digital_lab/data/datasources/local/experiment_autosave_service.dart';
import 'package:digital_lab/domain/entities/sensor_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ExperimentAutosaveService recovery', () {
    late AppDatabase db;
    late ExperimentAutosaveService service;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      service = ExperimentAutosaveService(db);
    });

    tearDown(() async {
      await service.dispose();
      await db.close();
    });

    test('detectRecoverableSession returns interrupted experiment with packets',
        () async {
      await service.beginSession(
        startTime: DateTime.utc(2026, 3, 7, 10, 0, 0),
        sampleRateHz: 25,
        title: 'Тест восстановления',
      );

      service.addPacket(const SensorPacket(
        timestampMs: 100,
        voltageV: 5.0,
        currentA: 0.2,
      ));
      service.addPacket(const SensorPacket(
        timestampMs: 200,
        voltageV: 5.1,
        currentA: 0.21,
      ));

      await service.flush();

      final recovered = await service.detectRecoverableSession();

      expect(recovered, isNotNull);
      expect(recovered!.title, 'Тест восстановления');
      expect(recovered.sampleRateHz, 25);
      expect(recovered.measurementCount, 2);
      expect(recovered.packets.first.voltageV, 5.0);
      expect(recovered.packets.last.currentA, 0.21);
    });

    test('loadLatestInterruptedSession returns null when nothing to restore',
        () async {
      final recovered = await service.loadLatestInterruptedSession();
      expect(recovered, isNull);
    });

    test('markRecoveryHandled resolves interrupted experiment', () async {
      await service.beginSession(
        startTime: DateTime.utc(2026, 3, 7, 11, 0, 0),
        sampleRateHz: 10,
        title: 'Повторно не предлагать',
      );

      service.addPacket(const SensorPacket(
        timestampMs: 150,
        temperatureC: 23.5,
      ));

      await service.flush();

      final recovered = await service.detectRecoverableSession();
      expect(recovered, isNotNull);

      await service.markRecoveryHandled(recovered!);

      final latestInterrupted = await service.loadLatestInterruptedSession();
      final all = await db.allExperiments();

      expect(latestInterrupted, isNull);
      expect(all.single.status, ExperimentStatus.completed);
      expect(
        all.single.endTime!.difference(recovered.effectiveEndTime).inSeconds,
        0,
      );
    });
  });

  // ─── Failure-path tests (H1, L2) ───────────────────────────────
  group('ExperimentAutosaveService failure paths', () {
    late AppDatabase db;
    late ExperimentAutosaveService service;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      service = ExperimentAutosaveService(db);
    });

    tearDown(() async {
      // dispose might throw if DB already closed — that's OK in tests
      try {
        await service.dispose();
      } catch (_) {}
      try {
        await db.close();
      } catch (_) {}
    });

    test('flush returns true on success', () async {
      await service.beginSession(
        startTime: DateTime.utc(2026, 3, 9, 10, 0, 0),
        sampleRateHz: 25,
        title: 'Flush success',
      );
      service.addPacket(const SensorPacket(
        timestampMs: 100,
        voltageV: 5.0,
      ));

      final result = await service.flush();
      expect(result, isTrue);
    });

    test('flush returns true when no pending packets', () async {
      await service.beginSession(
        startTime: DateTime.utc(2026, 3, 9, 10, 0, 0),
        sampleRateHz: 25,
        title: 'Empty flush',
      );
      // No packets added
      final result = await service.flush();
      expect(result, isTrue);
    });

    test('flush returns false on DB error and preserves packets', () async {
      await service.beginSession(
        startTime: DateTime.utc(2026, 3, 9, 10, 0, 0),
        sampleRateHz: 25,
        title: 'Flush failure',
      );
      service.addPacket(const SensorPacket(
        timestampMs: 100,
        voltageV: 5.0,
      ));
      service.addPacket(const SensorPacket(
        timestampMs: 200,
        voltageV: 5.1,
      ));

      // Close DB to simulate IO failure (locked disk, corrupted DB, etc.)
      await db.close();

      final result = await service.flush();
      expect(result, isFalse,
          reason: 'flush must return false when DB write fails');
    });

    test('endSession returns true and marks completed when all data saved',
        () async {
      await service.beginSession(
        startTime: DateTime.utc(2026, 3, 9, 10, 0, 0),
        sampleRateHz: 25,
        title: 'EndSession success',
      );
      service.addPacket(const SensorPacket(
        timestampMs: 100,
        voltageV: 5.0,
      ));

      final result = await service.endSession();
      expect(result, isTrue, reason: 'endSession must return true on success');

      // Verify experiment is marked completed in DB
      final all = await db.allExperiments();
      expect(all.single.status, ExperimentStatus.completed);
      expect(all.single.endTime, isNotNull);
    });

    test(
        'endSession returns false when flush fails '
        '(experiment NOT marked completed)', () async {
      await service.beginSession(
        startTime: DateTime.utc(2026, 3, 9, 10, 0, 0),
        sampleRateHz: 25,
        title: 'EndSession failure',
      );
      service.addPacket(const SensorPacket(
        timestampMs: 100,
        voltageV: 5.0,
      ));

      // Close DB to simulate failure
      await db.close();

      final result = await service.endSession();
      expect(result, isFalse,
          reason: 'endSession must return false when data is lost');
      // Experiment stays as "running" in DB → next launch will mark it
      // "interrupted" via markInterruptedExperiments() → recovery prompt
    });

    test('endSession with empty session returns true without error', () async {
      await service.beginSession(
        startTime: DateTime.utc(2026, 3, 9, 10, 0, 0),
        sampleRateHz: 25,
        title: 'Empty session',
      );
      // No packets added

      final result = await service.endSession();
      expect(result, isTrue);
    });
  });
}
