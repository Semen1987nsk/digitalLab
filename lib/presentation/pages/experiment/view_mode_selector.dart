import 'package:flutter/material.dart';

import '../../themes/app_theme.dart';

/// Режим отображения данных эксперимента.
///
/// • [display] — крупное число для проектора
/// • [chart] — Y(t) график в реальном времени с LTTB-downsampling
/// • [table] — числовые данные построчно
enum ViewMode { display, chart, table }

/// Сегментный переключатель режимов в AppBar страницы эксперимента.
///
/// Vernier/PASCO-style: всегда видны три варианта, активный подсвечен
/// цветом датчика.
class ViewModeSelector extends StatelessWidget {
  final ViewMode mode;
  final Color color;
  final ValueChanged<ViewMode> onChanged;

  const ViewModeSelector({
    super.key,
    required this.mode,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _modeButton(ViewMode.display, Icons.monitor, 'Табло'),
          _modeButton(ViewMode.chart, Icons.show_chart, 'График'),
          _modeButton(ViewMode.table, Icons.table_rows_outlined, 'Таблица'),
        ],
      ),
    );
  }

  Widget _modeButton(ViewMode m, IconData icon, String tooltip) {
    final isSelected = mode == m;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onChanged(m),
        borderRadius: BorderRadius.circular(11),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color:
                isSelected ? color.withValues(alpha: 0.16) : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected ? color : AppColors.textHint,
              ),
              const SizedBox(width: 6),
              Text(
                tooltip,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  color: isSelected ? color : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
