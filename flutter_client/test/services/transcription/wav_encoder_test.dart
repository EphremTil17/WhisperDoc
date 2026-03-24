import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_client/services/transcription/wav_encoder.dart';

void main() {
  group('WavEncoder', () {
    test('produces 44-byte header for empty PCM input', () {
      final wav = WavEncoder.encode(Uint8List(0));

      expect(wav.length, 44);
    });

    test('output size equals header + PCM data length', () {
      final pcm = Uint8List(3200); // 0.1 s at 16 kHz/16-bit/mono
      final wav = WavEncoder.encode(pcm);

      expect(wav.length, 44 + 3200);
    });

    test('RIFF header is correct', () {
      final wav = WavEncoder.encode(Uint8List(100));
      final riff = String.fromCharCodes(wav.sublist(0, 4));

      expect(riff, 'RIFF');
    });

    test('WAVE format marker is correct', () {
      final wav = WavEncoder.encode(Uint8List(100));
      final wave = String.fromCharCodes(wav.sublist(8, 12));

      expect(wave, 'WAVE');
    });

    test('fmt chunk ID is correct', () {
      final wav = WavEncoder.encode(Uint8List(100));
      final fmt = String.fromCharCodes(wav.sublist(12, 16));

      expect(fmt, 'fmt ');
    });

    test('data chunk ID is correct', () {
      final wav = WavEncoder.encode(Uint8List(100));
      final data = String.fromCharCodes(wav.sublist(36, 40));

      expect(data, 'data');
    });

    test('RIFF chunk size is dataSize + 36', () {
      const pcmSize = 6400;
      final wav = WavEncoder.encode(Uint8List(pcmSize));
      final view = ByteData.sublistView(wav);
      final chunkSize = view.getUint32(4, Endian.little);

      expect(chunkSize, pcmSize + 36);
    });

    test('data sub-chunk size matches PCM data length', () {
      const pcmSize = 6400;
      final wav = WavEncoder.encode(Uint8List(pcmSize));
      final view = ByteData.sublistView(wav);
      final dataSize = view.getUint32(40, Endian.little);

      expect(dataSize, pcmSize);
    });

    test('audio format is PCM (1)', () {
      final wav = WavEncoder.encode(Uint8List(100));
      final view = ByteData.sublistView(wav);

      expect(view.getUint16(20, Endian.little), 1);
    });

    test('channel count is mono (1)', () {
      final wav = WavEncoder.encode(Uint8List(100));
      final view = ByteData.sublistView(wav);

      expect(view.getUint16(22, Endian.little), 1);
    });

    test('sample rate is 16000', () {
      final wav = WavEncoder.encode(Uint8List(100));
      final view = ByteData.sublistView(wav);

      expect(view.getUint32(24, Endian.little), 16000);
    });

    test('bits per sample is 16', () {
      final wav = WavEncoder.encode(Uint8List(100));
      final view = ByteData.sublistView(wav);

      expect(view.getUint16(34, Endian.little), 16);
    });

    test('byte rate is sampleRate * channels * bytesPerSample', () {
      final wav = WavEncoder.encode(Uint8List(100));
      final view = ByteData.sublistView(wav);
      final byteRate = view.getUint32(28, Endian.little);

      // 16000 * 1 * 2 = 32000
      expect(byteRate, 32000);
    });

    test('block align is channels * bytesPerSample', () {
      final wav = WavEncoder.encode(Uint8List(100));
      final view = ByteData.sublistView(wav);

      // 1 * 2 = 2
      expect(view.getUint16(32, Endian.little), 2);
    });

    test('PCM data is preserved after header', () {
      final pcm = Uint8List.fromList([0x01, 0x02, 0x03, 0x04]);
      final wav = WavEncoder.encode(pcm);

      expect(wav.sublist(44), pcm);
    });
  });
}
