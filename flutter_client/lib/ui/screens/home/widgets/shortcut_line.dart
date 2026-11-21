import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/ui/shared/widgets/crisp_text.dart';
import 'package:flutter_client/ui/shared/widgets/keycap.dart';

/// `[Ctrl Q] to talk`: the global shortcut on a band, then [trailing].
class ShortcutLine extends StatelessWidget {
  const ShortcutLine({super.key, required this.trailing, required this.style});

  final String trailing;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final hotkey = context.select((SettingsService s) => s.globalHotkey);

    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: AppSpace.sm,
      children: [
        Keycap(
          hotkey.replaceAll('+', ' '),
          style: style.copyWith(color: AppColors.text),
        ),
        CrispText(trailing, style: style),
      ],
    );
  }
}
