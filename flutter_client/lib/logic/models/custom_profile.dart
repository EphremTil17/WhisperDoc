import 'package:flutter_client/logic/models/dictation_profile.dart';
import 'package:flutter_client/logic/models/dictation_profile_spec.dart';

/// Immutable domain model representing a user-authored custom dictation profile.
class CustomProfile implements DictationProfileSpec {
  static const List<String> slotKeys = ['custom1', 'custom2', 'custom3'];

  /// Resolves the default naming convention (`Custom 1`, `Custom 2`, `Custom 3`) for a given slot.
  static String defaultNameForSlot(String key) {
    final index = slotKeys.indexOf(key);

    return index >= 0 ? 'Custom ${index + 1}' : 'Custom';
  }

  @override
  final String storageKey;

  final String name;

  final String userPrompt;

  const CustomProfile({
    required this.storageKey,
    required this.name,
    required this.userPrompt,
  });

  @override
  String get label => name;

  @override
  String? get systemPrompt {
    if (userPrompt.trim().isEmpty) return null;

    return '${DictationProfile.sharedPreamble}\nPROFILE: $name\n$userPrompt';
  }

  @override
  bool get requiresLlm => userPrompt.trim().isNotEmpty;

  @override
  bool get isEditable => true;

  Map<String, dynamic> toJson() => {
    'storageKey': storageKey,
    'name': name,
    'userPrompt': userPrompt,
  };

  /// Safely parses JSON into a [CustomProfile], skipping malformed or invalid entries.
  static CustomProfile? tryFromJson(Map<String, dynamic> json) {
    final key = json['storageKey'] as String?;
    final name = json['name'] as String?;
    final prompt = json['userPrompt'] as String?;

    if (key == null || !slotKeys.contains(key)) return null;
    if (name == null || name.trim().isEmpty) return null;
    if (prompt == null || prompt.trim().isEmpty) return null;

    return CustomProfile(
      storageKey: key,
      name: name.trim(),
      userPrompt: prompt.trim(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CustomProfile &&
          runtimeType == other.runtimeType &&
          storageKey == other.storageKey &&
          name == other.name &&
          userPrompt == other.userPrompt;

  @override
  int get hashCode => Object.hash(storageKey, name, userPrompt);
}
