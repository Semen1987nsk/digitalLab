import 'package:flutter/material.dart';

enum SubjectArea {
  physics(
    id: 'physics',
    title: 'Физика',
    subtitle: 'Цифровая лаборатория',
    description:
        'Измерения, графики, эксперименты и работа с датчиками в реальном времени.',
    icon: Icons.science_rounded,
    accentColor: Color(0xFF00BCD4),
    statusLabel: 'Готово',
    isAvailableNow: true,
  ),
  chemistry(
    id: 'chemistry',
    title: 'Химия',
    subtitle: 'Предметная рабочая область',
    description:
        'Практикумы, наблюдения реакций, измерительные сценарии и цифровые лабораторные работы.',
    icon: Icons.biotech_rounded,
    accentColor: Color(0xFF8BC34A),
    statusLabel: 'Скоро',
    isAvailableNow: false,
  ),
  biology(
    id: 'biology',
    title: 'Биология',
    subtitle: 'Предметная рабочая область',
    description:
        'Исследования живых систем, микропрактикумы, измерения среды и демонстрационные режимы.',
    icon: Icons.eco_rounded,
    accentColor: Color(0xFF4CAF50),
    statusLabel: 'Скоро',
    isAvailableNow: false,
  ),
  mathematics(
    id: 'mathematics',
    title: 'Математика',
    subtitle: 'Интерактивная среда',
    description:
        'Визуализация функций, моделирование, анализ данных и цифровые задания для урока.',
    icon: Icons.functions_rounded,
    accentColor: Color(0xFFFFB300),
    statusLabel: 'Скоро',
    isAvailableNow: false,
  ),
  ecology(
    id: 'ecology',
    title: 'Экология',
    subtitle: 'Полевые и школьные исследования',
    description:
        'Мониторинг окружающей среды, работа с параметрами воздуха, воды, света и учебными экологическими кейсами.',
    icon: Icons.public_rounded,
    accentColor: Color(0xFF26A69A),
    statusLabel: 'Скоро',
    isAvailableNow: false,
  ),
  physiology(
    id: 'physiology',
    title: 'Физиология',
    subtitle: 'Наблюдение за показателями организма',
    description:
        'Учебные сценарии по дыханию, пульсу, реакции организма и анализу физиологических данных в безопасном школьном формате.',
    icon: Icons.monitor_heart_rounded,
    accentColor: Color(0xFFE57373),
    statusLabel: 'Скоро',
    isAvailableNow: false,
  ),
  geography(
    id: 'geography',
    title: 'География',
    subtitle: 'Измерения среды и наблюдения',
    description:
        'Исследование климата, давления, влажности, освещённости и природных процессов в классе и на выездных занятиях.',
    icon: Icons.travel_explore_rounded,
    accentColor: Color(0xFF64B5F6),
    statusLabel: 'Скоро',
    isAvailableNow: false,
  ),
  obzr(
    id: 'obzr',
    title: 'ОБЗР',
    subtitle: 'Безопасность и практические сценарии',
    description:
        'Тренировочные модули по безопасности, действиям в среде, измерению факторов риска и наглядным учебным ситуациям.',
    icon: Icons.shield_rounded,
    accentColor: Color(0xFF90A4AE),
    statusLabel: 'Скоро',
    isAvailableNow: false,
  );

  const SubjectArea({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.icon,
    required this.accentColor,
    required this.statusLabel,
    required this.isAvailableNow,
  });

  final String id;
  final String title;
  final String subtitle;
  final String description;
  final IconData icon;
  final Color accentColor;
  final String statusLabel;
  final bool isAvailableNow;
}
