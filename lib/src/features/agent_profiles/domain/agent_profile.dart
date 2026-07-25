/// A user-declared launch configuration for an orchestration worker agent.
///
/// The catalog is the closed list an orchestrating agent may dispatch to. Alera
/// never derives a profile from a provider, an account, or a quota reading: the
/// user writes every field.
class AgentProfile {
  const AgentProfile({
    required this.id,
    required this.name,
    required this.agentType,
    required this.command,
    required this.createdAt,
    required this.updatedAt,
    this.description = '',
    this.quotaGroup,
  });

  factory AgentProfile.fromJson(Map<String, Object?> json) {
    return AgentProfile(
      id: _requiredString(json, 'id'),
      name: _requiredString(json, 'name'),
      agentType: _requiredString(json, 'agentType'),
      command: _requiredString(json, 'command'),
      description: _optionalString(json['description']) ?? '',
      quotaGroup: _optionalString(json['quotaGroup']),
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

  /// Free-form routing signal the orchestrator reads when choosing a profile
  /// for a stage.
  final String description;

  /// Profiles sharing a group drain the same usage bucket. Alera never measures
  /// this; it only uses the grouping the user asserted so a fallback can prefer
  /// a candidate from a different bucket.
  final String? quotaGroup;

  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'agentType': agentType,
      'command': command,
      'description': description,
      'quotaGroup': quotaGroup,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
    };
  }

  AgentProfile copyWith({
    String? name,
    String? agentType,
    String? command,
    String? description,
    String? quotaGroup,
    bool clearQuotaGroup = false,
  }) {
    return AgentProfile(
      id: id,
      name: name ?? this.name,
      agentType: agentType ?? this.agentType,
      command: command ?? this.command,
      description: description ?? this.description,
      quotaGroup: clearQuotaGroup ? null : (quotaGroup ?? this.quotaGroup),
      createdAt: createdAt,
      updatedAt: DateTime.now().toUtc(),
    );
  }
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
