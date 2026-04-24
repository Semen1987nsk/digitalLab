import 'package:flutter/material.dart';
import '../../themes/app_theme.dart';
import '../../widgets/page_preview_scaffold.dart';

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PagePreviewScaffold(
      title: 'История',
      subtitle:
          'Здесь появятся сохранённые эксперименты, повторный просмотр графиков и экспорт результатов для отчётов.',
      icon: Icons.history,
      accentColor: AppColors.primary,
      statusLabel: 'Скоро: журнал экспериментов',
      readinessNote:
          'Пока основная работа идёт через экран эксперимента. История будет оформлена как удобный архив для учителя и ученика, а не просто список файлов.',
      sections: [
        PagePreviewSection(
          title: 'Что появится первым',
          subtitle: 'Базовые функции для хранения и повторного использования опытов.',
          items: [
            (Icons.list_alt, 'Список сохранённых экспериментов с понятными карточками и датами.'),
            (Icons.filter_list, 'Фильтр по дате, датчику и лабораторной работе.'),
            (Icons.visibility_outlined, 'Быстрый повторный просмотр графика и измерений.'),
          ],
        ),
        PagePreviewSection(
          title: 'Для урока и отчётов',
          subtitle: 'Раздел будет полезен не только для хранения, но и для анализа.',
          items: [
            (Icons.layers_outlined, 'Наложение прошлых опытов на текущий эксперимент.'),
            (Icons.file_download_outlined, 'Экспорт в CSV, XLSX и PDF для учителя и ученика.'),
            (Icons.share_outlined, 'Подготовка данных к отчёту и повторной демонстрации на уроке.'),
          ],
        ),
      ],
    );
  }
}
