import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/services/audio_service.dart';
import 'package:flutter_client/core/services/hotkey_service.dart';
import 'package:flutter_client/core/services/websocket_service.dart';
import 'package:flutter_client/core/services/settings_service.dart';
import 'package:flutter_client/core/services/clipboard_service.dart';
import 'package:flutter_client/core/services/logging_service.dart';
import 'package:flutter_client/ui/components/custom_title_bar.dart';
import 'package:flutter_client/ui/components/floating_capsule.dart';
import 'package:flutter_client/ui/components/hamburger_menu.dart';
import 'package:flutter_client/ui/components/refined_icon_button.dart';
import 'package:flutter_client/ui/components/transcribed_text_area.dart';
import 'package:flutter_client/ui/components/audio_visualizer.dart';
import 'package:flutter_client/ui/screens/settings_screen.dart';
import 'package:flutter_client/ui/theme/app_theme.dart';
import 'package:google_fonts/google_fonts.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  StreamSubscription? _hotkeySubscription;
  StreamSubscription? _audioSubscription;
  StreamSubscription? _messageSubscription;

  String _transcriptionBuffer = '';

  @override
  void initState() {
    super.initState();
    _initHotkeys();
    _initWebSocketListeners();
    _initAudioListeners();
  }

  // Flag to indicate we're awaiting final transcription after recording stopped
  bool _awaitingFinalTranscription = false;

  void _initWebSocketListeners() {
    final wsService = context.read<WebSocketService>();
    final settingsService = context.read<SettingsService>();

    _messageSubscription = wsService.onMessage.listen((msg) {
      if (!mounted) return;

      // Handle transcription result (the main success case)
      if (msg.containsKey('text')) {
        final text = msg['text'] as String;
        setState(() {
          if (_transcriptionBuffer.isEmpty) {
            _transcriptionBuffer = text;
          } else {
            _transcriptionBuffer += ' $text';
          }
        });

        // If we were waiting for final transcription, trigger auto-copy/paste immediately
        if (_awaitingFinalTranscription) {
          _awaitingFinalTranscription = false;
          unawaited(_handleTranscriptionComplete(settingsService));
        }
      }
      // Handle event-based messages from server
      else if (msg.containsKey('event')) {
        final event = msg['event'] as String;

        if (event == 'error') {
          _awaitingFinalTranscription = false;
          final errorMsg = msg['message'] ?? msg['code'] ?? 'Unknown error';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: $errorMsg'),
              backgroundColor: Colors.redAccent,
            ),
          );
        } else if (event == 'status') {
          // Server status update (e.g., "Waking up GPU...")
          // Could show a subtle indicator, but for now just log it
          LoggingService().info(
            'Server status: ${msg['message']}',
            sendToServer: false,
          );
        }
        // 'hello' and 'pong' events are handled silently
      }
      // Legacy error format
      else if (msg.containsKey('error')) {
        _awaitingFinalTranscription = false;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${msg['error']}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    });
  }

  Future<void> _handleTranscriptionComplete(SettingsService settings) async {
    final textToCopy = _transcriptionBuffer.trim();
    if (textToCopy.isEmpty) return;

    LoggingService().info(
      'Transcription complete. Starting automation...',
      sendToServer: false,
    );

    try {
      if (settings.autoCopy) {
        await ClipboardService.copyToClipboard(textToCopy);
        if (settings.autoPaste) {
          await ClipboardService.simulatePaste();
        }
      }
      // Clear buffer only after successful automation
      if (mounted) {
        setState(() => _transcriptionBuffer = '');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Automation Error: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _initAudioListeners() {
    final wsService = context.read<WebSocketService>();
    _audioSubscription = context.read<AudioService>().audioStream.listen((
      data,
    ) {
      wsService.sendAudioChunk(data);
    });
  }

  void _initHotkeys() {
    final hotkeyService = context.read<HotkeyService>();
    final settings = context.read<SettingsService>();

    unawaited(
      hotkeyService.start().then((_) {
        _registerCurrentHotkey(hotkeyService, settings);
      }),
    );

    _hotkeySubscription = hotkeyService.onHotkeyPressed.listen((event) {
      if (event == 1) {
        // 1 is our hotkey ID
        unawaited(_toggleRecording());
      }
    });

    // Handle hotkey changes from settings
    settings.addListener(_onSettingsChanged);
  }

  void _onSettingsChanged() {
    final hotkeyService = context.read<HotkeyService>();
    final settings = context.read<SettingsService>();

    _registerCurrentHotkey(hotkeyService, settings);

    if (mounted) setState(() {});
  }

  void _registerCurrentHotkey(HotkeyService service, SettingsService settings) {
    unawaited(
      service.unregisterHotkey(1).then((_) {
        return service.registerHotkey(
          id: 1,
          modifiers: settings.hotkeyModifiers,
          vKey: settings.hotkeyVKey,
        );
      }),
    );
  }

  @override
  void dispose() {
    context.read<SettingsService>().removeListener(_onSettingsChanged);
    unawaited(_hotkeySubscription?.cancel());
    unawaited(_audioSubscription?.cancel());
    unawaited(_messageSubscription?.cancel());
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    final audioService = context.read<AudioService>();
    final wsService = context.read<WebSocketService>();

    if (audioService.isRecording) {
      await audioService.stopRecording();
      wsService.sendEndSignal();

      // Set flag to trigger auto-copy/paste when server sends transcription
      _awaitingFinalTranscription = true;
    } else {
      setState(() {
        _transcriptionBuffer = ''; // Clear buffer for new recording
        _awaitingFinalTranscription = false;
      });

      if (wsService.status != ConnectionStatus.connected) {
        await wsService.connect();
      }

      await audioService.startRecording();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRecording = context.select<AudioService, bool>(
      (service) => service.isRecording,
    );

    return Scaffold(
      body: Container(
        decoration: AppTheme.mainGradient,
        child: Column(
          children: [
            const CustomTitleBar(),
            Expanded(
              child: Stack(
                children: [
                  const Positioned(top: 10, right: 24, child: HamburgerMenu()),
                  SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        children: [
                          const SizedBox(height: 16),
                          // Title Section
                          const Text(
                            'WhisperDoc',
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -1.0,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'AI-Powered Speech-to-Text Dictation',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white54,
                            ),
                          ),

                          const SizedBox(height: 16),
                          FloatingCapsule(
                            isRecording: isRecording,
                            onTap: _toggleRecording,
                          ),

                          const SizedBox(height: 8),
                          if (isRecording) ...[
                            const AudioVisualizer(),
                            const SizedBox(height: 8),
                          ] else
                            const SizedBox(height: 8),

                          _buildHotkeyHint(),
                          const SizedBox(height: 12),
                          TranscribedTextArea(text: _transcriptionBuffer),

                          const SizedBox(height: 12),
                          // Footer with Settings and Status in one row
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              RefinedIconButton(
                                icon: Icons.settings_outlined,
                                iconColor: AppTheme.crimsonPrimary,
                                iconSize: 18,
                                onTap: () {
                                  unawaited(
                                    showDialog(
                                      context: context,
                                      builder: (ctx) => const SettingsScreen(),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(width: 16),
                              _buildStatusBar(),
                            ],
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHotkeyHint() {
    final settings = context.read<SettingsService>();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: RichText(
        text: TextSpan(
          style: TextStyle(
            color: Colors.white54,
            fontSize: 12,
            fontFamily: GoogleFonts.lexend().fontFamily,
          ),
          children: [
            const TextSpan(text: 'Press '),
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  settings.globalHotkey,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontFamily: GoogleFonts.lexend().fontFamily,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const TextSpan(text: ' to start recording'),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBar() {
    return StreamBuilder<ConnectionStatus>(
      stream: context.read<WebSocketService>().onStatusChanged,
      initialData: ConnectionStatus.disconnected,
      builder: (context, snapshot) {
        final status = snapshot.data ?? ConnectionStatus.disconnected;
        Color statusColor;
        String statusText;

        switch (status) {
          case ConnectionStatus.connected:
            statusColor = Colors.greenAccent;
            statusText = "Connected";
            break;
          case ConnectionStatus.connecting:
            statusColor = Colors.orangeAccent;
            statusText = "Connecting...";
            break;
          default:
            statusColor = Colors.white54;
            statusText = "Ready (Deep Sleep)";
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: statusColor.withValues(alpha: 0.4),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              statusText,
              style: TextStyle(
                color: statusColor,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                fontFamily: GoogleFonts.lexend().fontFamily,
              ),
            ),
          ],
        );
      },
    );
  }
}
