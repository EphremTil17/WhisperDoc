// Status codes and ages are the subject under test; the fake settings and
// server are rebuilt per test and the same catalog calls repeat on purpose.
// ignore_for_file: no-magic-number, avoid-late-keyword, prefer-match-file-name, prefer-moving-to-variable
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_client/infrastructure/constants/app_constants.dart';
import 'package:flutter_client/logic/models/model_selection_problem.dart';
import 'package:flutter_client/logic/models/transcription_source.dart';
import 'package:flutter_client/services/transcription/cloud_error.dart';
import 'package:flutter_client/services/transcription/cloud_http.dart';
import 'package:flutter_client/services/transcription/open_router_catalog.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSettings extends Mock
    with ChangeNotifier
    implements SettingsService {
  void changed() => notifyListeners();
}

/// Model ids the fake server lists.
abstract final class _Ids {
  static const mai = 'microsoft/mai-transcribe-2'; // the default, ZDR
  static const voxtral = 'mistralai/voxtral-small-transcribe-3-0'; // ZDR
  static const grok = 'x-ai/grok-stt-2.0'; // keeps data
  static const assembly = 'assemblyai/universal-3-5-pro'; // ZDR
  static const assemblyNew = 'assemblyai/universal-3-6-pro'; // ZDR
  static const qwen = 'qwen/qwen3-asr-0.6b'; // ZDR

  /// A `/models` entry.
  static Map<String, Object?> model(
    String id,
    String name, {
    String? retires,
  }) => {
    'id': id,
    'name': name,
    'expiration_date': retires,
    'pricing': {'prompt': '0.0001'},
  };
}

void main() {
  late _FakeSettings settings;
  late DateTime now;
  late List<Uri> requests;
  late List<String?> auths;
  late List<Map<String, Object?>> served;
  late Set<String> zdrIds;
  late http.Response? failure;
  late String? chosen;

  /// Each model's hosts' speech p50 in ms, as `/endpoints` reports them; a
  /// null entry is a host with no recent traffic.
  late Map<String, List<num?>> p50s;

  /// Models whose `/endpoints` answer fails.
  late Set<String> brokenEndpoints;

  final allServed = [
    _Ids.model(_Ids.qwen, 'Qwen: Qwen3 ASR 0.6B'),
    _Ids.model(_Ids.grok, 'SpaceXSI: Grok STT 2.0'),
    _Ids.model(_Ids.assemblyNew, 'AssemblyAI: Universal-3.6 Pro'),
    _Ids.model(_Ids.assembly, 'AssemblyAI: Universal-3.5 Pro'),
    _Ids.model(_Ids.voxtral, 'Mistral: Voxtral Small Transcribe 3'),
    _Ids.model(_Ids.mai, 'Microsoft AI: MAI-Transcribe 2'),
  ];

  http.Response route(http.Request request) {
    requests.add(request.url);
    auths.add(request.headers['Authorization']);
    final failed = failure;
    if (failed != null) return failed;
    final path = request.url.path;
    if (path == '/api/v1/models') {
      expect(request.url.queryParameters['output_modalities'], 'transcription');
      final zdrOnly = request.url.queryParameters['zdr'] == 'true';

      return http.Response(
        jsonEncode({
          'data': [
            for (final m in served)
              if (!zdrOnly || zdrIds.contains(m['id'])) m,
          ],
        }),
        200,
      );
    }
    // /api/v1/models/{author}/{slug}/endpoints
    final segments = request.url.pathSegments;
    if (path.startsWith('/api/v1/models/') && path.endsWith('/endpoints')) {
      final id = segments.skip(3).take(segments.length - 4).join('/');
      if (brokenEndpoints.contains(id)) {
        return http.Response('{"error":{"message":"nope"}}', 500);
      }

      return http.Response(
        jsonEncode({
          'data': {
            'endpoints': [
              for (final p50 in p50s[id] ?? const <num?>[])
                {
                  'provider_name': 'Host',
                  'tag': 'host',
                  'perf_last_30m_by_workload': p50 == null
                      ? null
                      : {
                          'stt': {
                            'latency': {'p50': p50, 'p90': p50 * 3},
                          },
                        },
                },
            ],
          },
        }),
        200,
      );
    }

    return http.Response('{}', 404);
  }

  OpenRouterCatalog catalog() => OpenRouterCatalog(
    settings,
    CloudHttp(client: MockClient((request) async => route(request))),
    clock: () => now,
  );

  int modelFetches() =>
      requests.where((u) => u.path == '/api/v1/models').length;

  int endpointFetches() =>
      requests.where((u) => u.path.endsWith('/endpoints')).length;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    settings = _FakeSettings();
    now = DateTime(2026, 11, 23, 9);
    requests = [];
    auths = [];
    served = [...allServed];
    zdrIds = {
      _Ids.mai,
      _Ids.voxtral,
      _Ids.assembly,
      _Ids.assemblyNew,
      _Ids.qwen,
    };
    failure = null;
    chosen = null;
    p50s = {
      _Ids.mai: [697, 420],
      _Ids.assembly: [292],
      _Ids.qwen: [null],
    };
    brokenEndpoints = {};
    when(() => settings.cachedOpenRouterApiKey).thenReturn('sk-or-key');
    when(() => settings.transcriptionSource)
        .thenReturn(TranscriptionSource.openRouter);
    when(() => settings.openRouterZdr).thenReturn(true);
    when(() => settings.openRouterModel).thenAnswer((_) => chosen);
    when(() => settings.setOpenRouterModel(any())).thenAnswer((call) async {
      chosen = call.positionalArguments.single as String;
    });
  });

  group('refresh', () {
    test('lists the models by name, maker first', () async {
      final list = catalog();

      await list.refresh();

      expect(list.models.map((m) => m.id), [
        _Ids.assembly,
        _Ids.assemblyNew,
        _Ids.mai,
        _Ids.voxtral,
        _Ids.qwen,
        _Ids.grok,
      ]);
      expect(list.hasList, isTrue);
      expect(list.lastError, isNull);
      expect(auths, everyElement('Bearer sk-or-key'));
      expect(list.find(_Ids.grok)?.zdr, isFalse);
      expect(list.find(_Ids.mai)?.zdr, isTrue);
      expect(modelFetches(), 2);
      expect(
        requests.where((u) => u.queryParameters['zdr'] == 'true'),
        hasLength(1),
      );
    });

    test('choices hide models that keep data while ZDR is on', () async {
      final list = catalog();
      await list.refresh();

      expect(list.choices.map((m) => m.id), isNot(contains(_Ids.grok)));
      expect(list.choices, hasLength(5));
      when(() => settings.openRouterZdr).thenReturn(false);
      expect(list.choices.map((m) => m.id), contains(_Ids.grok));
      expect(list.choices, hasLength(6));
    });

    test('a fresh list is not fetched again until it is stale', () async {
      final list = catalog();
      await list.refresh();
      now = now.add(const Duration(hours: 11));
      await list.refresh();
      expect(modelFetches(), 2);

      now = now.add(AppConstants.openRouterCatalogMaxAge);
      await list.refresh();
      expect(modelFetches(), 4);
    });

    test('force fetches even a fresh list', () async {
      final list = catalog();
      await list.refresh();

      await list.refresh(force: true);

      expect(modelFetches(), 4);
    });

    test('concurrent refreshes share one fetch', () async {
      final list = catalog();

      final first = list.refresh(force: true);
      final second = list.refresh(force: true);
      expect(list.isRefreshing, isTrue);
      await Future.wait([first, second]);

      expect(modelFetches(), 2);
      expect(list.isRefreshing, isFalse);
    });

    test(
      'a failure keeps the previous list and is retried next time',
      () async {
        final list = catalog();
        await list.refresh();
        failure = http.Response('{"error":{"message":"down"}}', 503);

        await list.refresh(force: true);

        expect(list.models, hasLength(6));
        expect(list.lastError?.type, CloudErrorType.serverError);
        expect(list.lastError?.message, 'down');

        failure = null;
        await list.refresh();
        expect(list.lastError, isNull);
        expect(modelFetches(), 6);
      },
    );

    test('an empty list is an error, not a wiped picker', () async {
      final list = catalog();
      await list.refresh();
      served = [];

      await list.refresh(force: true);

      expect(list.models, hasLength(6));
      expect(list.lastError?.type, CloudErrorType.unknown);
      expect(list.lastError?.message, 'OpenRouter listed no speech models');
    });

    test('entries that are not usable models are skipped', () async {
      served = [
        ...allServed,
        {'id': 'no-slash', 'name': 'Bad'},
        {'id': 'Upper/Case', 'name': 'Bad'},
        {'name': 'No id'},
      ];
      final list = catalog();

      await list.refresh();

      expect(list.models, hasLength(6));
    });

    test('without a key nothing is fetched', () async {
      when(() => settings.cachedOpenRouterApiKey).thenReturn(null);

      await catalog().refresh(force: true);

      expect(requests, isEmpty);
    });
  });

  group('the first model', () {
    test('is the default model when it is offered', () async {
      expect(AppConstants.openRouterDefaultModel, _Ids.mai);

      await catalog().refresh();

      expect(chosen, _Ids.mai);
    });

    test('skips the default when it is being retired', () async {
      served = [
        _Ids.model(
          _Ids.mai,
          'Microsoft AI: MAI-Transcribe 2',
          retires: '2026-12-22',
        ),
        ...allServed.where((m) => m['id'] != _Ids.mai),
      ];

      await catalog().refresh();

      expect(chosen, _Ids.assembly, reason: 'first lasting one by name');
    });

    test('without the default, is the first lasting one by name', () async {
      when(() => settings.openRouterZdr).thenReturn(false);
      served = [
        _Ids.model(_Ids.grok, 'SpaceXSI: Grok STT 2.0'),
        _Ids.model(
          _Ids.assembly,
          'AssemblyAI: Universal-3.5 Pro',
          retires: '2026-12-22',
        ),
        _Ids.model(_Ids.qwen, 'Qwen: Qwen3 ASR 0.6B'),
      ];

      await catalog().refresh();

      expect(chosen, _Ids.qwen);
    });

    test('is never a model that keeps data while ZDR is on', () async {
      served = [
        _Ids.model(_Ids.grok, 'SpaceXSI: Grok STT 2.0'),
        _Ids.model(_Ids.voxtral, 'Mistral: Voxtral Small Transcribe 3'),
      ];

      await catalog().refresh();

      expect(chosen, _Ids.voxtral);
    });

    test('takes a retiring model when nothing else fits', () async {
      served = [
        _Ids.model(
          _Ids.mai,
          'Microsoft AI: MAI-Transcribe 2',
          retires: '2026-12-22',
        ),
      ];

      await catalog().refresh();

      expect(chosen, _Ids.mai);
    });

    test('never replaces the user’s own choice', () async {
      chosen = _Ids.assembly;

      await catalog().refresh();

      expect(chosen, _Ids.assembly);
      verifyNever(() => settings.setOpenRouterModel(any()));
    });
  });

  group('selectionProblem', () {
    test('notChosen until a model is picked', () {
      expect(catalog().selectionProblem, ModelSelectionProblem.notChosen);
    });

    test('none without a list: only the request can tell', () {
      chosen = 'anything/at-all';

      expect(catalog().selectionProblem, ModelSelectionProblem.none);
    });

    test('retired when OpenRouter stopped listing the model', () async {
      chosen = 'gone/model';
      final list = catalog();
      await list.refresh();

      expect(list.selectionProblem, ModelSelectionProblem.retired);
    });

    test('retainsData for a data-keeping model while ZDR is on', () async {
      chosen = _Ids.grok;
      final list = catalog();
      await list.refresh();

      expect(list.selectionProblem, ModelSelectionProblem.retainsData);
      when(() => settings.openRouterZdr).thenReturn(false);
      expect(list.selectionProblem, ModelSelectionProblem.none);
    });

    test('none for a listed zero-retention model', () async {
      chosen = _Ids.assembly;
      final list = catalog();
      await list.refresh();

      expect(list.selectionProblem, ModelSelectionProblem.none);
    });
  });

  group('the saved list', () {
    test('restores without the network, in order', () async {
      chosen = _Ids.mai;
      await catalog().refresh();
      requests.clear();
      when(() => settings.transcriptionSource)
          .thenReturn(TranscriptionSource.server);

      final restored = catalog();
      await restored.load();

      expect(requests, isEmpty);
      expect(restored.hasList, isTrue);
      expect(restored.models.first.id, _Ids.assembly);
      expect(restored.find(_Ids.grok)?.zdr, isFalse);
      expect(restored.find(_Ids.mai)?.zdr, isTrue);
    });

    test('a stale saved list is refreshed when OpenRouter is in use', () async {
      chosen = _Ids.mai;
      await catalog().refresh();
      requests.clear();
      now = now.add(AppConstants.openRouterCatalogMaxAge);

      final restored = catalog();
      await restored.load();
      await pumpEventQueue();

      expect(modelFetches(), 2);
    });

    test('a fresh saved list is used as is', () async {
      chosen = _Ids.mai;
      await catalog().refresh();
      requests.clear();

      await catalog().load();
      await pumpEventQueue();

      expect(requests, isEmpty);
    });

    test('an unreadable saved list is ignored', () async {
      SharedPreferences.setMockInitialValues({
        'openrouter_catalog': 'not json',
      });
      when(() => settings.transcriptionSource)
          .thenReturn(TranscriptionSource.server);
      final list = catalog();

      await list.load();

      expect(list.hasList, isFalse);
      expect(list.models, isEmpty);
    });
  });

  group('settings changes', () {
    test('switching to OpenRouter fetches the list', () async {
      when(() => settings.transcriptionSource)
          .thenReturn(TranscriptionSource.server);
      final list = catalog();
      settings.changed();
      await pumpEventQueue();
      expect(requests, isEmpty);

      when(() => settings.transcriptionSource)
          .thenReturn(TranscriptionSource.openRouter);
      settings.changed();
      await pumpEventQueue();

      expect(modelFetches(), 2);
      expect(list.hasList, isTrue);
    });

    test('a new key refetches even a fresh list', () async {
      final list = catalog();
      await list.refresh();
      requests.clear();

      when(() => settings.cachedOpenRouterApiKey).thenReturn('sk-or-new');
      settings.changed();
      await pumpEventQueue();

      expect(modelFetches(), 2);
      expect(auths.skip(2), everyElement('Bearer sk-or-new'));
    });

    test('other changes only notify listeners', () async {
      final list = catalog();
      await list.refresh();
      requests.clear();
      var notified = 0;
      list.addListener(() => notified++);

      settings.changed();
      await pumpEventQueue();

      expect(requests, isEmpty);
      expect(notified, 1);
    });
  });

  group('latency', () {
    test('is read for every offered model', () async {
      final list = catalog();
      await list.refresh();
      requests.clear();
      auths.clear();

      await list.loadLatency();

      expect(list.latencyOf(_Ids.mai), const Duration(milliseconds: 420));
      expect(list.latencyOf(_Ids.assembly), const Duration(milliseconds: 292));
      expect(list.latencyOf(_Ids.qwen), isNull, reason: 'no recent traffic');
      expect(list.latencyOf(_Ids.voxtral), isNull, reason: 'no hosts');
      // Zero data retention is on: models it hides aren't read.
      expect(endpointFetches(), list.choices.length);
      expect(list.choices.length, lessThan(list.models.length));
      expect(auths, everyElement('Bearer sk-or-key'));
    });

    test(
      'is read a batch at a time, with one notification at each end',
      () async {
        served = [
          for (var i = 0; i < AppConstants.openRouterLatencyBatch * 2 + 1; i++)
            _Ids.model('acme/m$i', 'Acme: M$i'),
        ];
        zdrIds = {for (final m in served) m['id']! as String};
        final list = catalog();
        await list.refresh();
        final loading = <bool>[];
        list.addListener(() => loading.add(list.isLoadingLatency));

        await list.loadLatency();

        expect(endpointFetches(), served.length);
        expect(loading, [true, false]);
      },
    );

    test(
      'stops when a whole batch fails, rather than wait out every timeout',
      () async {
        served = [
          for (var i = 0; i < AppConstants.openRouterLatencyBatch * 2 + 1; i++)
            _Ids.model('acme/m$i', 'Acme: M$i'),
        ];
        zdrIds = {for (final m in served) m['id']! as String};
        brokenEndpoints = {for (final m in served) m['id']! as String};
        final list = catalog();
        await list.refresh();

        await list.loadLatency();

        expect(endpointFetches(), AppConstants.openRouterLatencyBatch);
      },
    );

    test('a failed read is tried again on the next load', () async {
      brokenEndpoints = {_Ids.mai};
      final list = catalog();
      await list.refresh();
      await list.loadLatency();
      requests.clear();
      brokenEndpoints = {};

      await list.loadLatency();

      expect(endpointFetches(), 1, reason: 'only the one that failed');
      expect(list.latencyOf(_Ids.mai), const Duration(milliseconds: 420));
    });

    test(
      'a model new to the list gets a figure; the fresh ones aren’t read',
      () async {
        final list = catalog();
        await list.refresh();
        await list.loadLatency();
        served = [...served, _Ids.model('acme/new-stt', 'Acme: New STT')];
        zdrIds = {...zdrIds, 'acme/new-stt'};
        p50s['acme/new-stt'] = [333];
        await list.refresh(force: true);
        requests.clear();

        await list.loadLatency();

        expect(endpointFetches(), 1);
        expect(
          list.latencyOf('acme/new-stt'),
          const Duration(milliseconds: 333),
        );
      },
    );

    test('is not read while the list itself fails', () async {
      final list = catalog();
      await list.refresh();
      failure = http.Response('{"error":{"message":"User not found."}}', 401);
      await list.refresh(force: true);
      requests.clear();

      await list.loadLatency();

      expect(list.lastError, isNotNull);
      expect(requests, isEmpty);
    });

    test('is not read again while fresh', () async {
      final list = catalog();
      await list.refresh();
      await list.loadLatency();
      final first = endpointFetches();

      now = now.add(const Duration(minutes: 9));
      await list.loadLatency();
      expect(endpointFetches(), first);

      now = now.add(AppConstants.openRouterLatencyMaxAge);
      await list.loadLatency();
      expect(endpointFetches(), first * 2);
    });

    test('concurrent loads share one', () async {
      final list = catalog();
      await list.refresh();
      requests.clear();

      await Future.wait([list.loadLatency(), list.loadLatency()]);

      expect(endpointFetches(), list.choices.length);
    });

    test('a model whose hosts can’t be read just has no figure', () async {
      brokenEndpoints = {_Ids.mai};
      final list = catalog();
      await list.refresh();

      await list.loadLatency();

      expect(list.latencyOf(_Ids.mai), isNull);
      expect(list.latencyOf(_Ids.assembly), const Duration(milliseconds: 292));
    });

    test('needs a list and a key', () async {
      final list = catalog();
      await list.loadLatency();
      expect(requests, isEmpty, reason: 'no list yet');

      await list.refresh();
      requests.clear();
      when(() => settings.cachedOpenRouterApiKey).thenReturn(null);
      await list.loadLatency();
      expect(requests, isEmpty, reason: 'no key');
    });
  });

  group('typicalMedian', () {
    Map<String, dynamic> endpoints(List<Object?> entries) => {
      'data': {'endpoints': entries},
    };
    Map<String, Object?> host(Object? p50) => {
      'perf_last_30m_by_workload': {
        'stt': {
          'latency': {'p50': p50},
        },
      },
    };

    test('weights each host’s p50 by the requests it served', () {
      Map<String, Object?> counted(num p50, num count) => {
        'perf_last_30m_by_workload': {
          'stt': {
            'latency': {'p50': p50},
            'request_count': count,
          },
        },
      };

      // (400 × 3 + 1000 × 1) / 4 = 550: most requests take the fast host.
      expect(
        OpenRouterCatalog.typicalMedian(
          endpoints([counted(400, 3), counted(1000, 1)]),
        ),
        const Duration(milliseconds: 550),
      );
    });

    test('without request counts, takes the lowest p50', () {
      expect(
        OpenRouterCatalog.typicalMedian(
          endpoints([host(900), host(310.6), host(450)]),
        ),
        const Duration(milliseconds: 311),
      );
    });

    test('ignores hosts with no, zero or non-numeric figures', () {
      expect(
        OpenRouterCatalog.typicalMedian(
          endpoints([
            host(null),
            host(0),
            host('fast'),
            {'perf_last_30m_by_workload': null},
            {
              'perf_last_30m_by_workload': {'chat': <String, Object?>{}},
            },
            'junk',
            host(700),
          ]),
        ),
        const Duration(milliseconds: 700),
      );
    });

    test('is null when no host has a figure, or the shape is wrong', () {
      expect(OpenRouterCatalog.typicalMedian(endpoints([host(null)])), isNull);
      expect(OpenRouterCatalog.typicalMedian(endpoints([])), isNull);
      expect(OpenRouterCatalog.typicalMedian({'data': []}), isNull);
      expect(OpenRouterCatalog.typicalMedian({}), isNull);
    });
  });
}
