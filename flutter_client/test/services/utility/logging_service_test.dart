import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_client/services/utility/logging_service.dart';

void main() {
  group('LogEntry', () {
    test('formatted returns correct format', () {
      final entry = LogEntry(
        timestamp: DateTime(2026, 1, 10, 14, 30, 45),
        level: 'INFO',
        message: 'Test message',
      );

      expect(entry.formatted, equals('14:30:45 | INFO  | Test message'));
    });

    test('level is padded correctly', () {
      final entry = LogEntry(
        timestamp: DateTime(2026, 1, 10, 14, 30, 45),
        level: 'WARN',
        message: 'Warning',
      );

      // WARN should be padded to 5 chars
      expect(entry.formatted, contains('WARN '));
    });
  });

  group('LoggingService Buffer', () {
    test('logs getter returns list of entries', () {
      final service = LoggingService();

      // Clear any existing logs first by creating entries
      // Note: LoggingService is a singleton, so we work with what's there
      final initialCount = service.logs.length;

      service.info('Test log entry');

      expect(service.logs.length, greaterThan(initialCount));
    });

    test('logs list is unmodifiable', () {
      final service = LoggingService();
      final logs = service.logs;

      expect(
        () => (logs as List).add(
          LogEntry(
            timestamp: DateTime.now(),
            level: 'TEST',
            message: 'Should fail',
          ),
        ),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('different log levels work correctly', () {
      final service = LoggingService();
      final initialCount = service.logs.length;

      service.info('Info message');
      service.warning('Warning message');
      service.error('Error message');
      service.debug('Debug message');

      expect(service.logs.length, equals(initialCount + 4));
    });

    test('log entries have correct levels', () {
      final service = LoggingService();

      service.info('Test info');
      expect(service.logs.last.level, equals('INFO'));

      service.warning('Test warning');
      expect(service.logs.last.level, equals('WARN'));

      service.error('Test error');
      expect(service.logs.last.level, equals('ERROR'));

      service.debug('Test debug');
      expect(service.logs.last.level, equals('DEBUG'));
    });
  });

  group('LoggingService Stream', () {
    test('onLog stream emits entries', () async {
      final service = LoggingService();

      // Listen for the next entry
      final future = service.onLog.first;

      service.info('Stream test');

      final entry = await future;
      expect(entry.message, equals('Stream test'));
    });
  });
}
