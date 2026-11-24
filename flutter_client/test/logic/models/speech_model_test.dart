import 'package:flutter_client/logic/models/speech_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  SpeechModel? parse(Object? json, {bool zdr = true}) =>
      SpeechModel.fromJson(json, zdr: zdr);

  group('SpeechModel.fromJson', () {
    test('reads OpenRouter’s entry', () {
      final model = parse({
        'id': 'microsoft/mai-transcribe-2',
        'name': 'Microsoft AI: MAI-Transcribe 2',
        'expiration_date': '2026-12-22',
      });

      expect(model?.id, 'microsoft/mai-transcribe-2');
      expect(model?.maker, 'Microsoft AI');
      expect(model?.name, 'MAI-Transcribe 2');
      expect(model?.zdr, isTrue);
      expect(model?.retiresOn, DateTime.parse('2026-12-22'));
    });

    test('a model with no end date is not retiring', () {
      final model = parse({'id': 'acme/new-asr', 'name': 'Acme: New'});

      expect(model?.retiresOn, isNull);
    });

    test('a name without a maker is the whole name', () {
      final model = parse({'id': 'acme/plain', 'name': 'Plain ASR'});

      expect(model?.maker, isEmpty);
      expect(model?.name, 'Plain ASR');
    });

    test('a colon inside the model name survives', () {
      final model = parse({'id': 'acme/x', 'name': 'Acme: Model: Pro'});

      expect(model?.maker, 'Acme');
      expect(model?.name, 'Model: Pro');
    });

    test('a missing or blank name falls back to the id', () {
      expect(parse({'id': 'acme/x'})?.fullName, 'acme/x');
      expect(parse({'id': 'acme/x', 'name': '  '})?.fullName, 'acme/x');
    });

    test('rejects anything that is not an author/slug id', () {
      for (final id in [
        null,
        '',
        'no-slash',
        'Upper/case',
        '../etc/passwd',
        'a/b/../c?x',
        'a/b c',
      ]) {
        expect(parse({'id': id, 'name': 'X'}), isNull, reason: '$id');
      }
      expect(parse('not a map'), isNull);
      expect(parse(null), isNull);
    });

    test('accepts OpenRouter’s real id shapes', () {
      for (final id in [
        'nvidia/parakeet-tdt-0.6b-v3',
        'mistralai/voxtral-small-24b-2507-stt',
        'google/gemma-4-31b-it:free',
      ]) {
        expect(parse({'id': id})?.id, id);
      }
    });

    test('an unparsable retirement date is ignored', () {
      final model = parse({'id': 'acme/x', 'expiration_date': 'soon'});

      expect(model?.retiresOn, isNull);
    });
  });

  test('toJson round-trips through fromJson', () {
    final model = parse({
      'id': 'openai/whisper-large-v3-turbo',
      'name': 'OpenAI: Whisper Large V3 Turbo',
      'expiration_date': '2027-01-31',
    }, zdr: false);
    final json = model?.toJson();

    expect(json?['zdr'], isFalse);
    expect(parse(json, zdr: false), model);
  });

  test('sorts by full name, maker first, ignoring case', () {
    SpeechModel model(String id, String name) =>
        SpeechModel(id: id, fullName: name, zdr: true);
    final sorted = [
      model('a/3', 'Zed: One'),
      model('a/2', 'mistral: Voxtral'),
      model('a/1', 'AssemblyAI: Universal'),
      model('a/4', 'Microsoft AI: MAI'),
    ]..sort();

    expect(sorted.map((m) => m.id), ['a/1', 'a/4', 'a/2', 'a/3']);
  });

  test('equality covers every field', () {
    const base = SpeechModel(id: 'a/b', fullName: 'A: B', zdr: true);

    expect(base, const SpeechModel(id: 'a/b', fullName: 'A: B', zdr: true));
    expect(base.hashCode, isNot(0));
    expect(
      base,
      isNot(const SpeechModel(id: 'a/b', fullName: 'A: B', zdr: false)),
    );
    expect(
      base,
      isNot(
        SpeechModel(
          id: 'a/b',
          fullName: 'A: B',
          zdr: true,
          retiresOn: DateTime.parse('2027-01-31'),
        ),
      ),
    );
    expect(
      base,
      isNot(const SpeechModel(id: 'a/c', fullName: 'A: B', zdr: true)),
    );
  });
}
