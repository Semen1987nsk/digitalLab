import 'dart:math' as math;
import 'package:equatable/equatable.dart';

/// Пакет данных от мультидатчика.
///
/// Immutable, value-comparable через Equatable.
/// Все поля nullable — разные конфигурации отдают разные подмножества.
///
/// Базовая (6 датчиков): V, A, P, T, Acc, Mag
/// 360 (дополнительно): Distance, Force, Lux
class SensorPacket extends Equatable {
  final int timestampMs;

  // ── Базовые датчики (Классика) ──────────────────────────────

  /// Напряжение (В), ADS1115, диапазоны ±2/5/10/15 В
  final double? voltageV;

  /// Сила тока (А), INA226, диапазон ±1 А
  final double? currentA;

  /// Абсолютное давление (Па), BMP390, 0–500 кПа
  final double? pressurePa;

  /// Температура воздуха (°C), NTC-термистор, -40…+165°C
  final double? temperatureC;

  /// Ускорение по осям (м/с²), LIS3DH, ±2/4/8 g
  final double? accelX;
  final double? accelY;
  final double? accelZ;

  /// Магнитное поле (мТл), MLX90393, ±500 мТл
  final double? magneticFieldMt;

  /// Влажность воздуха (%), BME280, 0–100% RH
  final double? humidityPct;

  // ── Расширенные датчики (360) ───────────────────────────────

  /// Расстояние (мм), HC-SR04, 150–4000 мм
  final double? distanceMm;

  /// Сила (Н), HX711 + тензодатчик, ±50 Н
  final double? forceN;

  /// Освещённость (Лк), BH1750, 0–100 000 Лк
  final double? luxLx;

  // ── Модуль "Атом" (опция) ────────────────────────────────────

  /// Радиация (имп/мин), Счётчик Гейгера СБМ-20, 0–20 000 имп/мин
  final double? radiationCpm;

  const SensorPacket({
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
    this.radiationCpm,
  });

  /// Время в секундах (для графиков)
  double get timeSeconds => timestampMs / 1000.0;

  /// Модуль полного ускорения (м/с²)
  double get accelMagnitude {
    final ax = accelX ?? 0;
    final ay = accelY ?? 0;
    final az = accelZ ?? 0;
    return math.sqrt(ax * ax + ay * ay + az * az);
  }

  @override
  List<Object?> get props => [
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
        radiationCpm,
      ];

  @override
  String toString() {
    final parts = <String>['t=${timestampMs}ms'];
    if (voltageV != null) parts.add('V=${voltageV!.toStringAsFixed(3)}');
    if (currentA != null) parts.add('I=${currentA!.toStringAsFixed(4)}');
    if (temperatureC != null) {
      parts.add('T=${temperatureC!.toStringAsFixed(1)}°C');
    }
    if (pressurePa != null) {
      parts.add('P=${(pressurePa! / 1000).toStringAsFixed(1)}кПа');
    }
    if (magneticFieldMt != null) {
      parts.add('B=${magneticFieldMt!.toStringAsFixed(1)}мТл');
    }
    if (humidityPct != null) parts.add('H=${humidityPct!.toStringAsFixed(1)}%');
    if (distanceMm != null) parts.add('d=${distanceMm!.toStringAsFixed(1)}мм');
    if (forceN != null) parts.add('F=${forceN!.toStringAsFixed(2)}Н');
    if (luxLx != null) parts.add('E=${luxLx!.toStringAsFixed(0)}лк');
    if (radiationCpm != null) {
      parts.add('R=${radiationCpm!.toStringAsFixed(0)}имп/мин');
    }
    return 'SensorPacket(${parts.join(', ')})';
  }
}

/// Информация о подключённом устройстве
class DeviceInfo {
  final String name;
  final String firmwareVersion;
  final int batteryPercent;
  final List<String> enabledSensors;
  final ConnectionType connectionType;

  const DeviceInfo({
    required this.name,
    required this.firmwareVersion,
    required this.batteryPercent,
    required this.enabledSensors,
    required this.connectionType,
  });
}

enum ConnectionType { ble, usb, mock }

enum ConnectionStatus { disconnected, connecting, connected, error }
