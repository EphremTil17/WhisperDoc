import 'package:flutter_client/infrastructure/theme/app_icons.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/ui/shared/widgets/crisp_text.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// The active output style shown read-only while a session runs.
class LockedStyle extends StatelessWidget {
  const LockedStyle({super.key});

  static const double _padX = 10;

  @override
  Widget build(BuildContext context) {
    final label = context.select(
      (SettingsService s) => s.dictationProfile.label,
    );
    final muted = AppType.caption.copyWith(color: AppColors.textMuted);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _padX),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: AppSpace.sm,
        children: [
          const Icon(
            AppIcons.type,
            size: AppSizes.smallIconSize,
            color: AppColors.textMuted,
          ),
          Flexible(
            child: CrispText(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: muted,
            ),
          ),
        ],
      ),
    );
  }
}
