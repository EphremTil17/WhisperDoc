import 'dart:async';

import 'package:flutter_client/infrastructure/theme/app_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:flutter_client/services/utility/clipboard_service.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/ui/shared/widgets/caption_band.dart';
import 'package:flutter_client/ui/shared/widgets/crisp_text.dart';

/// The most recent transcript set as captions, with a copy action.
class LastTranscript extends StatefulWidget {
  const LastTranscript({super.key, required this.text});

  final String text;

  @override
  State<LastTranscript> createState() => _LastTranscriptState();
}

class _LastTranscriptState extends State<LastTranscript> {
  static const Duration _confirmFor = Duration(seconds: 2);
  static const double _checkSize = 14;

  bool _copied = false;
  Timer? _reset;

  Future<void> _copy() async {
    final ok = await ClipboardService.copyToClipboard(widget.text);
    if (!ok || !mounted) return;
    setState(() => _copied = true);
    _reset?.cancel();
    _reset = Timer(_confirmFor, () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  void dispose() {
    _reset?.cancel();
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
            if (autoCopy || _copied)
              const Icon(
                AppIcons.check,
                size: _checkSize,
                color: AppColors.textMuted,
              ),
            CrispText(
              autoCopy || _copied ? 'Copied' : 'Last transcript',
              style: AppType.caption.copyWith(color: AppColors.textMuted),
            ),
            IconButton(
              tooltip: _copied ? 'Copied' : 'Copy again',
              onPressed: () => unawaited(_copy()),
              icon: Icon(
                _copied ? AppIcons.check : AppIcons.copy,
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
