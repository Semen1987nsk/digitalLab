import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../domain/entities/sensor_data.dart';
import '../../../domain/math/lttb.dart';
import '../../blocs/experiment/experiment_provider.dart';
import '../../themes/app_theme.dart';
import '../../widgets/sensor_card/big_value_display.dart';

class ExperimentPage extends ConsumerStatefulWidget {
  final String sensorType;
  
  const ExperimentPage({super.key, required this.sensorType});

  @override
  ConsumerState<ExperimentPage> createState() => _ExperimentPageState();
}

class _ExperimentPageState extends ConsumerState<ExperimentPage> {
  // Режим отображения: 'chart', 'table', 'display'
  String _viewMode = 'chart';
  
  @override
  Widget build(BuildContext context) {
    final experimentState = ref.watch(experimentControllerProvider);
    final controller = ref.read(experimentControllerProvider.notifier);
    final connectionStatus = ref.watch(connectionStatusProvider);
    
    // Извлекаем значение расстояния из последнего пакета
    final lastPacket = experimentState.data.isNotEmpty 
        ? experimentState.data.last 
        : null;
    
    return Scaffold(
      appBar: AppBar(
        title: Text(_getSensorTitle()),
        actions: [
          // Переключатели режимов
          IconButton(
            icon: const Icon(Icons.monitor),
            tooltip: 'Табло',
            color: _viewMode == 'display' ? AppColors.primary : null,
            onPressed: () => setState(() => _viewMode = 'display'),
          ),
          IconButton(
            icon: const Icon(Icons.show_chart),
            tooltip: 'График',
            color: _viewMode == 'chart' ? AppColors.primary : null,
            onPressed: () => setState(() => _viewMode = 'chart'),
          ),
          IconButton(
            icon: const Icon(Icons.table_chart),
            tooltip: 'Таблица',
            color: _viewMode == 'table' ? AppColors.primary : null,
            onPressed: () => setState(() => _viewMode = 'table'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Column(
        children: [
          // Панель управления
          _ControlPanel(
            isRunning: experimentState.isRunning,
            measurementCount: experimentState.measurementCount,
            onStart: () => controller.start(),
            onStop: () => controller.stop(),
            onClear: () => controller.clear(),
            onCalibrate: () => controller.calibrate(widget.sensorType),
          ),
          
          // Основной контент
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _buildContent(experimentState, lastPacket),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildContent(ExperimentState state, SensorPacket? lastPacket) {
    switch (_viewMode) {
      case 'display':
        return BigValueDisplay(
          value: _getCurrentValue(lastPacket),
          unit: _getUnit(),
          label: _getSensorTitle(),
          color: _getSensorColor(),
        );
      
      case 'table':
        return _DataTable(
          data: state.data,
          sensorType: widget.sensorType,
        );
      
      case 'chart':
      default:
        return _RealtimeChart(
          data: state.data,
          sensorType: widget.sensorType,
          color: _getSensorColor(),
        );
    }
  }
  
  String _getSensorTitle() {
    switch (widget.sensorType) {
      case 'distance': return 'Расстояние';
      case 'temperature': return 'Температура';
      case 'voltage': return 'Напряжение';
      case 'acceleration': return 'Ускорение';
      default: return 'Датчик';
    }
  }
  
  String _getUnit() {
    switch (widget.sensorType) {
      case 'distance': return 'мм';
      case 'temperature': return '°C';
      case 'voltage': return 'В';
      case 'acceleration': return 'м/с²';
      default: return '';
    }
  }
  
  Color _getSensorColor() {
    switch (widget.sensorType) {
      case 'distance': return AppColors.distance;
      case 'temperature': return AppColors.temperature;
      case 'voltage': return AppColors.voltage;
      case 'acceleration': return AppColors.acceleration;
      default: return AppColors.primary;
    }
  }
  
  double _getCurrentValue(SensorPacket? packet) {
    if (packet == null) return 0;
    switch (widget.sensorType) {
      case 'distance': return packet.distanceMm ?? 0;
      case 'temperature': return packet.temperatureC ?? 0;
      case 'voltage': return packet.voltageV ?? 0;
      case 'acceleration': 
        final ax = packet.accelX ?? 0;
        final ay = packet.accelY ?? 0;
        final az = packet.accelZ ?? 0;
        return (ax * ax + ay * ay + az * az).abs();
      default: return 0;
    }
  }
}

/// Панель управления экспериментом
class _ControlPanel extends StatelessWidget {
  final bool isRunning;
  final int measurementCount;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onClear;
  final VoidCallback onCalibrate;
  
  const _ControlPanel({
    required this.isRunning,
    required this.measurementCount,
    required this.onStart,
    required this.onStop,
    required this.onClear,
    required this.onCalibrate,
  });
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Кнопка старт/стоп
          isRunning
              ? ElevatedButton.icon(
                  onPressed: onStop,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                  ),
                  icon: const Icon(Icons.stop),
                  label: const Text('Стоп'),
                )
              : ElevatedButton.icon(
                  onPressed: onStart,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Старт'),
                ),
          
          const SizedBox(width: 12),
          
          // Кнопка очистки
          OutlinedButton.icon(
            onPressed: isRunning ? null : onClear,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Очистить'),
          ),
          
          const SizedBox(width: 12),
          
          // Кнопка калибровки
          OutlinedButton.icon(
            onPressed: onCalibrate,
            icon: const Icon(Icons.tune),
            label: const Text('Ноль'),
          ),
          
          const Spacer(),
          
          // Счётчик измерений
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.data_usage, size: 20),
                const SizedBox(width: 8),
                Text(
                  '$measurementCount измерений',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// График в реальном времени с LTTB-прореживанием
class _RealtimeChart extends StatelessWidget {
  final List<SensorPacket> data;
  final String sensorType;
  final Color color;
  
  const _RealtimeChart({
    required this.data,
    required this.sensorType,
    required this.color,
  });
  
  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.show_chart, size: 64, color: AppColors.textHint),
            const SizedBox(height: 16),
            Text(
              'Нажмите "Старт" для начала измерений',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }
    
    // Преобразуем данные в точки для графика
    final points = data.map((p) {
      final y = _getValue(p);
      return DataPoint(p.timeSeconds, y);
    }).toList();
    
    // LTTB: прореживаем до 500 точек для производительности
    final downsampled = LTTB.downsample(points, 500);
    
    // Конвертируем в FlSpot для FL Chart
    final spots = downsampled.map((p) => FlSpot(p.x, p.y)).toList();
    
    // Находим границы для осей
    final minY = downsampled.map((p) => p.y).reduce((a, b) => a < b ? a : b);
    final maxY = downsampled.map((p) => p.y).reduce((a, b) => a > b ? a : b);
    final padding = (maxY - minY) * 0.1;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LineChart(
          LineChartData(
            gridData: FlGridData(
              show: true,
              drawVerticalLine: true,
              getDrawingHorizontalLine: (value) => FlLine(
                color: AppColors.textHint.withOpacity(0.2),
                strokeWidth: 1,
              ),
              getDrawingVerticalLine: (value) => FlLine(
                color: AppColors.textHint.withOpacity(0.2),
                strokeWidth: 1,
              ),
            ),
            titlesData: FlTitlesData(
              bottomTitles: AxisTitles(
                axisNameWidget: const Text('Время, с'),
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 30,
                  getTitlesWidget: (value, meta) => Text(
                    value.toStringAsFixed(1),
                    style: const TextStyle(fontSize: 10),
                  ),
                ),
              ),
              leftTitles: AxisTitles(
                axisNameWidget: Text(_getAxisLabel()),
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 50,
                  getTitlesWidget: (value, meta) => Text(
                    value.toStringAsFixed(1),
                    style: const TextStyle(fontSize: 10),
                  ),
                ),
              ),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            borderData: FlBorderData(
              show: true,
              border: Border.all(color: AppColors.textHint.withOpacity(0.3)),
            ),
            minY: minY - padding,
            maxY: maxY + padding,
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                curveSmoothness: 0.2,
                color: color,
                barWidth: 2,
                isStrokeCapRound: true,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  color: color.withOpacity(0.1),
                ),
              ),
            ],
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipItems: (spots) => spots.map((spot) {
                  return LineTooltipItem(
                    '${spot.y.toStringAsFixed(2)} ${_getUnit()}\n${spot.x.toStringAsFixed(2)} с',
                    TextStyle(color: color, fontWeight: FontWeight.bold),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  double _getValue(SensorPacket p) {
    switch (sensorType) {
      case 'distance': return p.distanceMm ?? 0;
      case 'temperature': return p.temperatureC ?? 0;
      case 'voltage': return p.voltageV ?? 0;
      case 'acceleration': 
        final ax = p.accelX ?? 0;
        final ay = p.accelY ?? 0;
        final az = p.accelZ ?? 0;
        return (ax * ax + ay * ay + az * az).abs();
      default: return 0;
    }
  }
  
  String _getAxisLabel() {
    switch (sensorType) {
      case 'distance': return 'Расстояние, мм';
      case 'temperature': return 'Температура, °C';
      case 'voltage': return 'Напряжение, В';
      case 'acceleration': return 'Ускорение, м/с²';
      default: return 'Значение';
    }
  }
  
  String _getUnit() {
    switch (sensorType) {
      case 'distance': return 'мм';
      case 'temperature': return '°C';
      case 'voltage': return 'В';
      case 'acceleration': return 'м/с²';
      default: return '';
    }
  }
}

/// Таблица данных
class _DataTable extends StatelessWidget {
  final List<SensorPacket> data;
  final String sensorType;
  
  const _DataTable({required this.data, required this.sensorType});
  
  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return Center(
        child: Text(
          'Нет данных',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    
    // Показываем последние 100 записей
    final displayData = data.length > 100 
        ? data.sublist(data.length - 100) 
        : data;
    
    return Card(
      child: SingleChildScrollView(
        child: DataTable(
          columns: const [
            DataColumn(label: Text('№')),
            DataColumn(label: Text('Время, с')),
            DataColumn(label: Text('Значение')),
          ],
          rows: displayData.asMap().entries.map((entry) {
            final index = data.length - displayData.length + entry.key + 1;
            final packet = entry.value;
            return DataRow(
              cells: [
                DataCell(Text('$index')),
                DataCell(Text(packet.timeSeconds.toStringAsFixed(2))),
                DataCell(Text('${_getValue(packet).toStringAsFixed(2)} ${_getUnit()}')),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
  
  double _getValue(SensorPacket p) {
    switch (sensorType) {
      case 'distance': return p.distanceMm ?? 0;
      case 'temperature': return p.temperatureC ?? 0;
      case 'voltage': return p.voltageV ?? 0;
      case 'acceleration': 
        final ax = p.accelX ?? 0;
        final ay = p.accelY ?? 0;
        final az = p.accelZ ?? 0;
        return (ax * ax + ay * ay + az * az).abs();
      default: return 0;
    }
  }
  
  String _getUnit() {
    switch (sensorType) {
      case 'distance': return 'мм';
      case 'temperature': return '°C';
      case 'voltage': return 'В';
      case 'acceleration': return 'м/с²';
      default: return '';
    }
  }
}
