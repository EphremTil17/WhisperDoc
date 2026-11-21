// ignore_for_file: avoid-late-keyword
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/controllers/profile_controller.dart';
import 'package:flutter_client/controllers/recording_controller.dart';
import 'package:flutter_client/infrastructure/theme/app_theme.dart';
import 'package:flutter_client/logic/models/dictation_profile.dart';
import 'package:flutter_client/services/hardware/audio_input_status.dart';
import 'package:flutter_client/services/hardware/audio_service.dart';
import 'package:flutter_client/services/transcription/groq_transcription_service.dart';
import 'package:flutter_client/services/transport/handshake_state_machine.dart';
import 'package:flutter_client/services/transport/websocket_service.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/services/utility/update_service.dart';
import 'package:flutter_client/ui/screens/home/widgets/account_indicator.dart';
import 'package:flutter_client/ui/screens/home/widgets/home_bottom_bar.dart';
import 'package:flutter_client/ui/screens/home/widgets/home_stage.dart';
import 'package:flutter_client/ui/shared/widgets/custom_title_bar.dart';

class _MockRecordingController extends Mock
    with ChangeNotifier
    implements RecordingController {}

class _MockProfileController extends Mock
    with ChangeNotifier
    implements ProfileController {}

class _MockSettingsService extends Mock
    with ChangeNotifier
    implements SettingsService {}

class _MockWebSocketService extends Mock
    with ChangeNotifier
    implements WebSocketService {}

class _MockUpdateService extends Mock
    with ChangeNotifier
    implements UpdateService {}

class _MockGroqTranscriptionService extends Mock
    with ChangeNotifier
    implements GroqTranscriptionService {}

// AudioService.dispose returns a Future, so it cannot take the ChangeNotifier
// mixin; the listener methods are stubbed by Mock instead.
class _MockAudioService extends Mock implements AudioService {}

class _MockHandshakeStateMachine extends Mock
    implements HandshakeStateMachine {}

/// Pumps the composed home screen (title bar, stage, bottom bar), or one of
/// the panels it opens, at the window's real 420×600 client size over mocked
/// services, and exposes the knobs that move it between states.
class HomeOrchestrator {
  HomeOrchestrator(this.tester) {
    when(() => recording.inputStatus).thenReturn(AudioInputStatus.available);
    when(() => recording.isRecording).thenReturn(false);
    when(() => recording.isTranscribing).thenReturn(false);
    when(() => recording.isSessionActive).thenReturn(false);
    when(() => recording.currentText).thenReturn('');
    when(() => recording.transcriptAt).thenReturn(null);
    when(() => recording.showSilenceWarning).thenReturn(false);
    when(() => recording.incognitoMode).thenReturn(false);
    when(recording.toggleRecording).thenAnswer((_) => Future.value());

    when(() => settings.isGroqMode).thenReturn(true);
    when(() => settings.dictationProfile).thenReturn(DictationProfile.raw);
    when(() => settings.globalHotkey).thenReturn('Ctrl+Q');
    when(() => settings.showVisualizer).thenReturn(true);
    when(() => settings.autoCopy).thenReturn(true);
    when(() => settings.customProfiles).thenReturn([]);
    when(settings.nextFreeCustomSlot).thenReturn('custom1');
    when(() => settings.cachedGroqApiKey).thenReturn('test-key');
    when(() => settings.groqModel).thenReturn('whisper-large-v3-turbo');
    when(() => settings.groqLanguage).thenReturn('');
    when(() => settings.groqPrompt).thenReturn('');
    when(() => settings.appVersion).thenReturn('3.1.0');
    when(() => settings.serverUri).thenReturn('wss://whisper.example.com/ws');
    when(() => settings.cachedApiKey).thenReturn(null);
    when(() => settings.microphoneId).thenReturn(null);
    when(() => settings.microphoneLabel).thenReturn(null);
    when(() => settings.autoPaste).thenReturn(true);

    when(() => profile.isAuthenticated).thenReturn(false);
    when(() => profile.currentUser).thenReturn(null);
    when(() => profile.updateStatus).thenReturn(UpdateStatus.upToDate);
    when(() => profile.latestVersion).thenReturn(null);
    when(() => profile.latestDownloadUrl).thenReturn(null);

    final handshake = _MockHandshakeStateMachine();
    when(() => handshake.state).thenReturn(HandshakeState.locked);
    when(() => ws.handshakeState).thenReturn(handshake);
    when(() => ws.status).thenReturn(ConnectionStatus.disconnected);
    when(() => ws.isAuthenticatedSession).thenReturn(true);
    when(() => update.status).thenReturn(UpdateStatus.upToDate);
    when(() => groq.hasValidCredentials).thenReturn(true);
    when(() => audio.amplitudeStream).thenAnswer((_) => levels.stream);
  }

  static const Size window = Size(420, 600);

  final WidgetTester tester;
  final RecordingController recording = _MockRecordingController();
  final SettingsService settings = _MockSettingsService();
  final ProfileController profile = _MockProfileController();
  final WebSocketService ws = _MockWebSocketService();
  final UpdateService update = _MockUpdateService();
  final GroqTranscriptionService groq = _MockGroqTranscriptionService();
  final AudioService audio = _MockAudioService();
  final StreamController<double> levels = StreamController<double>.broadcast();
  int incognitoTaps = 0;

  /// A transcript produced [age] ago (as the controller timestamps it).
  void showTranscript(String text, {Duration age = Duration.zero}) {
    when(() => recording.currentText).thenReturn(text);
    when(() => recording.transcriptAt).thenReturn(DateTime.now().subtract(age));
  }

  void startRecording() {
    when(() => recording.isRecording).thenReturn(true);
    when(() => recording.isSessionActive).thenReturn(true);
  }

  void removeGroqKey() {
    when(() => groq.hasValidCredentials).thenReturn(false);
    when(() => settings.cachedGroqApiKey).thenReturn(null);
  }

  void unplugMicrophone() {
    when(() => recording.inputStatus).thenReturn(AudioInputStatus.noDevice);
  }

  void offerUpdate() {
    when(() => update.status).thenReturn(UpdateStatus.advisory);
    when(() => profile.updateStatus).thenReturn(UpdateStatus.advisory);
    when(() => profile.latestVersion).thenReturn('3.2.0');
  }

  static bool _fontsLoaded = false;

  /// Real Lexend, Lucide and JetBrains Mono instead of the test font, so widths (and any
  /// captured pixels) match the app.
  static Future<void> _loadFonts() async {
    if (_fontsLoaded) return;
    const families = {
      'Lexend': [
        'assets/fonts/Lexend-Regular.ttf',
        'assets/fonts/Lexend-Medium.ttf',
        'assets/fonts/Lexend-SemiBold.ttf',
      ],
      'Lucide': ['assets/fonts/Lucide.ttf'],
      'JetBrains Mono': ['assets/fonts/JetBrainsMono-Regular.ttf'],
    };
    for (final MapEntry(key: family, value: files) in families.entries) {
      final loader = FontLoader(family);
      for (final file in files) {
        loader.addFont(rootBundle.load(file));
      }
      await loader.load();
    }
    _fontsLoaded = true;
  }

  /// The home screen as the window shows it.
  Future<void> pump() => _pumpApp(
    Scaffold(
      body: Column(
        children: [
          const CustomTitleBar(trailing: AccountIndicator()),
          const Expanded(child: HomeStage()),
          HomeBottomBar(onIncognitoTap: () => incognitoTaps++),
        ],
      ),
    ),
  );

  /// One panel (Account, Settings, …) filling the window.
  Future<void> pumpPanel(Widget panel) => _pumpApp(panel);

  Future<void> _pumpApp(Widget home) async {
    await tester.runAsync(_loadFonts);
    tester.view.physicalSize = window;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(levels.close);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<RecordingController>.value(value: recording),
          ChangeNotifierProvider<SettingsService>.value(value: settings),
          ChangeNotifierProvider<ProfileController>.value(value: profile),
          ChangeNotifierProvider<WebSocketService>.value(value: ws),
          ChangeNotifierProvider<UpdateService>.value(value: update),
          ChangeNotifierProvider<GroqTranscriptionService>.value(value: groq),
          ChangeNotifierProvider<AudioService>.value(value: audio),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.darkTheme,
          home: home,
        ),
      ),
    );
    await tester.pump();
  }
}
