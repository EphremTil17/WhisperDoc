import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/services/websocket_service.dart';
import 'core/services/audio_service.dart';
import 'core/services/hotkey_service.dart';
import 'core/services/logging_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Services
  final wsService = WebSocketService();
  final audioService = AudioService();
  final hotkeyService = HotkeyService();

  // Initial connection
  wsService.connect();

  runApp(
    MultiProvider(
      providers: [
        Provider.value(value: wsService),
        Provider.value(value: audioService),
        Provider.value(value: hotkeyService),
      ],
      child: const WhisperDocApp(),
    ),
  );
}

class WhisperDocApp extends StatelessWidget {
  const WhisperDocApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WhisperDoc',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorSchemeSeed: Colors.blueAccent,
      ),
      home: const InitializationScreen(),
    );
  }
}

class InitializationScreen extends StatefulWidget {
  const InitializationScreen({super.key});

  @override
  State<InitializationScreen> createState() => _InitializationScreenState();
}

class _InitializationScreenState extends State<InitializationScreen> {
  @override
  void initState() {
    super.initState();
    // ignore: discarded_futures
    _startHotkeyService();
  }

  Future<void> _startHotkeyService() async {
    final hotkeyService = context.read<HotkeyService>();
    try {
      await hotkeyService.start();
      LoggingService().info('Bootstrap: Hotkey Service Ready');
    } catch (e) {
      LoggingService().error(
        'Bootstrap: Failed to start Hotkey Service',
        error: e,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.mic_none, size: 64, color: Colors.blueAccent),
            const SizedBox(height: 16),
            const Text(
              'WhisperDoc',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('Native Windows Client'),
            const SizedBox(height: 32),
            StreamBuilder<ConnectionStatus>(
              stream: context.read<WebSocketService>().onStatusChanged,
              builder: (context, snapshot) {
                final status = snapshot.data ?? ConnectionStatus.disconnected;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _getStatusColor(status),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('Server: ${status.name.toUpperCase()}'),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(ConnectionStatus status) {
    switch (status) {
      case ConnectionStatus.connected:
        return Colors.green;
      case ConnectionStatus.connecting:
        return Colors.orange;
      case ConnectionStatus.disconnected:
        return Colors.red;
    }
  }
}
