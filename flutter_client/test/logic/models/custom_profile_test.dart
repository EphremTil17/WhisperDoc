import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_client/logic/models/custom_profile.dart';
import 'package:flutter_client/logic/models/dictation_profile.dart';
import 'package:flutter_client/logic/models/dictation_profile_spec.dart';

void main() {
  group('CustomProfile', () {
    test('implements DictationProfileSpec', () {
      const profile = CustomProfile(
        storageKey: 'custom1',
        name: 'My Profile',
        userPrompt: 'Rewrite as concise bullet points.',
      );

      expect(profile, isA<DictationProfileSpec>());
      expect(profile.storageKey, 'custom1');
      expect(profile.name, 'My Profile');
      expect(profile.label, 'My Profile');
      expect(profile.isEditable, isTrue);
    });

    test(
      'systemPrompt composes shared preamble, profile header, and user prompt',
      () {
        const profile = CustomProfile(
          storageKey: 'custom1',
          name: 'Engineering Spec',
          userPrompt: 'Preserve all details and backtick code symbols.',
        );

        final prompt = profile.systemPrompt;
        expect(prompt, isNotNull);
        expect(prompt, contains(DictationProfile.sharedPreamble));
        expect(prompt, contains('PROFILE: Engineering Spec'));
        expect(
          prompt,
          contains('Preserve all details and backtick code symbols.'),
        );
      },
    );

    test(
      'requiresLlm is true when userPrompt is non-empty, false when blank',
      () {
        const active = CustomProfile(
          storageKey: 'custom1',
          name: 'Test',
          userPrompt: 'Valid prompt',
        );
        expect(active.requiresLlm, isTrue);

        const empty = CustomProfile(
          storageKey: 'custom1',
          name: 'Test',
          userPrompt: '',
        );
        expect(empty.requiresLlm, isFalse);

        const whitespace = CustomProfile(
          storageKey: 'custom1',
          name: 'Test',
          userPrompt: '   \n  \t  ',
        );
        expect(whitespace.requiresLlm, isFalse);
      },
    );

    test('slotKeys contains exactly 3 slots', () {
      expect(CustomProfile.slotKeys, ['custom1', 'custom2', 'custom3']);
    });

    test('defaultNameForSlot produces sequential names', () {
      expect(CustomProfile.defaultNameForSlot('custom1'), 'Custom 1');
      expect(CustomProfile.defaultNameForSlot('custom2'), 'Custom 2');
      expect(CustomProfile.defaultNameForSlot('custom3'), 'Custom 3');
      expect(CustomProfile.defaultNameForSlot('custom99'), 'Custom');
    });

    test('toJson and tryFromJson round trip correctly', () {
      const original = CustomProfile(
        storageKey: 'custom2',
        name: 'Jira Format',
        userPrompt: 'Format as acceptance criteria.',
      );

      final json = original.toJson();
      expect(json, {
        'storageKey': 'custom2',
        'name': 'Jira Format',
        'userPrompt': 'Format as acceptance criteria.',
      });

      final restored = CustomProfile.tryFromJson(json);
      expect(restored, equals(original));
      expect(restored?.storageKey, 'custom2');
      expect(restored?.name, 'Jira Format');
      expect(restored?.userPrompt, 'Format as acceptance criteria.');
    });

    test('tryFromJson rejects malformed or invalid entries', () {
      // Invalid slot key
      expect(
        CustomProfile.tryFromJson({
          'storageKey': 'custom99',
          'name': 'Valid',
          'userPrompt': 'Valid',
        }),
        isNull,
      );

      // Blank or missing name
      expect(
        CustomProfile.tryFromJson({
          'storageKey': 'custom1',
          'name': '',
          'userPrompt': 'Valid',
        }),
        isNull,
      );
      expect(
        CustomProfile.tryFromJson({
          'storageKey': 'custom1',
          'userPrompt': 'Valid',
        }),
        isNull,
      );

      // Blank or missing prompt
      expect(
        CustomProfile.tryFromJson({
          'storageKey': 'custom1',
          'name': 'Valid',
          'userPrompt': '   ',
        }),
        isNull,
      );
      expect(
        CustomProfile.tryFromJson({'storageKey': 'custom1', 'name': 'Valid'}),
        isNull,
      );
    });

    test('equality and hashCode compare field values', () {
      const a = CustomProfile(
        storageKey: 'custom1',
        name: 'Name',
        userPrompt: 'Prompt',
      );
      const b = CustomProfile(
        storageKey: 'custom1',
        name: 'Name',
        userPrompt: 'Prompt',
      );
      const c = CustomProfile(
        storageKey: 'custom2',
        name: 'Name',
        userPrompt: 'Prompt',
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });
}
