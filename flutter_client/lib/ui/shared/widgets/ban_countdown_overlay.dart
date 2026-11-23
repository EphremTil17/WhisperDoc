import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_client/infrastructure/theme/app_icons.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:flutter_client/logic/mappers/home_status_mapper.dart';
import 'package:flutter_client/ui/shared/widgets/app_button.dart';
import 'package:flutter_client/ui/shared/widgets/caption_cue.dart';
import 'package:flutter_client/ui/shared/widgets/crisp_text.dart';

/// Ban countdown overlay widget displayed when IP is banned by the backend.
///
/// Shows:
/// - Warning message about ban status
/// - Countdown timer showing remaining seconds
/// - Disabled reconnect button during cooldown
/// - Enabled reconnect button after cooldown expires
///
/// Designed to be shown as a modal overlay or integrated into status UI.
class BanCountdownOverlay extends StatefulWidget {
  const BanCountdownOverlay({
    super.key,
    required this.countdownStream,
    required this.initialSeconds,
    required this.onReconnect,
  });

  final Stream<int> countdownStream;

  /// Cooldown at the moment the overlay appears. The stream only emits on the
  /// next tick, so without this the overlay briefly showed "Ban expired" with
  /// Reconnect enabled.
  final int initialSeconds;
  final VoidCallback onReconnect;

  @override
  State<BanCountdownOverlay> createState() => _BanCountdownOverlayState();
}

class _BanCountdownOverlayState extends State<BanCountdownOverlay> {
  static const _secondsPerMinute = 60;

  int _remainingSeconds = 0;
  StreamSubscription<int>? _subscription;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.initialSeconds;
    _subscription = widget.countdownStream.listen((seconds) {
      if (mounted) {
        setState(() {
          _remainingSeconds = seconds;
        });
      }
    });
  }

  String _formatDuration(int seconds) {
    if (seconds <= 0) return '0s';

    final minutes = seconds ~/ _secondsPerMinute;
    final remainingSeconds = seconds % _secondsPerMinute;

    if (minutes > 0) {
      return '${minutes}m ${remainingSeconds}s';
    }

    return '${seconds}s';
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isBanned = _remainingSeconds > 0;

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.controlAll,
        border: Border.fromBorderSide(BorderSide(color: AppColors.rule)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: AppSpace.md,
          children: [
            const CaptionCue('paused', tone: CueTone.alert, icon: AppIcons.ban),
            CrispText(
              isBanned
                  ? 'Too many failed sign-in attempts.'
                  : 'You can reconnect now.',
              textAlign: TextAlign.center,
              style: AppType.title,
            ),
            if (isBanned)
              CrispText(
                'Try again in ${_formatDuration(_remainingSeconds)}',
                style: AppType.caption.copyWith(color: AppColors.textMuted),
              ),
            const SizedBox(height: AppSpace.xs),
            AppButton(
              label: isBanned ? 'Please wait' : 'Reconnect',
              leading: const Icon(
                AppIcons.refreshCw,
                size: AppSizes.smallIconSize,
              ),
              onPressed: isBanned ? null : widget.onReconnect,
            ),
          ],
        ),
      ),
    );
  }
}
