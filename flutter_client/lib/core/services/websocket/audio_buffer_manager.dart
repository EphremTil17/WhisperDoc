import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../logging_service.dart';

/// Manages temporary audio buffering during the WebSocket handshake.
class AudioBufferManager {
  final List<Uint8List> _buffer = [];
  static const int _maxBufferSize = 160000; // ~5s of 16kHz 16-bit audio
  int _currentSizeBytes = 0;
  final LoggingService _logger = LoggingService();

  /// Adds a chunk to the buffer if space allows.
  void add(Uint8List chunk) {
    if (_currentSizeBytes + chunk.length <= _maxBufferSize) {
      _buffer.add(chunk);
      _currentSizeBytes += chunk.length;
    } else {
      _logger.warning('Audio buffer full, dropping chunk');
    }
  }

  /// Flushes all buffered chunks into the provided WebSocket channel.
  void flush(WebSocketChannel channel) {
    if (_buffer.isEmpty) return;

    _logger.info('Flushing ${_buffer.length} buffered audio chunks');
    for (final chunk in _buffer) {
      channel.sink.add(chunk);
    }
    clear();
  }

  /// Clears the buffer and resets the size counter.
  void clear() {
    _buffer.clear();
    _currentSizeBytes = 0;
  }

  bool get isEmpty => _buffer.isEmpty;
}
