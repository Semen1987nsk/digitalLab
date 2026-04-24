import 'dart:io';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import '../../data/datasources/local/app_database.dart';
import '../entities/calibration_data.dart';
import '../entities/sensor_data.dart';
import '../entities/sensor_type.dart';
import 'sensor_utils.dart';

class ExportUtils {
  static Future<String> exportToCsv(
    List<SensorPacket> data,
    SensorType sensor, {
    VoltageCalibration? voltageCalibration,
  }) async {
    if (data.isEmpty) return '';

    final List<List<dynamic>> rows = [];
    
    // Заголовок
    rows.add(['Время (с)', '${sensor.axisLabel} (${sensor.unit})']);

    // Данные (с учётом калибровки)
    for (final packet in data) {
      final value = SensorUtils.getCalibratedValue(
        packet, sensor,
        voltageCalibration: voltageCalibration,
      );
      if (value != null) {
        rows.add([
          packet.timeSeconds.toStringAsFixed(3),
          value.toStringAsFixed(sensor.defaultDecimalPlaces),
        ]);
      }
    }

    final String csv = const ListToCsvConverter(fieldDelimiter: ';').convert(rows);

    // UTF-8 BOM — без него Excel на Windows открывает кириллицу как кракозябры.
    // BOM безвреден для других программ (LibreOffice, Google Sheets, Python/pandas).
    const String utf8Bom = '\uFEFF';

    // Получаем директорию для сохранения
    Directory? directory;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      directory = await getDownloadsDirectory();
    } else {
      directory = await getApplicationDocumentsDirectory();
    }

    if (directory == null) {
      throw Exception('Не удалось получить директорию для сохранения');
    }

    final String timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final String fileName = 'Эксперимент_${sensor.name}_$timestamp.csv';
    final String filePath = '${directory.path}${Platform.pathSeparator}$fileName';

    final File file = File(filePath);
    await file.writeAsString('$utf8Bom$csv');

    return filePath;
  }

  // ─────────────────────────────────────────────────────────────
  //  Streaming export from SQLite (H1: memory-safe for long experiments)
  // ─────────────────────────────────────────────────────────────

  /// Экспортирует ПОЛНЫЙ эксперимент из SQLite в CSV постранично.
  ///
  /// В отличие от [exportToCsv], который работает с in-memory буфером
  /// (ограничен 50K точками), этот метод читает данные из БД страницами
  /// по [pageSize] строк и пишет в файл инкрементально.
  ///
  /// Это позволяет экспортировать 45-минутный эксперимент (270K строк)
  /// на школьном Celeron N4000 с 4GB RAM без OOM.
  ///
  /// Возвращает путь к файлу или пустую строку если нет данных.
  static Future<String> exportFullExperimentFromDb(
    AppDatabase db,
    int experimentId,
    SensorType sensor, {
    VoltageCalibration? voltageCalibration,
    int pageSize = 5000,
  }) async {
    // 1. Проверяем что данные есть
    final totalCount = await db.measurementCountFor(experimentId);
    if (totalCount == 0) return '';

    // 2. Готовим выходной файл
    Directory? directory;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      directory = await getDownloadsDirectory();
    } else {
      directory = await getApplicationDocumentsDirectory();
    }
    if (directory == null) {
      throw Exception('Не удалось получить директорию для сохранения');
    }

    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final fileName = 'Эксперимент_${sensor.name}_$timestamp.csv';
    final filePath = '${directory.path}${Platform.pathSeparator}$fileName';
    final file = File(filePath);
    final sink = file.openWrite();

    // UTF-8 BOM + заголовок
    const utf8Bom = '\uFEFF';
    const converter = ListToCsvConverter(fieldDelimiter: ';');
    sink.write(utf8Bom);
    sink.writeln(converter.convert(
      [['Время (с)', '${sensor.axisLabel} (${sensor.unit})']],
    ));

    // 3. Постраничная выгрузка: читаем [pageSize] строк → пишем → освобождаем
    int offset = 0;
    int writtenRows = 0;
    while (true) {
      final page = await db.measurementsPaged(
        experimentId,
        pageSize: pageSize,
        offset: offset,
      );
      if (page.isEmpty) break;

      for (final row in page) {
        final packet = _measurementToPacket(row);
        final value = SensorUtils.getCalibratedValue(
          packet, sensor,
          voltageCalibration: voltageCalibration,
        );
        if (value != null) {
          sink.writeln(converter.convert([
            [
              packet.timeSeconds.toStringAsFixed(3),
              value.toStringAsFixed(sensor.defaultDecimalPlaces),
            ],
          ]));
          writtenRows++;
        }
      }

      offset += page.length;
    }

    await sink.flush();
    await sink.close();

    if (writtenRows == 0) {
      // Нет данных для этого типа датчика — удаляем пустой файл
      await file.delete();
      return '';
    }

    return filePath;
  }

  /// Конвертирует строку БД в SensorPacket для использования в
  /// [SensorUtils.getCalibratedValue].
  static SensorPacket _measurementToPacket(MeasurementEntry row) {
    return SensorPacket(
      timestampMs: row.timestampMs,
      voltageV: row.voltageV,
      currentA: row.currentA,
      pressurePa: row.pressurePa,
      temperatureC: row.temperatureC,
      accelX: row.accelX,
      accelY: row.accelY,
      accelZ: row.accelZ,
      magneticFieldMt: row.magneticFieldMt,
      humidityPct: row.humidityPct,
      distanceMm: row.distanceMm,
      forceN: row.forceN,
      luxLx: row.luxLx,
      radiationCpm: row.radiationCpm,
    );
  }
}
