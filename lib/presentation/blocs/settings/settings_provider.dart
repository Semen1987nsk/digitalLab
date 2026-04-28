import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════════════════════
//  SETTINGS PROVIDER — пользовательские настройки приложения.
//
//  Тема живёт отдельно (themeModeProvider), чтобы не пересобирать
//  весь settings tree при смене темы. Здесь — только единицы и
//  частота дискретизации по умолчанию.
//
//  Хранится в SharedPreferences, переживает перезапуск.
// ═══════════════════════════════════════════════════════════════

enum TemperatureUnit { celsius, fahrenheit, kelvin }

enum PressureUnit { pascal, kilopascal, mmHg }

enum DistanceUnit { mm, cm, m }

class AppSettings {
  final TemperatureUnit temperatureUnit;
  final PressureUnit pressureUnit;
  final DistanceUnit distanceUnit;
  final int defaultSampleRateHz;

  const AppSettings({
    this.temperatureUnit = TemperatureUnit.celsius,
    this.pressureUnit = PressureUnit.pascal,
    this.distanceUnit = DistanceUnit.mm,
    this.defaultSampleRateHz = 10,
  });

  AppSettings copyWith({
    TemperatureUnit? temperatureUnit,
    PressureUnit? pressureUnit,
    DistanceUnit? distanceUnit,
    int? defaultSampleRateHz,
  }) =>
      AppSettings(
        temperatureUnit: temperatureUnit ?? this.temperatureUnit,
        pressureUnit: pressureUnit ?? this.pressureUnit,
        distanceUnit: distanceUnit ?? this.distanceUnit,
        defaultSampleRateHz: defaultSampleRateHz ?? this.defaultSampleRateHz,
      );
}

class SettingsController extends StateNotifier<AppSettings> {
  SettingsController() : super(const AppSettings()) {
    _load();
  }

  static const _kTempUnit = 'settings.temperatureUnit';
  static const _kPresUnit = 'settings.pressureUnit';
  static const _kDistUnit = 'settings.distanceUnit';
  static const _kSampleRate = 'settings.defaultSampleRateHz';

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = AppSettings(
        temperatureUnit: TemperatureUnit.values[(prefs.getInt(_kTempUnit) ?? 0)
            .clamp(0, TemperatureUnit.values.length - 1)],
        pressureUnit: PressureUnit.values[(prefs.getInt(_kPresUnit) ?? 0)
            .clamp(0, PressureUnit.values.length - 1)],
        distanceUnit: DistanceUnit.values[(prefs.getInt(_kDistUnit) ?? 0)
            .clamp(0, DistanceUnit.values.length - 1)],
        defaultSampleRateHz: (prefs.getInt(_kSampleRate) ?? 10).clamp(1, 1000),
      );
    } catch (_) {
      // На повреждённом профиле остаёмся с default state.
    }
  }

  Future<void> setTemperatureUnit(TemperatureUnit unit) async {
    state = state.copyWith(temperatureUnit: unit);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kTempUnit, unit.index);
  }

  Future<void> setPressureUnit(PressureUnit unit) async {
    state = state.copyWith(pressureUnit: unit);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kPresUnit, unit.index);
  }

  Future<void> setDistanceUnit(DistanceUnit unit) async {
    state = state.copyWith(distanceUnit: unit);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kDistUnit, unit.index);
  }

  Future<void> setDefaultSampleRate(int hz) async {
    state = state.copyWith(defaultSampleRateHz: hz.clamp(1, 1000));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kSampleRate, state.defaultSampleRateHz);
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsController, AppSettings>((ref) {
  return SettingsController();
});
