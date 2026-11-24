import 'package:material_ui/material_ui.dart';
import 'package:flutter_client/infrastructure/theme/app_icons.dart';
import 'package:flutter_client/logic/mappers/home_status_mapper.dart';

/// Glyphs for a blocked state: the cue shows what broke, the fix button shows
/// what to do about it.
extension HomeFixIcon on HomeFix {
  /// Beside the crimson cue: the problem.
  IconData get problemIcon => switch (this) {
    HomeFix.openSettings || HomeFix.retryMicrophone => AppIcons.micOff,
    HomeFix.openAccount => AppIcons.keyRound,
    HomeFix.chooseModel => AppIcons.cpu,
    HomeFix.retryServer => AppIcons.serverOff,
    HomeFix.trustServer => AppIcons.shieldAlert,
    HomeFix.none => AppIcons.ban,
  };

  /// On the fix button: the action.
  IconData get actionIcon => switch (this) {
    HomeFix.openSettings => AppIcons.mic,
    HomeFix.retryMicrophone || HomeFix.retryServer => AppIcons.refreshCw,
    HomeFix.trustServer => AppIcons.shieldCheck,
    HomeFix.openAccount => AppIcons.keyRound,
    HomeFix.chooseModel => AppIcons.cpu,
    HomeFix.none => AppIcons.ban,
  };
}
