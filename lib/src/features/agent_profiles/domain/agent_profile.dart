/// A user-declared launch configuration for an orchestration worker agent.
///
/// The catalog is the closed list an orchestrating agent may dispatch to. Alera
/// never derives a profile from a provider, an account, or a quota reading: the
/// user writes every field.
enum AgentProfileLaunchMode {
  managed,
  command;

  static AgentProfileLaunchMode fromJson(Object? value) {
    return value == 'managed'
        ? AgentProfileLaunchMode.managed
        : AgentProfileLaunchMode.command;
  }
}

class AgentProfile {
  const AgentProfile({
    required this.id,
    required this.name,
    required this.agentType,
    required this.command,
    required this.createdAt,
    required this.updatedAt,
    this.revision = 0,
    this.description = '',
    this.quotaGroup,
    this.launchMode = AgentProfileLaunchMode.command,
    this.managedConfig = const <String, Object?>{},
    this.customPrompt = '',
  });

  factory AgentProfile.fromJson(Map<String, Object?> json) {
    return AgentProfile(
      id: _requiredString(json, 'id'),
      name: _requiredString(json, 'name'),
      agentType: _requiredString(json, 'agentType'),
      command: _requiredString(json, 'command'),
      launchMode: AgentProfileLaunchMode.fromJson(json['launchMode']),
      managedConfig: _jsonObject(json['managedConfig']),
      customPrompt: _optionalString(json['customPrompt']) ?? '',
      description: _optionalString(json['description']) ?? '',
      quotaGroup: _optionalString(json['quotaGroup']),
      revision: _nonNegativeInt(json['revision']),
      createdAt: _dateTime(json['createdAt']),
      updatedAt: _dateTime(json['updatedAt']),
    );
  }

  final String id;
  final String name;

  /// The built-in adapter that drives readiness detection, preamble injection
  /// and submission for this profile.
  final String agentType;

  /// The interactive launch command. A one-shot mode cannot satisfy the worker
  /// contract of accept, heartbeat and complete.
  final String command;
  final AgentProfileLaunchMode launchMode;

  /// Adapter-specific overrides. Missing keys mean the CLI's own default.
  final Map<String, Object?> managedConfig;

  /// Instructions appended after a dispatched prompt and before project-level
  /// instructions.
  final String customPrompt;

  /// Free-form routing signal the orchestrator reads when choosing a profile
  /// for a stage.
  final String description;

  /// Profiles sharing a group drain the same usage bucket. Alera never measures
  /// this; it only uses the grouping the user asserted so a fallback can prefer
  /// a candidate from a different bucket.
  final String? quotaGroup;

  /// Monotonic concurrency token for all persisted profile fields, including
  /// catalog order.
  final int revision;

  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'agentType': agentType,
      'command': command,
      'launchMode': launchMode.name,
      'managedConfig': launchMode == AgentProfileLaunchMode.managed
          ? managedConfig
          : null,
      'customPrompt': customPrompt,
      'description': description,
      'quotaGroup': quotaGroup,
      'revision': revision,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
    };
  }

  AgentProfile copyWith({
    String? name,
    String? agentType,
    String? command,
    AgentProfileLaunchMode? launchMode,
    Map<String, Object?>? managedConfig,
    String? customPrompt,
    String? description,
    String? quotaGroup,
    bool clearQuotaGroup = false,
  }) {
    return AgentProfile(
      id: id,
      name: name ?? this.name,
      agentType: agentType ?? this.agentType,
      command: command ?? this.command,
      launchMode: launchMode ?? this.launchMode,
      managedConfig: managedConfig ?? this.managedConfig,
      customPrompt: customPrompt ?? this.customPrompt,
      description: description ?? this.description,
      quotaGroup: clearQuotaGroup ? null : (quotaGroup ?? this.quotaGroup),
      revision: revision,
      createdAt: createdAt,
      updatedAt: DateTime.now().toUtc(),
    );
  }
}

int _nonNegativeInt(Object? value) {
  return value is int && value >= 0 ? value : 0;
}

Map<String, Object?> _jsonObject(Object? value) {
  return value is Map
      ? Map<String, Object?>.from(value)
      : const <String, Object?>{};
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String && value.trim().isNotEmpty) {
    return value;
  }
  throw FormatException('Agent profile is missing "$key".');
}

String? _optionalString(Object? value) {
  if (value is String && value.trim().isNotEmpty) {
    return value;
  }
  return null;
}

DateTime _dateTime(Object? value) {
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) {
      return parsed.toUtc();
    }
  }
  return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}
