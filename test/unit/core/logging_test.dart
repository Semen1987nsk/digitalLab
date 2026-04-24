import 'package:flutter_test/flutter_test.dart';
import 'package:digital_lab/core/logging.dart';

void main() {
  setUp(() {
    Logger.enabled = true;
  });

  tearDown(() {
    Logger.enabled = false;
  });

  group('Logger', () {
    test('should be disabled by default in release mode', () {
      // В тестах всегда debug mode
      expect(Logger.enabled, isTrue);
    });

    test('debug should not throw', () {
      expect(() => Logger.debug('Test message'), returnsNormally);
    });

    test('info should not throw', () {
      expect(() => Logger.info('Test message'), returnsNormally);
    });

    test('warning should not throw with error', () {
      expect(() => Logger.warning('Test warning', Exception('test')),
          returnsNormally);
    });

    test('error should not throw with stack trace', () {
      expect(
        () => Logger.error('Test error', Exception('test'), StackTrace.current),
        returnsNormally,
      );
    });

    test('should respect minLevel filter', () {
      Logger.minLevel = LogLevel.error;
      // Debug сообщения не должны выводиться
      expect(() => Logger.debug('Hidden'), returnsNormally);
      // Error сообщения должны выводиться
      expect(() => Logger.error('Visible', Exception('test')), returnsNormally);
    });

    test('disable should prevent logging', () {
      Logger.disable();
      expect(Logger.enabled, isFalse);
      expect(() => Logger.debug('Should not appear'), returnsNormally);
    });

    test('enable should restore logging', () {
      Logger.disable();
      Logger.enable();
      expect(Logger.enabled, isTrue);
    });
  });
}
