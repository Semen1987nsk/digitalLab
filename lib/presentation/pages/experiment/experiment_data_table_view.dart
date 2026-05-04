import 'package:flutter/material.dart';

import '../../../domain/entities/calibration_data.dart';
import '../../../domain/entities/sensor_data.dart';
import '../../../domain/entities/sensor_type.dart';
import '../../../domain/utils/sensor_utils.dart';
import '../../themes/app_theme.dart';

/// Табличный режим просмотра эксперимента.
///
/// Показывает последние 500 строк через `ListView.builder` с фиксированной
/// высотой строки → O(1) layout, рендерится только видимая часть. На школьном
/// Celeron это ~10× быстрее `DataTable`, который рендерит все строки сразу.
class DataTableView extends StatelessWidget {
  final List<SensorPacket> data;
  final SensorType sensor;
  final VoltageCalibration? voltageCalibration;

  const DataTableView({
    super.key,
    required this.data,
    required this.sensor,
    this.voltageCalibration,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: sensor.color.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: sensor.color.withValues(alpha: 0.30),
                  ),
                ),
                child: Icon(
                  Icons.table_rows_outlined,
                  size: 32,
                  color: sensor.color.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Таблица пуста',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Нажмите «Старт», чтобы начать запись. Значения появятся здесь по мере поступления данных.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  height: 1.4,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final display = data.length > 500 ? data.sublist(data.length - 500) : data;
    final baseIndex = data.length - display.length;

    return Card(
      child: Column(
        children: [
          Container(
            color: AppColors.surfaceLight,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                const SizedBox(
                    width: 48,
                    child: Text('№',
                        style: TextStyle(fontWeight: FontWeight.w600))),
                const SizedBox(
                    width: 100,
                    child: Text('Время, с',
                        style: TextStyle(fontWeight: FontWeight.w600))),
                Expanded(
                  child: Text(
                    '${sensor.title}, ${sensor.unit}',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: sensor.color),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.cardBorder),
          Expanded(
            child: ListView.builder(
              itemCount: display.length,
              itemExtent: 40,
              reverse: true,
              itemBuilder: (context, index) {
                final dataIdx = display.length - 1 - index;
                final p = display[dataIdx];
                final v = SensorUtils.getCalibratedValue(p, sensor,
                    voltageCalibration: voltageCalibration);
                final rowNum = baseIndex + dataIdx + 1;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 48,
                        child: Text(
                          '$rowNum',
                          style: const TextStyle(
                              fontSize: 13, color: AppColors.textHint),
                        ),
                      ),
                      SizedBox(
                        width: 100,
                        child: Text(
                          p.timeSeconds.toStringAsFixed(2),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          v != null ? SensorUtils.formatValue(v, sensor) : '—',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: sensor.color,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
