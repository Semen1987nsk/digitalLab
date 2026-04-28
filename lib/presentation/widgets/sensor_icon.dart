import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../domain/entities/sensor_type.dart';

/// Кастомные иконки физических величин.
///
/// Заменяют общие Material-иконки (Icons.bolt, Icons.thermostat и т. д.)
/// на стилизованные «символ величины + рамка» в едином графическом языке.
/// Это усиливает айдентику продукта в нише, где конкуренты (Vernier,
/// PASCO) используют физические символы, а не general-purpose иконки.
///
/// Все SVG используют currentColor — `color` параметр перекрашивает иконку.
class SensorIcon extends StatelessWidget {
  const SensorIcon({
    super.key,
    required this.sensor,
    this.size = 24,
    this.color,
  });

  final SensorType sensor;
  final double size;

  /// Если null — берётся `sensor.color`.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? sensor.color;
    return SvgPicture.asset(
      'assets/icons/sensors/${sensor.id}.svg',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(tint, BlendMode.srcIn),
      semanticsLabel: sensor.title,
    );
  }
}
