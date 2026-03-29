import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:flutter_client/services/hardware/audio_service.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/controllers/recording_controller.dart';
import 'package:flutter_client/infrastructure/theme/app_theme.dart';

class AudioSection extends StatefulWidget {
  const AudioSection({super.key});

  @override
  State<AudioSection> createState() => _AudioSectionState();
}

class _AudioSectionState extends State<AudioSection> {
  static const _fontSize = 14.0;
  static const _iconSize = 20.0;

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

  DropdownButtonBuilder _buildSelectedItemBuilder(
    List<InputDevice> devices,
    bool isRecording,
  ) {
    return (context) {
      return [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('Default (System Voice Input)'),
        ),
        ...devices.map(
          (device) => DropdownMenuItem<String?>(
            value: device.id,
            child: Text(device.label, overflow: TextOverflow.ellipsis),
          ),
        ),
      ].map((item) {
        final label = (item.child as Text).data ?? '';

        return Align(
          alignment: Alignment.centerLeft,
          child: Text(
            label,
            style: GoogleFonts.lexend(
              color: isRecording ? Colors.white38 : Colors.white,
              fontSize: _fontSize,
            ),
          ),
        );
      }).toList();
    };
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final recordingController = context.watch<RecordingController>();
    final isRecording = recordingController.isRecording;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('AUDIO INPUT', style: AppTheme.sectionTitleStyle),
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
          builder: (context, snapshot) {
            final devices = snapshot.data ?? [];
            final currentId = settings.microphoneId;

            // Ensure currentId is in the list or it's null (Default)
            final foundSelected =
                currentId == null || devices.any((d) => d.id == currentId);

            return DropdownButtonFormField<String?>(
              initialValue: foundSelected ? currentId : null,
              isExpanded: true,
              dropdownColor: const Color(0xFF1E1E23),
              icon: Icon(
                Icons.keyboard_arrow_down,
                color: isRecording ? Colors.white10 : Colors.white24,
                size: _iconSize,
              ),
              borderRadius: const BorderRadius.all(Radius.circular(8)),
              style: GoogleFonts.lexend(
                color: isRecording ? Colors.white38 : Colors.white,
                fontSize: _fontSize,
              ),
              decoration: const InputDecoration(
                filled: true,
                fillColor: Colors.black26,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                  borderSide: BorderSide.none,
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
              ),
              selectedItemBuilder: _buildSelectedItemBuilder(
                devices,
                isRecording,
              ),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(
                    'Default (System Voice Input)',
                    style: GoogleFonts.lexend(fontSize: _fontSize),
                  ),
                ),
                ...devices.map(
                  (d) => DropdownMenuItem<String?>(
                    value: d.id,
                    child: Text(
                      d.label,
                      style: GoogleFonts.lexend(fontSize: _fontSize),
                    ),
                  ),
                ),
              ],
              onChanged: isRecording
                  ? null
                  : _buildDeviceChangedHandler(settings, devices),
            );
          },
        ),
      ],
    );
  }
}
