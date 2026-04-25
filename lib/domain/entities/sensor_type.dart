import 'package:flutter/material.dart';

/// Тип датчика с полной метаинформацией.
///
/// Каждое значение enum содержит всё необходимое для отображения:
/// название, единицу, цвет, иконку, диапазон оси.
enum SensorType {
  voltage(
    id: 'voltage',
    title: 'Напряжение',
    subtitle: 'Вольтметр · ADS1115',
    unit: 'В',
    axisLabel: 'Напряжение, В',
    color: Color(0xFFFFEB3B),
    icon: Icons.bolt,
    minRange: 1.0,
    defaultDecimalPlaces: 2,
  ),
  current(
    id: 'current',
    title: 'Сила тока',
    subtitle: 'Амперметр · INA226',
    unit: 'А',
    axisLabel: 'Сила тока, А',
    color: Color(0xFF2196F3),
    icon: Icons.electric_meter,
    minRange: 0.5,
    defaultDecimalPlaces: 3,
  ),
  pressure(
    id: 'pressure',
    title: 'Давление',
    subtitle: 'Барометр · BMP390',
    unit: 'кПа',
    axisLabel: 'Давление, кПа',
    color: Color(0xFF9C27B0),
    icon: Icons.speed,
    minRange: 5.0,
    defaultDecimalPlaces: 1,
  ),
  temperature(
    id: 'temperature',
    title: 'Температура',
    subtitle: 'Термометр · NTC',
    unit: '°C',
    axisLabel: 'Температура, °C',
    color: Color(0xFFF44336),
    icon: Icons.thermostat,
    minRange: 5.0,
    defaultDecimalPlaces: 1,
  ),
  acceleration(
    id: 'acceleration',
    title: 'Ускорение',
    subtitle: 'Акселерометр · LIS3DH',
    unit: 'м/с²',
    axisLabel: 'Ускорение, м/с²',
    color: Color(0xFFFF9800),
    icon: Icons.open_with,
    minRange: 2.0,
    defaultDecimalPlaces: 2,
  ),
  magneticField(
    id: 'magnetic_field',
    title: 'Магнитное поле',
    subtitle: 'Датчик Холла · MLX90393',
    unit: 'мТл',
    axisLabel: 'Магнитное поле, мТл',
    color: Color(0xFF3F51B5),
    icon: Icons.waves,
    minRange: 10.0,
    defaultDecimalPlaces: 1,
  ),
  distance(
    id: 'distance',
    title: 'Расстояние',
    subtitle: 'Дальномер · HC-SR04',
    unit: 'см',
    axisLabel: 'Расстояние, см',
    color: Color(0xFF00BCD4),
    icon: Icons.straighten,
    minRange: 20.0,
    defaultDecimalPlaces: 1,
  ),
  force(
    id: 'force',
    title: 'Сила',
    subtitle: 'Динамометр · HX711',
    unit: 'Н',
    axisLabel: 'Сила, Н',
    color: Color(0xFF4CAF50),
    icon: Icons.fitness_center,
    minRange: 5.0,
    defaultDecimalPlaces: 2,
  ),
  lux(
    id: 'lux',
    title: 'Освещённость',
    subtitle: 'Люксметр · BH1750',
    unit: 'лк',
    axisLabel: 'Освещённость, лк',
    color: Color(0xFFFFC107),
    icon: Icons.light_mode,
    minRange: 100.0,
    defaultDecimalPlaces: 0,
  ),

  /// Модуль «Атом» — подключается при наличии счётчика Гейгера.
  radiation(
    id: 'radiation',
    title: 'Радиация',
    subtitle: 'Счётчик Гейгера · СБМ-20',
    unit: 'имп/мин',
    axisLabel: 'Радиация, имп/мин',
    color: Color(0xFF76FF03),
    icon: Icons.radar,
    minRange: 50.0,
    defaultDecimalPlaces: 0,
  );

  const SensorType({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.unit,
    required this.axisLabel,
    required this.color,
    required this.icon,
    required this.minRange,
    required this.defaultDecimalPlaces,
  });

  /// Строковый идентификатор (совместимость с HAL)
  final String id;

  /// Русское название для UI
  final String title;

  /// Подзаголовок с указанием чипа
  final String subtitle;

  /// Единица измерения
  final String unit;

  /// Подпись оси Y на графике
  final String axisLabel;

  /// Цвет датчика (графики, карточки, иконки)
  final Color color;

  /// Иконка Material
  final IconData icon;

  /// Минимальный диапазон оси Y (для стабильности графика)
  final double minRange;

  /// Знаки после запятой по умолчанию
  final int defaultDecimalPlaces;

  /// Найти по строковому ID
  static SensorType? fromId(String id) {
    for (final s in values) {
      if (s.id == id) return s;
    }
    return null;
  }
}
