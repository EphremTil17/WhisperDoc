import 'dart:io';

import 'package:flutter_client/services/utility/logging_service.dart';

/// Transport security service for RFC 1918 validation and WSS enforcement.
///
/// Implements transport layer security following established patterns from the
/// Python terminal client:
/// - Enforce WSS (wss://)for all public IPs
/// - Allow WS (ws://) only for RFC 1918 private networks
/// - Whitelist common local development patterns (localhost, *.local, 127.*)
///
/// Security Properties:
/// - Prevents downgrade attacks on public networks
/// - Protects credentials from man-in-the-middle attacks
/// - Allows flexible local development without SSL overhead
class TransportSecurityService {
  static const int _shift24 = 24;
  static const int _shift16 = 16;
  static const int _shift8 = 8;

  final LoggingService _logger = LoggingService();

  // RFC 1918 private network ranges
  static final List<_IPRange> _privateRanges = [
    _IPRange('10.0.0.0', '10.255.255.255'), // 10.0.0.0/8
    _IPRange('172.16.0.0', '172.31.255.255'), // 172.16.0.0/12
    _IPRange('192.168.0.0', '192.168.255.255'), // 192.168.0.0/16
    _IPRange('127.0.0.0', '127.255.255.255'), // 127.0.0.0/8 (loopback)
  ];

  // Whitelist patterns for fast-path local development
  static final List<String> _localPatterns = ['localhost', '127.0.0.1', '::1'];

  /// Robust URI normalization.
  /// Handles protocol upgrades (https -> wss), endpoint appending (/ws),
  /// and local-dev protocol enforcement (ws:// for localhost).
  String normalizeUri(String uriString) {
    try {
      if (uriString.isEmpty) return uriString;

      var working = uriString.trim();

      // 1. Pre-process to ensure we have a parseable scheme
      if (!working.contains('://')) {
        // Temporarily assume wss to facilitate parsing host/port
        working = 'wss://$working';
      }

      final uri = Uri.parse(working);
      var scheme = uri.scheme.toLowerCase();
      final host = uri.host.toLowerCase();
      final port = uri.port;
      var path = uri.path;

      // 2. Determine Robust Protocol Scheme
      final bool hadScheme = uriString.contains('://');

      if (hadScheme) {
        // Map HTTP schemes to WS equivalents, but preserve ws/wss
        if (scheme == 'https') {
          scheme = 'wss';
        } else if (scheme == 'http') {
          scheme = 'ws';
        }
        // If it's already ws or wss, leave it alone to allow validation to catch public ws
      } else {
        // No scheme provided: apply defaults based on host
        scheme = (_isWhitelistedLocal(host) || isPrivateIP(host))
            ? 'ws'
            : 'wss';
      }

      // 3. Robust Path Management
      // If user provided a base domain, append the canonical /ws endpoint
      if (path.isEmpty || path == '/') {
        path = '/ws';
      }

      // 4. Reconstruct Normalized URI
      return Uri(
        scheme: scheme,
        host: host,
        port: port > 0 ? port : null,
        path: path,
        query: uri.query.isNotEmpty ? uri.query : null,
      ).toString();
    } catch (e) {
      _logger.warning('Normalization failed for "$uriString": $e');

      return uriString;
    }
  }

  /// Validate server URI and return security status
  Future<SecurityStatus> validateServerUri(String uriString) async {
    try {
      final normalizedUriString = normalizeUri(uriString);
      final uri = Uri.parse(normalizedUriString);
      final scheme = uri.scheme.toLowerCase();
      final host = uri.host;

      // 1. WSS is always secure
      if (scheme == 'wss') {
        _logger.info('Transport security: WSS (secure)');

        return SecurityStatus.secure;
      }

      // 2. Non-WS/WSS is blocked
      if (scheme != 'ws') {
        _logger.warning('Transport security: Invalid scheme $scheme (blocked)');

        return SecurityStatus.blocked;
      }

      // 3. Check whitelist patterns first (fast path)
      if (_isWhitelistedLocal(host)) {
        _logger.info(
          'Transport security: WS on whitelisted local host (localDev)',
        );

        return SecurityStatus.localDev;
      }

      // 4. Resolve hostname to IP(s) if needed
      final resolvedIps = _isValidIPAddress(host)
          ? [host]
          : await _resolveHostAddresses(host);

      if (resolvedIps.isEmpty) {
        _logger.warning(
          'Transport security: Failed to resolve hostname (blocked)',
        );

        return SecurityStatus.blocked;
      }

      // 5. Require every resolved IP to be private (RFC 1918 / loopback)
      if (resolvedIps.every(isPrivateIP)) {
        _logger.info(
          'Transport security: WS on private IP ${resolvedIps.first} (localDev)',
        );

        return SecurityStatus.localDev;
      }

      // 6. Public IP with WS is blocked
      _logger.error(
        'Transport security: WS connection to public IP ${resolvedIps.first} (BLOCKED)',
      );

      return SecurityStatus.blocked;
    } catch (e) {
      _logger.error('Transport security validation failed', error: e);

      return SecurityStatus.blocked;
    }
  }

  /// Returns true when [host] is allowed to use cleartext `ws://` without
  /// DNS lookup: loopback (`localhost`, `127.0.0.0/8`, `::1`), mDNS (`*.local`),
  /// or an RFC 1918 private IP literal.
  static bool isLocalOrPrivateHost(String host) =>
      _isWhitelistedLocalHost(host) || _isPrivateIpLiteral(host);

  /// Check if an IP address is in RFC 1918 private range or loopback
  bool isPrivateIP(String ipString) => _isPrivateIpLiteral(ipString);

  static bool _isPrivateIpLiteral(String ipString) {
    if (ipString.isEmpty) return false;

    // tryParse is robust: returns null if not a valid IP (avoids noisy exceptions for hostnames)
    final ip = InternetAddress.tryParse(ipString);
    if (ip == null) return false;

    if (ip.isLoopback) return true;

    // Only check IPv4 private ranges
    if (ip.type == InternetAddressType.IPv4) {
      final ipNum = _ipToIntStatic(ipString);
      for (final range in _privateRanges) {
        if (ipNum >= range.start && ipNum <= range.end) {
          return true;
        }
      }
    }

    return false;
  }

  // --- Private Helper Methods ---

  bool _isWhitelistedLocal(String host) => _isWhitelistedLocalHost(host);

  static bool _isWhitelistedLocalHost(String host) {
    final hostLower = host.toLowerCase();

    // Exact matches
    if (_localPatterns.contains(hostLower)) {
      return true;
    }

    // Pattern: *.local (mDNS)
    if (hostLower.endsWith('.local')) {
      return true;
    }

    return false;
  }

  bool _isValidIPAddress(String host) {
    return InternetAddress.tryParse(host) != null;
  }

  Future<List<String>> _resolveHostAddresses(String hostname) async {
    try {
      _logger.info('Resolving hostname: $hostname');
      final addresses = await InternetAddress.lookup(hostname);
      if (addresses.isNotEmpty) {
        final ips = addresses.map((a) => a.address).toList(growable: false);
        _logger.info('Resolved $hostname to ${ips.first}');

        return ips;
      }

      return const [];
    } catch (e) {
      _logger.warning('DNS resolution failed for $hostname');

      return const [];
    }
  }

  static int _ipToIntStatic(String ip) {
    final parts = ip.split('.');

    return (int.parse(parts.first) << _shift24) |
        (int.parse(parts[1]) << _shift16) |
        (int.parse(parts[2]) << _shift8) |
        int.parse(parts[3]);
  }
}

/// Security status for WebSocket connections
enum SecurityStatus {
  secure, // WSS connection
  localDev, // WS connection on private IP (RFC 1918)
  blocked, // WS connection on public IP (security violation)
}

/// Helper class for IP range checking
class _IPRange {
  final int start;
  final int end;

  static const int _shift24 = 24;
  static const int _shift16 = 16;
  static const int _shift8 = 8;

  _IPRange(String startIp, String endIp)
    : start = _ipStringToInt(startIp),
      end = _ipStringToInt(endIp);

  static int _ipStringToInt(String ip) {
    final parts = ip.split('.');

    return (int.parse(parts.first) << _shift24) |
        (int.parse(parts[1]) << _shift16) |
        (int.parse(parts[2]) << _shift8) |
        int.parse(parts[3]);
  }
}
