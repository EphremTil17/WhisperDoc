import 'dart:async';
import 'package:logger/logger.dart';
import 'package:flutter_client/services/transport/websocket_service.dart';

class LoggingService {
  static final LoggingService _instance = LoggingService._internal();

  final Logger _logger = Logger(printer: _CompactPrinter());
  WebSocketService? _webSocketService;

  // Log buffer for UI consumption (last 200 entries)
  final List<LogEntry> _logBuffer = [];
  static const int _maxBufferSize = 200;

  final StreamController<LogEntry> _logStreamController =
      StreamController<LogEntry>.broadcast();

  Stream<LogEntry> get onLog => _logStreamController.stream;
  List<LogEntry> get logs => List.unmodifiable(_logBuffer);

  factory LoggingService() => _instance;

  LoggingService._internal();

  void attachWebSocket(WebSocketService service) {
    _webSocketService = service;
  }

  void info(String message, {bool sendToServer = false}) {
    _logger.i(message);
    _addToBuffer('INFO', message);
    if (sendToServer) _sendLogToServer('INFO', message);
  }

  void warning(String message, {bool sendToServer = false}) {
    _logger.w(message);
    _addToBuffer('WARN', message);
    if (sendToServer) _sendLogToServer('WARNING', message);
  }

  void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    bool sendToServer = false,
  }) {
    _logger.e(message, error: error, stackTrace: stackTrace);
    _addToBuffer('ERROR', '$message${error != null ? ' - $error' : ''}');
    if (sendToServer) _sendLogToServer('ERROR', '$message ${error ?? ''}');
  }

  void debug(String message, {bool sendToServer = false}) {
    _logger.d(message);
    _addToBuffer('DEBUG', message);
    if (sendToServer) _sendLogToServer('DEBUG', message);
  }

  void dispose() {
    unawaited(_logStreamController.close());
  }

  void _addToBuffer(String level, String message) {
    final entry = LogEntry(
      timestamp: DateTime.now().toUtc(),
      level: level,
      message: message,
    );
    _logBuffer.add(entry);
    if (_logBuffer.length > _maxBufferSize) {
      _logBuffer.removeAt(0);
    }
    _logStreamController.add(entry);
  }

  void _sendLogToServer(String level, String message) {
    final ws = _webSocketService;
    if (ws != null && ws.status == ConnectionStatus.connected) {
      try {
        ws.sendLog(level, message);
      } catch (e) {
        // ignore: avoid_print - logging fallback intentionally uses stdout
        print('Failed to send log to server: $e');
      }
    }
  }
}

/// Log entry for UI display
class LogEntry {
  final DateTime timestamp;
  final String level;
  final String message;

  static const int _levelColumnWidth = 5;
  static const int _twoDigitWidth = 2;

  String get formatted =>
      '${_formatTime(timestamp)} | ${level.padRight(_levelColumnWidth)} | $message';

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
  });

  static String _formatTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(_twoDigitWidth, '0')}:'
      '${dt.minute.toString().padLeft(_twoDigitWidth, '0')}:'
      '${dt.second.toString().padLeft(_twoDigitWidth, '0')}';
}

/// Compact single-line printer with ANSI colors matching backend format
class _CompactPrinter extends LogPrinter {
  static const int _twoDigitWidth = 2;

  // ANSI color codes
  static const _reset = '\x1B[0m';
  static const _gray = '\x1B[90m';
  static const _cyan = '\x1B[36m';
  static const _yellow = '\x1B[33m';
  static const _red = '\x1B[31m';
  static const _white = '\x1B[37m';

  @override
  List<String> log(LogEvent event) {
    final levelStr = _levelString(event.level);
    final levelColor = _levelColor(event.level);
    final time = _formatTime(event.time);
    final message = event.message;

    // Format: gray_time | colored_level | white_message
    return [
      '$_gray$time$_reset | $levelColor$levelStr$_reset | $_white$message$_reset',
    ];
  }

  String _levelString(Level level) {
    switch (level) {
      case Level.debug:
        return 'DEBUG';
      case Level.info:
        return 'INFO ';
      case Level.warning:
        return 'WARN ';
      case Level.error:
        return 'ERROR';
      default:
        return 'LOG  ';
    }
  }

  String _levelColor(Level level) {
    switch (level) {
      case Level.debug:
        return _gray;
      case Level.info:
        return _cyan;
      case Level.warning:
        return _yellow;
      case Level.error:
        return _red;
      default:
        return _white;
    }
  }

  String _formatTime(DateTime dt) {
    final utc = dt.toUtc();

    return '${utc.year}-${utc.month.toString().padLeft(_twoDigitWidth, '0')}-${utc.day.toString().padLeft(_twoDigitWidth, '0')} '
        '${utc.hour.toString().padLeft(_twoDigitWidth, '0')}:'
        '${utc.minute.toString().padLeft(_twoDigitWidth, '0')}:'
        '${utc.second.toString().padLeft(_twoDigitWidth, '0')}';
  }
}
