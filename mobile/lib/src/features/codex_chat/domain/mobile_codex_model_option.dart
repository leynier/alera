part of 'mobile_codex_state.dart';

@immutable
class MobileCodexModelOption {
  const MobileCodexModelOption({
    required this.id,
    required this.label,
    this.isDefault = false,
    this.contextWindowTokens,
    this.supportsFastMode = false,
    this.reasoningEfforts = const <String>[],
    this.defaultReasoningEffort,
    this.metadata = const <String, Object?>{},
  });

  factory MobileCodexModelOption.fromJson(Object? value) {
    final json = _map(value);
    final id = _first(<Object?>[json['id'], json['model'], json['name']]);
    return MobileCodexModelOption(
      id: id.isEmpty ? 'unknown' : id,
      label: _first(<Object?>[
        json['displayName'],
        json['label'],
        json['name'],
        id,
      ]),
      isDefault: json['isDefault'] == true || json['default'] == true,
      contextWindowTokens: _int(
        json['contextWindowTokens'] ?? json['contextWindow'],
      ),
      defaultReasoningEffort: _string(json['defaultReasoningEffort']),
      supportsFastMode:
          json['supportsFastMode'] == true ||
          _containsFast(json['serviceTier']) ||
          _containsFast(json['additionalSpeedTiers']) ||
          _containsFast(json['serviceTiers']) ||
          _containsFast(json['supportedServiceTiers']) ||
          _containsFast(json['serviceTierOptions']),
      reasoningEfforts: _reasoningEfforts(
        json['reasoningEfforts'] ??
            json['supportedReasoningEfforts'] ??
            (json['reasoning'] is Map
                ? (json['reasoning'] as Map)['efforts']
                : null),
      ),
      metadata: json,
    );
  }

  final String id;
  final String label;
  final bool isDefault;
  final int? contextWindowTokens;
  final bool supportsFastMode;
  final List<String> reasoningEfforts;
  final String? defaultReasoningEffort;
  final Map<String, Object?> metadata;
}
