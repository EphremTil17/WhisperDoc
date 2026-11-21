import 'dart:async';

import 'package:flutter_client/infrastructure/theme/app_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/controllers/recording_controller.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:flutter_client/logic/mappers/home_status_mapper.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/ui/features/recording/widgets/profile_action_button.dart';
import 'package:flutter_client/ui/screens/home/home_navigation.dart';
import 'package:flutter_client/ui/screens/home/home_status_reader.dart';
import 'package:flutter_client/ui/shared/widgets/app_button.dart';

/// Record/Stop and the output style on the left; History, Incognito and
/// Settings on the right. While a session runs, everything but Stop locks
/// behind a single lock glyph.
class HomeBottomBar extends StatelessWidget {
  const HomeBottomBar({super.key, required this.onIncognitoTap});

  final VoidCallback onIncognitoTap;

  static const double _markSize = 10;

  @override
  Widget build(BuildContext context) {
    final status = context.watchHomeStatus();
    final isGroqMode = context.select((SettingsService s) => s.isGroqMode);
    final incognito = context.select((RecordingController c) => c.incognitoMode);
    final listening = status.phase == HomePhase.listening;
    final locked = listening || status.phase == HomePhase.working;
    final canToggle = status.canRecord || listening;

    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.rule)),
      ),
      child: SizedBox(
        height: AppSizes.bottomBar,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(
            start: AppSpace.lg,
            end: AppSpace.sm,
          ),
          child: Row(
            spacing: AppSpace.xs,
            children: [
              AppButton(
                label: listening ? 'Stop' : 'Record',
                tone: AppButtonTone.record,
                leading: DecoratedBox(
                  decoration: BoxDecoration(
                    color: canToggle ? AppColors.text : Colors.transparent,
                    border: canToggle
                        ? null
                        : const Border.fromBorderSide(
                            BorderSide(color: AppColors.record),
                          ),
                    shape: listening ? BoxShape.rectangle : BoxShape.circle,
                  ),
                  child: const SizedBox.square(dimension: _markSize),
                ),
                onPressed: canToggle
                    ? () => unawaited(
                        context.read<RecordingController>().toggleRecording(),
                      )
                    : null,
              ),
              // Output styles rewrite text through Groq, so the picker only
              // appears where it can act.
              // The picker takes its natural width; the rest stays empty.
              // Long custom names ellipsize instead of overflowing.
              Expanded(
                child: isGroqMode && !locked
                    ? const Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: ProfileActionButton(),
                      )
                    : const SizedBox.shrink(),
              ),
              if (locked)
                const Tooltip(
                  message: 'Other controls are locked while recording',
                  child: SizedBox.square(
                    dimension: AppSizes.iconButton,
                    child: Icon(
                      AppIcons.lock,
                      size: AppSizes.smallIconSize,
                      color: AppColors.textMuted,
                    ),
                  ),
                )
              else ...[
                IconButton(
                  tooltip: 'History',
                  onPressed: () => unawaited(HomeNavigation.openHistory(context)),
                  icon: const Icon(AppIcons.history),
                ),
                IconButton(
                  tooltip: incognito ? 'Incognito: on' : 'Incognito: off',
                  isSelected: incognito,
                  onPressed: onIncognitoTap,
                  icon: const Icon(AppIcons.eyeOff),
                  color: incognito ? AppColors.text : null,
                ),
                IconButton(
                  tooltip: 'Settings',
                  onPressed: () => unawaited(HomeNavigation.openSettings(context)),
                  icon: const Icon(AppIcons.slidersHorizontal),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
