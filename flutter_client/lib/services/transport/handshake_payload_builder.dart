import 'package:package_info_plus/package_info_plus.dart';

/// Builder for constructing WebSocket handshake payloads.
class HandshakePayloadBuilder {
  /// Builds the 'hello' event payload for the WebSocket handshake.
  Future<Map<String, dynamic>> buildHello({
    required String token,
    required String authType,
    required bool incognito,
  }) async {
    final info = await PackageInfo.fromPlatform();

    return {
      'event': 'hello',
      'client': 'flutter_windows',
      'version': info.version,
      'token': token,
      'auth_type': authType,
      'incognito': incognito,
    };
  }
}
