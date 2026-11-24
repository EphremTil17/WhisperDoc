// Mocktail matchers must be invoked inline to register each argument matcher.
// ignore_for_file: prefer-match-file-name, avoid-late-keyword, prefer-moving-to-variable

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_client/infrastructure/constants/app_constants.dart';
import 'package:flutter_client/logic/models/custom_profile.dart';
import 'package:flutter_client/logic/models/dictation_profile.dart';
import 'package:flutter_client/logic/models/transcription_source.dart';
import 'package:flutter_client/services/utility/secure_vault_service.dart';
import 'package:flutter_client/services/utility/settings_service.dart';

import '../../fakes/in_memory_vault.dart';

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
        version: '3.2.0',
        buildNumber: '1',
        buildSignature: '',
      );

      mockVault = _MockSecureVaultService();
      when(() => mockVault.initialize())
          .thenAnswer((_) => Future<void>.value());
      when(() => mockVault.retrieveCredential(any<String>()))
          .thenAnswer((_) async => null);
      when(() => mockVault.storeCredential(any<String>(), any<String>()))
          .thenAnswer((_) => Future<void>.value());

      SharedPreferences.setMockInitialValues({
        'transcription_mode': 'groq',
        'groq_language': 'en',
        'groq_model': 'whisper-large-v3',
      });
      settings = SettingsService(vault: mockVault);
      await settings.load();
    });

    test('loads groq configuration from shared preferences correctly', () {
      expect(settings.transcriptionSource, TranscriptionSource.groq);
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
      expect(settings.transcriptionSource, TranscriptionSource.groq);
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

    test('normalizes unsupported setGroqModel input to groqDefaultModel', () async {
      // Start with large-v3
      expect(settings.groqModel, 'whisper-large-v3');

      // Attempt to set an unknown model -> should normalize to default (turbo)
      await settings.setGroqModel('unknown-model-xyz');

      expect(settings.groqModel, AppConstants.groqDefaultModel);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('groq_model'), AppConstants.groqDefaultModel);
    });

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

    test('reverts persisted dictationProfile to raw when loaded in WhisperDoc backend mode', () async {
      SharedPreferences.setMockInitialValues({
        'transcription_mode': 'whisper',
        'dictation_profile': 'professional',
      });
      final backendSettings = SettingsService(vault: mockVault);
      await backendSettings.load();

      expect(backendSettings.dictationProfile, DictationProfile.raw);
    });

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

    test('saveCustomProfile adds profiles up to 3 slots and nextFreeCustomSlot reflects availability', () async {
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
    });

    test('saveCustomProfile rejects blank name or blank prompt or prompt > 2000 chars', () {
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
    });

    test('saveCustomProfile updates existing profile in place without consuming new slots', () async {
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
    });

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

    test('loading with stored custom key resolves to CustomProfile when in Groq mode', () async {
      SharedPreferences.setMockInitialValues({
        'transcription_mode': 'groq',
        'dictation_profile': 'custom1',
        'custom_profiles_json': '[{"storageKey":"custom1","name":"Loaded Profile","userPrompt":"Loaded Prompt"}]',
      });

      final loadedSettings = SettingsService(vault: mockVault);
      await loadedSettings.load();

      expect(loadedSettings.customProfiles.length, 1);
      expect(loadedSettings.dictationProfile.storageKey, 'custom1');
      expect(loadedSettings.dictationProfile.label, 'Loaded Profile');
      expect(loadedSettings.dictationProfile.requiresLlm, isTrue);
    });

    test('switching to the server reverts dictationProfile to raw', () async {
      await settings.setTranscriptionSource(TranscriptionSource.groq);
      await settings.setDictationProfile(DictationProfile.clean);
      expect(settings.dictationProfile, DictationProfile.clean);

      await settings.setTranscriptionSource(TranscriptionSource.server);
      expect(settings.dictationProfile, DictationProfile.raw);
    });

    test(
      'setDictationProfile enforces raw profile when the server transcribes',
      () async {
        await settings.setTranscriptionSource(TranscriptionSource.server);
        expect(settings.transcriptionSource, TranscriptionSource.server);

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

  group('SettingsService persistence', () {
    const ctrlShift = 0x0006;
    const vkF9 = 0x78;

    var vault = InMemoryVault();

    /// A fresh service over the stored preferences and [vault], as on launch.
    Future<SettingsService> launch() async {
      final settings = SettingsService(vault: vault);
      await settings.load();

      return settings;
    }

    setUp(() {
      PackageInfo.setMockInitialValues(
        appName: 'WhisperDoc',
        packageName: 'com.whisperdoc',
        version: '3.2.0',
        buildNumber: '1',
        buildSignature: '',
      );
      SharedPreferences.setMockInitialValues({});
      vault = InMemoryVault();
    });

    test('a first launch uses the defaults', () async {
      final settings = await launch();

      expect(settings.serverUri, AppConstants.defaultServerUri);
      expect(settings.globalHotkey, AppConstants.defaultHotkeyDisplay);
      expect(settings.hotkeyModifiers, AppConstants.defaultHotkeyModifiers);
      expect(settings.hotkeyVKey, AppConstants.defaultHotkeyVKey);
      expect(settings.microphoneId, isNull);
      expect(settings.autoCopy, isTrue);
      expect(settings.autoPaste, isTrue);
      expect(settings.showVisualizer, isTrue);
      expect(settings.animateBackground, isTrue);
      expect(settings.incognitoMode, isFalse);
      expect(settings.transcriptionSource, TranscriptionSource.server);
      expect(settings.groqModel, AppConstants.groqDefaultModel);
      expect(settings.cachedApiKey, isNull);
      expect(settings.cachedGroqApiKey, isNull);
      expect(settings.appVersion, '3.2.0');
      expect(settings.vault, same(vault));
      expect(vault.initializeCalls, 1);
    });

    test('display toggles survive a restart', () async {
      final settings = await launch();
      await settings.setShowVisualizer(false);
      await settings.setAnimateBackground(false);
      await settings.setIncognitoMode(true);

      final reloaded = await launch();

      expect(reloaded.showVisualizer, isFalse);
      expect(reloaded.animateBackground, isFalse);
      expect(reloaded.incognitoMode, isTrue);
    });

    test('turning copy off turns paste off too', () async {
      final settings = await launch();

      await settings.setAutoCopy(false);
      final reloaded = await launch();

      expect(settings.autoPaste, isFalse);
      expect(reloaded.autoCopy, isFalse);
      expect(reloaded.autoPaste, isFalse);
    });

    test('turning paste on turns copy on too', () async {
      SharedPreferences.setMockInitialValues({
        'auto_copy': false,
        'auto_paste': false,
      });
      final settings = await launch();

      await settings.setAutoPaste(true);
      final reloaded = await launch();

      expect(settings.autoCopy, isTrue);
      expect(reloaded.autoCopy, isTrue);
      expect(reloaded.autoPaste, isTrue);
    });

    test('turning paste off leaves copy on', () async {
      final settings = await launch();

      await settings.setAutoPaste(false);
      final reloaded = await launch();

      expect(reloaded.autoCopy, isTrue);
      expect(reloaded.autoPaste, isFalse);
    });

    test('setting a value it already has does not notify', () async {
      final settings = await launch();
      var notified = 0;
      settings.addListener(() => notified++);

      await settings.setAutoCopy(true);
      await settings.setAutoPaste(true);
      await settings.setShowVisualizer(true);
      await settings.setAnimateBackground(true);
      await settings.setIncognitoMode(false);
      await settings.setServerUri(AppConstants.defaultServerUri);
      await settings.setTranscriptionSource(TranscriptionSource.server);
      await settings.setGroqLanguage('');
      await settings.setGroqPrompt('');
      await settings.setMicrophoneSelection(null, null);

      expect(notified, 0);
    });

    test('the server address survives a restart', () async {
      final settings = await launch();
      var notified = 0;
      settings.addListener(() => notified++);

      await settings.setServerUri('wss://whisper.example.org/ws');
      final reloaded = await launch();

      expect(notified, 1);
      expect(reloaded.serverUri, 'wss://whisper.example.org/ws');
    });

    test('trusted servers are remembered until cleared', () async {
      const origin = 'https://whisper.example.org:443';
      final settings = await launch();
      expect(settings.isTrustedServer(origin), isFalse);

      await settings.trustServer(origin);
      final reloaded = await launch();

      expect(reloaded.isTrustedServer(origin), isTrue);
      expect(reloaded.isTrustedServer('https://evil.example:443'), isFalse);

      await reloaded.clearTrustedServers();
      final cleared = await launch();

      expect(reloaded.isTrustedServer(origin), isFalse);
      expect(cleared.isTrustedServer(origin), isFalse);
    });

    test('trusting a server twice or clearing none does not notify', () async {
      const origin = 'https://whisper.example.org:443';
      final settings = await launch();
      await settings.clearTrustedServers();
      await settings.trustServer(origin);
      var notified = 0;
      settings.addListener(() => notified++);

      await settings.trustServer(origin);

      expect(notified, 0);
    });

    test('a recorded shortcut survives a restart', () async {
      final settings = await launch();
      var notified = 0;
      settings.addListener(() => notified++);

      await settings.setHotkey(
        display: 'Ctrl+Shift+F9',
        modifiers: ctrlShift,
        vKey: vkF9,
      );
      final reloaded = await launch();

      expect(notified, 1);
      expect(reloaded.globalHotkey, 'Ctrl+Shift+F9');
      expect(reloaded.hotkeyModifiers, ctrlShift);
      expect(reloaded.hotkeyVKey, vkF9);
    });

    test('a chosen microphone survives a restart until reset', () async {
      final settings = await launch();

      await settings.setMicrophoneSelection('mic-usb', 'USB Microphone');
      final reloaded = await launch();

      expect(reloaded.microphoneId, 'mic-usb');
      expect(reloaded.microphoneLabel, 'USB Microphone');

      await reloaded.setMicrophoneSelection(null, null);
      final reset = await launch();

      expect(reset.microphoneId, isNull);
      expect(reset.microphoneLabel, isNull);
    });

    test('API keys live in the vault, not in preferences', () async {
      final settings = await launch();

      await settings.setApiKey('wd-static-key');
      await settings.setGroqApiKey('gsk_test');
      final prefs = await SharedPreferences.getInstance();
      final reloaded = await launch();

      expect(vault.entries['api_key'], 'wd-static-key');
      expect(vault.entries['groq_api_key'], 'gsk_test');
      expect(prefs.getKeys(), isEmpty);
      expect(reloaded.cachedApiKey, 'wd-static-key');
      expect(reloaded.cachedGroqApiKey, 'gsk_test');
    });

    test('an empty API key deletes the stored one', () async {
      vault.entries['api_key'] = 'old-key';
      vault.entries['groq_api_key'] = 'gsk_old';
      final settings = await launch();

      await settings.setApiKey('');
      await settings.setGroqApiKey('');

      expect(settings.cachedApiKey, isNull);
      expect(settings.cachedGroqApiKey, isNull);
      expect(vault.entries, isEmpty);
    });

    test('the Groq prompt is kept in the vault', () async {
      final settings = await launch();

      await settings.setGroqPrompt('Medical terms: tachycardia');
      final reloaded = await launch();

      expect(vault.entries['groq_prompt'], 'Medical terms: tachycardia');
      expect(reloaded.groqPrompt, 'Medical terms: tachycardia');

      await reloaded.setGroqPrompt('');

      expect(vault.entries.containsKey('groq_prompt'), isFalse);
    });

    test(
      'a prompt left in preferences by older versions moves to the vault',
      () async {
        SharedPreferences.setMockInitialValues({
          'groq_prompt': 'legacy prompt',
        });

        final settings = await launch();
        final prefs = await SharedPreferences.getInstance();

        expect(settings.groqPrompt, 'legacy prompt');
        expect(vault.entries['groq_prompt'], 'legacy prompt');
        expect(prefs.containsKey('groq_prompt'), isFalse);
      },
    );

    test('an empty legacy prompt is dropped, not moved', () async {
      SharedPreferences.setMockInitialValues({'groq_prompt': ''});

      await launch();
      final prefs = await SharedPreferences.getInstance();

      expect(vault.entries, isEmpty);
      expect(prefs.containsKey('groq_prompt'), isFalse);
    });

    test('Groq mode and language survive a restart', () async {
      final settings = await launch();

      await settings.setTranscriptionSource(TranscriptionSource.groq);
      await settings.setGroqLanguage('am');
      final reloaded = await launch();

      expect(reloaded.transcriptionSource, TranscriptionSource.groq);
      expect(reloaded.groqLanguage, 'am');
    });

    test('a chosen profile survives a restart in Groq mode', () async {
      final settings = await launch();
      await settings.setTranscriptionSource(TranscriptionSource.groq);

      await settings.setDictationProfile(DictationProfile.professional);
      final reloaded = await launch();

      expect(reloaded.dictationProfile, DictationProfile.professional);
    });

    test(
      'OpenRouter settings survive a restart, its key only in the vault',
      () async {
        final settings = await launch();
        await settings.setTranscriptionSource(TranscriptionSource.openRouter);
        await settings.setOpenRouterApiKey('sk-or-v1-abc');
        await settings.setOpenRouterModel('microsoft/mai-transcribe-2');
        await settings.setOpenRouterZdr(false);
        await settings.setOpenRouterLanguage('fr');

        final reloaded = await launch();
        final prefs = await SharedPreferences.getInstance();

        expect(reloaded.transcriptionSource, TranscriptionSource.openRouter);
        expect(prefs.getString('transcription_mode'), 'openrouter');
        expect(reloaded.cachedOpenRouterApiKey, 'sk-or-v1-abc');
        expect(vault.entries['openrouter_api_key'], 'sk-or-v1-abc');
        expect(
          prefs.getKeys().where((k) => prefs.get(k) == 'sk-or-v1-abc'),
          isEmpty,
        );
        expect(reloaded.openRouterModel, 'microsoft/mai-transcribe-2');
        expect(reloaded.openRouterZdr, isFalse);
        expect(reloaded.openRouterLanguage, 'fr');
      },
    );

    test('OpenRouter keeps zero data by default, with no model yet', () async {
      final settings = await launch();

      expect(settings.openRouterZdr, isTrue);
      expect(settings.openRouterModel, isNull);
      expect(settings.openRouterLanguage, isEmpty);
      expect(settings.cachedOpenRouterApiKey, isNull);
    });

    test(
      'choosing a model saves it, and the same one again does nothing',
      () async {
        final settings = await launch();
        var notified = 0;
        settings.addListener(() => notified++);

        await settings.setOpenRouterModel('deepgram/nova-3');
        await settings.setOpenRouterModel('deepgram/nova-3');
        final reloaded = await launch();

        expect(notified, 1);
        expect(reloaded.openRouterModel, 'deepgram/nova-3');
      },
    );

    test('the rewrite model is the default until another is chosen, and that '
        'survives a restart', () async {
      final settings = await launch();
      expect(
        (settings.openRouterRewriteModel, settings.hasCustomRewriteModel),
        (AppConstants.openRouterTransformModel, false),
      );
      var notified = 0;
      settings.addListener(() => notified++);

      await settings.setOpenRouterRewriteModel('deepseek/deepseek-v4.1');
      await settings.setOpenRouterRewriteModel('deepseek/deepseek-v4.1');
      final reloaded = await launch();

      expect(notified, 1);
      expect(
        (reloaded.openRouterRewriteModel, reloaded.hasCustomRewriteModel),
        ('deepseek/deepseek-v4.1', true),
      );
    });

    test('an empty rewrite model, or the default, goes back to it', () async {
      final settings = await launch();
      final prefs = await SharedPreferences.getInstance();
      final cleared = <bool>[];
      for (final reset in ['', AppConstants.openRouterTransformModel]) {
        await settings.setOpenRouterRewriteModel('anthropic/claude-haiku-5.5');
        await settings.setOpenRouterRewriteModel(reset);
        cleared.add(
          !settings.hasCustomRewriteModel &&
              !prefs.containsKey('openrouter_rewrite_model'),
        );
      }

      expect(cleared, [true, true]);
      expect(
        settings.openRouterRewriteModel,
        AppConstants.openRouterTransformModel,
      );
    });

    test(
      'a stored rewrite model that isn’t an OpenRouter id is ignored',
      () async {
        SharedPreferences.setMockInitialValues({
          'openrouter_rewrite_model': '../models/x',
        });

        final settings = await launch();

        expect(settings.hasCustomRewriteModel, isFalse);
      },
    );

    test('removing the OpenRouter key deletes it from the vault', () async {
      final settings = await launch();
      await settings.setOpenRouterApiKey('sk-or-v1-abc');

      await settings.setOpenRouterApiKey('');

      expect(settings.cachedOpenRouterApiKey, isNull);
      expect(vault.entries.containsKey('openrouter_api_key'), isFalse);
    });

    test('the cloud key is the active source’s own key', () async {
      final settings = await launch();
      await settings.setGroqApiKey('gsk_groq');
      await settings.setOpenRouterApiKey('sk-or-v1-abc');

      // The server has no cloud key, however many are saved.
      expect((settings.cloudApiKey, settings.hasCloudKey), (null, false));
      await settings.setTranscriptionSource(TranscriptionSource.groq);
      expect(settings.cloudApiKey, 'gsk_groq');
      await settings.setTranscriptionSource(TranscriptionSource.openRouter);
      expect(settings.cloudApiKey, 'sk-or-v1-abc');
      await settings.setOpenRouterApiKey('');
      expect(settings.hasCloudKey, isFalse);
    });

    test('settings saved before OpenRouter, or unknown, still load', () async {
      const stored = {
        'groq': TranscriptionSource.groq,
        'backend': TranscriptionSource.server,
        'whisper': TranscriptionSource.server,
      };
      final loaded = <String, TranscriptionSource>{};
      for (final mode in stored.keys) {
        SharedPreferences.setMockInitialValues({'transcription_mode': mode});
        loaded[mode] = (await launch()).transcriptionSource;
      }

      expect(loaded, stored);
    });

    test('output styles work on OpenRouter and survive a restart', () async {
      final settings = await launch();
      await settings.setTranscriptionSource(TranscriptionSource.openRouter);

      await settings.setDictationProfile(DictationProfile.clean);
      final reloaded = await launch();

      expect(settings.supportsStyles, isTrue);
      expect(reloaded.dictationProfile, DictationProfile.clean);
    });

    test('moving between cloud sources keeps the chosen style', () async {
      final settings = await launch();
      await settings.setTranscriptionSource(TranscriptionSource.groq);
      await settings.setDictationProfile(DictationProfile.casual);

      await settings.setTranscriptionSource(TranscriptionSource.openRouter);

      expect(settings.dictationProfile, DictationProfile.casual);
    });

    test('leaving Groq mode stores the raw profile', () async {
      final settings = await launch();
      await settings.setTranscriptionSource(TranscriptionSource.groq);
      await settings.setDictationProfile(DictationProfile.clean);

      await settings.setTranscriptionSource(TranscriptionSource.server);
      final prefs = await SharedPreferences.getInstance();

      expect(prefs.getString('dictation_profile'), 'raw');
    });

    test('saved custom profiles survive a restart', () async {
      const profile = CustomProfile(
        storageKey: 'custom2',
        name: 'SOAP note',
        userPrompt: 'Format as a SOAP note',
      );
      final settings = await launch();
      await settings.setTranscriptionSource(TranscriptionSource.groq);

      await settings.saveCustomProfile(profile);
      await settings.setDictationProfile(profile);
      final reloaded = await launch();

      expect(reloaded.customProfiles, [profile]);
      expect(reloaded.dictationProfile.storageKey, 'custom2');
      expect(reloaded.nextFreeCustomSlot(), 'custom1');
    });

    test('a deleted custom profile stays deleted after a restart', () async {
      const profile = CustomProfile(
        storageKey: 'custom1',
        name: 'SOAP note',
        userPrompt: 'Format as a SOAP note',
      );
      final settings = await launch();
      await settings.saveCustomProfile(profile);

      await settings.deleteCustomProfile('custom1');
      final reloaded = await launch();

      expect(reloaded.customProfiles, isEmpty);
    });

    test('editing the active custom profile keeps it active', () async {
      final settings = await launch();
      await settings.setTranscriptionSource(TranscriptionSource.groq);
      await settings.saveCustomProfile(
        const CustomProfile(
          storageKey: 'custom1',
          name: 'Draft',
          userPrompt: 'Draft prompt',
        ),
      );
      await settings.setDictationProfile(settings.customProfiles.single);

      await settings.saveCustomProfile(
        const CustomProfile(
          storageKey: 'custom1',
          name: 'Final',
          userPrompt: 'Final prompt',
        ),
      );

      expect(settings.dictationProfile.label, 'Final');
    });

    test('a prompt at the length limit is accepted', () async {
      final settings = await launch();
      final prompt = 'a' * AppConstants.customProfileMaxPromptLength;

      await settings.saveCustomProfile(
        CustomProfile(storageKey: 'custom1', name: 'Long', userPrompt: prompt),
      );

      expect(settings.customProfiles.single.userPrompt, prompt);
    });

    test('corrupt custom profile data loads as no profiles', () async {
      SharedPreferences.setMockInitialValues({
        'custom_profiles_json': '{not json',
      });

      final settings = await launch();

      expect(settings.customProfiles, isEmpty);
      expect(settings.nextFreeCustomSlot(), 'custom1');
    });

    test('nothing can be changed before load', () {
      final settings = SettingsService(vault: vault);

      expect(() => settings.setAutoCopy(false), throwsStateError);
      expect(() => settings.setApiKey('key'), throwsStateError);
      expect(
        () => settings.trustServer('https://a.example:443'),
        throwsStateError,
      );
      expect(() => settings.vault, throwsStateError);
    });

    test('a vault that fails to open fails the load', () async {
      final broken = _MockSecureVaultService();
      when(broken.initialize).thenThrow(StateError('credential store locked'));

      await expectLater(
        SettingsService(vault: broken).load(),
        throwsStateError,
      );
    });
  });

  group('SettingsService.getTokenLabel', () {
    test('a three-part token is a JWT', () {
      expect(
        SettingsService.getTokenLabel('eyJhbGciOi.eyJzdWIiOi.c2lnbmF0dXJl'),
        'Access Token (JWT)',
      );
    });

    test('anything else is an API key', () {
      expect(SettingsService.getTokenLabel('wd_live_123'), 'API Key');
      expect(SettingsService.getTokenLabel('a.b'), 'API Key');
      expect(SettingsService.getTokenLabel('a.b.c.d'), 'API Key');
    });
  });
}
