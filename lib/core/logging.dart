import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Уровни логирования
enum LogLevel { debug, info, warning, error }

/// Система логирования для production-ready приложения
///
/// **Debug mode**: структурированный вывод через `debugPrint`.
/// **Release mode**: запись в файл `labosfera.log` с ротацией (макс. 2 MB).
///
/// Использование:
/// ```dart
/// await Logger.init();          // вызвать один раз при старте
/// Logger.debug('USB HAL: порт открыт');
/// Logger.error('Ошибка подключения', error, stackTrace);
/// ```
class Logger {
  /// Включено ли логирование (теперь **true** и в release)
  static bool enabled = true;

  /// Минимальный уровень для вывода
  static LogLevel minLevel = kDebugMode ? LogLevel.debug : LogLevel.warning;

  /// Максимальный размер лог-файла перед ротацией (2 MB)
  static const int _maxLogBytes = 2 * 1024 * 1024;

  /// Файл лога (инициализируется через [init])
  static File? _logFile;

  /// Буфер для отложенных записей до init()
  static final List<String> _pendingLines = [];

  /// Инициализация файлового логгера.
  ///
  /// Вызывается один раз в `main()`. До вызова `init()` все сообщения
  /// буферизируются и сбрасываются в файл после инициализации.
  static Future<void> init() async {
    try {
      final dir = await getApplicationSupportDirectory();
      _logFile = File('${dir.path}${Platform.pathSeparator}labosfera.log');

      // Ротация: если файл > 2 MB, переименовываем в .old и начинаем новый
      if (await _logFile!.exists()) {
        final stat = await _logFile!.stat();
        if (stat.size > _maxLogBytes) {
          final oldFile = File('${_logFile!.path}.old');
          if (await oldFile.exists()) await oldFile.delete();
          await _logFile!.rename(oldFile.path);
          _logFile = File('${dir.path}${Platform.pathSeparator}labosfera.log');
        }
      }

      // Сброс буфера
      if (_pendingLines.isNotEmpty) {
        final sink = _logFile!.openWrite(mode: FileMode.append);
        for (final line in _pendingLines) {
          sink.writeln(line);
        }
        await sink.flush();
        await sink.close();
        _pendingLines.clear();
      }
    } catch (e) {
      // Если файловая система недоступна — fallback на debugPrint
      debugPrint('Logger.init failed: $e');
      _logFile = null;
    }
  }

  /// Отладочное сообщение (детали работы)
  static void debug(String message, [Object? error, StackTrace? stackTrace]) {
    _log(LogLevel.debug, message, error, stackTrace);
  }

  /// Информационное сообщение (важные события)
  static void info(String message) {
    _log(LogLevel.info, message);
  }

  /// Предупреждение (потенциальная проблема)
  static void warning(String message, [Object? error]) {
    _log(LogLevel.warning, message, error);
  }

  /// Ошибка (требует внимания)
  static void error(String message, Object? error, [StackTrace? stackTrace]) {
    _log(LogLevel.error, message, error, stackTrace);
  }

  static void _log(
    LogLevel level,
    String message, [
    Object? error,
    StackTrace? trace,
  ]) {
    if (!enabled || level.index < minLevel.index) return;

    final prefix = switch (level) {
      LogLevel.debug => '🔍',
      LogLevel.info => 'ℹ️',
      LogLevel.warning => '⚠️',
      LogLevel.error => '🔴',
    };

    final timestamp = DateTime.now().toIso8601String().substring(11, 23);
    final buf = StringBuffer('$prefix [$timestamp] $message');

    if (error != null) {
      buf.write('\n  ╰─ Error: $error');
    }

    if (trace != null && level == LogLevel.error) {
      // Показываем только первые 5 строк стека
      final lines = trace.toString().split('\n').take(5).join('\n');
      buf.write('\n  ╰─ Stack:\n$lines');
    }

    final formatted = buf.toString();

    // Debug mode: всегда пишем в консоль
    if (kDebugMode) {
      debugPrint(formatted);
    }

    // Release mode (и debug тоже): пишем в файл
    _writeToFile(formatted);
  }

  /// Асинхронная запись в файл (fire-and-forget для производительности).
  static void _writeToFile(String line) {
    final file = _logFile;
    if (file == null) {
      // init() ещё не вызван — буферизируем
      if (_pendingLines.length < 200) {
        _pendingLines.add(line);
      }
      return;
    }

    // Fire-and-forget: не ждём завершения I/O
    file.writeAsString('$line\n', mode: FileMode.append).catchError((e) {
      // Ошибка записи — ничего не делаем, чтобы не уронить приложение
      return file;
    });
  }

  /// Путь к текущему лог-файлу (для диагностики / экспорта).
  static String? get logFilePath => _logFile?.path;

  /// Временно отключить логирование (для performance-critical секций)
  static void disable() => enabled = false;

  /// Включить логирование
  static void enable() => enabled = true;
}
