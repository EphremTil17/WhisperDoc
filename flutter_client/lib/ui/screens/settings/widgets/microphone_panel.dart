import 'dart:async';

import 'package:flutter_client/infrastructure/theme/app_icons.dart';
import 'package:flutter_client/services/hardware/audio_service.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/ui/shared/widgets/panel/choice_panel.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

/// Pick the input device. The list is read when the panel opens and on
/// refresh; a remembered device that is gone shows as the system default.
class MicrophonePanel extends StatefulWidget {
  const MicrophonePanel({super.key});

  @override
  State<MicrophonePanel> createState() => _MicrophonePanelState();
}

class _MicrophonePanelState extends State<MicrophonePanel> {
  Future<List<InputDevice>> _devices = Future.value(const <InputDevice>[]);

  @override
  void initState() {
    super.initState();
    _devices = _load();
  }

  Future<List<InputDevice>> _load() =>
      context.read<AudioService>().listInputDevices();

  void _select(List<InputDevice> devices, String? id) {
    final label = devices.where((d) => d.id == id).firstOrNull?.label;
    unawaited(
      context.read<SettingsService>().setMicrophoneSelection(id, label),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = context.select((SettingsService s) => s.microphoneId);

    return FutureBuilder<List<InputDevice>>(
      future: _devices,
      builder: (context, snapshot) {
        final devices = snapshot.data ?? const <InputDevice>[];
        final cue = switch (snapshot.connectionState) {
          ConnectionState.waiting => 'looking for microphones',
          _ when devices.isEmpty => 'no microphones found',
          _ => null,
        };
        final listed = current == null || devices.any((d) => d.id == current);

        return ChoicePanel<String?>(
          title: 'Microphone',
          options: [
            (null, 'System default'),
            for (final device in devices) (device.id, device.label),
          ],
          selected: listed ? current : null,
          onSelected: (id) => _select(devices, id),
          actions: [
            IconButton(
              tooltip: 'Refresh devices',
              onPressed: () => setState(() => _devices = _load()),
              icon: const Icon(AppIcons.refreshCw),
            ),
          ],
          cue: cue,
          note: 'System default follows the input chosen in Windows.',
        );
      },
    );
  }
}
