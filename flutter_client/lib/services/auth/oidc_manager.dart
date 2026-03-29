import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:flutter_client/infrastructure/constants/app_constants.dart';

/// Handles low-level OIDC protocol logic (PKCE, Discovery, Token Exchange).
class OidcManager {
  static const int _httpOk = 200;

  static Uri get _configuredIssuerUri =>
      _normalizeUri(Uri.parse(AppConstants.oidcIssuer));

  static Uri get _issuerOrigin => _configuredIssuerUri.replace(path: '');

  /// Discovers OIDC endpoints from the issuer.
  Future<Map<String, dynamic>> discover() async {
    final discoveryUri = Uri.parse(AppConstants.oidcDiscoveryUrl);
    _validateTrustedUri(
      discoveryUri,
      label: 'OIDC discovery endpoint',
      expectedOrigin: _issuerOrigin,
    );

    final response = await http.get(discoveryUri);
    if (response.statusCode != _httpOk) {
      throw Exception('Failed to discover OIDC endpoints: ${response.body}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('OIDC discovery returned an invalid document');
    }

    _validateDiscoveryDocument(decoded);

    return decoded;
  }

  /// Initiates the browser-based auth flow.
  Future<String> authenticate({
    required String authorizationEndpoint,
    required String state,
    required String codeChallenge,
  }) async {
    _validateEndpointString(
      authorizationEndpoint,
      label: 'OIDC authorization endpoint',
      expectedOrigin: _issuerOrigin,
    );

    final authUri = Uri.parse(authorizationEndpoint).replace(
      queryParameters: {
        'client_id': AppConstants.oidcClientId,
        'redirect_uri': AppConstants.oidcRedirectUri,
        'response_type': 'code',
        'scope': AppConstants.oidcScopes.join(' '),
        'state': state,
        'code_challenge': codeChallenge,
        'code_challenge_method': 'S256',
      },
    );

    final String successHtml = await rootBundle.loadString(
      'assets/auth/success.html',
    );

    return await FlutterWebAuth2.authenticate(
      url: authUri.toString(),
      callbackUrlScheme: AppConstants.oidcRedirectUri,
      options: FlutterWebAuth2Options(
        useWebview: false,
        landingPageHtml: successHtml,
      ),
    );
  }

  /// Exchanges an auth code or refresh token for new tokens.
  Future<Map<String, dynamic>> exchangeToken({
    required String tokenEndpoint,
    String? code,
    String? codeVerifier,
    String? refreshToken,
  }) async {
    _validateEndpointString(
      tokenEndpoint,
      label: 'OIDC token endpoint',
      expectedOrigin: _issuerOrigin,
    );

    final Map<String, String> body = {'client_id': AppConstants.oidcClientId};

    if (code != null) {
      body['grant_type'] = 'authorization_code';
      body['code'] = code;
      body['redirect_uri'] = AppConstants.oidcRedirectUri;
      final verifier = codeVerifier;
      if (verifier == null) {
        throw ArgumentError('codeVerifier is required when code is provided');
      }
      body['code_verifier'] = verifier;
    } else if (refreshToken != null) {
      body['grant_type'] = 'refresh_token';
      body['refresh_token'] = refreshToken;
    } else {
      throw ArgumentError('Either code or refreshToken must be provided');
    }

    final response = await http.post(
      Uri.parse(tokenEndpoint),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: body,
    );

    if (response.statusCode != _httpOk) {
      throw Exception('Token exchange failed: ${response.body}');
    }

    return jsonDecode(response.body);
  }

  // --- Helpers ---

  String generateRandomString(int length) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~';
    final random = Random.secure();

    return List.generate(
      length,
      (index) => chars[random.nextInt(chars.length)],
    ).join();
  }

  String generateCodeChallenge(String verifier) {
    final bytes = utf8.encode(verifier);
    final digest = sha256.convert(bytes);

    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  static Uri _normalizeUri(Uri uri) {
    final path = uri.path;
    final normalizedPath = path.endsWith('/') && path.length > 1
        ? path.replaceFirst(RegExp(r'/$'), '')
        : path;

    return uri.replace(
      scheme: uri.scheme.toLowerCase(),
      host: uri.host.toLowerCase(),
      path: normalizedPath,
    );
  }

  void _validateDiscoveryDocument(Map<String, dynamic> discovery) {
    final issuer = _requireString(discovery['issuer'], 'issuer');
    final authorizationEndpoint = _requireString(
      discovery['authorization_endpoint'],
      'authorization_endpoint',
    );
    final tokenEndpoint = _requireString(
      discovery['token_endpoint'],
      'token_endpoint',
    );

    final discoveredIssuer = _normalizeUri(Uri.parse(issuer));
    final configuredIssuer = _configuredIssuerUri.toString();
    final discoveredIssuerString = discoveredIssuer.toString();

    if (discoveredIssuerString != configuredIssuer) {
      throw Exception(
        'OIDC discovery issuer mismatch: expected $configuredIssuer but received $discoveredIssuerString',
      );
    }

    _validateEndpointString(
      authorizationEndpoint,
      label: 'OIDC authorization endpoint',
      expectedOrigin: _issuerOrigin,
    );
    _validateEndpointString(
      tokenEndpoint,
      label: 'OIDC token endpoint',
      expectedOrigin: _issuerOrigin,
    );
  }

  void _validateEndpointString(
    String value, {
    required String label,
    required Uri expectedOrigin,
  }) {
    _validateTrustedUri(
      Uri.parse(value),
      label: label,
      expectedOrigin: expectedOrigin,
    );
  }

  void _validateTrustedUri(
    Uri uri, {
    required String label,
    required Uri expectedOrigin,
  }) {
    if (!uri.hasScheme || uri.host.isEmpty) {
      throw Exception('$label must be an absolute URI');
    }

    final normalized = _normalizeUri(uri);
    if (!_isTrustedScheme(normalized)) {
      throw Exception('$label must use HTTPS unless it targets loopback');
    }

    if (normalized.host != expectedOrigin.host ||
        normalized.scheme != expectedOrigin.scheme ||
        normalized.port != expectedOrigin.port) {
      throw Exception(
        '$label must stay on the configured issuer origin (${expectedOrigin.toString()})',
      );
    }
  }

  bool _isTrustedScheme(Uri uri) {
    if (uri.scheme == 'https') {
      return true;
    }

    return uri.scheme == 'http' && _isLoopbackHost(uri.host);
  }

  bool _isLoopbackHost(String host) {
    final normalizedHost = host.toLowerCase();

    return normalizedHost == 'localhost' ||
        normalizedHost == '127.0.0.1' ||
        normalizedHost == '::1';
  }

  String _requireString(Object? value, String fieldName) {
    if (value is! String || value.trim().isEmpty) {
      throw Exception('OIDC discovery missing valid "$fieldName"');
    }

    return value;
  }
}
