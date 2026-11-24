import 'package:flutter_client/controllers/profile_controller.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:flutter_client/logic/models/model_selection_problem.dart';
import 'package:flutter_client/logic/models/transcription_source.dart';
import 'package:flutter_client/services/transcription/open_router_catalog.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/ui/screens/account/widgets/source_selector.dart';
import 'package:flutter_client/ui/shared/widgets/crisp_text.dart';
import 'package:flutter_client/ui/shared/widgets/source_glyph.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// Where dictation goes (the source selector), then who or what is
/// transcribing and one line on its state.
class AccountIdentity extends StatelessWidget {
  const AccountIdentity({super.key});

  static const double _avatar = 40;

  /// Matches the icon-to-label gap in panel rows.
  static const double _glyphGap = 24;

  static bool _isTrustedAvatarUrl(Object? value) {
    if (value is! String || value.isEmpty) return false;
    final uri = Uri.tryParse(value);

    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
  }

  /// A display claim from the ID token, or [fallback] when it is missing,
  /// blank or not text (the initial avatar needs at least one character).
  static String _claim(
    Map<String, dynamic> claims,
    String key,
    String fallback,
  ) {
    final value = claims[key];
    final text = value is String ? value.trim() : '';

    return text.isEmpty ? fallback : text;
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final profile = context.watch<ProfileController>();
    final source = settings.transcriptionSource;

    final user = source == TranscriptionSource.server && profile.isAuthenticated
        ? profile.currentUser
        : null;
    final picture = user?['picture'];
    final hasDeveloperKey = settings.cachedApiKey?.isNotEmpty ?? false;

    final (String name, String status, bool needsYou) = switch ((
      source,
      user,
    )) {
      (TranscriptionSource.server, final Map<String, dynamic> signedIn) => (
        _claim(signedIn, 'name', 'Signed in'),
        _claim(signedIn, 'email', 'WhisperDoc server'),
        false,
      ),
      (TranscriptionSource.server, null) when hasDeveloperKey => (
        'WhisperDoc server',
        'Using a developer key',
        false,
      ),
      (TranscriptionSource.server, null) => (
        'WhisperDoc server',
        'Sign in to start',
        true,
      ),
      (final cloud, _) when !settings.hasCloudKey => (
        cloud.label,
        'Add your API key to start',
        true,
      ),
      (TranscriptionSource.groq, _) => (
        'Groq',
        'Transcribing with your API key',
        false,
      ),
      (TranscriptionSource.openRouter, _) => _openRouterStatus(context),
    };
    final nameStyle = AppType.body.copyWith(fontWeight: FontWeight.w600);
    // A signed-in person gets an avatar (picture, else their initial on a
    // band square); a service gets its bare glyph in the rows' icon column,
    // so the name lines up with the row labels below.
    final initial = ColoredBox(
      color: AppColors.band,
      child: Center(
        child: CrispText(name.characters.first.toUpperCase(), style: nameStyle),
      ),
    );
    final avatarPx = (_avatar * MediaQuery.devicePixelRatioOf(context)).round();
    final avatarUrl = _isTrustedAvatarUrl(picture) ? picture as String : null;
    final Widget leading = user == null
        ? SourceGlyph(
            source,
            color: needsYou ? AppColors.alert : AppColors.text,
          )
        : ClipRRect(
            borderRadius: AppRadius.controlAll,
            child: SizedBox.square(
              dimension: _avatar,
              child: avatarUrl != null
                  ? Image.network(
                      avatarUrl,
                      fit: BoxFit.cover,
                      cacheWidth: avatarPx,
                      cacheHeight: avatarPx,
                      semanticLabel: 'Profile picture',
                      loadingBuilder: (_, image, progress) =>
                          progress == null ? image : initial,
                      errorBuilder: (_, _, _) => initial,
                    )
                  : initial,
            ),
          );

    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpace.md,
        children: [
          const SourceSelector(),
          Padding(
            padding: const EdgeInsets.only(left: AppSpace.sm),
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
                        style: nameStyle,
                      ),
                      CrispText(
                        status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.caption.copyWith(
                          color: needsYou
                              ? AppColors.alert
                              : AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// OpenRouter with a key: the model in use, and whether it keeps data.
  static (String, String, bool) _openRouterStatus(BuildContext context) {
    final catalog = context.watch<OpenRouterCatalog>();
    final settings = context.read<SettingsService>();
    final model = catalog.find(settings.openRouterModel);

    return switch (catalog.selectionProblem) {
      ModelSelectionProblem.none => (
        'OpenRouter',
        [
          model?.name ?? settings.openRouterModel ?? '',
          if (settings.openRouterZdr) 'zero data retention',
        ].join(' · '),
        false,
      ),
      ModelSelectionProblem.notChosen when catalog.isRefreshing => (
        'OpenRouter',
        'Loading models…',
        false,
      ),
      ModelSelectionProblem.notChosen => ('OpenRouter', 'Choose a model', true),
      ModelSelectionProblem.retired => (
        'OpenRouter',
        'Your model was retired; choose another',
        true,
      ),
      ModelSelectionProblem.retainsData => (
        'OpenRouter',
        'Your model keeps data; choose another',
        true,
      ),
    };
  }
}
