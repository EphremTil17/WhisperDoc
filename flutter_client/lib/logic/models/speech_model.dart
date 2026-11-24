import 'package:flutter/foundation.dart';
import 'package:flutter_client/logic/models/open_router_model_id.dart';

/// A speech-to-text model OpenRouter serves, as the model picker shows it.
@immutable
class SpeechModel implements Comparable<SpeechModel> {
  const SpeechModel({
    required this.id,
    required this.fullName,
    required this.zdr,
    this.retiresOn,
  });

  /// OpenRouter's id, e.g. `microsoft/mai-transcribe-2`.
  final String id;

  /// OpenRouter's display name, e.g. `Microsoft AI: MAI-Transcribe 2`.
  final String fullName;

  /// At least one host keeps no data (zero data retention).
  final bool zdr;

  /// The day OpenRouter stops serving it, when announced.
  final DateTime? retiresOn;

  /// The model's own name, without the maker: `MAI-Transcribe 2`.
  String get name {
    final parts = fullName.split(': ');

    return parts.length > 1 ? parts.skip(1).join(': ') : fullName;
  }

  /// Who makes it: `Microsoft AI`; empty when the name doesn't say.
  String get maker {
    final parts = fullName.split(': ');

    return parts.length > 1 ? parts.first : '';
  }

  /// An entry of OpenRouter's `/models` list (or of the saved copy of one);
  /// null when it isn't a usable model.
  static SpeechModel? fromJson(Object? json, {required bool zdr}) {
    if (json is! Map<String, dynamic>) return null;
    final id = json['id'];
    if (id is! String || !OpenRouterModelId.isValid(id)) return null;
    final rawName = json['name'];
    final name = rawName is String ? rawName.trim() : '';
    final expiration = json['expiration_date'];

    return SpeechModel(
      id: id,
      fullName: name.isNotEmpty ? name : id,
      zdr: zdr,
      retiresOn: expiration is String ? DateTime.tryParse(expiration) : null,
    );
  }

  /// The saved form, read back by [fromJson].
  Map<String, Object?> toJson() => {
    'id': id,
    'name': fullName,
    'expiration_date': retiresOn?.toIso8601String(),
    'zdr': zdr,
  };

  /// By maker, then model: the order a person scans a list in.
  @override
  int compareTo(SpeechModel other) =>
      fullName.toLowerCase().compareTo(other.fullName.toLowerCase());

  @override
  bool operator ==(Object other) =>
      other is SpeechModel &&
      other.id == id &&
      other.fullName == fullName &&
      other.zdr == zdr &&
      other.retiresOn == retiresOn;

  @override
  int get hashCode => Object.hash(id, fullName, zdr, retiresOn);
}
