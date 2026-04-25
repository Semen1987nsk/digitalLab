import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistent theme mode (system/light/dark).
///
/// Хранится в SharedPreferences под ключом [_prefsKey]. По умолчанию
/// — [ThemeMode.dark] (основной сценарий: школьные классы с обычным
/// освещением + поддержка СанПиН по нагрузке на зрение).
class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.dark) {
    _load();
  }

  static const _prefsKey = 'app.themeMode';

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      switch (raw) {
        case 'light':
          state = ThemeMode.light;
        case 'dark':
          state = ThemeMode.dark;
        case 'system':
          state = ThemeMode.system;
      }
    } catch (_) {
      // ignore — остаёмся на default
    }
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, mode.name);
    } catch (_) {
      // ignore
    }
  }
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier();
});
