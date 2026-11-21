import 'dart:async';

import 'package:flutter_client/controllers/profile_controller.dart';
import 'package:flutter_client/controllers/recording_controller.dart';
import 'package:flutter_client/infrastructure/theme/app_icons.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/ui/screens/account/account_fields.dart';
import 'package:flutter_client/ui/shared/widgets/app_link.dart';
import 'package:flutter_client/ui/shared/widgets/crisp_text.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// Who or what is transcribing: the service (or signed-in user), one line
/// on its state, and the switch to the other service.
class AccountIdentity extends StatelessWidget {
  const AccountIdentity({super.key});

  static const double _avatar = 40;

  /// Matches the icon-to-label gap in panel rows.
  static const double _glyphGap = 24;

  /// Switching to Groq without a key goes straight to adding one.
  static Future<void> _switchService(BuildContext context) async {
    final settings = context.read<SettingsService>();
    final toGroq = !settings.isGroqMode;
    await settings.setTranscriptionMode(
      toGroq ? SettingsService.groqMode : SettingsService.backendMode,
    );
    final needsKey = settings.cachedGroqApiKey?.isEmpty ?? true;
    if (toGroq && needsKey && context.mounted) {
      await AccountFields.groqKey(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final profile = context.watch<ProfileController>();
    final busy = context.select((RecordingController c) => c.isSessionActive);

    final user = profile.isAuthenticated ? profile.currentUser : null;
    final picture = user?['picture'];
    final hasGroqKey = settings.cachedGroqApiKey?.isNotEmpty ?? false;
    final hasDeveloperKey = settings.cachedApiKey?.isNotEmpty ?? false;

    final (String name, String status, bool needsYou) = switch ((
      settings.isGroqMode,
      user,
    )) {
      (true, _) when hasGroqKey => (
        'Groq Cloud',
        'Transcribing with your API key',
        false,
      ),
      (true, _) => ('Groq Cloud', 'Add your API key to start', true),
      (false, final Map<String, dynamic> signedIn) => (
        signedIn['name'] as String? ?? 'Signed in',
        signedIn['email'] as String? ?? 'WhisperDoc server',
        false,
      ),
      (false, null) when hasDeveloperKey => (
        'WhisperDoc server',
        'Using a developer key',
        false,
      ),
      (false, null) => ('WhisperDoc server', 'Sign in to start', true),
    };
    final switchHint = switch ((busy, settings.isGroqMode)) {
      (true, _) => 'Finish the recording first',
      (false, true) => 'Use your WhisperDoc server',
      (false, false) => 'Use Groq Cloud',
    };
    // A signed-in person gets an avatar (picture, else their initial on a
    // band square); a service gets its bare glyph in the rows' icon column,
    // so the name lines up with the row labels below.
    final initial = ColoredBox(
      color: AppColors.band,
      child: Center(
        child: CrispText(
          name.characters.first.toUpperCase(),
          style: AppType.body.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
    final Widget leading = user == null
        ? Icon(
            settings.isGroqMode ? AppIcons.cloud : AppIcons.server,
            size: AppSizes.smallIconSize,
            color: needsYou ? AppColors.alert : AppColors.text,
          )
        : ClipRRect(
            borderRadius: AppRadius.controlAll,
            child: SizedBox.square(
              dimension: _avatar,
              child: picture is String
                  ? Image.network(
                      picture,
                      fit: BoxFit.cover,
                      semanticLabel: 'Profile picture',
                      loadingBuilder: (_, image, progress) =>
                          progress == null ? image : initial,
                      errorBuilder: (_, _, _) => initial,
                    )
                  : initial,
            ),
          );

    return Padding(
      padding: const EdgeInsets.only(left: AppSpace.sm, top: AppSpace.sm),
      child: Row(
        children: [
          leading,
          SizedBox(width: user == null ? _glyphGap : AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CrispText(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.body.copyWith(fontWeight: FontWeight.w600),
                ),
                CrispText(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.caption.copyWith(
                    color: needsYou ? AppColors.alert : AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Tooltip(
            message: switchHint,
            child: AppLink(
              label: 'Switch service',
              onPressed: busy ? null : () => unawaited(_switchService(context)),
            ),
          ),
        ],
      ),
    );
  }
}
