import '../entities/calibration_data.dart';
import '../entities/sensor_data.dart';
import '../entities/sensor_type.dart';

/// Утилиты для работы с типами датчиков.
///
/// Извлечение значений из SensorPacket, конвертация единиц.
class SensorUtils {
  SensorUtils._();

  /// Извлечь значение из пакета по типу датчика.
  /// Возвращает `null` если датчик не передаёт данных.
  /// Значения конвертируются в удобные единицы для отображения.
  static double? getValue(SensorPacket? packet, SensorType type) {
    if (packet == null) return null;
    switch (type) {
      case SensorType.voltage:
        return packet.voltageV;
      case SensorType.current:
        return packet.currentA;
      case SensorType.pressure:
        final pa = packet.pressurePa;
        return pa != null ? pa / 1000.0 : null; // Па → кПа
      case SensorType.temperature:
        return packet.temperatureC;
      case SensorType.acceleration:
        // Если хотя бы одна ось есть — считаем модуль
        if (packet.accelX == null && packet.accelY == null && packet.accelZ == null) {
          return null;
        }
        return packet.accelMagnitude;
      case SensorType.magneticField:
        return packet.magneticFieldMt;
      case SensorType.distance:
        final mm = packet.distanceMm;
        return mm != null ? mm / 10.0 : null; // мм → см
      case SensorType.force:
        return packet.forceN;
      case SensorType.lux:
        return packet.luxLx;
      case SensorType.radiation:
        return packet.radiationCpm;
    }
  }

  /// Форматирует значение с правильным количеством знаков
  static String formatValue(double value, SensorType type) {
    return value.toStringAsFixed(type.defaultDecimalPlaces);
  }

  /// Извлечь значение с учётом программной калибровки.
  ///
  /// Для датчика напряжения: применяет VoltageCalibration (gain + offset).
  /// Для остальных датчиков: возвращает сырое значение без изменений.
  ///
  /// Архитектура (Vernier/PASCO/Keithley):
  /// RAW данные хранятся в буфере. Калибровка применяется
  /// при отображении (график, таблица, табло, экспорт).
  static double? getCalibratedValue(
    SensorPacket? packet,
    SensorType type, {
    VoltageCalibration? voltageCalibration,
  }) {
    final raw = getValue(packet, type);
    if (raw == null) return null;
    if (type == SensorType.voltage && voltageCalibration != null) {
      return voltageCalibration.apply(raw);
    }
    return raw;
  }
}
