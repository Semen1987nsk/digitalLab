/// Форматирование физических величин с автоматическим выбором единиц
///
/// Соответствует:
/// - Международной системе СИ
/// - Школьным стандартам РФ (ФГОС)
/// - Лучшим практикам (Vernier, PASCO, Phywe)
library;

/// Форматирует расстояние с автоматическим выбором единиц
///
/// Примеры:
/// - 5 мм → "5.0 мм"
/// - 50 мм → "5.0 см"
/// - 1720 мм → "172.0 см" или "1.72 м"
/// - 15000 мм → "15.0 м"
class DistanceFormatter {
  /// Минимальное значение для показа в см (мм)
  static const double _cmThreshold = 10.0; // 1 см

  /// Минимальное значение для показа в м (мм)
  static const double _mThreshold = 1000.0; // 1 м

  /// Форматировать расстояние (входные данные в мм)
  static String format(double valueMm, {int decimals = 1}) {
    if (valueMm.abs() >= _mThreshold) {
      // Показываем в метрах
      final valueM = valueMm / 1000.0;
      return '${valueM.toStringAsFixed(decimals)} м';
    } else if (valueMm.abs() >= _cmThreshold) {
      // Показываем в сантиметрах
      final valueCm = valueMm / 10.0;
      return '${valueCm.toStringAsFixed(decimals)} см';
    } else {
      // Показываем в миллиметрах
      return '${valueMm.toStringAsFixed(decimals)} мм';
    }
  }

  /// Получить значение в указанных единицах
  static double convert(double valueMm, DistanceUnit unit) {
    switch (unit) {
      case DistanceUnit.mm:
        return valueMm;
      case DistanceUnit.cm:
        return valueMm / 10.0;
      case DistanceUnit.m:
        return valueMm / 1000.0;
    }
  }

  /// Получить название единицы измерения
  static String unitName(DistanceUnit unit) {
    switch (unit) {
      case DistanceUnit.mm:
        return 'мм';
      case DistanceUnit.cm:
        return 'см';
      case DistanceUnit.m:
        return 'м';
    }
  }

  /// Автоматически определить лучшую единицу для диапазона значений
  static DistanceUnit bestUnit(double minMm, double maxMm) {
    final range = (maxMm - minMm).abs();
    final maxAbs = maxMm.abs();

    if (maxAbs >= _mThreshold || range >= _mThreshold) {
      return DistanceUnit.m;
    } else if (maxAbs >= _cmThreshold || range >= _cmThreshold) {
      return DistanceUnit.cm;
    } else {
      return DistanceUnit.mm;
    }
  }
}

/// Единицы измерения расстояния
enum DistanceUnit { mm, cm, m }

/// Форматирование температуры
class TemperatureFormatter {
  static String format(double valueCelsius, {int decimals = 1}) {
    return '${valueCelsius.toStringAsFixed(decimals)} °C';
  }

  static double toKelvin(double celsius) => celsius + 273.15;
  static double toFahrenheit(double celsius) => celsius * 9 / 5 + 32;
}

/// Форматирование напряжения
class VoltageFormatter {
  static String format(double valueV, {int decimals = 2}) {
    if (valueV.abs() >= 1.0) {
      return '${valueV.toStringAsFixed(decimals)} В';
    } else {
      final mV = valueV * 1000;
      return '${mV.toStringAsFixed(decimals ~/ 2)} мВ';
    }
  }
}

/// Форматирование силы тока
class CurrentFormatter {
  static String format(double valueA, {int decimals = 3}) {
    if (valueA.abs() >= 1.0) {
      return '${valueA.toStringAsFixed(decimals.clamp(0, 10))} А';
    } else if (valueA.abs() >= 0.001) {
      final mA = valueA * 1000;
      return '${mA.toStringAsFixed((decimals - 1).clamp(0, 10))} мА';
    } else {
      final uA = valueA * 1000000;
      return '${uA.toStringAsFixed((decimals - 2).clamp(0, 10))} мкА';
    }
  }
}

/// Форматирование давления
class PressureFormatter {
  static String format(double valuePa, {int decimals = 1}) {
    if (valuePa >= 1000) {
      final kPa = valuePa / 1000;
      return '${kPa.toStringAsFixed(decimals)} кПа';
    } else {
      return '${valuePa.toStringAsFixed(decimals)} Па';
    }
  }

  /// Конвертация в мм рт.ст. (для барометра)
  static String formatMmHg(double valuePa, {int decimals = 1}) {
    final mmHg = valuePa / 133.322;
    return '${mmHg.toStringAsFixed(decimals)} мм рт.ст.';
  }

  /// Конвертация в атмосферы
  static String formatAtm(double valuePa, {int decimals = 3}) {
    final atm = valuePa / 101325;
    return '${atm.toStringAsFixed(decimals)} атм';
  }
}

/// Форматирование времени
class TimeFormatter {
  static String format(int timestampMs) {
    if (timestampMs < 1000) {
      return '$timestampMs мс';
    } else if (timestampMs < 60000) {
      final seconds = timestampMs / 1000.0;
      return '${seconds.toStringAsFixed(1)} с';
    } else {
      final minutes = timestampMs ~/ 60000;
      final seconds = (timestampMs % 60000) / 1000.0;
      return '$minutes:${seconds.toStringAsFixed(1).padLeft(4, '0')}';
    }
  }

  /// Для оси X графика (только секунды)
  static String formatAxisX(int timestampMs) {
    final seconds = timestampMs / 1000.0;
    return seconds.toStringAsFixed(1);
  }
}

/// Универсальный форматтер для любой физической величины
class PhysicsFormatter {
  static String format(double value, String sensorType) {
    switch (sensorType.toLowerCase()) {
      case 'distance':
      case 'расстояние':
        return DistanceFormatter.format(value);
      case 'temperature':
      case 'температура':
        return TemperatureFormatter.format(value);
      case 'voltage':
      case 'напряжение':
        return VoltageFormatter.format(value);
      case 'current':
      case 'ток':
        return CurrentFormatter.format(value);
      case 'pressure':
      case 'давление':
        return PressureFormatter.format(value);
      default:
        return value.toStringAsFixed(2);
    }
  }
}
