/// Токен отмены для безопасного прерывания асинхронных операций
///
/// Используется для предотвращения race conditions при:
/// - Одновременном connect() и dispose()
/// - Нескольких параллельных scan операциях
/// - Отмене long-running операций
///
/// Pattern (как CancellationToken в C#):
/// ```dart
/// final token = CancellationToken();
///
/// Future<void> longOperation() async {
///   for (int i = 0; i < 1000; i++) {
///     if (token.isCancelled) {
///       return; // Прерываем операцию
///     }
///     await doWork();
///   }
/// }
///
/// // В другом месте:
/// token.cancel();
/// ```
class CancellationToken {
  bool _isCancelled = false;

  /// Проверка: отменена ли операция
  bool get isCancelled => _isCancelled;

  /// Отменить операцию
  void cancel() {
    _isCancelled = true;
  }

  /// Сбросить токен (для повторного использования)
  void reset() {
    _isCancelled = false;
  }

  /// Выбросить исключение если отменено
  void throwIfCancelled() {
    if (_isCancelled) {
      throw const OperationCancelledException();
    }
  }
}

/// Исключение при отмене операции
class OperationCancelledException implements Exception {
  final String? message;
  const OperationCancelledException([this.message]);

  @override
  String toString() => message ?? 'Операция отменена';
}
