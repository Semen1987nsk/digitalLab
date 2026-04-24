import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../../../domain/entities/sensor_data.dart';
import 'app_database.dart';

class RecoveredExperimentSession {
  final int experimentId;
  final String title;
  final DateTime startTime;
  final DateTime? endTime;
  final int sampleRateHz;
  final List<SensorPacket> packets;

  const RecoveredExperimentSession({
    required this.experimentId,
    required this.title,
    required this.startTime,
    required this.endTime,
    required this.sampleRateHz,
    required this.packets,
  });

  int get measurementCount => packets.length;

  DateTime get effectiveEndTime {
    if (endTime != null) return endTime!;
    if (packets.isEmpty) return startTime;
    return startTime.add(Duration(milliseconds: packets.last.timestampMs));
  }
}

// ═══════════════════════════════════════════════════════════════
//  АВТОСОХРАНЕНИЕ ЭКСПЕРИМЕНТА В SQLite
// ═══════════════════════════════════════════════════════════════
//
//  Жизненный цикл:
//  1. beginSession()  → INSERT experiment (status=running)
//  2. addPackets()    → копят в RAM-очередь
//  3. Timer 30s       → batch INSERT measurements + кэш count
//  4. endSession()    → финальный flush + UPDATE status=completed
//
//  Если приложение крашнулось:
//  → При следующем запуске markInterruptedExperiments()
//  → UI предлагает «Восстановить последний эксперимент?»
//
//  Потокобезопасность:
//  - addPackets() и _flush() вызываются из UI-изолята.
//  - Drift NativeDatabase.createInBackground() работает в
//    собственном изоляте → INSERT не блокирует UI.
// ═══════════════════════════════════════════════════════════════

class ExperimentAutosaveService {
  final AppDatabase _db;

  /// Текущий experiment ID (null = нет активной сессии)
  int? _experimentId;

  /// Буфер «ожидающих записи» пакетов.
  /// Наполняется через addPackets(), сбрасывается в _flush().
  final List<SensorPacket> _pendingPackets = [];

  /// Число уже записанных в БД измерений (для кэша в experiments.measurementCount).
  int _flushedCount = 0;

  /// Периодический таймер автосохранения.
  Timer? _autosaveTimer;

  /// Интервал автосохранения (по умолчанию 30 секунд).
  static const Duration autosaveInterval = Duration(seconds: 30);

  /// Максимальное число пакетов в RAM-очереди.
  /// Защита от OOM, если flush() постоянно падает (нет диска, БД залочена).
  /// 100 Гц × 60 с × 2 буфера = ~12 000 пакетов ≈ 1.5 МБ.
  static const int _maxPendingPackets = 12000;

  ExperimentAutosaveService(this._db);

  /// Активна ли сессия?
  bool get isActive => _experimentId != null;

  /// ID текущего эксперимента.
  int? get experimentId => _experimentId;

  // ─────────────────────────────────────────────────────────────
  //  PUBLIC API
  // ─────────────────────────────────────────────────────────────

  /// Начинает новую сессию автосохранения.
  ///
  /// Создаёт запись в таблице experiments, запускает таймер.
  Future<int> beginSession({
    required DateTime startTime,
    required int sampleRateHz,
    String title = '',
  }) async {
    // Если предыдущая сессия не закрыта — завершаем
    if (_experimentId != null) {
      debugPrint('Autosave: принудительное завершение предыдущей сессии #$_experimentId');
      await endSession();
    }

    final id = await _db.createExperiment(
      startTime: startTime,
      sampleRateHz: sampleRateHz,
      title: title,
    );

    _experimentId = id;
    _pendingPackets.clear();
    _flushedCount = 0;

    // Запуск периодического автосохранения
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer.periodic(autosaveInterval, (_) => flush());

    debugPrint('Autosave: сессия #$id начата (rate=${sampleRateHz}Hz, '
        'interval=${autosaveInterval.inSeconds}s)');

    return id;
  }

  /// Добавляет пакеты в очередь на запись.
  ///
  /// Вызывается из ExperimentController при каждом новом пакете данных.
  /// Фактическая запись в БД — при flush() (по таймеру или при stop).
  void addPacket(SensorPacket packet) {
    if (_experimentId == null) return;
    _pendingPackets.add(packet);
    // Защита от OOM: если flush постоянно падает, не даём
    // очереди расти бесконечно — дропаем старейшие 10%.
    if (_pendingPackets.length > _maxPendingPackets) {
      const dropCount = _maxPendingPackets ~/ 10;
      _pendingPackets.removeRange(0, dropCount);
      debugPrint('Autosave: ВНИМАНИЕ — очередь переполнена, '
          'отброшено $dropCount старых пакетов');
    }
  }

  /// Немедленно записывает все ожидающие пакеты в БД.
  ///
  /// Возвращает `true` если запись успешна, `false` при ошибке.
  /// При ошибке пакеты возвращаются обратно в очередь.
  ///
  /// Вызывается:
  /// 1. Периодически (каждые 30 секунд по таймеру)
  /// 2. При остановке эксперимента (endSession)
  /// 3. Можно вызвать вручную из UI (кнопка «Сохранить»)
  Future<bool> flush() async {
    final expId = _experimentId;
    if (expId == null || _pendingPackets.isEmpty) return true;

    // Забираем всё из очереди и очищаем до await-а,
    // чтобы новые пакеты не потерялись.
    final toFlush = List<SensorPacket>.of(_pendingPackets);
    _pendingPackets.clear();

    final rows = toFlush.map((p) => MeasurementsCompanion.insert(
          experimentId: expId,
          timestampMs: p.timestampMs,
          voltageV: Value(p.voltageV),
          currentA: Value(p.currentA),
          pressurePa: Value(p.pressurePa),
          temperatureC: Value(p.temperatureC),
          accelX: Value(p.accelX),
          accelY: Value(p.accelY),
          accelZ: Value(p.accelZ),
          magneticFieldMt: Value(p.magneticFieldMt),
          humidityPct: Value(p.humidityPct),
          distanceMm: Value(p.distanceMm),
          forceN: Value(p.forceN),
          luxLx: Value(p.luxLx),
          radiationCpm: Value(p.radiationCpm),
        )).toList();

    try {
      await _db.insertMeasurements(expId, rows);
      _flushedCount += toFlush.length;
      await _db.updateMeasurementCount(expId, _flushedCount);
      debugPrint('Autosave: записано ${toFlush.length} точек '
          '(всего $_flushedCount) для эксперимента #$expId');
      return true;
    } catch (e) {
      // При ошибке возвращаем пакеты обратно в очередь
      _pendingPackets.insertAll(0, toFlush);
      debugPrint('Autosave: ОШИБКА записи: $e');
      return false;
    }
  }

  /// Завершает сессию: flush + обновление статуса.
  ///
  /// Если финальный flush не удался:
  /// - эксперимент НЕ помечается `completed`
  /// - остаётся `running` → при следующем запуске станет `interrupted`
  /// - recovery prompt предложит восстановить данные из БД
  ///
  /// Возвращает `true` если все данные сохранены, `false` если были потери.
  Future<bool> endSession() async {
    _autosaveTimer?.cancel();
    _autosaveTimer = null;

    final expId = _experimentId;
    if (expId == null) return true;

    // Финальный flush (попытка 1)
    var flushOk = await flush();

    // Если flush не удался — повторная попытка (защита от потери данных).
    // Типичные причины: БД залочена другим процессом, диск не готов.
    if (!flushOk && _pendingPackets.isNotEmpty) {
      debugPrint('Autosave: повторная попытка flush '
          '(${_pendingPackets.length} пакетов не записано)...');
      await Future.delayed(const Duration(milliseconds: 500));
      flushOk = await flush();
    }

    // Третья попытка с увеличенной паузой
    if (!flushOk && _pendingPackets.isNotEmpty) {
      debugPrint('Autosave: 3-я попытка flush '
          '(${_pendingPackets.length} пакетов)...');
      await Future.delayed(const Duration(seconds: 1));
      flushOk = await flush();
    }

    final dataLost = _pendingPackets.isNotEmpty;

    if (dataLost) {
      // ── CRITICAL: НЕ помечаем completed ──
      // Эксперимент остаётся running → при следующем запуске
      // markInterruptedExperiments() пометит его interrupted,
      // и recovery prompt предложит восстановить данные.
      debugPrint('⚠️ Autosave: ${_pendingPackets.length} пакетов НЕ сохранено! '
          'Эксперимент #$expId оставлен как running для recovery.');
    } else {
      // Все данные сохранены — безопасно завершить
      try {
        await _db.completeExperiment(expId, endTime: DateTime.now());
      } catch (e) {
        debugPrint('Autosave: ошибка завершения эксперимента #$expId: $e');
      }
    }

    debugPrint('Autosave: сессия #$expId завершена '
        '(всего $_flushedCount измерений${dataLost ? ', ЕСТЬ ПОТЕРИ' : ''})');  

    _experimentId = null;
    _pendingPackets.clear();
    _flushedCount = 0;
    return !dataLost;
  }

  /// Подготавливает сценарий восстановления при старте приложения.
  ///
  /// 1. Помечает все зависшие `running` эксперименты как `interrupted`
  /// 2. Загружает последний прерванный эксперимент целиком
  /// 3. Возвращает null, если восстанавливать нечего
  Future<RecoveredExperimentSession?> detectRecoverableSession() async {
    final interrupted = await _db.markInterruptedExperiments();
    if (interrupted > 0) {
      debugPrint('Autosave: обнаружено $interrupted прерванных экспериментов');
    }
    return loadLatestInterruptedSession();
  }

  /// Загружает последний прерванный эксперимент без повторной смены статуса.
  ///
  /// P0 FIX: вместо единого `measurementsFor()` (который грузит ВСЕ строки
  /// в RAM) используем `measurementsPaged()` — постраничная подгрузка по 5 000
  /// строк. Пиковое потребление Drift/SQLite: ~5K строк, а не 270K.
  Future<RecoveredExperimentSession?> loadLatestInterruptedSession() async {
    final lastInterrupted = await _db.latestInterruptedExperiment();
    if (lastInterrupted == null) return null;

    final totalCount =
        await _db.measurementCountFor(lastInterrupted.id);
    if (totalCount == 0) return null;

    const pageSize = 5000;
    final packets = <SensorPacket>[];
    var offset = 0;

    while (offset < totalCount) {
      final rows = await _db.measurementsPaged(
        lastInterrupted.id,
        pageSize: pageSize,
        offset: offset,
      );
      if (rows.isEmpty) break; // safety: no more data

      for (final m in rows) {
        packets.add(SensorPacket(
          timestampMs: m.timestampMs,
          voltageV: m.voltageV,
          currentA: m.currentA,
          pressurePa: m.pressurePa,
          temperatureC: m.temperatureC,
          accelX: m.accelX,
          accelY: m.accelY,
          accelZ: m.accelZ,
          magneticFieldMt: m.magneticFieldMt,
          humidityPct: m.humidityPct,
          distanceMm: m.distanceMm,
          forceN: m.forceN,
          luxLx: m.luxLx,
          radiationCpm: m.radiationCpm,
        ));
      }
      offset += rows.length;
    }

    debugPrint('Autosave: восстановлено ${packets.length} точек '
        '(${(totalCount / pageSize).ceil()} страниц) '
        'из эксперимента #${lastInterrupted.id}');

    return RecoveredExperimentSession(
      experimentId: lastInterrupted.id,
      title: lastInterrupted.title,
      startTime: lastInterrupted.startTime,
      endTime: lastInterrupted.endTime,
      sampleRateHz: lastInterrupted.sampleRateHz,
      packets: packets,
    );
  }

  /// Помечает interrupted-сессию как обработанную пользователем.
  ///
  /// Вызывается и при восстановлении, и при пропуске recovery prompt.
  /// После этого сессия больше не должна предлагаться повторно.
  Future<void> markRecoveryHandled(RecoveredExperimentSession session) async {
    await _db.resolveInterruptedExperiment(
      session.experimentId,
      endTime: session.effectiveEndTime,
    );
  }

  /// Dispose — завершает сессию (если активна) и отменяет таймер.
  ///
  /// Вызывается при уничтожении провайдера. Без endSession() данные
  /// в RAM-очереди теряются, а эксперимент остаётся со статусом `running`.
  Future<void> dispose() async {
    _autosaveTimer?.cancel();
    _autosaveTimer = null;
    if (_experimentId != null) {
      try {
        await endSession();
      } catch (e) {
        debugPrint('Autosave: ошибка при dispose: $e');
      }
    }
  }
}
