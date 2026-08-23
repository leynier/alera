class AgentProfileTabReference {
  const AgentProfileTabReference({
    required this.workspaceId,
    required this.tabId,
  });

  factory AgentProfileTabReference.fromJson(Map<String, Object?> json) {
    return AgentProfileTabReference(
      workspaceId: json['workspaceId'] as String,
      tabId: json['tabId'] as String,
    );
  }

  final String workspaceId;
  final String tabId;
}

class AgentProfileRemovalImpact {
  const AgentProfileRemovalImpact({
    required this.profileId,
    required this.exists,
    this.revision,
    required this.isDefault,
    required this.automationIds,
    required this.hasAutomationPolicy,
    required this.executionPolicyRunIds,
    required this.tabs,
  });

  factory AgentProfileRemovalImpact.fromJson(Map<String, Object?> json) {
    final automationIds = json['automationIds'];
    final executionPolicyRunIds = json['executionPolicyRunIds'];
    final tabs = json['tabs'];
    return AgentProfileRemovalImpact(
      profileId: json['profileId'] as String,
      exists: json['exists'] as bool? ?? false,
      revision: json['revision'] as int?,
      isDefault: json['isDefault'] as bool? ?? false,
      automationIds: automationIds is List
          ? automationIds.whereType<String>().toList(growable: false)
          : const <String>[],
      hasAutomationPolicy: json['hasAutomationPolicy'] as bool? ?? false,
      executionPolicyRunIds: executionPolicyRunIds is List
          ? executionPolicyRunIds.whereType<String>().toList(growable: false)
          : const <String>[],
      tabs: tabs is List
          ? <AgentProfileTabReference>[
              for (final item in tabs)
                if (item is Map)
                  AgentProfileTabReference.fromJson(
                    Map<String, Object?>.from(item),
                  ),
            ]
          : const <AgentProfileTabReference>[],
    );
  }

  final String profileId;
  final bool exists;
  final int? revision;
  final bool isDefault;
  final List<String> automationIds;
  final bool hasAutomationPolicy;
  final List<String> executionPolicyRunIds;
  final List<AgentProfileTabReference> tabs;

  bool get hasBlockingReferences =>
      automationIds.isNotEmpty ||
      executionPolicyRunIds.isNotEmpty ||
      tabs.isNotEmpty;

  String removalMessage(String profileName) {
    final references = <String>[
      if (automationIds.isNotEmpty)
        '${automationIds.length} automation${automationIds.length == 1 ? '' : 's'}',
      if (tabs.isNotEmpty) '${tabs.length} tab${tabs.length == 1 ? '' : 's'}',
      if (isDefault) 'the default profile setting',
      if (hasAutomationPolicy) 'an automation policy',
      if (executionPolicyRunIds.isNotEmpty)
        '${executionPolicyRunIds.length} active execution '
            '${executionPolicyRunIds.length == 1 ? 'policy' : 'policies'}',
    ];
    if (references.isEmpty) {
      return '$profileName has no references. Deleting it cannot be undone.';
    }
    final effect = references.join(', ');
    if (hasBlockingReferences) {
      return '$profileName is referenced by $effect. Remove its automation and '
          'tab references before deleting it.';
    }
    return '$profileName is referenced by $effect. These references will be '
        'cleared atomically when the profile is deleted.';
  }
}
