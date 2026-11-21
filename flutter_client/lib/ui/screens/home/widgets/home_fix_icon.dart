import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_client/logic/mappers/home_status_mapper.dart';

/// The glyph shown beside a blocked cue and on its fix button.
extension HomeFixIcon on HomeFix {
  IconData get icon => switch (this) {
    HomeFix.openSettings || HomeFix.retryMicrophone => LucideIcons.micOff,
    HomeFix.openAccount => LucideIcons.keyRound,
    HomeFix.none => LucideIcons.circlePause,
  };
}
