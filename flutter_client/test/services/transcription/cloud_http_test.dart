// HTTP status codes and timings are the subject under test; requests are
// captured into late locals by the mock handlers.
// ignore_for_file: no-magic-number, avoid-late-keyword
import 'dart:convert';
import 'dart:io';

import 'package:flutter_client/services/transcription/cloud_error.dart';
import 'package:flutter_client/services/transcription/cloud_http.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final uri = Uri.parse('https://api.example.com/v1/thing');
  const timeout = Duration(seconds: 5);

  group('CloudHttp JSON calls', () {
    test('getJson sends the bearer key and decodes the object', () async {
      late http.Request seen;
      final cloud = CloudHttp(
        client: MockClient((request) async {
          seen = request;

          return http.Response('{"data":[1,2]}', 200);
        }),
      );

      final json = await cloud.getJson(
        'Svc',
        uri,
        apiKey: 'k1',
        timeout: timeout,
      );

      expect(seen.method, 'GET');
      expect(seen.url, uri);
      expect(seen.headers['Authorization'], 'Bearer k1');
      expect(json, {
        'data': [1, 2],
      });
    });

    test('postJson sends the body as JSON with its content type', () async {
      late http.Request seen;
      final cloud = CloudHttp(
        client: MockClient((request) async {
          seen = request;

          return http.Response('{"ok":true}', 200);
        }),
      );

      final json = await cloud.postJson(
        'Svc',
        uri,
        apiKey: 'k2',
        body: {'model': 'm', 'n': 3},
        timeout: timeout,
      );

      expect(seen.method, 'POST');
      expect(seen.headers['Authorization'], 'Bearer k2');
      expect(seen.headers['Content-Type'], startsWith('application/json'));
      expect(jsonDecode(seen.body), {'model': 'm', 'n': 3});
      expect(json, {'ok': true});
    });

    test('postEncodedJson sends the caller’s bytes untouched', () async {
      late String body;
      final cloud = CloudHttp(
        client: MockClient((request) async {
          body = request.body;

          return http.Response('{}', 200);
        }),
      );

      await cloud.postEncodedJson(
        'Svc',
        uri,
        apiKey: 'k',
        encoded: utf8.encode('{"pre":"encoded"}'),
        timeout: timeout,
      );

      expect(body, '{"pre":"encoded"}');
    });

    test('getBody returns the raw text', () async {
      final cloud = CloudHttp(
        client: MockClient((_) async => http.Response('not json', 200)),
      );

      expect(
        await cloud.getBody('Svc', uri, apiKey: 'k', timeout: timeout),
        'not json',
      );
    });

    test('a non-object or non-JSON answer is an unknown error', () async {
      for (final body in ['[1,2]', 'not json']) {
        final cloud = CloudHttp(
          client: MockClient((_) async => http.Response(body, 200)),
        );

        await expectLater(
          cloud.getJson('Svc', uri, apiKey: 'k', timeout: timeout),
          throwsA(
            isA<CloudError>()
                .having((e) => e.type, 'type', CloudErrorType.unknown)
                .having(
                  (e) => e.message,
                  'message',
                  'Unexpected response from Svc',
                ),
          ),
        );
      }
    });
  });

  group('CloudHttp failures', () {
    test('a non-200 status becomes a typed CloudError with retry-after', () {
      final cloud = CloudHttp(
        client: MockClient(
          (_) async => http.Response(
            '{"error":{"message":"slow down"}}',
            429,
            headers: {'retry-after': '7'},
          ),
        ),
      );

      expect(
        cloud.getJson('Svc', uri, apiKey: 'k', timeout: timeout),
        throwsA(
          isA<CloudError>()
              .having((e) => e.service, 'service', 'Svc')
              .having((e) => e.type, 'type', CloudErrorType.rateLimited)
              .having((e) => e.message, 'message', 'slow down')
              .having(
                (e) => e.retryAfter,
                'retryAfter',
                const Duration(seconds: 7),
              ),
        ),
      );
    });

    test('a closed kept-alive connection is retried once', () async {
      var calls = 0;
      final cloud = CloudHttp(
        client: MockClient((_) async {
          calls++;
          if (calls == 1) {
            throw http.ClientException(
              'Connection closed before full header was received',
            );
          }

          return http.Response('{"text":"ok"}', 200);
        }),
      );

      final json = await cloud.postJson(
        'Svc',
        uri,
        apiKey: 'k',
        body: {},
        timeout: timeout,
      );

      expect(calls, 2);
      expect(json, {'text': 'ok'});
    });

    test('a second closed connection is a network error, not a loop', () async {
      var calls = 0;
      final cloud = CloudHttp(
        client: MockClient((_) async {
          calls++;
          throw http.ClientException(
            'Connection closed before full header was received',
          );
        }),
      );

      await expectLater(
        cloud.getJson('Svc', uri, apiKey: 'k', timeout: timeout),
        throwsA(
          isA<CloudError>()
              .having((e) => e.type, 'type', CloudErrorType.networkError)
              .having(
                (e) => e.message,
                'message',
                'Connection closed before full header was received',
              ),
        ),
      );
      expect(calls, 2);
    });

    test('a dropped upload or refused connection is not sent twice', () async {
      for (final reason in [
        'Connection closed while receiving data',
        'Connection refused',
        'Failed host lookup',
      ]) {
        var calls = 0;
        final cloud = CloudHttp(
          client: MockClient((_) async {
            calls++;
            throw http.ClientException(reason);
          }),
        );

        await expectLater(
          cloud.postJson('Svc', uri, apiKey: 'k', body: {}, timeout: timeout),
          throwsA(
            isA<CloudError>().having(
              (e) => e.type,
              'type',
              CloudErrorType.networkError,
            ),
          ),
        );
        expect(calls, 1, reason: reason);
      }
    });

    test('a TLS failure is a network error, not an escape', () async {
      final cloud = CloudHttp(
        client: MockClient((_) async {
          throw const HandshakeException('CERTIFICATE_VERIFY_FAILED');
        }),
      );

      await expectLater(
        cloud.getJson('Svc', uri, apiKey: 'k', timeout: timeout),
        throwsA(
          isA<CloudError>()
              .having((e) => e.type, 'type', CloudErrorType.networkError)
              .having(
                (e) => e.userMessage,
                'userMessage',
                'Cannot reach Svc. Check your connection.',
              ),
        ),
      );
    });

    test('an HTTP error answer is never retried', () async {
      for (final status in [400, 401, 404, 500]) {
        var calls = 0;
        final cloud = CloudHttp(
          client: MockClient((_) async {
            calls++;

            return http.Response('{}', status);
          }),
        );

        await expectLater(
          cloud.getJson('Svc', uri, apiKey: 'k', timeout: timeout),
          throwsA(isA<CloudError>()),
        );
        expect(calls, 1, reason: 'status $status');
      }
    });

    test('a timeout is a network error', () {
      final cloud = CloudHttp(
        client: MockClient(
          (_) => Future.delayed(
            const Duration(milliseconds: 200),
            () => http.Response('{}', 200),
          ),
        ),
      );

      expect(
        cloud.getJson(
          'Svc',
          uri,
          apiKey: 'k',
          timeout: const Duration(milliseconds: 10),
        ),
        throwsA(
          isA<CloudError>()
              .having((e) => e.type, 'type', CloudErrorType.networkError)
              .having((e) => e.message, 'message', 'Request timed out'),
        ),
      );
    });

    test('a socket failure is a network error with its reason', () {
      final cloud = CloudHttp(
        client: MockClient((_) async => throw const SocketException('no dns')),
      );

      expect(
        cloud.getJson('Svc', uri, apiKey: 'k', timeout: timeout),
        throwsA(
          isA<CloudError>()
              .having((e) => e.type, 'type', CloudErrorType.networkError)
              .having((e) => e.message, 'message', 'no dns'),
        ),
      );
    });
  });

  group('CloudHttp.sendRequest', () {
    test('builds a fresh request for the retry', () async {
      var built = 0;
      var calls = 0;
      final cloud = CloudHttp(
        client: MockClient((request) async {
          calls++;
          if (calls == 1) {
            throw http.ClientException(
              'Connection closed before full header was received',
            );
          }

          return http.Response('{"text":"done"}', 200);
        }),
      );

      final response = await cloud.sendRequest('Svc', () {
        built++;

        return http.Request('POST', uri)..body = 'x';
      }, timeout: timeout);

      expect(built, 2);
      expect(response.body, '{"text":"done"}');
    });

    test('maps a failed upload like the JSON calls', () {
      final cloud = CloudHttp(
        client: MockClient((_) async => http.Response('too big', 413)),
      );

      expect(
        cloud.sendRequest(
          'Svc',
          () => http.Request('POST', uri),
          timeout: timeout,
        ),
        throwsA(
          isA<CloudError>().having(
            (e) => e.type,
            'type',
            CloudErrorType.fileTooLarge,
          ),
        ),
      );
    });
  });

  group('CloudHttp.warmUp', () {
    test('sends a keyless HEAD to the origin', () async {
      late http.Request seen;
      final cloud = CloudHttp(
        client: MockClient((request) async {
          seen = request;

          return http.Response('', 404);
        }),
      );

      await cloud.warmUp(Uri.parse('https://api.example.com'));

      expect(seen.method, 'HEAD');
      expect(seen.url, Uri.parse('https://api.example.com'));
      expect(seen.headers.containsKey('Authorization'), isFalse);
    });

    test('a failed warm-up is swallowed', () async {
      final cloud = CloudHttp(
        client: MockClient((_) async => throw const SocketException('down')),
      );

      await expectLater(
        cloud.warmUp(Uri.parse('https://api.example.com')),
        completes,
      );
    });
  });
}
