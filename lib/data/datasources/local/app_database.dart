import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

// ═══════════════════════════════════════════════════════════════
//  ТАБЛИЦА ЭКСПЕРИМЕНТОВ
// ═══════════════════════════════════════════════════════════════

/// Статус эксперимента в БД.
///
/// * running   — эксперимент активен, данные записываются
/// * completed — нормально остановлен пользователем
/// * interrupted — процесс крашнулся / пропало питание
///
/// При старте приложения ищем `running` → помечаем `interrupted`
/// и предлагаем восстановить данные.
class ExperimentStatusConverter extends TypeConverter<ExperimentStatus, int> {
  const ExperimentStatusConverter();

  @override
  ExperimentStatus fromSql(int fromDb) {
    if (fromDb < 0 || fromDb >= ExperimentStatus.values.length) {
      // Защита от RangeError при повреждённых данных или будущих миграциях.
      return ExperimentStatus.interrupted;
    }
    return ExperimentStatus.values[fromDb];
  }

  @override
  int toSql(ExperimentStatus value) => value.index;
}

enum ExperimentStatus { running, completed, interrupted }

@DataClassName('ExperimentEntry')
class Experiments extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// ISO-8601 wall-clock time (UTC) когда нажали "Старт"
  DateTimeColumn get startTime => dateTime()();

  /// null пока эксперимент идёт
  DateTimeColumn get endTime => dateTime().nullable()();

  /// Гц — частота дискретизации (1..1000)
  IntColumn get sampleRateHz => integer().withDefault(const Constant(10))();

  /// Статус: running / completed / interrupted
  IntColumn get status => integer()
      .map(const ExperimentStatusConverter())
      .withDefault(const Constant(0))();

  /// Необязательное название (например "Закон Ома — 8А класс")
  TextColumn get title => text().withDefault(const Constant(''))();

  /// Сколько точек уже сохранено (кэш — чтобы не делать COUNT каждый раз)
  IntColumn get measurementCount => integer().withDefault(const Constant(0))();
}

// ═══════════════════════════════════════════════════════════════
//  ТАБЛИЦА ИЗМЕРЕНИЙ (один ряд = один SensorPacket)
// ═══════════════════════════════════════════════════════════════

@DataClassName('MeasurementEntry')
class Measurements extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// FK → Experiments.id
  IntColumn get experimentId => integer().references(Experiments, #id)();

  /// Время от начала эксперимента, мс
  IntColumn get timestampMs => integer()();

  // ── Все поля из SensorPacket (nullable) ──────────────────────
  RealColumn get voltageV => real().nullable()();
  RealColumn get currentA => real().nullable()();
  RealColumn get pressurePa => real().nullable()();
  RealColumn get temperatureC => real().nullable()();
  RealColumn get accelX => real().nullable()();
  RealColumn get accelY => real().nullable()();
  RealColumn get accelZ => real().nullable()();
  RealColumn get magneticFieldMt => real().nullable()();
  RealColumn get humidityPct => real().nullable()();
  RealColumn get distanceMm => real().nullable()();
  RealColumn get forceN => real().nullable()();
  RealColumn get luxLx => real().nullable()();
  RealColumn get radiationCpm => real().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
        // Один timestamp на эксперимент — защита от дублей при повторной вставке
        {experimentId, timestampMs},
      ];
}

// ═══════════════════════════════════════════════════════════════
//  БАЗА ДАННЫХ
// ═══════════════════════════════════════════════════════════════

@DriftDatabase(tables: [Experiments, Measurements])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Для unit-тестов — in-memory БД
  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          // Заготовка для будущих миграций.
          // Пример (schemaVersion 2):
          // if (from < 2) {
          //   await m.addColumn(experiments, experiments.newColumn);
          // }
        },
      );

  // ─────────────────────────────────────────────────────────────
  //  EXPERIMENTS CRUD
  // ─────────────────────────────────────────────────────────────

  /// Создаёт новый эксперимент со статусом `running`.
  /// Возвращает id.
  Future<int> createExperiment({
    required DateTime startTime,
    required int sampleRateHz,
    String title = '',
  }) {
    return into(experiments).insert(ExperimentsCompanion.insert(
      startTime: startTime,
      sampleRateHz: Value(sampleRateHz),
      status: const Value(ExperimentStatus.running),
      title: Value(title),
    ));
  }

  /// Помечает эксперимент как завершённый (completed).
  Future<void> completeExperiment(int id, {required DateTime endTime}) {
    return (update(experiments)..where((t) => t.id.equals(id))).write(
      ExperimentsCompanion(
        endTime: Value(endTime),
        status: const Value(ExperimentStatus.completed),
      ),
    );
  }

  /// Помечает все `running` эксперименты как `interrupted`.
  /// Вызывается один раз при старте приложения.
  Future<int> markInterruptedExperiments() {
    return (update(experiments)
          ..where((t) => t.status.equals(ExperimentStatus.running.index)))
        .write(const ExperimentsCompanion(
      status: Value(ExperimentStatus.interrupted),
    ));
  }

  /// Последний прерванный эксперимент (если есть).
  Future<ExperimentEntry?> latestInterruptedExperiment() {
    return (select(experiments)
          ..where(
            (t) => t.status.equals(ExperimentStatus.interrupted.index),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.startTime)])
          ..limit(1))
        .getSingleOrNull();
  }

  /// Завершает ранее прерванный эксперимент после обработки recovery flow.
  ///
  /// Используется после решения пользователя:
  /// - «Восстановить»
  /// - «Пропустить»
  ///
  /// Это гарантирует, что один и тот же interrupted-эксперимент
  /// не будет предлагаться повторно при следующем запуске приложения.
  Future<void> resolveInterruptedExperiment(
    int id, {
    required DateTime endTime,
  }) {
    return (update(experiments)
          ..where((t) =>
              t.id.equals(id) &
              t.status.equals(ExperimentStatus.interrupted.index)))
        .write(
      ExperimentsCompanion(
        endTime: Value(endTime),
        status: const Value(ExperimentStatus.completed),
      ),
    );
  }

  /// Все эксперименты, отсортированные по дате (новые первыми).
  Future<List<ExperimentEntry>> allExperiments() {
    return (select(experiments)
          ..orderBy([(t) => OrderingTerm.desc(t.startTime)]))
        .get();
  }

  /// Удалить эксперимент и все его измерения.
  Future<void> deleteExperiment(int id) async {
    await (delete(measurements)..where((m) => m.experimentId.equals(id))).go();
    await (delete(experiments)..where((e) => e.id.equals(id))).go();
  }

  /// Обновляет кэшированное число измерений.
  Future<void> updateMeasurementCount(int experimentId, int count) {
    return (update(experiments)..where((t) => t.id.equals(experimentId)))
        .write(ExperimentsCompanion(measurementCount: Value(count)));
  }

  // ─────────────────────────────────────────────────────────────
  //  MEASUREMENTS CRUD
  // ─────────────────────────────────────────────────────────────

  /// Batch-вставка списка измерений (автосохранение каждые N секунд).
  ///
  /// Использует `insertAll` с `InsertMode.insertOrIgnore` чтобы
  /// дубли по (experimentId, timestampMs) молча пропускались.
  Future<void> insertMeasurements(
    int experimentId,
    List<MeasurementsCompanion> rows,
  ) async {
    if (rows.isEmpty) return;
    await batch((b) {
      b.insertAll(measurements, rows, mode: InsertMode.insertOrIgnore);
    });
  }

  /// Все измерения эксперимента, упорядоченные по времени.
  Future<List<MeasurementEntry>> measurementsFor(int experimentId) {
    return (select(measurements)
          ..where((m) => m.experimentId.equals(experimentId))
          ..orderBy([(m) => OrderingTerm.asc(m.timestampMs)]))
        .get();
  }

  /// Число измерений в эксперименте (быстрый COUNT).
  Future<int> measurementCountFor(int experimentId) async {
    final countExpr = measurements.id.count();
    final query = selectOnly(measurements)
      ..addColumns([countExpr])
      ..where(measurements.experimentId.equals(experimentId));
    final row = await query.getSingle();
    return row.read(countExpr) ?? 0;
  }

  // ─────────────────────────────────────────────────────────────
  //  STREAMING EXPORT (H1: memory-safe export for long experiments)
  // ─────────────────────────────────────────────────────────────

  /// Paginated measurements loader.
  ///
  /// Загружает измерения эксперимента страницами по [pageSize] строк.
  /// Это позволяет экспортировать 45-минутный эксперимент (270K строк)
  /// без загрузки всего в RAM — пишем в CSV-файл постранично.
  ///
  /// Использование:
  /// ```dart
  /// int offset = 0;
  /// while (true) {
  ///   final page = await db.measurementsPaged(id, pageSize: 5000, offset: offset);
  ///   if (page.isEmpty) break;
  ///   // write to CSV...
  ///   offset += page.length;
  /// }
  /// ```
  Future<List<MeasurementEntry>> measurementsPaged(
    int experimentId, {
    int pageSize = 5000,
    int offset = 0,
  }) {
    return (select(measurements)
          ..where((m) => m.experimentId.equals(experimentId))
          ..orderBy([(m) => OrderingTerm.asc(m.timestampMs)])
          ..limit(pageSize, offset: offset))
        .get();
  }
}

// ─────────────────────────────────────────────────────────────
//  Connection factory
// ─────────────────────────────────────────────────────────────

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    // Основной путь: AppData (стандартное расположение)
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File(p.join(dir.path, 'digital_lab.sqlite'));
      return NativeDatabase.createInBackground(file, logStatements: false);
    } catch (_) {
      // Fallback: если AppData недоступен (заблокированный школьный ПК,
      // повреждённый профиль, ограничения GPO) — временная директория.
      try {
        final fallbackFile = File(
          p.join(Directory.systemTemp.path, 'digital_lab.sqlite'),
        );
        return NativeDatabase.createInBackground(
          fallbackFile,
          logStatements: false,
        );
      } catch (_) {
        // Последний рубеж: in-memory БД.
        // Данные НЕ сохранятся между сессиями, но приложение не упадёт.
        return NativeDatabase.memory(logStatements: false);
      }
    }
  });
}
