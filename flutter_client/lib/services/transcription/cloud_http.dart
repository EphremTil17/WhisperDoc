import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_client/infrastructure/constants/app_constants.dart';
import 'package:flutter_client/services/utility/logging_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'cloud_error.dart';

/// The HTTP connection every cloud service call shares.
///
/// One keep-alive client means the TLS connection opened by [warmUp] while
/// the user talks is the one the upload uses when they stop, instead of a
/// fresh handshake (measured at 150–650 ms) after they let go.
class CloudHttp {
  CloudHttp({http.Client? client})
    : _client =
          client ??
          IOClient(HttpClient()..idleTimeout = AppConstants.cloudIdleTimeout);

  static const int _httpOk = 200;

  final http.Client _client;

  /// Opens (or keeps open) a connection to [origin] without sending anything
  /// that needs a key.
  Future<void> warmUp(Uri origin) async {
    try {
      await _client.head(origin).timeout(AppConstants.cloudWarmUpTimeout);
    } on Exception catch (e) {
      // Only a head start: the real request reports any real problem.
      LoggingService().debug('Warm-up of ${origin.host} failed: $e');
    }
  }

  /// GETs [uri] and decodes its JSON object.
  Future<Map<String, dynamic>> getJson(
    String service,
    Uri uri, {
    required String apiKey,
    required Duration timeout,
  }) async => _decodeObject(
    service,
    await _get(service, uri, apiKey: apiKey, timeout: timeout),
  );

  /// GETs [uri] and returns the raw body, for a caller that decodes a large
  /// one off the UI thread.
  Future<String> getBody(
    String service,
    Uri uri, {
    required String apiKey,
    required Duration timeout,
  }) async => (await _get(service, uri, apiKey: apiKey, timeout: timeout)).body;

  Future<http.Response> _get(
    String service,
    Uri uri, {
    required String apiKey,
    required Duration timeout,
  }) => _send(
    service,
    () => _client.get(uri, headers: _auth(apiKey)).timeout(timeout),
  );

  /// POSTs [body] as JSON and decodes the JSON object it returns.
  Future<Map<String, dynamic>> postJson(
    String service,
    Uri uri, {
    required String apiKey,
    required Map<String, Object?> body,
    required Duration timeout,
  }) => postEncodedJson(
    service,
    uri,
    apiKey: apiKey,
    encoded: utf8.encode(jsonEncode(body)),
    timeout: timeout,
  );

  /// [postJson] for a body the caller already encoded to UTF-8 bytes (off
  /// the UI thread, when it carries a whole recording).
  Future<Map<String, dynamic>> postEncodedJson(
    String service,
    Uri uri, {
    required String apiKey,
    required List<int> encoded,
    required Duration timeout,
  }) async {
    final response = await _send(
      service,
      () => _client
          .post(
            uri,
            headers: {..._auth(apiKey), 'Content-Type': 'application/json'},
            body: encoded,
          )
          .timeout(timeout),
    );

    return _decodeObject(service, response);
  }

  /// Sends a request built by [request] (a multipart upload), mapping
  /// failures like the JSON calls do.
  Future<http.Response> sendRequest(
    String service,
    http.BaseRequest Function() request, {
    required Duration timeout,
  }) => _send(
    service,
    () async => http.Response.fromStream(
      await _client.send(request()).timeout(timeout),
    ),
  );

  void dispose() => _client.close();

  /// Runs [call], retrying once when a kept-alive connection turns out to
  /// have been closed by the server, and maps every failure to [CloudError].
  Future<http.Response> _send(
    String service,
    Future<http.Response> Function() call,
  ) async {
    try {
      final response = await call().onError<http.ClientException>(
        (_, _) => call(),
        test: _isStaleConnection,
      );
      if (response.statusCode != _httpOk) {
        throw CloudError.fromResponse(
          service,
          response.statusCode,
          response.body,
          headers: response.headers,
        );
      }

      return response;
    } on CloudError {
      rethrow;
    } on TimeoutException catch (_, st) {
      Error.throwWithStackTrace(
        CloudError.network(service, 'Request timed out'),
        st,
      );
    } on SocketException catch (e, st) {
      Error.throwWithStackTrace(CloudError.network(service, e.message), st);
    } on http.ClientException catch (e, st) {
      Error.throwWithStackTrace(CloudError.network(service, e.message), st);
    } on IOException catch (e, st) {
      // TLS (a proxy that intercepts it, a wrong clock) and anything else
      // the transport raises: the user sees why, not nothing.
      Error.throwWithStackTrace(CloudError.network(service, '$e'), st);
    }
  }

  /// The one failure safe to send again: a kept-alive connection the server
  /// had already closed, so the request never got a header back. A dropped
  /// upload, a refused connection or a DNS failure is not retried (the
  /// first could be billed twice; the others would only fail twice).
  static bool _isStaleConnection(http.ClientException e) =>
      e.message.contains('Connection closed before full header was received');

  static Map<String, String> _auth(String apiKey) => {
    'Authorization': 'Bearer $apiKey',
  };

  static Map<String, dynamic> _decodeObject(
    String service,
    http.Response response,
  ) {
    try {
      final json = jsonDecode(response.body);
      if (json is Map<String, dynamic>) return json;
    } on FormatException {
      // Reported below.
    }

    throw CloudError(
      service: service,
      type: CloudErrorType.unknown,
      message: 'Unexpected response from $service',
    );
  }
}
