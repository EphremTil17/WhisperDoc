import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/controllers/recording_controller.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:flutter_client/logic/mappers/home_status_mapper.dart';
import 'package:flutter_client/logic/processors/level_normalizer.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/ui/screens/home/home_status_reader.dart';
import 'package:flutter_client/ui/screens/home/widgets/blocked_body.dart';
import 'package:flutter_client/ui/screens/home/widgets/home_fix_icon.dart';
import 'package:flutter_client/ui/screens/home/widgets/last_transcript.dart';
import 'package:flutter_client/ui/screens/home/widgets/listening_body.dart';
import 'package:flutter_client/ui/screens/home/widgets/listening_cue.dart';
import 'package:flutter_client/ui/screens/home/widgets/shortcut_line.dart';
import 'package:flutter_client/ui/shared/widgets/caption_band.dart';
import 'package:flutter_client/ui/shared/widgets/caption_cue.dart';
import 'package:flutter_client/ui/shared/widgets/topography_background.dart';

/// The middle of the window: one cue, then whatever the phase needs (the
/// shortcut, the fix, or the live meter), and the last transcript set as
/// captions at the bottom, all over contour lines that give way to the meter.
class HomeStage extends StatefulWidget {
  const HomeStage({super.key});

  @override
  State<HomeStage> createState() => _HomeStageState();
}

class _HomeStageState extends State<HomeStage> {
  static const double _cueTop = 64;
  static const double _bottomGap = 20;

  /// Lives as long as the home screen so the learned microphone range
  /// carries over from one recording to the next.
  final LevelNormalizer _normalizer = LevelNormalizer();

  @override
  Widget build(BuildContext context) {
    final status = context.watchHomeStatus();
    final text = context.select((RecordingController c) => c.currentText);
    final arrivedAt = context.select((RecordingController c) => c.transcriptAt);
    final moving = context.select((SettingsService s) => s.animateBackground);
    final phase = status.phase;

    // The contours flatten while recording so the meter has the stage.
    return TopographyBackground(
      active: phase != HomePhase.listening,
      moving: moving,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
        child: Column(
          children: [
            const SizedBox(height: _cueTop),
            if (phase == HomePhase.listening)
              ListeningCue(label: status.cue, tone: status.tone)
            else
              CaptionCue(
                status.cue,
                tone: status.tone,
                icon: phase == HomePhase.blocked
                    ? status.fix.problemIcon
                    : null,
              ),
            const SizedBox(height: AppSpace.md),
            switch (phase) {
              HomePhase.ready => const ShortcutLine(
                trailing: 'to talk',
                style: AppType.title,
              ),
              HomePhase.listening => ListeningBody(normalizer: _normalizer),
              HomePhase.blocked => BlockedBody(status: status),
              HomePhase.working => const SizedBox.shrink(),
            },
            const Spacer(),
            if (phase == HomePhase.listening)
              CaptionBand(
                '[ you’re speaking ]',
                style: AppType.captionBand.copyWith(color: AppColors.textMuted),
              )
            else if (arrivedAt != null && phase != HomePhase.working)
              LastTranscript(text: text, arrivedAt: arrivedAt),
            const SizedBox(height: _bottomGap),
          ],
        ),
      ),
    );
  }
}
