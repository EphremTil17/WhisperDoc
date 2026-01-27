import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:flutter_client/infrastructure/constants/app_constants.dart';

/// Handles low-level OIDC protocol logic (PKCE, Discovery, Token Exchange).
class OidcManager {
  /// Discovers OIDC endpoints from the issuer.
  Future<Map<String, dynamic>> discover() async {
    final response = await http.get(Uri.parse(AppConstants.oidcDiscoveryUrl));
    if (response.statusCode != 200) {
      throw Exception('Failed to discover OIDC endpoints: ${response.body}');
    }
    return jsonDecode(response.body);
  }

  /// Initiates the browser-based auth flow.
  Future<String> authenticate({
    required String authorizationEndpoint,
    required String state,
    required String codeChallenge,
  }) async {
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
    final Map<String, String> body = {'client_id': AppConstants.oidcClientId};

    if (code != null) {
      body['grant_type'] = 'authorization_code';
      body['code'] = code;
      body['redirect_uri'] = AppConstants.oidcRedirectUri;
      body['code_verifier'] = codeVerifier!;
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

    if (response.statusCode != 200) {
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
}
