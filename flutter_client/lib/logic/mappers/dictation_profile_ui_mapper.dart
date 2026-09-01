import 'package:flutter/material.dart';
import 'package:flutter_client/logic/models/dictation_profile.dart';
import 'package:flutter_client/logic/models/dictation_profile_spec.dart';

/// Presentation mapper translating [DictationProfileSpec] states into UI icons and descriptions.
class DictationProfileUiMapper {
  static const Map<DictationProfile, IconData> profileIcons = {
    DictationProfile.raw: Icons.mic_none_rounded,
    DictationProfile.clean: Icons.auto_fix_high_rounded,
    DictationProfile.professional: Icons.work_outline_rounded,
    DictationProfile.casual: Icons.chat_bubble_outline_rounded,
    DictationProfile.technical: Icons.code_rounded,
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
      return profileIcons[spec] ?? Icons.mic_none_rounded;
    }

    return Icons.tune_rounded;
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
