import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_client/services/transcription/wav_encoder.dart';

/// Test-scoped constants for [WavEncoder] assertions.
abstract final class _WavEncoderTest {
  // --- WAV header byte offsets ---
  static const int riffFourCcOffset = 0;
  static const int riffFourCcEnd = 4;
  static const int riffChunkSizeOffset = 4;
  static const int waveFourCcOffset = 8;
  static const int waveFourCcEnd = 12;
  static const int fmtFourCcOffset = 12;
  static const int fmtFourCcEnd = 16;
  static const int audioFormatOffset = 20;
  static const int channelCountOffset = 22;
  static const int sampleRateOffset = 24;
  static const int byteRateOffset = 28;
  static const int blockAlignOffset = 32;
  static const int bitsPerSampleOffset = 34;
  static const int dataFourCcOffset = 36;
  static const int dataFourCcEnd = 40;
  static const int dataChunkSizeOffset = 40;

  // --- WAV format field expected values ---
  static const int wavHeaderSizeBytes = 44;
  static const int riffChunkOverhead = 36; // RIFF chunk size = pcmSize + 36
  static const int pcmAudioFormatCode = 1; // PCM = 1
  static const int monoChannelCount = 1;
  static const int sampleRateHz = 16000;
  static const int bitsPerSample = 16;
  static const int byteRate = 32000; // 16000 * 1 * 2
  static const int blockAlign = 2; // 1 channel * 2 bytes/sample

  // --- Test PCM buffer sizes ---
  static const int emptyPcmSize = 0;
  static const int smallPcmSize = 100; // small non-zero buffer for header-only tests
  static const int shortClipPcmSize = 3200; // 0.1 s at 16 kHz / 16-bit / mono
  static const int standardPcmSize = 6400; // 0.2 s at 16 kHz / 16-bit / mono
}

void main() {
  group('WavEncoder', () {
    test('produces 44-byte header for empty PCM input', () {
      final wav = WavEncoder.encode(Uint8List(_WavEncoderTest.emptyPcmSize));

      expect(wav.length, _WavEncoderTest.wavHeaderSizeBytes);
    });

    test('output size equals header + PCM data length', () {
      final pcm = Uint8List(_WavEncoderTest.shortClipPcmSize); // 0.1 s at 16 kHz/16-bit/mono
      final wav = WavEncoder.encode(pcm);

      expect(wav.length, _WavEncoderTest.wavHeaderSizeBytes + _WavEncoderTest.shortClipPcmSize);
    });

    test('RIFF header is correct', () {
      final wav = WavEncoder.encode(Uint8List(_WavEncoderTest.smallPcmSize));
      final riff = String.fromCharCodes(wav.sublist(_WavEncoderTest.riffFourCcOffset, _WavEncoderTest.riffFourCcEnd));

      expect(riff, 'RIFF');
    });

    test('WAVE format marker is correct', () {
      final wav = WavEncoder.encode(Uint8List(_WavEncoderTest.smallPcmSize));
      final wave = String.fromCharCodes(wav.sublist(_WavEncoderTest.waveFourCcOffset, _WavEncoderTest.waveFourCcEnd));

      expect(wave, 'WAVE');
    });

    test('fmt chunk ID is correct', () {
      final wav = WavEncoder.encode(Uint8List(_WavEncoderTest.smallPcmSize));
      final fmt = String.fromCharCodes(wav.sublist(_WavEncoderTest.fmtFourCcOffset, _WavEncoderTest.fmtFourCcEnd));

      expect(fmt, 'fmt ');
    });

    test('data chunk ID is correct', () {
      final wav = WavEncoder.encode(Uint8List(_WavEncoderTest.smallPcmSize));
      final data = String.fromCharCodes(wav.sublist(_WavEncoderTest.dataFourCcOffset, _WavEncoderTest.dataFourCcEnd));

      expect(data, 'data');
    });

    test('RIFF chunk size is dataSize + 36', () {
      final pcmSize = _WavEncoderTest.standardPcmSize;
      final wav = WavEncoder.encode(Uint8List(pcmSize));
      final view = ByteData.sublistView(wav);
      final chunkSize = view.getUint32(_WavEncoderTest.riffChunkSizeOffset, Endian.little);

      expect(chunkSize, pcmSize + _WavEncoderTest.riffChunkOverhead);
    });

    test('data sub-chunk size matches PCM data length', () {
      final pcmSize = _WavEncoderTest.standardPcmSize;
      final wav = WavEncoder.encode(Uint8List(pcmSize));
      final view = ByteData.sublistView(wav);
      final dataSize = view.getUint32(_WavEncoderTest.dataChunkSizeOffset, Endian.little);

      expect(dataSize, pcmSize);
    });

    test('audio format is PCM (1)', () {
      final wav = WavEncoder.encode(Uint8List(_WavEncoderTest.smallPcmSize));
      final view = ByteData.sublistView(wav);

      expect(view.getUint16(_WavEncoderTest.audioFormatOffset, Endian.little), _WavEncoderTest.pcmAudioFormatCode);
    });

    test('channel count is mono (1)', () {
      final wav = WavEncoder.encode(Uint8List(_WavEncoderTest.smallPcmSize));
      final view = ByteData.sublistView(wav);

      expect(view.getUint16(_WavEncoderTest.channelCountOffset, Endian.little), _WavEncoderTest.monoChannelCount);
    });

    test('sample rate is 16000', () {
      final wav = WavEncoder.encode(Uint8List(_WavEncoderTest.smallPcmSize));
      final view = ByteData.sublistView(wav);

      expect(view.getUint32(_WavEncoderTest.sampleRateOffset, Endian.little), _WavEncoderTest.sampleRateHz);
    });

    test('bits per sample is 16', () {
      final wav = WavEncoder.encode(Uint8List(_WavEncoderTest.smallPcmSize));
      final view = ByteData.sublistView(wav);

      expect(view.getUint16(_WavEncoderTest.bitsPerSampleOffset, Endian.little), _WavEncoderTest.bitsPerSample);
    });

    test('byte rate is sampleRate * channels * bytesPerSample', () {
      final wav = WavEncoder.encode(Uint8List(_WavEncoderTest.smallPcmSize));
      final view = ByteData.sublistView(wav);
      final byteRate = view.getUint32(_WavEncoderTest.byteRateOffset, Endian.little);

      // 16000 * 1 * 2 = 32000
      expect(byteRate, _WavEncoderTest.byteRate);
    });

    test('block align is channels * bytesPerSample', () {
      final wav = WavEncoder.encode(Uint8List(_WavEncoderTest.smallPcmSize));
      final view = ByteData.sublistView(wav);

      // 1 * 2 = 2
      expect(view.getUint16(_WavEncoderTest.blockAlignOffset, Endian.little), _WavEncoderTest.blockAlign);
    });

    test('PCM data is preserved after header', () {
      final pcm = Uint8List.fromList([0x01, 0x02, 0x03, 0x04]);
      final wav = WavEncoder.encode(pcm);

      expect(wav.sublist(_WavEncoderTest.wavHeaderSizeBytes), pcm);
    });
  });
}
