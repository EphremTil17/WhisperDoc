import 'dart:async';

import 'package:flutter_client/controllers/recording_controller.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:flutter_client/logic/models/transcription_source.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/ui/screens/account/account_fields.dart';
import 'package:flutter_client/ui/screens/account/widgets/source_segment.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// Where dictation is transcribed: your server, Groq or OpenRouter, as one
/// segmented control. Locked while a dictation is under way.
class SourceSelector extends StatelessWidget {
  const SourceSelector({super.key});

  static const Map<TranscriptionSource, String> _shortLabels = {
    TranscriptionSource.server: 'Self-hosted',
    TranscriptionSource.groq: 'Groq',
    TranscriptionSource.openRouter: 'OpenRouter',
  };

  /// Switching to a cloud source without its key goes straight to adding
  /// one.
  static Future<void> _select(
    BuildContext context,
    TranscriptionSource source,
  ) async {
    final settings = context.read<SettingsService>();
    await settings.setTranscriptionSource(source);
    if (!context.mounted || !source.isCloud || settings.hasCloudKey) return;
    await AccountFields.apiKey(context, source);
  }

  @override
  Widget build(BuildContext context) {
    final current = context.select(
      (SettingsService s) => s.transcriptionSource,
    );
    final busy = context.select((RecordingController c) => c.isSessionActive);

    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border.fromBorderSide(BorderSide(color: AppColors.rule)),
      ),
      child: Row(
        children: [
          for (final (index, source) in TranscriptionSource.values.indexed) ...[
            if (index > 0)
              const SizedBox(
                width: 1,
                height: AppSizes.controlHeight,
                child: ColoredBox(color: AppColors.rule),
              ),
            Expanded(
              child: SourceSegment(
                source: source,
                label: _shortLabels[source] ?? source.label,
                selected: source == current,
                onTap: busy || source == current
                    ? null
                    : () => unawaited(_select(context, source)),
                hint: busy ? 'Finish the recording first' : source.label,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
