import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/services/settings_service.dart';
import 'package:flutter_client/core/services/websocket_service.dart';
import 'package:flutter_client/ui/components/glass_container.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _uriController;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsService>();
    _uriController = TextEditingController(text: settings.serverUri);
  }

  @override
  void dispose() {
    _uriController.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
    final settings = context.read<SettingsService>();
    await settings.setServerUri(_uriController.text);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: GlassContainer(
        opacity: 0.15,
        blur: 20,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Settings',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(color: Colors.white10),
            const SizedBox(height: 16),

            // Connection Section
            const Text(
              'CONNECTION',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Server URI',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _uriController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.black26,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                hintText: 'ws://localhost:9989/ws',
                hintStyle: const TextStyle(color: Colors.white24),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Test Connection Button
            Consumer<WebSocketService>(
              builder: (context, wsService, child) {
                final status = wsService.status;
                Color btnColor = Colors.white10;
                String btnText = 'Test Connection';

                if (status == ConnectionStatus.connected) {
                  btnColor = Colors.green.withValues(alpha: 0.2);
                  btnText = 'Connected';
                } else if (status == ConnectionStatus.connecting) {
                  btnText = 'Connecting...';
                }

                return FilledButton(
                  onPressed: () async {
                    // Update settings first to trigger reconnect
                    await context.read<SettingsService>().setServerUri(
                      _uriController.text,
                    );
                    // The WebSocketService listens to this and will auto-reconnect
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: btnColor,
                    foregroundColor: status == ConnectionStatus.connected
                        ? Colors.greenAccent
                        : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(btnText),
                );
              },
            ),

            const SizedBox(height: 24),

            // Placeholder for Audio/Hotkeys (Phase 4)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.white30),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Audio & Hotkey settings coming in next update.',
                      style: TextStyle(color: Colors.white30, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Footer
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'v1.5.0',
                  style: TextStyle(color: Colors.white24, fontSize: 12),
                ),
                TextButton(onPressed: _saveSettings, child: const Text('Done')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
