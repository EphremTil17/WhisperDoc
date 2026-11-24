// Each notifyListeners() announces a different state change and returns
// nothing, so the repeats have no value to share.
// ignore_for_file: prefer-moving-to-variable
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_client/infrastructure/constants/app_constants.dart';
import 'package:flutter_client/logic/models/model_selection_problem.dart';
import 'package:flutter_client/logic/models/speech_model.dart';
import 'package:flutter_client/logic/models/transcription_source.dart';
import 'package:flutter_client/services/utility/logging_service.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cloud_error.dart';
import 'cloud_http.dart';

/// What OpenRouter serves right now, and whether the chosen model is in it.
///
/// OpenRouter's own API is the only source of which models exist: nothing
/// is hard-coded, so a new model shows up and a retired one disappears on
/// the next refresh. The last list is saved, so the picker opens instantly
/// and a vanished model is caught even before the network answers.
class OpenRouterCatalog extends ChangeNotifier {
  OpenRouterCatalog(
    this._settings,
    this._http, {
    @visibleForTesting DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now {
    _lastKey = _settings.cachedOpenRouterApiKey;
    _wasActive = _isActive;
    _lastZdr = _settings.openRouterZdr;
    _lastModel = _settings.openRouterModel;
    _settings.addListener(_onSettingsChanged);
  }

  static const String _cacheKey = 'openrouter_catalog';
  static final String _service = TranscriptionSource.openRouter.label;

  final SettingsService _settings;
  final CloudHttp _http;
  final DateTime Function() _now;

  List<SpeechModel> _models = const [];
  DateTime? _fetchedAt;
  CloudError? _lastError;
  Future<void>? _refreshing;

  /// Each model's typical median latency over OpenRouter's last 30 minutes;
  /// read when the picker opens, kept for
  /// [AppConstants.openRouterLatencyMaxAge].
  final Map<String, Duration> _latency = {};

  /// When each model's figure was last read successfully (a model with no
  /// recent traffic counts as read, with no figure).
  final Map<String, DateTime> _latencyReadAt = {};
  Future<void>? _loadingLatency;

  String? _lastKey;
  bool _wasActive = false;
  bool _lastZdr = true;
  String? _lastModel;
  bool _disposed = false;

  bool get _isActive =>
      _settings.transcriptionSource == TranscriptionSource.openRouter;

  /// Every speech model OpenRouter serves, by name.
  @visibleForTesting
  List<SpeechModel> get models => _models;

  /// What the picker offers: only models with a zero-retention host while
  /// that is required.
  List<SpeechModel> get choices => _settings.openRouterZdr
      ? _models.where((m) => m.zdr).toList(growable: false)
      : _models;

  /// A list has been fetched, now or on an earlier run.
  bool get hasList => _fetchedAt != null;
  bool get isRefreshing => _refreshing != null;

  /// Why the last refresh failed; null after a success.
  CloudError? get lastError => _lastError;

  /// [modelId]'s typical median time to a full transcript (see
  /// [typicalMedian]); null before [loadLatency], or with no recent traffic.
  Duration? latencyOf(String modelId) => _latency[modelId];

  /// Figures are being read.
  bool get isLoadingLatency => _loadingLatency != null;

  SpeechModel? find(String? id) {
    for (final model in _models) {
      if (model.id == id) return model;
    }

    return null;
  }

  /// Whether the chosen model can be used as things stand.
  ModelSelectionProblem get selectionProblem {
    final id = _settings.openRouterModel;
    if (id == null) return ModelSelectionProblem.notChosen;
    // Without a list, only the request itself can tell.
    if (!hasList) return ModelSelectionProblem.none;
    final model = find(id);
    if (model == null) return ModelSelectionProblem.retired;
    if (_settings.openRouterZdr && !model.zdr) {
      return ModelSelectionProblem.retainsData;
    }

    return ModelSelectionProblem.none;
  }

  /// Restores the saved list, then refreshes it if OpenRouter is in use and
  /// the list is stale. Never throws.
  Future<void> load() async {
    try {
      final saved = (await SharedPreferences.getInstance()).getString(
        _cacheKey,
      );
      if (saved != null) _restore(saved);
    } on Exception catch (e) {
      LoggingService().warning('Saved OpenRouter model list unreadable: $e');
    }
    if (_isActive && _hasKey) unawaited(refresh());
  }

  /// Fetches the model list unless the one held is fresh (or [force]).
  /// Concurrent calls share one fetch. Never throws: a failure is kept in
  /// [lastError] and the previous list stays.
  Future<void> refresh({bool force = false}) {
    final running = _refreshing;
    if (running != null) return running;
    final fetchedAt = _fetchedAt;
    final fresh =
        fetchedAt != null &&
        _now().difference(fetchedAt) < AppConstants.openRouterCatalogMaxAge;
    if (!_hasKey || (fresh && _lastError == null && !force)) {
      return Future.value();
    }

    final future = _fetch().whenComplete(() {
      _refreshing = null;
      _notify();
    });
    _refreshing = future;
    _notify();

    return future;
  }

  /// Reads the latency of each offered model that has no recent figure (a
  /// few small requests at a time): models new to the list get one, and a
  /// failed read is tried again next time. Skipped while the list itself
  /// failed, since the same failure would only repeat. Concurrent calls
  /// share one load; one notification at the end. Never throws.
  Future<void> loadLatency() {
    final running = _loadingLatency;
    if (running != null) return running;
    final apiKey = _settings.cachedOpenRouterApiKey;
    final due = choices
        .where((m) => !_isFresh(_latencyReadAt[m.id]))
        .toList(growable: false);
    if (apiKey == null || apiKey.isEmpty || _lastError != null) {
      return Future.value();
    }
    if (due.isEmpty) return Future.value();

    final future = _loadLatency(due, apiKey).whenComplete(() {
      _loadingLatency = null;
      _notify();
    });
    _loadingLatency = future;
    _notify();

    return future;
  }

  @override
  void dispose() {
    _disposed = true;
    _settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  /// A refresh can finish after [dispose]; by then nobody is listening.
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool get _hasKey => _settings.cachedOpenRouterApiKey?.isNotEmpty ?? false;

  /// Switching to OpenRouter, or a new key, is when a list is first needed
  /// (and a refresh after a failed key can finally succeed).
  void _onSettingsChanged() {
    final key = _settings.cachedOpenRouterApiKey;
    final active = _isActive;
    final zdr = _settings.openRouterZdr;
    final model = _settings.openRouterModel;
    final keyChanged = key != _lastKey;
    final activated = active && !_wasActive;
    // Only these change what is offered or whether the choice fits; every
    // other setting (a toggle, the hotkey) leaves listeners alone.
    final relevant =
        keyChanged ||
        active != _wasActive ||
        zdr != _lastZdr ||
        model != _lastModel;
    _lastKey = key;
    _wasActive = active;
    _lastZdr = zdr;
    _lastModel = model;
    if (active && (keyChanged || activated)) {
      unawaited(refresh(force: keyChanged));
    }
    if (relevant) _notify();
  }

  Future<void> _fetch() async {
    final apiKey = _settings.cachedOpenRouterApiKey;
    if (apiKey == null) return;
    final endpoint = Uri.parse(AppConstants.openRouterModelsEndpoint);
    Uri query(Map<String, String> params) =>
        endpoint.replace(queryParameters: params);

    try {
      // Every speech model, and the ones with a zero-retention host: two
      // ~25 KB answers in parallel, so turning ZDR off needs no refetch.
      final lists = await Future.wait([
        _http.getJson(
          _service,
          query({'output_modalities': 'transcription'}),
          apiKey: apiKey,
          timeout: AppConstants.openRouterCatalogTimeout,
        ),
        _http.getJson(
          _service,
          query({'output_modalities': 'transcription', 'zdr': 'true'}),
          apiKey: apiKey,
          timeout: AppConstants.openRouterCatalogTimeout,
        ),
      ]);
      final zdrIds = {
        for (final entry in _entries(lists.last))
          if (entry is Map<String, dynamic>) entry['id'],
      };
      final models = [
        for (final entry in _entries(lists.first))
          ?SpeechModel.fromJson(
            entry,
            zdr: entry is Map<String, dynamic> && zdrIds.contains(entry['id']),
          ),
      ]..sort();
      if (models.isEmpty) {
        throw CloudError(
          service: _service,
          type: CloudErrorType.unknown,
          message: 'OpenRouter listed no speech models',
        );
      }

      _models = List.unmodifiable(models);
      _fetchedAt = _now();
      _lastError = null;
      LoggingService().info('OpenRouter lists ${models.length} speech models');
    } on CloudError catch (e) {
      _lastError = e;
      LoggingService().warning('OpenRouter model list: ${e.message}');

      return;
    }

    // The list is good either way. Each step below only costs its own part
    // (the saved copy, the automatic first choice) and must not escape a
    // background call, nor stop the other.
    try {
      await _save();
    } on Exception catch (e) {
      LoggingService().warning('OpenRouter model list not saved: $e');
    }
    try {
      await _chooseFirstModel();
    } on Exception catch (e) {
      LoggingService().warning('OpenRouter first model not chosen: $e');
    }
  }

  /// A user who just picked OpenRouter gets [AppConstants.openRouterDefaultModel]
  /// when it fits their privacy setting, else the first offered model that
  /// isn't being retired.
  Future<void> _chooseFirstModel() async {
    if (_settings.openRouterModel != null) return;
    final options = choices;
    if (options.isEmpty) return;
    final lasting = options.where((m) => m.retiresOn == null);
    final model =
        lasting
            .where((m) => m.id == AppConstants.openRouterDefaultModel)
            .firstOrNull ??
        lasting.firstOrNull ??
        options.first;
    await _settings.setOpenRouterModel(model.id);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _cacheKey,
      jsonEncode({
        'fetchedAt': _fetchedAt?.toIso8601String(),
        'models': [for (final model in _models) model.toJson()],
      }),
    );
  }

  void _restore(String saved) {
    final json = jsonDecode(saved);
    if (json is! Map<String, dynamic>) return;
    final fetchedAt = json['fetchedAt'];
    final entries = json['models'];
    if (fetchedAt is! String || entries is! List) return;
    final models = [
      for (final entry in entries)
        ?SpeechModel.fromJson(
          entry,
          zdr: entry is Map<String, dynamic> && entry['zdr'] == true,
        ),
    ]..sort();
    _models = List.unmodifiable(models);
    _fetchedAt = DateTime.tryParse(fetchedAt);
    _notify();
  }

  bool _isFresh(DateTime? at) =>
      at != null &&
      _now().difference(at) < AppConstants.openRouterLatencyMaxAge;

  Future<void> _loadLatency(List<SpeechModel> models, String apiKey) async {
    const batch = AppConstants.openRouterLatencyBatch;
    for (var start = 0; start < models.length; start += batch) {
      final read = await Future.wait([
        for (final model in models.skip(start).take(batch))
          _readLatency(model.id, apiKey),
      ]);
      // A whole batch that failed means OpenRouter can't be reached right
      // now: stop rather than wait out every remaining timeout.
      if (!read.contains(true)) return;
    }
  }

  /// Whether OpenRouter answered for [modelId].
  Future<bool> _readLatency(String modelId, String apiKey) async {
    try {
      final json = await _http.getJson(
        _service,
        Uri.parse(
          '${AppConstants.openRouterModelsEndpoint}/$modelId/endpoints',
        ),
        apiKey: apiKey,
        timeout: AppConstants.openRouterCatalogTimeout,
      );
      final typical = typicalMedian(json);
      if (typical == null) {
        _latency.remove(modelId);
      } else {
        _latency[modelId] = typical;
      }
      _latencyReadAt[modelId] = _now();

      return true;
    } on CloudError catch (e) {
      LoggingService().debug('Latency of $modelId: ${e.message}');

      return false;
    }
  }

  /// The speech latency a request typically gets: each host's `p50` over
  /// OpenRouter's last 30 minutes, weighted by how many requests it served,
  /// since OpenRouter (not the app) picks the host for a transcription.
  /// Hosts without a request count fall back to the fastest median; null
  /// when no host saw traffic.
  @visibleForTesting
  static Duration? typicalMedian(Map<String, dynamic> json) {
    final data = json['data'];
    final endpoints = data is Map<String, dynamic> ? data['endpoints'] : null;
    if (endpoints is! List) return null;
    num? fastest;
    num weighted = 0;
    num requests = 0;
    for (final endpoint in endpoints) {
      if (endpoint is! Map<String, dynamic>) continue;
      final perf = endpoint['perf_last_30m_by_workload'];
      final stt = perf is Map<String, dynamic> ? perf['stt'] : null;
      if (stt is! Map<String, dynamic>) continue;
      final latency = stt['latency'];
      final p50 = latency is Map<String, dynamic> ? latency['p50'] : null;
      if (p50 is! num || p50 <= 0) continue;
      if (fastest == null || p50 < fastest) fastest = p50;
      final count = stt['request_count'];
      if (count is num && count > 0) {
        weighted += p50 * count;
        requests += count;
      }
    }
    final ms = requests > 0 ? weighted / requests : fastest;

    return ms == null ? null : Duration(milliseconds: ms.round());
  }

  static List<Object?> _entries(Map<String, dynamic> json) {
    final data = json['data'];

    return data is List ? data : const [];
  }
}
