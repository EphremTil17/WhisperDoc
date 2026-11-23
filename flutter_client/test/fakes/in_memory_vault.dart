// A shared fake library, not a test: its public class is the point.
// ignore_for_file: avoid-top-level-members-in-tests
import 'package:flutter_client/services/utility/secure_vault_service.dart';
import 'package:mocktail/mocktail.dart';

/// A [SecureVaultService] that keeps credentials in a map, so a test can
/// check what was stored, read it back after a reload, and seed old entries.
class InMemoryVault extends Fake implements SecureVaultService {
  /// The stored credentials, by key.
  final Map<String, String> entries = {};
  int initializeCalls = 0;

  @override
  Future<void> initialize() async => initializeCalls++;

  @override
  Future<void> storeCredential(String key, String value) async =>
      entries[key] = value;

  @override
  Future<String?> retrieveCredential(String key) async => entries[key];

  @override
  Future<void> deleteCredential(String key) async => entries.remove(key);
}
