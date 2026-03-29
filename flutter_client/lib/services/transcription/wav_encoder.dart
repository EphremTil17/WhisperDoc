import 'dart:typed_data';

/// Encodes raw PCM audio data into a WAV file container.
///
/// Produces a valid RIFF/WAVE file with a 44-byte header. Hardcoded for the
/// WhisperDoc capture format: 16 kHz, 16-bit signed LE, mono — which is also
/// the optimal input format for Groq's Whisper API (lowest server-side decode
/// overhead).
class WavEncoder {
  static const int _sampleRateHertz = 16000;
  static const int _bitsPerSample = 16;
  static const int _channelCount = 1;
  static const int _pcmAudioFormatCode = 1;
  static const int _waveHeaderSizeBytes = 44;
  static const int _riffChunkSizeExcludesLeadingBytes = 8;
  static const int _bitsPerByte = 8;
  static const int _pcmFmtChunkSizeBytes = 16;
  static const int _fourCcLength = 4;

  static const int _riffChunkIdOffset = 0;
  static const int _riffChunkSizeOffset = 4;
  static const int _waveFormatOffset = 8;
  static const int _fmtChunkIdOffset = 12;
  static const int _fmtChunkSizeOffset = 16;
  static const int _audioFormatOffset = 20;
  static const int _channelCountOffset = 22;
  static const int _sampleRateOffset = 24;
  static const int _byteRateOffset = 28;
  static const int _blockAlignOffset = 32;
  static const int _bitsPerSampleOffset = 34;
  static const int _dataChunkIdOffset = 36;
  static const int _dataChunkSizeOffset = 40;

  static const String _riffChunkId = 'RIFF';
  static const String _waveFormat = 'WAVE';
  static const String _fmtChunkId = 'fmt ';
  static const String _dataChunkId = 'data';

  /// Wraps [pcmData] (raw 16-bit LE mono samples at 16 kHz) in a WAV container.
  static Uint8List encode(Uint8List pcmData) {
    final int dataSizeBytes = pcmData.length;
    final int bytesPerSample = _bitsPerSample ~/ _bitsPerByte;
    final int riffChunkSize =
        dataSizeBytes +
        _waveHeaderSizeBytes -
        _riffChunkSizeExcludesLeadingBytes;
    final int byteRate = _sampleRateHertz * _channelCount * bytesPerSample;
    final int blockAlign = _channelCount * bytesPerSample;

    final ByteData buffer = ByteData(_waveHeaderSizeBytes + dataSizeBytes);

    // RIFF header
    _writeFourCc(buffer, _riffChunkIdOffset, _riffChunkId);
    buffer.setUint32(_riffChunkSizeOffset, riffChunkSize, Endian.little);
    _writeFourCc(buffer, _waveFormatOffset, _waveFormat);

    // fmt sub-chunk
    _writeFourCc(buffer, _fmtChunkIdOffset, _fmtChunkId);
    buffer.setUint32(_fmtChunkSizeOffset, _pcmFmtChunkSizeBytes, Endian.little);
    buffer.setUint16(_audioFormatOffset, _pcmAudioFormatCode, Endian.little);
    buffer.setUint16(_channelCountOffset, _channelCount, Endian.little);
    buffer.setUint32(_sampleRateOffset, _sampleRateHertz, Endian.little);
    buffer.setUint32(_byteRateOffset, byteRate, Endian.little);
    buffer.setUint16(_blockAlignOffset, blockAlign, Endian.little);
    buffer.setUint16(_bitsPerSampleOffset, _bitsPerSample, Endian.little);

    // data sub-chunk
    _writeFourCc(buffer, _dataChunkIdOffset, _dataChunkId);
    buffer.setUint32(_dataChunkSizeOffset, dataSizeBytes, Endian.little);

    // Copy PCM data after header
    final Uint8List bytes = buffer.buffer.asUint8List();
    bytes.setRange(
      _waveHeaderSizeBytes,
      _waveHeaderSizeBytes + dataSizeBytes,
      pcmData,
    );

    return bytes;
  }

  static void _writeFourCc(ByteData buffer, int offset, String value) {
    if (value.length != _fourCcLength) {
      throw ArgumentError.value(value, 'value', 'FourCC must be 4 characters.');
    }

    final List<int> charCodes = value.codeUnits;
    for (int index = 0; index < _fourCcLength; index++) {
      buffer.setUint8(offset + index, charCodes[index]);
    }
  }
}
