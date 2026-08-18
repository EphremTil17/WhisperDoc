// Mocktail matchers must be invoked inline to register each argument matcher.
// ignore_for_file: prefer-match-file-name, avoid-late-keyword, prefer-moving-to-variable

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_client/infrastructure/constants/app_constants.dart';
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
        version: '2.25.2',
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
  });
}
