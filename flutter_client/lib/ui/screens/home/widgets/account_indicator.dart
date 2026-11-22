import 'dart:async';

import 'package:flutter_client/infrastructure/theme/app_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:flutter_client/logic/mappers/home_status_mapper.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/ui/screens/home/home_navigation.dart';
import 'package:flutter_client/ui/screens/home/home_status_reader.dart';

/// Title-bar entry to the account: a bare service glyph that only grows a
/// dot when something needs the user (amber: update, crimson: attention).
class AccountIndicator extends StatelessWidget {
  const AccountIndicator({super.key});

  static const double _dotRing = 2;

  /// An 8px dot plus its ring on both sides.
  static const double _dotOuter = 12;

  @override
  Widget build(BuildContext context) {
    final isGroqMode = context.select((SettingsService s) => s.isGroqMode);
    final badge = context.watchHomeStatus().badge;

    final (Color? dot, String tooltip) = switch (badge) {
      AccountBadge.none => (null, 'Account'),
      AccountBadge.update => (AppColors.update, 'Account · update available'),
      AccountBadge.attention => (AppColors.record, 'Account · needs attention'),
    };

    return IconButton(
      tooltip: tooltip,
      onPressed: () => unawaited(HomeNavigation.openAccount(context)),
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(
            isGroqMode ? AppIcons.cloud : AppIcons.user,
            color: AppColors.text,
            size: AppSizes.iconSize,
          ),
          if (dot != null)
            PositionedDirectional(
              end: -_dotRing,
              bottom: -_dotRing,
              // The ground-coloured ring separates the dot from the glyph.
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: dot,
                  shape: BoxShape.circle,
                  border: const Border.fromBorderSide(
                    BorderSide(color: AppColors.ground, width: _dotRing),
                  ),
                ),
                child: const SizedBox.square(
                  dimension: _dotOuter,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
