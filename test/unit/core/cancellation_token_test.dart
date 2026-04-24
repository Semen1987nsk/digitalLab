import 'package:flutter_test/flutter_test.dart';
import 'package:digital_lab/core/cancellation_token.dart';

void main() {
  group('CancellationToken', () {
    test('should start uncancelled', () {
      final token = CancellationToken();
      expect(token.isCancelled, isFalse);
    });

    test('cancel should set isCancelled to true', () {
      final token = CancellationToken();
      token.cancel();
      expect(token.isCancelled, isTrue);
    });

    test('reset should clear cancellation', () {
      final token = CancellationToken();
      token.cancel();
      token.reset();
      expect(token.isCancelled, isFalse);
    });

    test('throwIfCancelled should throw when cancelled', () {
      final token = CancellationToken();
      token.cancel();
      expect(
        () => token.throwIfCancelled(),
        throwsA(isA<OperationCancelledException>()),
      );
    });

    test('throwIfCancelled should not throw when not cancelled', () {
      final token = CancellationToken();
      expect(() => token.throwIfCancelled(), returnsNormally);
    });

    test('multiple cancellations should be idempotent', () {
      final token = CancellationToken();
      token.cancel();
      token.cancel();
      token.cancel();
      expect(token.isCancelled, isTrue);
    });

    test('should prevent race condition in async operation', () async {
      final token = CancellationToken();
      bool operationCompleted = false;

      // Симулируем long-running операцию
      Future<void> longOperation() async {
        for (int i = 0; i < 100; i++) {
          if (token.isCancelled) {
            return;
          }
          await Future.delayed(const Duration(milliseconds: 1));
        }
        operationCompleted = true;
      }

      // Запускаем операцию
      final future = longOperation();

      // Отменяем через 10ms
      await Future.delayed(const Duration(milliseconds: 10));
      token.cancel();

      await future;

      // Операция должна прерваться до завершения
      expect(operationCompleted, isFalse);
    });
  });

  group('OperationCancelledException', () {
    test('should have default message', () {
      const exception = OperationCancelledException();
      expect(exception.toString(), equals('Операция отменена'));
    });

    test('should support custom message', () {
      const exception = OperationCancelledException('Custom message');
      expect(exception.toString(), equals('Custom message'));
    });
  });
}
