import 'package:logger/logger.dart';
import '../../core/services/websocket_service.dart';

class LoggingService {
  static final LoggingService _instance = LoggingService._internal();

  factory LoggingService() => _instance;

  LoggingService._internal();

  final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 5,
      lineLength: 80,
      colors: true,
      printEmojis: true,
      dateTimeFormat: DateTimeFormat.dateAndTime,
    ),
  );

  WebSocketService? _webSocketService;

  void attachWebSocket(WebSocketService service) {
    _webSocketService = service;
  }

  void info(String message, {bool sendToServer = true}) {
    _logger.i(message);
    if (sendToServer) _sendLogToServer('INFO', message);
  }

  void warning(String message, {bool sendToServer = true}) {
    _logger.w(message);
    if (sendToServer) _sendLogToServer('WARNING', message);
  }

  void error(
    String message, {
    dynamic error,
    StackTrace? stackTrace,
    bool sendToServer = true,
  }) {
    _logger.e(message, error: error, stackTrace: stackTrace);
    if (sendToServer) _sendLogToServer('ERROR', '$message ${error ?? ''}');
  }

  void debug(String message, {bool sendToServer = false}) {
    _logger.d(message);
    if (sendToServer) _sendLogToServer('DEBUG', message);
  }

  void _sendLogToServer(String level, String message) {
    // Avoid sending logs if not connected or if it's a log from the socket service itself (to prevent loops)
    // We rely on the caller to set sendToServer=false if they are the socket service.

    if (_webSocketService != null &&
        _webSocketService!.status == ConnectionStatus.connected) {
      try {
        _webSocketService!.sendLog(level, message);
      } catch (e) {
        // Fallback to minimal print if sending fails, to avoid loops
        // ignore: avoid_print
        print('Failed to send log to server: $e');
      }
    }
  }
}
