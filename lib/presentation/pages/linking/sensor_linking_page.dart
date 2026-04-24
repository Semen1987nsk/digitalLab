import 'package:flutter/material.dart';
import '../../themes/app_theme.dart';
import '../../widgets/page_preview_scaffold.dart';

class SensorLinkingPage extends StatelessWidget {
  const SensorLinkingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PagePreviewScaffold(
      title: 'Связка датчиков',
      subtitle:
          'Этот раздел станет одним из главных преимуществ Labosfera: совместные графики, X-Y режимы и сравнение нескольких параметров в одном опыте.',
      icon: Icons.cable,
      accentColor: AppColors.version360,
      statusLabel: 'Скоро: multi-sensor анализ',
      readinessNote:
          'Функция проектируется как отдельный сильный инструмент для лабораторных работ. Наша цель — сделать её мощной, но понятной даже для школьного сценария.',
      sections: [
        PagePreviewSection(
          title: 'Сценарии экспериментов',
          subtitle: 'Здесь будут собраны самые ценные режимы для школьной физики.',
          items: [
            (Icons.stacked_line_chart, 'Два параметра на одном графике с согласованными шкалами.'),
            (Icons.align_vertical_bottom, 'Двойная ось Y для сравнения разных величин.'),
            (Icons.show_chart, 'X-Y параметрический режим для ВАХ, PV и других зависимостей.'),
          ],
        ),
        PagePreviewSection(
          title: 'Инструменты анализа',
          subtitle: 'Раздел готовится как настоящий исследовательский инструмент, а не просто красивая надстройка.',
          items: [
            (Icons.layers_outlined, 'Наложение прошлых экспериментов на текущие данные.'),
            (Icons.draw_outlined, 'Инструмент «Предсказание» для сравнения гипотезы и результата.'),
            (Icons.hub_outlined, 'Работа сразу с несколькими устройствами и общим экспериментом.'),
          ],
        ),
      ],
    );
  }
}
