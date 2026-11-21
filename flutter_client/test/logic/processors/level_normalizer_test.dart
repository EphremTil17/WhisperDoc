import 'dart:math' as math;

import 'package:flutter_client/logic/processors/level_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Signal levels in dBFS. Each pair is speech over its own pauses; the quiet
  // and loud pairs share a 20 dB swing so only the input gain differs.
  const quietSpeechDb = -50.0;
  const quietPauseDb = -70.0;
  const loudSpeechDb = -15.0;
  const loudPauseDb = -35.0;
  const midSpeechDb = -45.0;
  const midPauseDb = -65.0;
  const roomNoiseDb = -65.0;
  const roomNoiseJitterDb = 4.0;
  const spikeDb = -10.0;
  const probeDb = -40.0;

  const decibelsPerDecade = 20.0;
  const tenfold = 10.0;
  const phase = Duration(milliseconds: 500); // speech/pause alternation
  const defaultStep = Duration(milliseconds: 50);
  const fastStep = Duration(milliseconds: 20);
  const slowStep = Duration(milliseconds: 100);
  const runLength = Duration(seconds: 10);
  const afterRun = Duration(seconds: 11);
  const noiseSeed = 7;
  const centre = 0.5; // shifts Random.nextDouble() to -0.5..0.5

  const fullMeter = 0.9;
  const silent = 0.1;
  const sameShape = 0.01;
  const rateTolerance = 0.05;

  double raw(double db) => math.pow(tenfold, db / decibelsPerDecade).toDouble();

  /// Alternates [speechDb] and [pauseDb] every [phase] for [runLength],
  /// sampled every [step]; returns the output for the last speech sample.
  double speechPattern(
    LevelNormalizer normalizer, {
    required double speechDb,
    required double pauseDb,
    Duration step = defaultStep,
  }) {
    var t = Duration.zero;
    var lastSpeech = 0.0;
    while (t < runLength) {
      final inSpeech = (t.inMicroseconds ~/ phase.inMicroseconds).isEven;
      final out = normalizer.normalize(raw(inSpeech ? speechDb : pauseDb), t);
      if (inSpeech) lastSpeech = out;
      t += step;
    }

    return lastSpeech;
  }

  group('LevelNormalizer', () {
    test('treats an exact zero as the reset signal and returns zero', () {
      final normalizer = LevelNormalizer();
      final speech = raw(midSpeechDb);
      speechPattern(normalizer, speechDb: midSpeechDb, pauseDb: midPauseDb);
      final before = normalizer.normalize(speech, afterRun);
      final resetAt = afterRun + defaultStep;

      expect(normalizer.normalize(0, resetAt), 0);
      expect(
        normalizer.normalize(speech, resetAt + defaultStep),
        closeTo(before, rateTolerance),
      );
    });

    test('a quiet mic and a loud mic fill the meter the same way', () {
      final quiet = speechPattern(
        LevelNormalizer(),
        speechDb: quietSpeechDb,
        pauseDb: quietPauseDb,
      );
      final loud = speechPattern(
        LevelNormalizer(),
        speechDb: loudSpeechDb,
        pauseDb: loudPauseDb,
      );

      expect(quiet, greaterThan(fullMeter));
      expect(loud, closeTo(quiet, sameShape));
    });

    test('steady room noise reads as silence', () {
      final normalizer = LevelNormalizer();
      final random = math.Random(noiseSeed);
      var out = 1.0;
      for (var t = Duration.zero; t < runLength; t += defaultStep) {
        final jitter = (random.nextDouble() - centre) * roomNoiseJitterDb;
        out = normalizer.normalize(raw(roomNoiseDb + jitter), t);
      }

      expect(out, lessThan(silent));
    });

    test('a sudden loud sound reaches full scale immediately', () {
      final normalizer = LevelNormalizer();
      speechPattern(normalizer, speechDb: quietSpeechDb, pauseDb: quietPauseDb);

      expect(normalizer.normalize(raw(spikeDb), afterRun), 1.0);
    });

    test('output does not depend on how often samples arrive', () {
      final fast = speechPattern(
        LevelNormalizer(),
        speechDb: midSpeechDb,
        pauseDb: midPauseDb,
        step: fastStep,
      );
      final slow = speechPattern(
        LevelNormalizer(),
        speechDb: midSpeechDb,
        pauseDb: midPauseDb,
        step: slowStep,
      );

      expect(fast, closeTo(slow, rateTolerance));
    });

    test('reset forgets the learned range', () {
      final normalizer = LevelNormalizer();
      final probe = raw(probeDb);
      final fresh = normalizer.normalize(probe, Duration.zero);

      speechPattern(normalizer, speechDb: loudSpeechDb, pauseDb: loudPauseDb);
      normalizer.reset();

      expect(normalizer.normalize(probe, Duration.zero), fresh);
    });
  });
}
