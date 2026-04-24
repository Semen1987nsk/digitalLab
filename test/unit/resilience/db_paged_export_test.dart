import 'package:drift/native.dart';
import 'package:digital_lab/data/datasources/local/app_database.dart';
import 'package:digital_lab/data/datasources/local/experiment_autosave_service.dart';
import 'package:digital_lab/domain/entities/sensor_data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;

// ═══════════════════════════════════════════════════════════════
//  Resilience tests: Memory-safe DB export for long experiments
//
//  Гипотеза H1 Principal Engineer аудита:
//  "45-минутный эксперимент при 100Hz = 270K строк. Нельзя загрузить
//   всё в RAM на школьном Celeron с 4GB. Нужна постраничная выгрузка."
//
//  Тестируем:
//  1. measurementsPaged() возвращает правильные страницы
//  2. Полная выгрузка через пагинацию = все данные
//  3. Autosave + paged export: end-to-end flow
// ═══════════════════════════════════════════════════════════════

void main() {
  group('AppDatabase.measurementsPaged', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('returns empty for non-existent experiment', () async {
      final page = await db.measurementsPaged(999, pageSize: 100, offset: 0);
      expect(page, isEmpty);
    });

    test('paginates measurements correctly', () async {
      // Создаём эксперимент
      final expId = await db.createExperiment(
        startTime: DateTime.utc(2026, 3, 7, 10, 0),
        sampleRateHz: 10,
        title: 'Тест пагинации',
      );

      // Вставляем 25 измерений
      final rows = <MeasurementsCompanion>[];
      for (int i = 0; i < 25; i++) {
        rows.add(MeasurementsCompanion.insert(
          experimentId: expId,
          timestampMs: i * 100,
          voltageV: Value(5.0 + i * 0.1),
        ));
      }
      await db.insertMeasurements(expId, rows);

      // Страница 1: элементы 0-9
      final page1 = await db.measurementsPaged(expId, pageSize: 10, offset: 0);
      expect(page1, hasLength(10));
      expect(page1.first.timestampMs, 0);
      expect(page1.last.timestampMs, 900);

      // Страница 2: элементы 10-19
      final page2 = await db.measurementsPaged(expId, pageSize: 10, offset: 10);
      expect(page2, hasLength(10));
      expect(page2.first.timestampMs, 1000);
      expect(page2.last.timestampMs, 1900);

      // Страница 3: элементы 20-24 (неполная)
      final page3 = await db.measurementsPaged(expId, pageSize: 10, offset: 20);
      expect(page3, hasLength(5));
      expect(page3.first.timestampMs, 2000);
      expect(page3.last.timestampMs, 2400);

      // Страница 4: пустая (offset за пределами)
      final page4 = await db.measurementsPaged(expId, pageSize: 10, offset: 30);
      expect(page4, isEmpty);
    });

    test('paginated read == full read', () async {
      final expId = await db.createExperiment(
        startTime: DateTime.utc(2026, 3, 7, 10, 0),
        sampleRateHz: 100,
      );

      final rows = <MeasurementsCompanion>[];
      for (int i = 0; i < 50; i++) {
        rows.add(MeasurementsCompanion.insert(
          experimentId: expId,
          timestampMs: i * 10,
          temperatureC: Value(20.0 + i * 0.01),
        ));
      }
      await db.insertMeasurements(expId, rows);

      // Full read
      final allRows = await db.measurementsFor(expId);
      expect(allRows, hasLength(50));

      // Paginated read
      final paginatedAll = <MeasurementEntry>[];
      int offset = 0;
      while (true) {
        final page = await db.measurementsPaged(expId, pageSize: 15, offset: offset);
        if (page.isEmpty) break;
        paginatedAll.addAll(page);
        offset += page.length;
      }

      // Same data
      expect(paginatedAll.length, allRows.length);
      for (int i = 0; i < allRows.length; i++) {
        expect(paginatedAll[i].timestampMs, allRows[i].timestampMs);
        expect(paginatedAll[i].temperatureC, allRows[i].temperatureC);
      }
    });

    test('measurementCountFor returns correct count', () async {
      final expId = await db.createExperiment(
        startTime: DateTime.utc(2026, 3, 7),
        sampleRateHz: 10,
      );

      // Insert 42 measurements
      await db.insertMeasurements(
        expId,
        List.generate(
          42,
          (i) => MeasurementsCompanion.insert(
            experimentId: expId,
            timestampMs: i * 100,
          ),
        ),
      );

      expect(await db.measurementCountFor(expId), 42);
    });
  });

  group('Autosave + paginated export end-to-end', () {
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

    test('autosaved packets are retrievable via measurementsPaged', () async {
      await service.beginSession(
        startTime: DateTime.utc(2026, 3, 7, 10, 0),
        sampleRateHz: 50,
      );

      // Add 100 packets
      for (int i = 0; i < 100; i++) {
        service.addPacket(SensorPacket(
          timestampMs: i * 20,
          voltageV: 5.0 + i * 0.01,
          currentA: 0.5,
        ));
      }

      // Force flush
      final flushed = await service.flush();
      expect(flushed, isTrue);

      final expId = service.experimentId;
      expect(expId, isNotNull);

      // Verify count
      expect(await db.measurementCountFor(expId!), 100);

      // Paginated read
      final page1 = await db.measurementsPaged(expId, pageSize: 30, offset: 0);
      expect(page1, hasLength(30));
      expect(page1.first.voltageV, closeTo(5.0, 0.001));
      expect(page1.last.voltageV, closeTo(5.29, 0.001));

      final page2 = await db.measurementsPaged(expId, pageSize: 30, offset: 30);
      expect(page2, hasLength(30));

      final page3 = await db.measurementsPaged(expId, pageSize: 30, offset: 60);
      expect(page3, hasLength(30));

      final page4 = await db.measurementsPaged(expId, pageSize: 30, offset: 90);
      expect(page4, hasLength(10));

      final page5 = await db.measurementsPaged(expId, pageSize: 30, offset: 120);
      expect(page5, isEmpty);
    });
  });
}
