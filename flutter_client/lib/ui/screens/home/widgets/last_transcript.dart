import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/infrastructure/theme/app_icons.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:flutter_client/logic/formatters/clock_time.dart';
import 'package:flutter_client/services/utility/clipboard_service.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/ui/shared/widgets/caption_band.dart';
import 'package:flutter_client/ui/shared/widgets/crisp_text.dart';

/// The most recent transcript set as captions, then `✓ 2 min ago` and a
/// copy action. The tick means auto-copy already put it on the clipboard.
class LastTranscript extends StatefulWidget {
  const LastTranscript({
    super.key,
    required this.text,
    required this.arrivedAt,
  });

  final String text;

  /// When the transcript was produced (owned by the recording controller).
  final DateTime arrivedAt;

  @override
  State<LastTranscript> createState() => _LastTranscriptState();
}

class _LastTranscriptState extends State<LastTranscript> {
  static const Duration _confirmFor = Duration(seconds: 2);
  static const Duration _ageRefresh = Duration(seconds: 30);
  static const double _checkSize = 14;

  /// Cached relative age label; only triggers a rebuild when the label changes.
  String _age = '';
  bool _justCopied = false;
  Timer? _ageTimer;
  Timer? _confirmTimer;

  String _ageFor(DateTime now) {
    // A transcript newer than the clock reads as "just now".
    final clamped = now.isBefore(widget.arrivedAt) ? widget.arrivedAt : now;

    return ClockTime.ago(clamped.difference(widget.arrivedAt));
  }

  @override
  void initState() {
    super.initState();
    _age = _ageFor(DateTime.now());
    _ageTimer = Timer.periodic(_ageRefresh, _onAgeTick);
  }

  @override
  void didUpdateWidget(LastTranscript old) {
    super.didUpdateWidget(old);
    if (old.arrivedAt != widget.arrivedAt) {
      _age = _ageFor(DateTime.now());
    }
  }

  void _onAgeTick(Timer _) {
    final next = _ageFor(DateTime.now());
    if (next == _age) return;
    setState(() => _age = next);
  }

  Future<void> _copy() async {
    final ok = await ClipboardService.copyToClipboard(
      widget.text,
      private: context.read<SettingsService>().incognitoMode,
    );
    if (!ok || !mounted) return;
    setState(() => _justCopied = true);
    _confirmTimer?.cancel();
    _confirmTimer = Timer(_confirmFor, _endConfirm);
  }

  void _endConfirm() {
    if (mounted) setState(() => _justCopied = false);
  }

  @override
  void dispose() {
    _ageTimer?.cancel();
    _confirmTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final autoCopy = context.select((SettingsService s) => s.autoCopy);

    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: AppSpace.sm,
      children: [
        CaptionBand(widget.text),
        Row(
          mainAxisSize: MainAxisSize.min,
          spacing: AppSpace.xs,
          children: [
            if (autoCopy || _justCopied)
              const Icon(
                AppIcons.check,
                size: _checkSize,
                color: AppColors.textMuted,
              ),
            CrispText(
              _justCopied ? 'Copied' : _age,
              style: AppType.caption.copyWith(color: AppColors.textMuted),
            ),
            IconButton(
              tooltip: 'Copy again',
              onPressed: () => unawaited(_copy()),
              icon: const Icon(
                AppIcons.copy,
                size: AppSizes.smallIconSize,
                color: AppColors.text,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
