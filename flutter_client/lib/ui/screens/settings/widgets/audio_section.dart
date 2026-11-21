import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:flutter_client/services/hardware/audio_service.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/controllers/recording_controller.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:flutter_client/ui/shared/widgets/app_dropdown.dart';

class AudioSection extends StatefulWidget {
  const AudioSection({super.key});

  @override
  State<AudioSection> createState() => _AudioSectionState();
}

class _AudioSectionState extends State<AudioSection> {
  Future<List<InputDevice>> _devicesFuture = Future<List<InputDevice>>.value(
    const <InputDevice>[],
  );

  @override
  void initState() {
    super.initState();
    _devicesFuture = _loadDevices();
  }

  Future<List<InputDevice>> _loadDevices() {
    return context.read<AudioService>().listInputDevices();
  }

  void _refreshDevices() {
    _devicesFuture = _loadDevices();
  }

  void _handleRefreshPressed() {
    setState(_refreshDevices);
  }

  ValueChanged<String?> _buildDeviceChangedHandler(
    SettingsService settings,
    List<InputDevice> devices,
  ) {
    return (id) {
      final label = id == null
          ? null
          : devices.firstWhere((device) => device.id == id).label;
      unawaited(settings.setMicrophoneSelection(id, label));
    };
  }

  Widget _buildDevicePicker(
    SettingsService settings,
    List<InputDevice> devices,
    bool isRecording,
  ) {
    final currentId = settings.microphoneId;
    // A remembered device that is no longer present shows as Default.
    final isListed = currentId == null || devices.any((d) => d.id == currentId);

    return AppDropdown<String?>(
      value: isListed ? currentId : null,
      items: [
        const AppDropdownItem(
          value: null,
          label: 'Default (System Voice Input)',
        ),
        for (final device in devices)
          AppDropdownItem(value: device.id, label: device.label),
      ],
      onChanged: isRecording
          ? null
          : _buildDeviceChangedHandler(settings, devices),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final isRecording = context.select(
      (RecordingController c) => c.isRecording,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Microphone', style: AppType.label),
            if (!isRecording)
              IconButton(
                onPressed: _handleRefreshPressed,
                icon: const Icon(
                  Icons.refresh,
                  color: Colors.white38,
                  size: 16,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Refresh Devices',
              ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Voice Input Device',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        const SizedBox(height: 8),
        FutureBuilder<List<InputDevice>>(
          future: _devicesFuture,
          builder: (context, snapshot) => _buildDevicePicker(
            settings,
            snapshot.data ?? const [],
            isRecording,
          ),
        ),
      ],
    );
  }
}
