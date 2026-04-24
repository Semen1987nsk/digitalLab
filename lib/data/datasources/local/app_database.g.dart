// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $ExperimentsTable extends Experiments
    with TableInfo<$ExperimentsTable, ExperimentEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ExperimentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _startTimeMeta =
      const VerificationMeta('startTime');
  @override
  late final GeneratedColumn<DateTime> startTime = GeneratedColumn<DateTime>(
      'start_time', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _endTimeMeta =
      const VerificationMeta('endTime');
  @override
  late final GeneratedColumn<DateTime> endTime = GeneratedColumn<DateTime>(
      'end_time', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _sampleRateHzMeta =
      const VerificationMeta('sampleRateHz');
  @override
  late final GeneratedColumn<int> sampleRateHz = GeneratedColumn<int>(
      'sample_rate_hz', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(10));
  @override
  late final GeneratedColumnWithTypeConverter<ExperimentStatus, int> status =
      GeneratedColumn<int>('status', aliasedName, false,
              type: DriftSqlType.int,
              requiredDuringInsert: false,
              defaultValue: const Constant(0))
          .withConverter<ExperimentStatus>($ExperimentsTable.$converterstatus);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _measurementCountMeta =
      const VerificationMeta('measurementCount');
  @override
  late final GeneratedColumn<int> measurementCount = GeneratedColumn<int>(
      'measurement_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  @override
  List<GeneratedColumn> get $columns =>
      [id, startTime, endTime, sampleRateHz, status, title, measurementCount];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'experiments';
  @override
  VerificationContext validateIntegrity(Insertable<ExperimentEntry> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('start_time')) {
      context.handle(_startTimeMeta,
          startTime.isAcceptableOrUnknown(data['start_time']!, _startTimeMeta));
    } else if (isInserting) {
      context.missing(_startTimeMeta);
    }
    if (data.containsKey('end_time')) {
      context.handle(_endTimeMeta,
          endTime.isAcceptableOrUnknown(data['end_time']!, _endTimeMeta));
    }
    if (data.containsKey('sample_rate_hz')) {
      context.handle(
          _sampleRateHzMeta,
          sampleRateHz.isAcceptableOrUnknown(
              data['sample_rate_hz']!, _sampleRateHzMeta));
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    }
    if (data.containsKey('measurement_count')) {
      context.handle(
          _measurementCountMeta,
          measurementCount.isAcceptableOrUnknown(
              data['measurement_count']!, _measurementCountMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ExperimentEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ExperimentEntry(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      startTime: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}start_time'])!,
      endTime: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}end_time']),
      sampleRateHz: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}sample_rate_hz'])!,
      status: $ExperimentsTable.$converterstatus.fromSql(attachedDatabase
          .typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}status'])!),
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      measurementCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}measurement_count'])!,
    );
  }

  @override
  $ExperimentsTable createAlias(String alias) {
    return $ExperimentsTable(attachedDatabase, alias);
  }

  static TypeConverter<ExperimentStatus, int> $converterstatus =
      const ExperimentStatusConverter();
}

class ExperimentEntry extends DataClass implements Insertable<ExperimentEntry> {
  final int id;

  /// ISO-8601 wall-clock time (UTC) когда нажали "Старт"
  final DateTime startTime;

  /// null пока эксперимент идёт
  final DateTime? endTime;

  /// Гц — частота дискретизации (1..1000)
  final int sampleRateHz;

  /// Статус: running / completed / interrupted
  final ExperimentStatus status;

  /// Необязательное название (например "Закон Ома — 8А класс")
  final String title;

  /// Сколько точек уже сохранено (кэш — чтобы не делать COUNT каждый раз)
  final int measurementCount;
  const ExperimentEntry(
      {required this.id,
      required this.startTime,
      this.endTime,
      required this.sampleRateHz,
      required this.status,
      required this.title,
      required this.measurementCount});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['start_time'] = Variable<DateTime>(startTime);
    if (!nullToAbsent || endTime != null) {
      map['end_time'] = Variable<DateTime>(endTime);
    }
    map['sample_rate_hz'] = Variable<int>(sampleRateHz);
    {
      map['status'] =
          Variable<int>($ExperimentsTable.$converterstatus.toSql(status));
    }
    map['title'] = Variable<String>(title);
    map['measurement_count'] = Variable<int>(measurementCount);
    return map;
  }

  ExperimentsCompanion toCompanion(bool nullToAbsent) {
    return ExperimentsCompanion(
      id: Value(id),
      startTime: Value(startTime),
      endTime: endTime == null && nullToAbsent
          ? const Value.absent()
          : Value(endTime),
      sampleRateHz: Value(sampleRateHz),
      status: Value(status),
      title: Value(title),
      measurementCount: Value(measurementCount),
    );
  }

  factory ExperimentEntry.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ExperimentEntry(
      id: serializer.fromJson<int>(json['id']),
      startTime: serializer.fromJson<DateTime>(json['startTime']),
      endTime: serializer.fromJson<DateTime?>(json['endTime']),
      sampleRateHz: serializer.fromJson<int>(json['sampleRateHz']),
      status: serializer.fromJson<ExperimentStatus>(json['status']),
      title: serializer.fromJson<String>(json['title']),
      measurementCount: serializer.fromJson<int>(json['measurementCount']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'startTime': serializer.toJson<DateTime>(startTime),
      'endTime': serializer.toJson<DateTime?>(endTime),
      'sampleRateHz': serializer.toJson<int>(sampleRateHz),
      'status': serializer.toJson<ExperimentStatus>(status),
      'title': serializer.toJson<String>(title),
      'measurementCount': serializer.toJson<int>(measurementCount),
    };
  }

  ExperimentEntry copyWith(
          {int? id,
          DateTime? startTime,
          Value<DateTime?> endTime = const Value.absent(),
          int? sampleRateHz,
          ExperimentStatus? status,
          String? title,
          int? measurementCount}) =>
      ExperimentEntry(
        id: id ?? this.id,
        startTime: startTime ?? this.startTime,
        endTime: endTime.present ? endTime.value : this.endTime,
        sampleRateHz: sampleRateHz ?? this.sampleRateHz,
        status: status ?? this.status,
        title: title ?? this.title,
        measurementCount: measurementCount ?? this.measurementCount,
      );
  ExperimentEntry copyWithCompanion(ExperimentsCompanion data) {
    return ExperimentEntry(
      id: data.id.present ? data.id.value : this.id,
      startTime: data.startTime.present ? data.startTime.value : this.startTime,
      endTime: data.endTime.present ? data.endTime.value : this.endTime,
      sampleRateHz: data.sampleRateHz.present
          ? data.sampleRateHz.value
          : this.sampleRateHz,
      status: data.status.present ? data.status.value : this.status,
      title: data.title.present ? data.title.value : this.title,
      measurementCount: data.measurementCount.present
          ? data.measurementCount.value
          : this.measurementCount,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ExperimentEntry(')
          ..write('id: $id, ')
          ..write('startTime: $startTime, ')
          ..write('endTime: $endTime, ')
          ..write('sampleRateHz: $sampleRateHz, ')
          ..write('status: $status, ')
          ..write('title: $title, ')
          ..write('measurementCount: $measurementCount')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id, startTime, endTime, sampleRateHz, status, title, measurementCount);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ExperimentEntry &&
          other.id == this.id &&
          other.startTime == this.startTime &&
          other.endTime == this.endTime &&
          other.sampleRateHz == this.sampleRateHz &&
          other.status == this.status &&
          other.title == this.title &&
          other.measurementCount == this.measurementCount);
}

class ExperimentsCompanion extends UpdateCompanion<ExperimentEntry> {
  final Value<int> id;
  final Value<DateTime> startTime;
  final Value<DateTime?> endTime;
  final Value<int> sampleRateHz;
  final Value<ExperimentStatus> status;
  final Value<String> title;
  final Value<int> measurementCount;
  const ExperimentsCompanion({
    this.id = const Value.absent(),
    this.startTime = const Value.absent(),
    this.endTime = const Value.absent(),
    this.sampleRateHz = const Value.absent(),
    this.status = const Value.absent(),
    this.title = const Value.absent(),
    this.measurementCount = const Value.absent(),
  });
  ExperimentsCompanion.insert({
    this.id = const Value.absent(),
    required DateTime startTime,
    this.endTime = const Value.absent(),
    this.sampleRateHz = const Value.absent(),
    this.status = const Value.absent(),
    this.title = const Value.absent(),
    this.measurementCount = const Value.absent(),
  }) : startTime = Value(startTime);
  static Insertable<ExperimentEntry> custom({
    Expression<int>? id,
    Expression<DateTime>? startTime,
    Expression<DateTime>? endTime,
    Expression<int>? sampleRateHz,
    Expression<int>? status,
    Expression<String>? title,
    Expression<int>? measurementCount,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (startTime != null) 'start_time': startTime,
      if (endTime != null) 'end_time': endTime,
      if (sampleRateHz != null) 'sample_rate_hz': sampleRateHz,
      if (status != null) 'status': status,
      if (title != null) 'title': title,
      if (measurementCount != null) 'measurement_count': measurementCount,
    });
  }

  ExperimentsCompanion copyWith(
      {Value<int>? id,
      Value<DateTime>? startTime,
      Value<DateTime?>? endTime,
      Value<int>? sampleRateHz,
      Value<ExperimentStatus>? status,
      Value<String>? title,
      Value<int>? measurementCount}) {
    return ExperimentsCompanion(
      id: id ?? this.id,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      sampleRateHz: sampleRateHz ?? this.sampleRateHz,
      status: status ?? this.status,
      title: title ?? this.title,
      measurementCount: measurementCount ?? this.measurementCount,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (startTime.present) {
      map['start_time'] = Variable<DateTime>(startTime.value);
    }
    if (endTime.present) {
      map['end_time'] = Variable<DateTime>(endTime.value);
    }
    if (sampleRateHz.present) {
      map['sample_rate_hz'] = Variable<int>(sampleRateHz.value);
    }
    if (status.present) {
      map['status'] =
          Variable<int>($ExperimentsTable.$converterstatus.toSql(status.value));
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (measurementCount.present) {
      map['measurement_count'] = Variable<int>(measurementCount.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ExperimentsCompanion(')
          ..write('id: $id, ')
          ..write('startTime: $startTime, ')
          ..write('endTime: $endTime, ')
          ..write('sampleRateHz: $sampleRateHz, ')
          ..write('status: $status, ')
          ..write('title: $title, ')
          ..write('measurementCount: $measurementCount')
          ..write(')'))
        .toString();
  }
}

class $MeasurementsTable extends Measurements
    with TableInfo<$MeasurementsTable, MeasurementEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MeasurementsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _experimentIdMeta =
      const VerificationMeta('experimentId');
  @override
  late final GeneratedColumn<int> experimentId = GeneratedColumn<int>(
      'experiment_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES experiments (id)'));
  static const VerificationMeta _timestampMsMeta =
      const VerificationMeta('timestampMs');
  @override
  late final GeneratedColumn<int> timestampMs = GeneratedColumn<int>(
      'timestamp_ms', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _voltageVMeta =
      const VerificationMeta('voltageV');
  @override
  late final GeneratedColumn<double> voltageV = GeneratedColumn<double>(
      'voltage_v', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _currentAMeta =
      const VerificationMeta('currentA');
  @override
  late final GeneratedColumn<double> currentA = GeneratedColumn<double>(
      'current_a', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _pressurePaMeta =
      const VerificationMeta('pressurePa');
  @override
  late final GeneratedColumn<double> pressurePa = GeneratedColumn<double>(
      'pressure_pa', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _temperatureCMeta =
      const VerificationMeta('temperatureC');
  @override
  late final GeneratedColumn<double> temperatureC = GeneratedColumn<double>(
      'temperature_c', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _accelXMeta = const VerificationMeta('accelX');
  @override
  late final GeneratedColumn<double> accelX = GeneratedColumn<double>(
      'accel_x', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _accelYMeta = const VerificationMeta('accelY');
  @override
  late final GeneratedColumn<double> accelY = GeneratedColumn<double>(
      'accel_y', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _accelZMeta = const VerificationMeta('accelZ');
  @override
  late final GeneratedColumn<double> accelZ = GeneratedColumn<double>(
      'accel_z', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _magneticFieldMtMeta =
      const VerificationMeta('magneticFieldMt');
  @override
  late final GeneratedColumn<double> magneticFieldMt = GeneratedColumn<double>(
      'magnetic_field_mt', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _humidityPctMeta =
      const VerificationMeta('humidityPct');
  @override
  late final GeneratedColumn<double> humidityPct = GeneratedColumn<double>(
      'humidity_pct', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _distanceMmMeta =
      const VerificationMeta('distanceMm');
  @override
  late final GeneratedColumn<double> distanceMm = GeneratedColumn<double>(
      'distance_mm', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _forceNMeta = const VerificationMeta('forceN');
  @override
  late final GeneratedColumn<double> forceN = GeneratedColumn<double>(
      'force_n', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _luxLxMeta = const VerificationMeta('luxLx');
  @override
  late final GeneratedColumn<double> luxLx = GeneratedColumn<double>(
      'lux_lx', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _radiationCpmMeta =
      const VerificationMeta('radiationCpm');
  @override
  late final GeneratedColumn<double> radiationCpm = GeneratedColumn<double>(
      'radiation_cpm', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        experimentId,
        timestampMs,
        voltageV,
        currentA,
        pressurePa,
        temperatureC,
        accelX,
        accelY,
        accelZ,
        magneticFieldMt,
        humidityPct,
        distanceMm,
        forceN,
        luxLx,
        radiationCpm
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'measurements';
  @override
  VerificationContext validateIntegrity(Insertable<MeasurementEntry> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('experiment_id')) {
      context.handle(
          _experimentIdMeta,
          experimentId.isAcceptableOrUnknown(
              data['experiment_id']!, _experimentIdMeta));
    } else if (isInserting) {
      context.missing(_experimentIdMeta);
    }
    if (data.containsKey('timestamp_ms')) {
      context.handle(
          _timestampMsMeta,
          timestampMs.isAcceptableOrUnknown(
              data['timestamp_ms']!, _timestampMsMeta));
    } else if (isInserting) {
      context.missing(_timestampMsMeta);
    }
    if (data.containsKey('voltage_v')) {
      context.handle(_voltageVMeta,
          voltageV.isAcceptableOrUnknown(data['voltage_v']!, _voltageVMeta));
    }
    if (data.containsKey('current_a')) {
      context.handle(_currentAMeta,
          currentA.isAcceptableOrUnknown(data['current_a']!, _currentAMeta));
    }
    if (data.containsKey('pressure_pa')) {
      context.handle(
          _pressurePaMeta,
          pressurePa.isAcceptableOrUnknown(
              data['pressure_pa']!, _pressurePaMeta));
    }
    if (data.containsKey('temperature_c')) {
      context.handle(
          _temperatureCMeta,
          temperatureC.isAcceptableOrUnknown(
              data['temperature_c']!, _temperatureCMeta));
    }
    if (data.containsKey('accel_x')) {
      context.handle(_accelXMeta,
          accelX.isAcceptableOrUnknown(data['accel_x']!, _accelXMeta));
    }
    if (data.containsKey('accel_y')) {
      context.handle(_accelYMeta,
          accelY.isAcceptableOrUnknown(data['accel_y']!, _accelYMeta));
    }
    if (data.containsKey('accel_z')) {
      context.handle(_accelZMeta,
          accelZ.isAcceptableOrUnknown(data['accel_z']!, _accelZMeta));
    }
    if (data.containsKey('magnetic_field_mt')) {
      context.handle(
          _magneticFieldMtMeta,
          magneticFieldMt.isAcceptableOrUnknown(
              data['magnetic_field_mt']!, _magneticFieldMtMeta));
    }
    if (data.containsKey('humidity_pct')) {
      context.handle(
          _humidityPctMeta,
          humidityPct.isAcceptableOrUnknown(
              data['humidity_pct']!, _humidityPctMeta));
    }
    if (data.containsKey('distance_mm')) {
      context.handle(
          _distanceMmMeta,
          distanceMm.isAcceptableOrUnknown(
              data['distance_mm']!, _distanceMmMeta));
    }
    if (data.containsKey('force_n')) {
      context.handle(_forceNMeta,
          forceN.isAcceptableOrUnknown(data['force_n']!, _forceNMeta));
    }
    if (data.containsKey('lux_lx')) {
      context.handle(
          _luxLxMeta, luxLx.isAcceptableOrUnknown(data['lux_lx']!, _luxLxMeta));
    }
    if (data.containsKey('radiation_cpm')) {
      context.handle(
          _radiationCpmMeta,
          radiationCpm.isAcceptableOrUnknown(
              data['radiation_cpm']!, _radiationCpmMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
        {experimentId, timestampMs},
      ];
  @override
  MeasurementEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MeasurementEntry(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      experimentId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}experiment_id'])!,
      timestampMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}timestamp_ms'])!,
      voltageV: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}voltage_v']),
      currentA: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}current_a']),
      pressurePa: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}pressure_pa']),
      temperatureC: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}temperature_c']),
      accelX: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}accel_x']),
      accelY: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}accel_y']),
      accelZ: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}accel_z']),
      magneticFieldMt: attachedDatabase.typeMapping.read(
          DriftSqlType.double, data['${effectivePrefix}magnetic_field_mt']),
      humidityPct: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}humidity_pct']),
      distanceMm: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}distance_mm']),
      forceN: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}force_n']),
      luxLx: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}lux_lx']),
      radiationCpm: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}radiation_cpm']),
    );
  }

  @override
  $MeasurementsTable createAlias(String alias) {
    return $MeasurementsTable(attachedDatabase, alias);
  }
}

class MeasurementEntry extends DataClass
    implements Insertable<MeasurementEntry> {
  final int id;

  /// FK → Experiments.id
  final int experimentId;

  /// Время от начала эксперимента, мс
  final int timestampMs;
  final double? voltageV;
  final double? currentA;
  final double? pressurePa;
  final double? temperatureC;
  final double? accelX;
  final double? accelY;
  final double? accelZ;
  final double? magneticFieldMt;
  final double? humidityPct;
  final double? distanceMm;
  final double? forceN;
  final double? luxLx;
  final double? radiationCpm;
  const MeasurementEntry(
      {required this.id,
      required this.experimentId,
      required this.timestampMs,
      this.voltageV,
      this.currentA,
      this.pressurePa,
      this.temperatureC,
      this.accelX,
      this.accelY,
      this.accelZ,
      this.magneticFieldMt,
      this.humidityPct,
      this.distanceMm,
      this.forceN,
      this.luxLx,
      this.radiationCpm});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['experiment_id'] = Variable<int>(experimentId);
    map['timestamp_ms'] = Variable<int>(timestampMs);
    if (!nullToAbsent || voltageV != null) {
      map['voltage_v'] = Variable<double>(voltageV);
    }
    if (!nullToAbsent || currentA != null) {
      map['current_a'] = Variable<double>(currentA);
    }
    if (!nullToAbsent || pressurePa != null) {
      map['pressure_pa'] = Variable<double>(pressurePa);
    }
    if (!nullToAbsent || temperatureC != null) {
      map['temperature_c'] = Variable<double>(temperatureC);
    }
    if (!nullToAbsent || accelX != null) {
      map['accel_x'] = Variable<double>(accelX);
    }
    if (!nullToAbsent || accelY != null) {
      map['accel_y'] = Variable<double>(accelY);
    }
    if (!nullToAbsent || accelZ != null) {
      map['accel_z'] = Variable<double>(accelZ);
    }
    if (!nullToAbsent || magneticFieldMt != null) {
      map['magnetic_field_mt'] = Variable<double>(magneticFieldMt);
    }
    if (!nullToAbsent || humidityPct != null) {
      map['humidity_pct'] = Variable<double>(humidityPct);
    }
    if (!nullToAbsent || distanceMm != null) {
      map['distance_mm'] = Variable<double>(distanceMm);
    }
    if (!nullToAbsent || forceN != null) {
      map['force_n'] = Variable<double>(forceN);
    }
    if (!nullToAbsent || luxLx != null) {
      map['lux_lx'] = Variable<double>(luxLx);
    }
    if (!nullToAbsent || radiationCpm != null) {
      map['radiation_cpm'] = Variable<double>(radiationCpm);
    }
    return map;
  }

  MeasurementsCompanion toCompanion(bool nullToAbsent) {
    return MeasurementsCompanion(
      id: Value(id),
      experimentId: Value(experimentId),
      timestampMs: Value(timestampMs),
      voltageV: voltageV == null && nullToAbsent
          ? const Value.absent()
          : Value(voltageV),
      currentA: currentA == null && nullToAbsent
          ? const Value.absent()
          : Value(currentA),
      pressurePa: pressurePa == null && nullToAbsent
          ? const Value.absent()
          : Value(pressurePa),
      temperatureC: temperatureC == null && nullToAbsent
          ? const Value.absent()
          : Value(temperatureC),
      accelX:
          accelX == null && nullToAbsent ? const Value.absent() : Value(accelX),
      accelY:
          accelY == null && nullToAbsent ? const Value.absent() : Value(accelY),
      accelZ:
          accelZ == null && nullToAbsent ? const Value.absent() : Value(accelZ),
      magneticFieldMt: magneticFieldMt == null && nullToAbsent
          ? const Value.absent()
          : Value(magneticFieldMt),
      humidityPct: humidityPct == null && nullToAbsent
          ? const Value.absent()
          : Value(humidityPct),
      distanceMm: distanceMm == null && nullToAbsent
          ? const Value.absent()
          : Value(distanceMm),
      forceN:
          forceN == null && nullToAbsent ? const Value.absent() : Value(forceN),
      luxLx:
          luxLx == null && nullToAbsent ? const Value.absent() : Value(luxLx),
      radiationCpm: radiationCpm == null && nullToAbsent
          ? const Value.absent()
          : Value(radiationCpm),
    );
  }

  factory MeasurementEntry.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MeasurementEntry(
      id: serializer.fromJson<int>(json['id']),
      experimentId: serializer.fromJson<int>(json['experimentId']),
      timestampMs: serializer.fromJson<int>(json['timestampMs']),
      voltageV: serializer.fromJson<double?>(json['voltageV']),
      currentA: serializer.fromJson<double?>(json['currentA']),
      pressurePa: serializer.fromJson<double?>(json['pressurePa']),
      temperatureC: serializer.fromJson<double?>(json['temperatureC']),
      accelX: serializer.fromJson<double?>(json['accelX']),
      accelY: serializer.fromJson<double?>(json['accelY']),
      accelZ: serializer.fromJson<double?>(json['accelZ']),
      magneticFieldMt: serializer.fromJson<double?>(json['magneticFieldMt']),
      humidityPct: serializer.fromJson<double?>(json['humidityPct']),
      distanceMm: serializer.fromJson<double?>(json['distanceMm']),
      forceN: serializer.fromJson<double?>(json['forceN']),
      luxLx: serializer.fromJson<double?>(json['luxLx']),
      radiationCpm: serializer.fromJson<double?>(json['radiationCpm']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'experimentId': serializer.toJson<int>(experimentId),
      'timestampMs': serializer.toJson<int>(timestampMs),
      'voltageV': serializer.toJson<double?>(voltageV),
      'currentA': serializer.toJson<double?>(currentA),
      'pressurePa': serializer.toJson<double?>(pressurePa),
      'temperatureC': serializer.toJson<double?>(temperatureC),
      'accelX': serializer.toJson<double?>(accelX),
      'accelY': serializer.toJson<double?>(accelY),
      'accelZ': serializer.toJson<double?>(accelZ),
      'magneticFieldMt': serializer.toJson<double?>(magneticFieldMt),
      'humidityPct': serializer.toJson<double?>(humidityPct),
      'distanceMm': serializer.toJson<double?>(distanceMm),
      'forceN': serializer.toJson<double?>(forceN),
      'luxLx': serializer.toJson<double?>(luxLx),
      'radiationCpm': serializer.toJson<double?>(radiationCpm),
    };
  }

  MeasurementEntry copyWith(
          {int? id,
          int? experimentId,
          int? timestampMs,
          Value<double?> voltageV = const Value.absent(),
          Value<double?> currentA = const Value.absent(),
          Value<double?> pressurePa = const Value.absent(),
          Value<double?> temperatureC = const Value.absent(),
          Value<double?> accelX = const Value.absent(),
          Value<double?> accelY = const Value.absent(),
          Value<double?> accelZ = const Value.absent(),
          Value<double?> magneticFieldMt = const Value.absent(),
          Value<double?> humidityPct = const Value.absent(),
          Value<double?> distanceMm = const Value.absent(),
          Value<double?> forceN = const Value.absent(),
          Value<double?> luxLx = const Value.absent(),
          Value<double?> radiationCpm = const Value.absent()}) =>
      MeasurementEntry(
        id: id ?? this.id,
        experimentId: experimentId ?? this.experimentId,
        timestampMs: timestampMs ?? this.timestampMs,
        voltageV: voltageV.present ? voltageV.value : this.voltageV,
        currentA: currentA.present ? currentA.value : this.currentA,
        pressurePa: pressurePa.present ? pressurePa.value : this.pressurePa,
        temperatureC:
            temperatureC.present ? temperatureC.value : this.temperatureC,
        accelX: accelX.present ? accelX.value : this.accelX,
        accelY: accelY.present ? accelY.value : this.accelY,
        accelZ: accelZ.present ? accelZ.value : this.accelZ,
        magneticFieldMt: magneticFieldMt.present
            ? magneticFieldMt.value
            : this.magneticFieldMt,
        humidityPct: humidityPct.present ? humidityPct.value : this.humidityPct,
        distanceMm: distanceMm.present ? distanceMm.value : this.distanceMm,
        forceN: forceN.present ? forceN.value : this.forceN,
        luxLx: luxLx.present ? luxLx.value : this.luxLx,
        radiationCpm:
            radiationCpm.present ? radiationCpm.value : this.radiationCpm,
      );
  MeasurementEntry copyWithCompanion(MeasurementsCompanion data) {
    return MeasurementEntry(
      id: data.id.present ? data.id.value : this.id,
      experimentId: data.experimentId.present
          ? data.experimentId.value
          : this.experimentId,
      timestampMs:
          data.timestampMs.present ? data.timestampMs.value : this.timestampMs,
      voltageV: data.voltageV.present ? data.voltageV.value : this.voltageV,
      currentA: data.currentA.present ? data.currentA.value : this.currentA,
      pressurePa:
          data.pressurePa.present ? data.pressurePa.value : this.pressurePa,
      temperatureC: data.temperatureC.present
          ? data.temperatureC.value
          : this.temperatureC,
      accelX: data.accelX.present ? data.accelX.value : this.accelX,
      accelY: data.accelY.present ? data.accelY.value : this.accelY,
      accelZ: data.accelZ.present ? data.accelZ.value : this.accelZ,
      magneticFieldMt: data.magneticFieldMt.present
          ? data.magneticFieldMt.value
          : this.magneticFieldMt,
      humidityPct:
          data.humidityPct.present ? data.humidityPct.value : this.humidityPct,
      distanceMm:
          data.distanceMm.present ? data.distanceMm.value : this.distanceMm,
      forceN: data.forceN.present ? data.forceN.value : this.forceN,
      luxLx: data.luxLx.present ? data.luxLx.value : this.luxLx,
      radiationCpm: data.radiationCpm.present
          ? data.radiationCpm.value
          : this.radiationCpm,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MeasurementEntry(')
          ..write('id: $id, ')
          ..write('experimentId: $experimentId, ')
          ..write('timestampMs: $timestampMs, ')
          ..write('voltageV: $voltageV, ')
          ..write('currentA: $currentA, ')
          ..write('pressurePa: $pressurePa, ')
          ..write('temperatureC: $temperatureC, ')
          ..write('accelX: $accelX, ')
          ..write('accelY: $accelY, ')
          ..write('accelZ: $accelZ, ')
          ..write('magneticFieldMt: $magneticFieldMt, ')
          ..write('humidityPct: $humidityPct, ')
          ..write('distanceMm: $distanceMm, ')
          ..write('forceN: $forceN, ')
          ..write('luxLx: $luxLx, ')
          ..write('radiationCpm: $radiationCpm')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      experimentId,
      timestampMs,
      voltageV,
      currentA,
      pressurePa,
      temperatureC,
      accelX,
      accelY,
      accelZ,
      magneticFieldMt,
      humidityPct,
      distanceMm,
      forceN,
      luxLx,
      radiationCpm);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MeasurementEntry &&
          other.id == this.id &&
          other.experimentId == this.experimentId &&
          other.timestampMs == this.timestampMs &&
          other.voltageV == this.voltageV &&
          other.currentA == this.currentA &&
          other.pressurePa == this.pressurePa &&
          other.temperatureC == this.temperatureC &&
          other.accelX == this.accelX &&
          other.accelY == this.accelY &&
          other.accelZ == this.accelZ &&
          other.magneticFieldMt == this.magneticFieldMt &&
          other.humidityPct == this.humidityPct &&
          other.distanceMm == this.distanceMm &&
          other.forceN == this.forceN &&
          other.luxLx == this.luxLx &&
          other.radiationCpm == this.radiationCpm);
}

class MeasurementsCompanion extends UpdateCompanion<MeasurementEntry> {
  final Value<int> id;
  final Value<int> experimentId;
  final Value<int> timestampMs;
  final Value<double?> voltageV;
  final Value<double?> currentA;
  final Value<double?> pressurePa;
  final Value<double?> temperatureC;
  final Value<double?> accelX;
  final Value<double?> accelY;
  final Value<double?> accelZ;
  final Value<double?> magneticFieldMt;
  final Value<double?> humidityPct;
  final Value<double?> distanceMm;
  final Value<double?> forceN;
  final Value<double?> luxLx;
  final Value<double?> radiationCpm;
  const MeasurementsCompanion({
    this.id = const Value.absent(),
    this.experimentId = const Value.absent(),
    this.timestampMs = const Value.absent(),
    this.voltageV = const Value.absent(),
    this.currentA = const Value.absent(),
    this.pressurePa = const Value.absent(),
    this.temperatureC = const Value.absent(),
    this.accelX = const Value.absent(),
    this.accelY = const Value.absent(),
    this.accelZ = const Value.absent(),
    this.magneticFieldMt = const Value.absent(),
    this.humidityPct = const Value.absent(),
    this.distanceMm = const Value.absent(),
    this.forceN = const Value.absent(),
    this.luxLx = const Value.absent(),
    this.radiationCpm = const Value.absent(),
  });
  MeasurementsCompanion.insert({
    this.id = const Value.absent(),
    required int experimentId,
    required int timestampMs,
    this.voltageV = const Value.absent(),
    this.currentA = const Value.absent(),
    this.pressurePa = const Value.absent(),
    this.temperatureC = const Value.absent(),
    this.accelX = const Value.absent(),
    this.accelY = const Value.absent(),
    this.accelZ = const Value.absent(),
    this.magneticFieldMt = const Value.absent(),
    this.humidityPct = const Value.absent(),
    this.distanceMm = const Value.absent(),
    this.forceN = const Value.absent(),
    this.luxLx = const Value.absent(),
    this.radiationCpm = const Value.absent(),
  })  : experimentId = Value(experimentId),
        timestampMs = Value(timestampMs);
  static Insertable<MeasurementEntry> custom({
    Expression<int>? id,
    Expression<int>? experimentId,
    Expression<int>? timestampMs,
    Expression<double>? voltageV,
    Expression<double>? currentA,
    Expression<double>? pressurePa,
    Expression<double>? temperatureC,
    Expression<double>? accelX,
    Expression<double>? accelY,
    Expression<double>? accelZ,
    Expression<double>? magneticFieldMt,
    Expression<double>? humidityPct,
    Expression<double>? distanceMm,
    Expression<double>? forceN,
    Expression<double>? luxLx,
    Expression<double>? radiationCpm,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (experimentId != null) 'experiment_id': experimentId,
      if (timestampMs != null) 'timestamp_ms': timestampMs,
      if (voltageV != null) 'voltage_v': voltageV,
      if (currentA != null) 'current_a': currentA,
      if (pressurePa != null) 'pressure_pa': pressurePa,
      if (temperatureC != null) 'temperature_c': temperatureC,
      if (accelX != null) 'accel_x': accelX,
      if (accelY != null) 'accel_y': accelY,
      if (accelZ != null) 'accel_z': accelZ,
      if (magneticFieldMt != null) 'magnetic_field_mt': magneticFieldMt,
      if (humidityPct != null) 'humidity_pct': humidityPct,
      if (distanceMm != null) 'distance_mm': distanceMm,
      if (forceN != null) 'force_n': forceN,
      if (luxLx != null) 'lux_lx': luxLx,
      if (radiationCpm != null) 'radiation_cpm': radiationCpm,
    });
  }

  MeasurementsCompanion copyWith(
      {Value<int>? id,
      Value<int>? experimentId,
      Value<int>? timestampMs,
      Value<double?>? voltageV,
      Value<double?>? currentA,
      Value<double?>? pressurePa,
      Value<double?>? temperatureC,
      Value<double?>? accelX,
      Value<double?>? accelY,
      Value<double?>? accelZ,
      Value<double?>? magneticFieldMt,
      Value<double?>? humidityPct,
      Value<double?>? distanceMm,
      Value<double?>? forceN,
      Value<double?>? luxLx,
      Value<double?>? radiationCpm}) {
    return MeasurementsCompanion(
      id: id ?? this.id,
      experimentId: experimentId ?? this.experimentId,
      timestampMs: timestampMs ?? this.timestampMs,
      voltageV: voltageV ?? this.voltageV,
      currentA: currentA ?? this.currentA,
      pressurePa: pressurePa ?? this.pressurePa,
      temperatureC: temperatureC ?? this.temperatureC,
      accelX: accelX ?? this.accelX,
      accelY: accelY ?? this.accelY,
      accelZ: accelZ ?? this.accelZ,
      magneticFieldMt: magneticFieldMt ?? this.magneticFieldMt,
      humidityPct: humidityPct ?? this.humidityPct,
      distanceMm: distanceMm ?? this.distanceMm,
      forceN: forceN ?? this.forceN,
      luxLx: luxLx ?? this.luxLx,
      radiationCpm: radiationCpm ?? this.radiationCpm,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (experimentId.present) {
      map['experiment_id'] = Variable<int>(experimentId.value);
    }
    if (timestampMs.present) {
      map['timestamp_ms'] = Variable<int>(timestampMs.value);
    }
    if (voltageV.present) {
      map['voltage_v'] = Variable<double>(voltageV.value);
    }
    if (currentA.present) {
      map['current_a'] = Variable<double>(currentA.value);
    }
    if (pressurePa.present) {
      map['pressure_pa'] = Variable<double>(pressurePa.value);
    }
    if (temperatureC.present) {
      map['temperature_c'] = Variable<double>(temperatureC.value);
    }
    if (accelX.present) {
      map['accel_x'] = Variable<double>(accelX.value);
    }
    if (accelY.present) {
      map['accel_y'] = Variable<double>(accelY.value);
    }
    if (accelZ.present) {
      map['accel_z'] = Variable<double>(accelZ.value);
    }
    if (magneticFieldMt.present) {
      map['magnetic_field_mt'] = Variable<double>(magneticFieldMt.value);
    }
    if (humidityPct.present) {
      map['humidity_pct'] = Variable<double>(humidityPct.value);
    }
    if (distanceMm.present) {
      map['distance_mm'] = Variable<double>(distanceMm.value);
    }
    if (forceN.present) {
      map['force_n'] = Variable<double>(forceN.value);
    }
    if (luxLx.present) {
      map['lux_lx'] = Variable<double>(luxLx.value);
    }
    if (radiationCpm.present) {
      map['radiation_cpm'] = Variable<double>(radiationCpm.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MeasurementsCompanion(')
          ..write('id: $id, ')
          ..write('experimentId: $experimentId, ')
          ..write('timestampMs: $timestampMs, ')
          ..write('voltageV: $voltageV, ')
          ..write('currentA: $currentA, ')
          ..write('pressurePa: $pressurePa, ')
          ..write('temperatureC: $temperatureC, ')
          ..write('accelX: $accelX, ')
          ..write('accelY: $accelY, ')
          ..write('accelZ: $accelZ, ')
          ..write('magneticFieldMt: $magneticFieldMt, ')
          ..write('humidityPct: $humidityPct, ')
          ..write('distanceMm: $distanceMm, ')
          ..write('forceN: $forceN, ')
          ..write('luxLx: $luxLx, ')
          ..write('radiationCpm: $radiationCpm')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $ExperimentsTable experiments = $ExperimentsTable(this);
  late final $MeasurementsTable measurements = $MeasurementsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      [experiments, measurements];
}

typedef $$ExperimentsTableCreateCompanionBuilder = ExperimentsCompanion
    Function({
  Value<int> id,
  required DateTime startTime,
  Value<DateTime?> endTime,
  Value<int> sampleRateHz,
  Value<ExperimentStatus> status,
  Value<String> title,
  Value<int> measurementCount,
});
typedef $$ExperimentsTableUpdateCompanionBuilder = ExperimentsCompanion
    Function({
  Value<int> id,
  Value<DateTime> startTime,
  Value<DateTime?> endTime,
  Value<int> sampleRateHz,
  Value<ExperimentStatus> status,
  Value<String> title,
  Value<int> measurementCount,
});

final class $$ExperimentsTableReferences
    extends BaseReferences<_$AppDatabase, $ExperimentsTable, ExperimentEntry> {
  $$ExperimentsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$MeasurementsTable, List<MeasurementEntry>>
      _measurementsRefsTable(_$AppDatabase db) =>
          MultiTypedResultKey.fromTable(db.measurements,
              aliasName: $_aliasNameGenerator(
                  db.experiments.id, db.measurements.experimentId));

  $$MeasurementsTableProcessedTableManager get measurementsRefs {
    final manager = $$MeasurementsTableTableManager($_db, $_db.measurements)
        .filter((f) => f.experimentId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_measurementsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$ExperimentsTableFilterComposer
    extends Composer<_$AppDatabase, $ExperimentsTable> {
  $$ExperimentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get startTime => $composableBuilder(
      column: $table.startTime, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get endTime => $composableBuilder(
      column: $table.endTime, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get sampleRateHz => $composableBuilder(
      column: $table.sampleRateHz, builder: (column) => ColumnFilters(column));

  ColumnWithTypeConverterFilters<ExperimentStatus, ExperimentStatus, int>
      get status => $composableBuilder(
          column: $table.status,
          builder: (column) => ColumnWithTypeConverterFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get measurementCount => $composableBuilder(
      column: $table.measurementCount,
      builder: (column) => ColumnFilters(column));

  Expression<bool> measurementsRefs(
      Expression<bool> Function($$MeasurementsTableFilterComposer f) f) {
    final $$MeasurementsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.measurements,
        getReferencedColumn: (t) => t.experimentId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$MeasurementsTableFilterComposer(
              $db: $db,
              $table: $db.measurements,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$ExperimentsTableOrderingComposer
    extends Composer<_$AppDatabase, $ExperimentsTable> {
  $$ExperimentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get startTime => $composableBuilder(
      column: $table.startTime, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get endTime => $composableBuilder(
      column: $table.endTime, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get sampleRateHz => $composableBuilder(
      column: $table.sampleRateHz,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get measurementCount => $composableBuilder(
      column: $table.measurementCount,
      builder: (column) => ColumnOrderings(column));
}

class $$ExperimentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ExperimentsTable> {
  $$ExperimentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get startTime =>
      $composableBuilder(column: $table.startTime, builder: (column) => column);

  GeneratedColumn<DateTime> get endTime =>
      $composableBuilder(column: $table.endTime, builder: (column) => column);

  GeneratedColumn<int> get sampleRateHz => $composableBuilder(
      column: $table.sampleRateHz, builder: (column) => column);

  GeneratedColumnWithTypeConverter<ExperimentStatus, int> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<int> get measurementCount => $composableBuilder(
      column: $table.measurementCount, builder: (column) => column);

  Expression<T> measurementsRefs<T extends Object>(
      Expression<T> Function($$MeasurementsTableAnnotationComposer a) f) {
    final $$MeasurementsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.measurements,
        getReferencedColumn: (t) => t.experimentId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$MeasurementsTableAnnotationComposer(
              $db: $db,
              $table: $db.measurements,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$ExperimentsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ExperimentsTable,
    ExperimentEntry,
    $$ExperimentsTableFilterComposer,
    $$ExperimentsTableOrderingComposer,
    $$ExperimentsTableAnnotationComposer,
    $$ExperimentsTableCreateCompanionBuilder,
    $$ExperimentsTableUpdateCompanionBuilder,
    (ExperimentEntry, $$ExperimentsTableReferences),
    ExperimentEntry,
    PrefetchHooks Function({bool measurementsRefs})> {
  $$ExperimentsTableTableManager(_$AppDatabase db, $ExperimentsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ExperimentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ExperimentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ExperimentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<DateTime> startTime = const Value.absent(),
            Value<DateTime?> endTime = const Value.absent(),
            Value<int> sampleRateHz = const Value.absent(),
            Value<ExperimentStatus> status = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<int> measurementCount = const Value.absent(),
          }) =>
              ExperimentsCompanion(
            id: id,
            startTime: startTime,
            endTime: endTime,
            sampleRateHz: sampleRateHz,
            status: status,
            title: title,
            measurementCount: measurementCount,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required DateTime startTime,
            Value<DateTime?> endTime = const Value.absent(),
            Value<int> sampleRateHz = const Value.absent(),
            Value<ExperimentStatus> status = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<int> measurementCount = const Value.absent(),
          }) =>
              ExperimentsCompanion.insert(
            id: id,
            startTime: startTime,
            endTime: endTime,
            sampleRateHz: sampleRateHz,
            status: status,
            title: title,
            measurementCount: measurementCount,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$ExperimentsTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({measurementsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (measurementsRefs) db.measurements],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (measurementsRefs)
                    await $_getPrefetchedData<ExperimentEntry,
                            $ExperimentsTable, MeasurementEntry>(
                        currentTable: table,
                        referencedTable: $$ExperimentsTableReferences
                            ._measurementsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$ExperimentsTableReferences(db, table, p0)
                                .measurementsRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.experimentId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$ExperimentsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ExperimentsTable,
    ExperimentEntry,
    $$ExperimentsTableFilterComposer,
    $$ExperimentsTableOrderingComposer,
    $$ExperimentsTableAnnotationComposer,
    $$ExperimentsTableCreateCompanionBuilder,
    $$ExperimentsTableUpdateCompanionBuilder,
    (ExperimentEntry, $$ExperimentsTableReferences),
    ExperimentEntry,
    PrefetchHooks Function({bool measurementsRefs})>;
typedef $$MeasurementsTableCreateCompanionBuilder = MeasurementsCompanion
    Function({
  Value<int> id,
  required int experimentId,
  required int timestampMs,
  Value<double?> voltageV,
  Value<double?> currentA,
  Value<double?> pressurePa,
  Value<double?> temperatureC,
  Value<double?> accelX,
  Value<double?> accelY,
  Value<double?> accelZ,
  Value<double?> magneticFieldMt,
  Value<double?> humidityPct,
  Value<double?> distanceMm,
  Value<double?> forceN,
  Value<double?> luxLx,
  Value<double?> radiationCpm,
});
typedef $$MeasurementsTableUpdateCompanionBuilder = MeasurementsCompanion
    Function({
  Value<int> id,
  Value<int> experimentId,
  Value<int> timestampMs,
  Value<double?> voltageV,
  Value<double?> currentA,
  Value<double?> pressurePa,
  Value<double?> temperatureC,
  Value<double?> accelX,
  Value<double?> accelY,
  Value<double?> accelZ,
  Value<double?> magneticFieldMt,
  Value<double?> humidityPct,
  Value<double?> distanceMm,
  Value<double?> forceN,
  Value<double?> luxLx,
  Value<double?> radiationCpm,
});

final class $$MeasurementsTableReferences extends BaseReferences<_$AppDatabase,
    $MeasurementsTable, MeasurementEntry> {
  $$MeasurementsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ExperimentsTable _experimentIdTable(_$AppDatabase db) =>
      db.experiments.createAlias($_aliasNameGenerator(
          db.measurements.experimentId, db.experiments.id));

  $$ExperimentsTableProcessedTableManager get experimentId {
    final $_column = $_itemColumn<int>('experiment_id')!;

    final manager = $$ExperimentsTableTableManager($_db, $_db.experiments)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_experimentIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$MeasurementsTableFilterComposer
    extends Composer<_$AppDatabase, $MeasurementsTable> {
  $$MeasurementsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get timestampMs => $composableBuilder(
      column: $table.timestampMs, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get voltageV => $composableBuilder(
      column: $table.voltageV, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get currentA => $composableBuilder(
      column: $table.currentA, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get pressurePa => $composableBuilder(
      column: $table.pressurePa, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get temperatureC => $composableBuilder(
      column: $table.temperatureC, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get accelX => $composableBuilder(
      column: $table.accelX, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get accelY => $composableBuilder(
      column: $table.accelY, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get accelZ => $composableBuilder(
      column: $table.accelZ, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get magneticFieldMt => $composableBuilder(
      column: $table.magneticFieldMt,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get humidityPct => $composableBuilder(
      column: $table.humidityPct, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get distanceMm => $composableBuilder(
      column: $table.distanceMm, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get forceN => $composableBuilder(
      column: $table.forceN, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get luxLx => $composableBuilder(
      column: $table.luxLx, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get radiationCpm => $composableBuilder(
      column: $table.radiationCpm, builder: (column) => ColumnFilters(column));

  $$ExperimentsTableFilterComposer get experimentId {
    final $$ExperimentsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.experimentId,
        referencedTable: $db.experiments,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ExperimentsTableFilterComposer(
              $db: $db,
              $table: $db.experiments,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$MeasurementsTableOrderingComposer
    extends Composer<_$AppDatabase, $MeasurementsTable> {
  $$MeasurementsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get timestampMs => $composableBuilder(
      column: $table.timestampMs, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get voltageV => $composableBuilder(
      column: $table.voltageV, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get currentA => $composableBuilder(
      column: $table.currentA, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get pressurePa => $composableBuilder(
      column: $table.pressurePa, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get temperatureC => $composableBuilder(
      column: $table.temperatureC,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get accelX => $composableBuilder(
      column: $table.accelX, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get accelY => $composableBuilder(
      column: $table.accelY, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get accelZ => $composableBuilder(
      column: $table.accelZ, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get magneticFieldMt => $composableBuilder(
      column: $table.magneticFieldMt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get humidityPct => $composableBuilder(
      column: $table.humidityPct, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get distanceMm => $composableBuilder(
      column: $table.distanceMm, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get forceN => $composableBuilder(
      column: $table.forceN, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get luxLx => $composableBuilder(
      column: $table.luxLx, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get radiationCpm => $composableBuilder(
      column: $table.radiationCpm,
      builder: (column) => ColumnOrderings(column));

  $$ExperimentsTableOrderingComposer get experimentId {
    final $$ExperimentsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.experimentId,
        referencedTable: $db.experiments,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ExperimentsTableOrderingComposer(
              $db: $db,
              $table: $db.experiments,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$MeasurementsTableAnnotationComposer
    extends Composer<_$AppDatabase, $MeasurementsTable> {
  $$MeasurementsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get timestampMs => $composableBuilder(
      column: $table.timestampMs, builder: (column) => column);

  GeneratedColumn<double> get voltageV =>
      $composableBuilder(column: $table.voltageV, builder: (column) => column);

  GeneratedColumn<double> get currentA =>
      $composableBuilder(column: $table.currentA, builder: (column) => column);

  GeneratedColumn<double> get pressurePa => $composableBuilder(
      column: $table.pressurePa, builder: (column) => column);

  GeneratedColumn<double> get temperatureC => $composableBuilder(
      column: $table.temperatureC, builder: (column) => column);

  GeneratedColumn<double> get accelX =>
      $composableBuilder(column: $table.accelX, builder: (column) => column);

  GeneratedColumn<double> get accelY =>
      $composableBuilder(column: $table.accelY, builder: (column) => column);

  GeneratedColumn<double> get accelZ =>
      $composableBuilder(column: $table.accelZ, builder: (column) => column);

  GeneratedColumn<double> get magneticFieldMt => $composableBuilder(
      column: $table.magneticFieldMt, builder: (column) => column);

  GeneratedColumn<double> get humidityPct => $composableBuilder(
      column: $table.humidityPct, builder: (column) => column);

  GeneratedColumn<double> get distanceMm => $composableBuilder(
      column: $table.distanceMm, builder: (column) => column);

  GeneratedColumn<double> get forceN =>
      $composableBuilder(column: $table.forceN, builder: (column) => column);

  GeneratedColumn<double> get luxLx =>
      $composableBuilder(column: $table.luxLx, builder: (column) => column);

  GeneratedColumn<double> get radiationCpm => $composableBuilder(
      column: $table.radiationCpm, builder: (column) => column);

  $$ExperimentsTableAnnotationComposer get experimentId {
    final $$ExperimentsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.experimentId,
        referencedTable: $db.experiments,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ExperimentsTableAnnotationComposer(
              $db: $db,
              $table: $db.experiments,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$MeasurementsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $MeasurementsTable,
    MeasurementEntry,
    $$MeasurementsTableFilterComposer,
    $$MeasurementsTableOrderingComposer,
    $$MeasurementsTableAnnotationComposer,
    $$MeasurementsTableCreateCompanionBuilder,
    $$MeasurementsTableUpdateCompanionBuilder,
    (MeasurementEntry, $$MeasurementsTableReferences),
    MeasurementEntry,
    PrefetchHooks Function({bool experimentId})> {
  $$MeasurementsTableTableManager(_$AppDatabase db, $MeasurementsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MeasurementsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MeasurementsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MeasurementsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> experimentId = const Value.absent(),
            Value<int> timestampMs = const Value.absent(),
            Value<double?> voltageV = const Value.absent(),
            Value<double?> currentA = const Value.absent(),
            Value<double?> pressurePa = const Value.absent(),
            Value<double?> temperatureC = const Value.absent(),
            Value<double?> accelX = const Value.absent(),
            Value<double?> accelY = const Value.absent(),
            Value<double?> accelZ = const Value.absent(),
            Value<double?> magneticFieldMt = const Value.absent(),
            Value<double?> humidityPct = const Value.absent(),
            Value<double?> distanceMm = const Value.absent(),
            Value<double?> forceN = const Value.absent(),
            Value<double?> luxLx = const Value.absent(),
            Value<double?> radiationCpm = const Value.absent(),
          }) =>
              MeasurementsCompanion(
            id: id,
            experimentId: experimentId,
            timestampMs: timestampMs,
            voltageV: voltageV,
            currentA: currentA,
            pressurePa: pressurePa,
            temperatureC: temperatureC,
            accelX: accelX,
            accelY: accelY,
            accelZ: accelZ,
            magneticFieldMt: magneticFieldMt,
            humidityPct: humidityPct,
            distanceMm: distanceMm,
            forceN: forceN,
            luxLx: luxLx,
            radiationCpm: radiationCpm,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required int experimentId,
            required int timestampMs,
            Value<double?> voltageV = const Value.absent(),
            Value<double?> currentA = const Value.absent(),
            Value<double?> pressurePa = const Value.absent(),
            Value<double?> temperatureC = const Value.absent(),
            Value<double?> accelX = const Value.absent(),
            Value<double?> accelY = const Value.absent(),
            Value<double?> accelZ = const Value.absent(),
            Value<double?> magneticFieldMt = const Value.absent(),
            Value<double?> humidityPct = const Value.absent(),
            Value<double?> distanceMm = const Value.absent(),
            Value<double?> forceN = const Value.absent(),
            Value<double?> luxLx = const Value.absent(),
            Value<double?> radiationCpm = const Value.absent(),
          }) =>
              MeasurementsCompanion.insert(
            id: id,
            experimentId: experimentId,
            timestampMs: timestampMs,
            voltageV: voltageV,
            currentA: currentA,
            pressurePa: pressurePa,
            temperatureC: temperatureC,
            accelX: accelX,
            accelY: accelY,
            accelZ: accelZ,
            magneticFieldMt: magneticFieldMt,
            humidityPct: humidityPct,
            distanceMm: distanceMm,
            forceN: forceN,
            luxLx: luxLx,
            radiationCpm: radiationCpm,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$MeasurementsTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({experimentId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (experimentId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.experimentId,
                    referencedTable:
                        $$MeasurementsTableReferences._experimentIdTable(db),
                    referencedColumn:
                        $$MeasurementsTableReferences._experimentIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$MeasurementsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $MeasurementsTable,
    MeasurementEntry,
    $$MeasurementsTableFilterComposer,
    $$MeasurementsTableOrderingComposer,
    $$MeasurementsTableAnnotationComposer,
    $$MeasurementsTableCreateCompanionBuilder,
    $$MeasurementsTableUpdateCompanionBuilder,
    (MeasurementEntry, $$MeasurementsTableReferences),
    MeasurementEntry,
    PrefetchHooks Function({bool experimentId})>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ExperimentsTableTableManager get experiments =>
      $$ExperimentsTableTableManager(_db, _db.experiments);
  $$MeasurementsTableTableManager get measurements =>
      $$MeasurementsTableTableManager(_db, _db.measurements);
}
