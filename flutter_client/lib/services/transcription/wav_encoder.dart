import 'dart:typed_data';

/// Encodes raw PCM audio data into a WAV file container.
///
/// Produces a valid RIFF/WAVE file with a 44-byte header. Hardcoded for the
/// WhisperDoc capture format: 16 kHz, 16-bit signed LE, mono — which is also
/// the optimal input format for Groq's Whisper API (lowest server-side decode
/// overhead).
class WavEncoder {
  static const int _sampleRate = 16000;
  static const int _bitsPerSample = 16;
  static const int _numChannels = 1;
  static const int _audioFormat = 1; // PCM
  static const int _headerSize = 44;

  /// Wraps [pcmData] (raw 16-bit LE mono samples at 16 kHz) in a WAV container.
  static Uint8List encode(Uint8List pcmData) {
    final int dataSize = pcmData.length;
    final int fileSize = dataSize + _headerSize - 8; // RIFF chunk size
    final int byteRate = _sampleRate * _numChannels * (_bitsPerSample ~/ 8);
    final int blockAlign = _numChannels * (_bitsPerSample ~/ 8);

    final buffer = ByteData(_headerSize + dataSize);

    // RIFF header
    buffer.setUint8(0, 0x52); // 'R'
    buffer.setUint8(1, 0x49); // 'I'
    buffer.setUint8(2, 0x46); // 'F'
    buffer.setUint8(3, 0x46); // 'F'
    buffer.setUint32(4, fileSize, Endian.little);
    buffer.setUint8(8, 0x57); // 'W'
    buffer.setUint8(9, 0x41); // 'A'
    buffer.setUint8(10, 0x56); // 'V'
    buffer.setUint8(11, 0x45); // 'E'

    // fmt sub-chunk
    buffer.setUint8(12, 0x66); // 'f'
    buffer.setUint8(13, 0x6D); // 'm'
    buffer.setUint8(14, 0x74); // 't'
    buffer.setUint8(15, 0x20); // ' '
    buffer.setUint32(16, 16, Endian.little); // Sub-chunk size (PCM = 16)
    buffer.setUint16(20, _audioFormat, Endian.little);
    buffer.setUint16(22, _numChannels, Endian.little);
    buffer.setUint32(24, _sampleRate, Endian.little);
    buffer.setUint32(28, byteRate, Endian.little);
    buffer.setUint16(32, blockAlign, Endian.little);
    buffer.setUint16(34, _bitsPerSample, Endian.little);

    // data sub-chunk
    buffer.setUint8(36, 0x64); // 'd'
    buffer.setUint8(37, 0x61); // 'a'
    buffer.setUint8(38, 0x74); // 't'
    buffer.setUint8(39, 0x61); // 'a'
    buffer.setUint32(40, dataSize, Endian.little);

    // Copy PCM data after header
    final bytes = buffer.buffer.asUint8List();
    bytes.setRange(_headerSize, _headerSize + dataSize, pcmData);

    return bytes;
  }
}
