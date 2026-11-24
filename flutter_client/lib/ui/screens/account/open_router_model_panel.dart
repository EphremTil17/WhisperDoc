import 'dart:async';

import 'package:flutter_client/infrastructure/constants/app_constants.dart';
import 'package:flutter_client/infrastructure/constants/speech_model_accuracy.dart';
import 'package:flutter_client/infrastructure/theme/app_icons.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:flutter_client/logic/mappers/home_status_mapper.dart';
import 'package:flutter_client/logic/models/speech_model.dart';
import 'package:flutter_client/services/transcription/open_router_catalog.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/ui/screens/account/widgets/speech_model_header.dart';
import 'package:flutter_client/ui/screens/account/widgets/speech_model_row.dart';
import 'package:flutter_client/ui/shared/widgets/caption_cue.dart';
import 'package:flutter_client/ui/shared/widgets/panel/app_panel.dart';
import 'package:flutter_client/ui/shared/widgets/panel/panel_note.dart';
import 'package:flutter_client/ui/shared/widgets/app_link.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// Every speech model OpenRouter serves right now as a small table: most
/// accurate first by a dated Artificial Analysis snapshot, with OpenRouter's
/// live latency, and links to compare further. Opening it refreshes a stale
/// list; picking one applies it and goes back.
class OpenRouterModelPanel extends StatefulWidget {
  const OpenRouterModelPanel({super.key});

  @override
  State<OpenRouterModelPanel> createState() => _OpenRouterModelPanelState();
}

class _OpenRouterModelPanelState extends State<OpenRouterModelPanel> {
  @override
  void initState() {
    super.initState();
    unawaited(_load(context.read<OpenRouterCatalog>()));
  }

  /// The list first (latency is read per listed model), then the figures.
  static Future<void> _load(
    OpenRouterCatalog catalog, {
    bool force = false,
  }) async {
    await catalog.refresh(force: force);
    await catalog.loadLatency();
  }

  void _pick(SpeechModel model) {
    unawaited(context.read<SettingsService>().setOpenRouterModel(model.id));
    Navigator.of(context).pop();
  }

  /// Most accurate first; ties, and models never measured (after the rest),
  /// by name. Dart's sort isn't stable, so the name order is explicit.
  static List<SpeechModel> _byAccuracy(List<SpeechModel> models) {
    const rates = SpeechModelAccuracy.wordErrorRate;

    return [...models]..sort((a, b) {
      final x = rates[a.id];
      final y = rates[b.id];
      if (x != null && y != null && x != y) return x.compareTo(y);
      if (x == null && y != null) return 1;
      if (x != null && y == null) return -1;

      return a.compareTo(b);
    });
  }

  /// Opens one of the fixed comparison pages in the browser.
  static void _open(String url) => unawaited(
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
  );

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<OpenRouterCatalog>();
    final (selected, zdr) = context.select(
      (SettingsService s) => (s.openRouterModel, s.openRouterZdr),
    );
    final choices = _byAccuracy(catalog.choices);
    final loading = catalog.isRefreshing;
    final error = loading ? null : catalog.lastError;
    final current = catalog.find(selected);
    final missing = selected != null && catalog.hasList && current == null;
    // Hidden from the list while zero data retention is on; say why.
    final hidden = zdr && current != null && !current.zdr;

    return AppPanel(
      title: 'Model',
      actions: [
        IconButton(
          tooltip: 'Refresh the list',
          onPressed: loading
              ? null
              : () => unawaited(_load(catalog, force: true)),
          icon: const Icon(AppIcons.refreshCw),
        ),
      ],
      // Comparing further is a side trip, so it waits at the bottom, out of
      // the list's way.
      footer: Align(
        alignment: AlignmentDirectional.centerStart,
        // The links' own padding hangs into the footer inset, so their text
        // lines up with the rows above.
        child: Transform.translate(
          offset: const Offset(-AppSpace.sm, 0),
          child: Wrap(
            children: [
              AppLink(
                label: 'Compare on OpenRouter',
                color: AppColors.textMuted,
                onPressed: () => _open(AppConstants.openRouterCompareUrl),
              ),
              AppLink(
                label: 'Accuracy leaderboard',
                color: AppColors.textMuted,
                onPressed: () => _open(AppConstants.speechAccuracyUrl),
              ),
            ],
          ),
        ),
      ),
      children: [
        if (missing)
          PanelNote(
            'OpenRouter no longer serves $selected. Choose another.',
            color: AppColors.alert,
          ),
        if (hidden)
          PanelNote(
            'Your model, ${current.name}, keeps data, so it isn’t listed '
            'while zero data retention is on. Choose another, or turn zero '
            'data retention off in Account.',
            color: AppColors.alert,
          ),
        if (choices.isNotEmpty) const SpeechModelHeader(),
        for (final (index, model) in choices.indexed)
          SpeechModelRow(
            model: model,
            wordErrorRate: SpeechModelAccuracy.wordErrorRate[model.id],
            latency: catalog.latencyOf(model.id),
            latencyLoading: catalog.isLoadingLatency,
            selected: model.id == selected,
            rule: index < choices.length - 1,
            onTap: () => _pick(model),
          ),
        if (choices.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AppSpace.md),
            child: Center(
              child: CaptionCue(switch ((loading, error)) {
                (true, _) => 'loading models',
                (false, null) when zdr && catalog.hasList =>
                  'no models keep zero data',
                (false, null) => 'no models',
                (false, _) => 'couldn’t load models',
              }, tone: error == null ? CueTone.muted : CueTone.alert),
            ),
          ),
        if (error != null) PanelNote(error.userMessage, color: AppColors.alert),
        PanelNote(
          'WER is the word error rate (lower is better) as '
          '${SpeechModelAccuracy.source} measured it on '
          '${SpeechModelAccuracy.measuredOn}; — means not measured. Latency '
          'is OpenRouter’s median time to a full transcript over the last '
          '30 minutes, across the hosts it sends requests to; your clips may '
          'differ, and a model with no recent traffic shows none. '
          '${zdr ? 'Only models that can keep zero data are listed.' : 'Some of these models keep your audio.'}',
        ),
      ],
    );
  }
}
