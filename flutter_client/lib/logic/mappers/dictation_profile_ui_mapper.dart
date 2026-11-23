import 'package:flutter_client/infrastructure/theme/app_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_client/logic/models/dictation_profile.dart';
import 'package:flutter_client/logic/models/dictation_profile_spec.dart';

/// Presentation mapper translating [DictationProfileSpec] states into UI icons and descriptions.
class DictationProfileUiMapper {
  static const Map<DictationProfile, IconData> profileIcons = {
    DictationProfile.raw: AppIcons.mic,
    DictationProfile.clean: AppIcons.sparkles,
    DictationProfile.professional: AppIcons.briefcase,
    DictationProfile.casual: AppIcons.messageCircle,
    DictationProfile.technical: AppIcons.code,
  };

  static const Map<DictationProfile, String> profileSubtitles = {
    DictationProfile.raw: 'Verbatim transcription',
    DictationProfile.clean: 'Clean disfluencies',
    DictationProfile.professional: 'Executive prose',
    DictationProfile.casual: 'Team chat style',
    DictationProfile.technical: 'Zero-omission spec',
  };

  static IconData iconFor(DictationProfileSpec spec) {
    if (spec is DictationProfile) {
      return profileIcons[spec] ?? AppIcons.mic;
    }

    return AppIcons.slidersHorizontal;
  }

  static String subtitleFor(
    DictationProfileSpec spec, {
    bool isKeyBlocked = false,
  }) {
    if (isKeyBlocked) {
      return 'Requires Groq API key';
    }

    if (spec is DictationProfile) {
      return profileSubtitles[spec] ?? '';
    }

    return 'Custom prompt';
  }
}
