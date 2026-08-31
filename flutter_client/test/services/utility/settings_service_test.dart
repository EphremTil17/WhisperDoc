// Mocktail matchers must be invoked inline to register each argument matcher.
// ignore_for_file: prefer-match-file-name, avoid-late-keyword, prefer-moving-to-variable

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_client/infrastructure/constants/app_constants.dart';
import 'package:flutter_client/logic/models/custom_profile.dart';
import 'package:flutter_client/logic/models/dictation_profile.dart';
import 'package:flutter_client/services/utility/secure_vault_service.dart';
import 'package:flutter_client/services/utility/settings_service.dart';

class _MockSecureVaultService extends Mock implements SecureVaultService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsService - Groq Model & Configuration', () {
    late SettingsService settings;
    late _MockSecureVaultService mockVault;

    setUp(() async {
      PackageInfo.setMockInitialValues(
        appName: 'WhisperDoc',
        packageName: 'com.whisperdoc',
        version: '3.0.0',
        buildNumber: '1',
        buildSignature: '',
      );

      mockVault = _MockSecureVaultService();
      when(
        () => mockVault.initialize(),
      ).thenAnswer((_) => Future<void>.value());
      when(
        () => mockVault.retrieveCredential(any<String>()),
      ).thenAnswer((_) async => null);
      when(
        () => mockVault.storeCredential(any<String>(), any<String>()),
      ).thenAnswer((_) => Future<void>.value());

      SharedPreferences.setMockInitialValues({
        'transcription_mode': 'groq',
        'groq_language': 'en',
        'groq_model': 'whisper-large-v3',
      });
      settings = SettingsService(vault: mockVault);
      await settings.load();
    });

    test('loads groq configuration from shared preferences correctly', () {
      expect(settings.isGroqMode, isTrue);
      expect(settings.groqLanguage, 'en');
      expect(settings.groqModel, 'whisper-large-v3');
    });

    test('setGroqModel updates groqModel and notifies listeners', () async {
      var notified = false;
      settings.addListener(() {
        notified = true;
      });

      await settings.setGroqModel('whisper-large-v3-turbo');

      expect(settings.groqModel, 'whisper-large-v3-turbo');
      expect(notified, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('groq_model'), 'whisper-large-v3-turbo');
    });

    test('setGroqModel does not notify if model is identical', () async {
      var notified = false;
      settings.addListener(() {
        notified = true;
      });

      await settings.setGroqModel('whisper-large-v3'); // same value as setUp

      expect(notified, isFalse);
    });

    test('initializes injected vault during load', () {
      expect(settings.isGroqMode, isTrue);
      verify(() => mockVault.initialize()).called(1);
    });

    test('normalizes unsupported loaded model to groqDefaultModel', () async {
      SharedPreferences.setMockInitialValues({
        'groq_model': 'deprecated-or-invalid-model',
      });
      final invalidSettings = SettingsService(vault: mockVault);
      await invalidSettings.load();

      expect(invalidSettings.groqModel, AppConstants.groqDefaultModel);
    });

    test('trims whitespace when loading valid padded model string', () async {
      SharedPreferences.setMockInitialValues({
        'groq_model': '  whisper-large-v3  ',
      });
      final paddedSettings = SettingsService(vault: mockVault);
      await paddedSettings.load();

      expect(paddedSettings.groqModel, 'whisper-large-v3');
    });

    test(
      'normalizes unsupported setGroqModel input to groqDefaultModel',
      () async {
        // Start with large-v3
        expect(settings.groqModel, 'whisper-large-v3');

        // Attempt to set an unknown model -> should normalize to default (turbo)
        await settings.setGroqModel('unknown-model-xyz');

        expect(settings.groqModel, AppConstants.groqDefaultModel);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('groq_model'), AppConstants.groqDefaultModel);
      },
    );

    test('defaults dictationProfile to raw when not persisted', () {
      expect(settings.dictationProfile, DictationProfile.raw);
    });

    test(
      'loads persisted dictationProfile correctly when in Groq mode',
      () async {
        SharedPreferences.setMockInitialValues({
          'transcription_mode': 'groq',
          'dictation_profile': 'professional',
        });
        final proSettings = SettingsService(vault: mockVault);
        await proSettings.load();

        expect(proSettings.dictationProfile, DictationProfile.professional);
      },
    );

    test(
      'reverts persisted dictationProfile to raw when loaded in WhisperDoc backend mode',
      () async {
        SharedPreferences.setMockInitialValues({
          'transcription_mode': 'whisper',
          'dictation_profile': 'professional',
        });
        final backendSettings = SettingsService(vault: mockVault);
        await backendSettings.load();

        expect(backendSettings.dictationProfile, DictationProfile.raw);
      },
    );

    test(
      'falls back to raw when unknown dictation_profile is stored',
      () async {
        SharedPreferences.setMockInitialValues({
          'dictation_profile': 'unknown_profile_key',
        });
        final fallbackSettings = SettingsService(vault: mockVault);
        await fallbackSettings.load();

        expect(fallbackSettings.dictationProfile, DictationProfile.raw);
      },
    );

    test('setDictationProfile updates profile and persists to prefs', () async {
      var notified = false;
      settings.addListener(() {
        notified = true;
      });

      await settings.setDictationProfile(DictationProfile.clean);

      expect(settings.dictationProfile, DictationProfile.clean);
      expect(notified, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('dictation_profile'), 'clean');
    });

    test('setDictationProfile does not notify if unchanged', () async {
      var notified = false;
      settings.addListener(() {
        notified = true;
      });

      await settings.setDictationProfile(DictationProfile.raw); // Already raw

      expect(notified, isFalse);
    });

    test(
      'saveCustomProfile adds profiles up to 3 slots and nextFreeCustomSlot reflects availability',
      () async {
        expect(settings.nextFreeCustomSlot(), 'custom1');
        expect(settings.customProfiles, isEmpty);

        const p1 = CustomProfile(
          storageKey: 'custom1',
          name: 'Custom 1',
          userPrompt: 'Prompt 1',
        );
        await settings.saveCustomProfile(p1);

        expect(settings.customProfiles.length, 1);
        expect(settings.customProfiles.first, equals(p1));
        expect(settings.nextFreeCustomSlot(), 'custom2');

        const p2 = CustomProfile(
          storageKey: 'custom2',
          name: 'Custom 2',
          userPrompt: 'Prompt 2',
        );
        await settings.saveCustomProfile(p2);
        expect(settings.nextFreeCustomSlot(), 'custom3');

        const p3 = CustomProfile(
          storageKey: 'custom3',
          name: 'Custom 3',
          userPrompt: 'Prompt 3',
        );
        await settings.saveCustomProfile(p3);
        expect(settings.customProfiles.length, CustomProfile.slotKeys.length);
        expect(settings.nextFreeCustomSlot(), isNull);

        // Attempting to add an invalid slot key throws ArgumentError
        const p4 = CustomProfile(
          storageKey: 'custom4',
          name: 'Custom 4',
          userPrompt: 'Prompt 4',
        );
        expect(() => settings.saveCustomProfile(p4), throwsArgumentError);
      },
    );

    test(
      'saveCustomProfile rejects blank name or blank prompt or prompt > 2000 chars',
      () async {
        expect(
          () => settings.saveCustomProfile(
            const CustomProfile(
              storageKey: 'custom1',
              name: '   ',
              userPrompt: 'Valid prompt',
            ),
          ),
          throwsArgumentError,
        );

        expect(
          () => settings.saveCustomProfile(
            const CustomProfile(
              storageKey: 'custom1',
              name: 'Valid Name',
              userPrompt: '   \n  \t  ',
            ),
          ),
          throwsArgumentError,
        );

        final overLengthPrompt =
            'a' * (AppConstants.customProfileMaxPromptLength + 1);
        expect(
          () => settings.saveCustomProfile(
            CustomProfile(
              storageKey: 'custom1',
              name: 'Valid Name',
              userPrompt: overLengthPrompt,
            ),
          ),
          throwsArgumentError,
        );
      },
    );

    test(
      'saveCustomProfile updates existing profile in place without consuming new slots',
      () async {
        const original = CustomProfile(
          storageKey: 'custom1',
          name: 'Old Name',
          userPrompt: 'Old Prompt',
        );
        await settings.saveCustomProfile(original);

        const updated = CustomProfile(
          storageKey: 'custom1',
          name: 'New Name',
          userPrompt: 'New Prompt',
        );
        await settings.saveCustomProfile(updated);

        expect(settings.customProfiles.length, 1);
        expect(settings.customProfiles.first.name, 'New Name');
        expect(settings.customProfiles.first.userPrompt, 'New Prompt');
      },
    );

    test('deleteCustomProfile frees the slot', () async {
      await settings.saveCustomProfile(
        const CustomProfile(
          storageKey: 'custom1',
          name: 'Custom 1',
          userPrompt: 'Prompt 1',
        ),
      );
      await settings.saveCustomProfile(
        const CustomProfile(
          storageKey: 'custom2',
          name: 'Custom 2',
          userPrompt: 'Prompt 2',
        ),
      );

      expect(settings.nextFreeCustomSlot(), 'custom3');

      await settings.deleteCustomProfile('custom1');

      expect(settings.customProfiles.length, 1);
      expect(settings.customProfiles.first.storageKey, 'custom2');
      // custom1 is now free again
      expect(settings.nextFreeCustomSlot(), 'custom1');
    });

    test(
      'deleting active custom profile resets dictationProfile to Raw',
      () async {
        const custom = CustomProfile(
          storageKey: 'custom1',
          name: 'Active Custom',
          userPrompt: 'Active Prompt',
        );
        await settings.saveCustomProfile(custom);
        await settings.setDictationProfile(custom);

        expect(settings.dictationProfile.storageKey, 'custom1');

        await settings.deleteCustomProfile('custom1');

        expect(settings.dictationProfile, equals(DictationProfile.raw));
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('dictation_profile'), 'raw');
      },
    );

    test(
      'loading with stored custom key resolves to CustomProfile when in Groq mode',
      () async {
        SharedPreferences.setMockInitialValues({
          'transcription_mode': 'groq',
          'dictation_profile': 'custom1',
          'custom_profiles_json':
              '[{"storageKey":"custom1","name":"Loaded Profile","userPrompt":"Loaded Prompt"}]',
        });

        final loadedSettings = SettingsService(vault: mockVault);
        await loadedSettings.load();

        expect(loadedSettings.customProfiles.length, 1);
        expect(loadedSettings.dictationProfile.storageKey, 'custom1');
        expect(loadedSettings.dictationProfile.label, 'Loaded Profile');
        expect(loadedSettings.dictationProfile.requiresLlm, isTrue);
      },
    );

    test(
      'switching transcription mode to whisper reverts dictationProfile to raw',
      () async {
        await settings.setTranscriptionMode('groq');
        await settings.setDictationProfile(DictationProfile.clean);
        expect(settings.dictationProfile, DictationProfile.clean);

        await settings.setTranscriptionMode('whisper');
        expect(settings.dictationProfile, DictationProfile.raw);
      },
    );

    test(
      'setDictationProfile enforces raw profile when in WhisperDoc backend mode',
      () async {
        await settings.setTranscriptionMode('whisper');
        expect(settings.isGroqMode, isFalse);

        await settings.setDictationProfile(DictationProfile.professional);
        expect(settings.dictationProfile, DictationProfile.raw);
      },
    );

    test(
      'loading with stored custom key falls back to Raw when slot not present',
      () async {
        SharedPreferences.setMockInitialValues({
          'dictation_profile': 'custom3',
          'custom_profiles_json': '[]',
        });

        final loadedSettings = SettingsService(vault: mockVault);
        await loadedSettings.load();

        expect(loadedSettings.dictationProfile, equals(DictationProfile.raw));
      },
    );

    test(
      'loading skips malformed, invalid slot, or duplicate slot entries',
      () async {
        SharedPreferences.setMockInitialValues({
          'custom_profiles_json': '''
        [
          {"storageKey":"custom1","name":"Valid Profile","userPrompt":"Valid Prompt"},
          {"storageKey":"custom1","name":"Duplicate Slot","userPrompt":"Ignored"},
          {"storageKey":"custom99","name":"Invalid Slot","userPrompt":"Ignored"},
          {"storageKey":"custom2","name":"","userPrompt":"Missing Name"},
          {"storageKey":"custom3"}
        ]
        ''',
        });

        final loadedSettings = SettingsService(vault: mockVault);
        await loadedSettings.load();

        expect(loadedSettings.customProfiles.length, 1);
        expect(loadedSettings.customProfiles.first.storageKey, 'custom1');
        expect(loadedSettings.customProfiles.first.name, 'Valid Profile');
      },
    );
  });
}
