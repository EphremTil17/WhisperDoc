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
  const LastTranscript({super.key, required this.text});

  final String text;

  @override
  State<LastTranscript> createState() => _LastTranscriptState();
}

class _LastTranscriptState extends State<LastTranscript> {
  static const Duration _confirmFor = Duration(seconds: 2);
  static const Duration _ageRefresh = Duration(seconds: 30);
  static const double _checkSize = 14;

  /// When this transcript appeared (it appears as transcription finishes).
  DateTime _arrivedAt = DateTime.now();

  /// Clock the age is measured against; ticks every [_ageRefresh].
  DateTime _now = DateTime.now();
  bool _justCopied = false;
  Timer? _ageTimer;
  Timer? _confirmTimer;

  @override
  void initState() {
    super.initState();
    _ageTimer = Timer.periodic(
      _ageRefresh,
      (_) => setState(() => _now = DateTime.now()),
    );
  }

  @override
  void didUpdateWidget(LastTranscript old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) _arrivedAt = _now = DateTime.now();
  }

  Future<void> _copy() async {
    final ok = await ClipboardService.copyToClipboard(widget.text);
    if (!ok || !mounted) return;
    setState(() => _justCopied = true);
    _confirmTimer?.cancel();
    _confirmTimer = Timer(_confirmFor, () {
      if (mounted) setState(() => _justCopied = false);
    });
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
    final age = ClockTime.ago(_now.difference(_arrivedAt));

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
              _justCopied ? 'Copied' : age,
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
