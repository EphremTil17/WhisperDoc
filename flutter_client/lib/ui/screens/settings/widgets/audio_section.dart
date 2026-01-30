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
  late Future<List<InputDevice>> _devicesFuture;

  @override
  void initState() {
    super.initState();
    _refreshDevices();
  }

  void _refreshDevices() {
    setState(() {
      _devicesFuture = context.read<AudioService>().listInputDevices();
    });
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
                onPressed: _refreshDevices,
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
                size: 20,
              ),
              borderRadius: BorderRadius.circular(8),
              style: GoogleFonts.lexend(
                color: isRecording ? Colors.white38 : Colors.white,
                fontSize: 14,
              ),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.black26,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
              ),
              selectedItemBuilder: (context) {
                return [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Default (System Voice Input)'),
                  ),
                  ...devices.map(
                    (d) => DropdownMenuItem<String?>(
                      value: d.id,
                      child: Text(d.label, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ].map((item) {
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      (item.child as Text).data!,
                      style: GoogleFonts.lexend(
                        color: isRecording ? Colors.white38 : Colors.white,
                        fontSize: 14,
                      ),
                    ),
                  );
                }).toList();
              },
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(
                    'Default (System Voice Input)',
                    style: GoogleFonts.lexend(fontSize: 14),
                  ),
                ),
                ...devices.map(
                  (d) => DropdownMenuItem<String?>(
                    value: d.id,
                    child: Text(
                      d.label,
                      style: GoogleFonts.lexend(fontSize: 14),
                    ),
                  ),
                ),
              ],
              onChanged: isRecording
                  ? null
                  : (id) async {
                      final label = id == null
                          ? null
                          : devices.firstWhere((d) => d.id == id).label;
                      await settings.setMicrophoneSelection(id, label);
                    },
            );
          },
        ),
      ],
    );
  }
}
