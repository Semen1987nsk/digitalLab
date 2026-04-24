import 'package:flutter/material.dart';
import '../../themes/app_theme.dart';
import '../../widgets/page_preview_scaffold.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PagePreviewScaffold(
      title: 'Настройки',
      subtitle:
          'Раздел настроек объединит подключение, единицы измерения, режимы работы и сервисные параметры приложения.',
      icon: Icons.settings,
      accentColor: AppColors.textSecondary,
      statusLabel: 'Скоро: настройки системы',
      readinessNote:
          'Критичные действия уже доступны в рабочих экранах. Полный раздел настроек будет собран как спокойный и понятный центр управления приложением.',
      sections: [
        PagePreviewSection(
          title: 'Подключение и измерения',
          subtitle: 'Основные параметры работы датчиков и отображения данных.',
          items: [
            (Icons.usb, 'Выбор режима подключения: COM, BLE или симуляция.'),
            (Icons.straighten, 'Единицы измерения для температуры, давления и расстояния.'),
            (Icons.speed_outlined, 'Частота дискретизации и параметры эксперимента.'),
          ],
        ),
        PagePreviewSection(
          title: 'Сервис и приложение',
          subtitle: 'Помощь учителю, диагностика и сведения о системе.',
          items: [
            (Icons.dark_mode, 'Оформление, режимы интерфейса и адаптация под экран.'),
            (Icons.bug_report_outlined, 'Журналы и безопасная диагностика для сложных случаев.'),
            (Icons.info_outline, 'Версия приложения, лицензии и служебная информация.'),
          ],
        ),
      ],
    );
  }
}
