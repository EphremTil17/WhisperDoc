import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/services/audio_service.dart';
import 'package:flutter_client/core/services/hotkey_service.dart';
import 'package:flutter_client/core/services/websocket_service.dart'; // Import for ConnectionStatus
import 'package:flutter_client/ui/components/custom_title_bar.dart';
import 'package:flutter_client/ui/components/floating_capsule.dart';
import 'package:flutter_client/ui/components/hamburger_menu.dart';
import 'package:flutter_client/ui/screens/settings_screen.dart';
import 'package:flutter_client/ui/theme/app_theme.dart';
import 'package:google_fonts/google_fonts.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _AppColors {
  static const crimsonPrimary = Color(0xFFD4183D);
}

class _HomeScreenState extends State<HomeScreen> {
  StreamSubscription? _hotkeySubscription;
  StreamSubscription? _audioSubscription;
  StreamSubscription? _messageSubscription;

  @override
  void initState() {
    super.initState();
    _initHotkeys();
    _initWebSocketListeners();
    _initAudioListeners();
  }

  void _initWebSocketListeners() {
    _messageSubscription = context.read<WebSocketService>().onMessage.listen((
      msg,
    ) {
      if (msg.containsKey('text')) {
        final text = msg['text'] as String;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Transcribed: $text'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      } else if (msg.containsKey('error')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${msg['error']}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    });
  }

  void _initAudioListeners() {
    _audioSubscription = context.read<AudioService>().audioStream.listen((
      data,
    ) {
      context.read<WebSocketService>().sendAudioChunk(data);
    });
  }

  void _initHotkeys() {
    // Start the service if not already started
    // ignore: discarded_futures
    context.read<HotkeyService>().start();

    // Listen for hotkeys
    _hotkeySubscription = context.read<HotkeyService>().onHotkeyPressed.listen((
      event,
    ) {
      // ignore: discarded_futures
      _toggleRecording();
    });
  }

  @override
  void dispose() {
    // ignore: discarded_futures
    _hotkeySubscription?.cancel();
    // ignore: discarded_futures
    _audioSubscription?.cancel();
    // ignore: discarded_futures
    _messageSubscription?.cancel();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    final audioService = context.read<AudioService>();
    final wsService = context.read<WebSocketService>();

    if (audioService.isRecording) {
      await audioService.stopRecording();
      wsService.sendEndSignal();
    } else {
      // Trigger connection in background (don't await)
      if (wsService.status != ConnectionStatus.connected) {
        // ignore: discarded_futures
        wsService.connect();
      }

      // START RECORDING IMMEDIATELY
      // The WebSocketService will buffer the chunks until the connection is ready
      await audioService.startRecording();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch AudioService for recording state
    final isRecording = context.select<AudioService, bool>(
      (service) => service.isRecording,
    );

    return Scaffold(
      body: Container(
        decoration: AppTheme.mainGradient,
        child: Column(
          children: [
            // CustomTitleBar relative to the Column, but we will use Stack for absolute positioning of Menu
            const CustomTitleBar(),

            // Main Content Area
            Expanded(
              child: Stack(
                children: [
                  // Hamburger Menu - Top Right
                  const Positioned(top: 24, right: 24, child: HamburgerMenu()),

                  // Center Content
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Title...
                        const Text(
                          'WhisperDoc',
                          style: TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -1.0,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'AI-Powered Speech-to-Text Dictation',
                          style: TextStyle(fontSize: 14, color: Colors.white54),
                        ),
                        const SizedBox(height: 48),

                        // Main Interaction Capsule...
                        FloatingCapsule(
                          isRecording: isRecording,
                          onTap: _toggleRecording,
                        ),

                        const SizedBox(height: 32),

                        // Hotkey Hint...
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.1),
                            ),
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
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.1,
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'Ctrl+Alt+W',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 11,
                                        fontFamily:
                                            GoogleFonts.lexend().fontFamily,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                const TextSpan(text: ' to start recording'),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 32),

                        // Red Settings Button (Below Hotkey Hint)
                        GestureDetector(
                          onTap: () {
                            // ignore: discarded_futures
                            showDialog(
                              context: context,
                              builder: (ctx) => const SettingsScreen(),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _AppColors.crimsonPrimary.withValues(
                                alpha: 0.1,
                              ),
                              border: Border.all(
                                color: _AppColors.crimsonPrimary.withValues(
                                  alpha: 0.3,
                                ),
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.settings_outlined,
                              color: _AppColors.crimsonPrimary,
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Footer / Status Bar
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: StreamBuilder<ConnectionStatus>(
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
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
