import 'package:alera_agent_chat/src/agent_chat_json.dart';

/// A skill the agent behind a chat offers, in the shape of T3 Code's
/// `ServerProviderSkill`. A person invokes one by typing `$name`; the runtime
/// adapter turns that mention into the provider's native form when it sends
/// the prompt, so the composer only inserts the text.
final class const AgentChatProviderSkill({
  required final String name,
  required final String path,
  final bool enabled = true,
  final String? description,
  final String? scope,
  final String? displayName,
  final String? shortDescription,

  /// Claude `disable-model-invocation`: only a person can invoke it.
  final bool userInvocationOnly = false,

  /// `false` for Claude `user-invocable: false`: only the agent can invoke
  /// it, so composers hide it.
  final bool userInvocable = true,
}) {
  /// A skill of an `agentChat.skills` answer, or `null` without a name that
  /// can be typed as one token or without a path.
  static AgentChatProviderSkill? tryParse(Object? value) {
    final json = agentChatJsonMap(value);
    String? text(Object? value) {
      final trimmed = agentChatJsonString(value)?.trim();
      return trimmed == null || trimmed.isEmpty ? null : trimmed;
    }

    final typed = text(json['name']) ?? '';
    final name = typed.startsWith(r'$') ? typed.substring(1) : typed;
    final path = text(json['path']);
    if (name.isEmpty || name.contains(RegExp(r'\s')) || path == null) {
      return null;
    }
    return AgentChatProviderSkill(
      name: name,
      path: path,
      enabled: agentChatJsonBool(json['enabled'], true),
      description: text(json['description']),
      scope: text(json['scope']),
      displayName: text(json['displayName']),
      shortDescription: text(json['shortDescription']),
      userInvocationOnly: agentChatJsonBool(json['userInvocationOnly']),
      userInvocable: agentChatJsonBool(json['userInvocable'], true),
    );
  }

  /// T3 Code's `formatProviderSkillDisplayName`: the display name, else the
  /// name in title case split at spaces, `:`, `_` and `-`.
  String get label {
    final display = displayName?.trim();
    if (display != null && display.isNotEmpty) return display;
    return <String>[
      for (final segment in name.split(RegExp(r'[\s:_-]+')))
        if (segment.isNotEmpty) segment[0].toUpperCase() + segment.substring(1),
    ].join(' ');
  }

  /// What a menu row shows beside the label, as T3 Code's composer does.
  String get detail =>
      shortDescription ??
      description ??
      (scope != null ? '$scope skill' : 'Run provider skill');

  /// T3 Code's `isProviderSkillUserInvocable`: enabled and not agent-only.
  bool get isUserInvocable => enabled && userInvocable;

  /// What picking the skill puts in the prompt: the mention and a space.
  String get insertion => '\$$name ';

  /// Where the skill comes from, for grouping and labels.
  AgentChatSkillSourceKind get sourceKind {
    final normalizedPath = path.replaceAll(r'\', '/');
    if (normalizedPath.contains('/.codex/plugins/') ||
        normalizedPath.contains('/.agents/plugins/')) {
      return AgentChatSkillSourceKind.app;
    }
    return switch (scope?.trim().toLowerCase()) {
      'repo' || 'repository' => AgentChatSkillSourceKind.repo,
      'project' || 'workspace' || 'local' => AgentChatSkillSourceKind.project,
      'user' || 'personal' => AgentChatSkillSourceKind.personal,
      'system' => AgentChatSkillSourceKind.system,
      _ => AgentChatSkillSourceKind.other,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is AgentChatProviderSkill &&
      other.name == name &&
      other.path == path &&
      other.enabled == enabled &&
      other.description == description &&
      other.scope == scope &&
      other.displayName == displayName &&
      other.shortDescription == shortDescription &&
      other.userInvocationOnly == userInvocationOnly &&
      other.userInvocable == userInvocable;

  @override
  int get hashCode => Object.hash(
    name,
    path,
    enabled,
    description,
    scope,
    displayName,
    shortDescription,
    userInvocationOnly,
    userInvocable,
  );

  @override
  String toString() => 'AgentChatProviderSkill(\$$name)';
}

/// T3 Code's `ProviderSkillSourceKind`.
enum AgentChatSkillSourceKind { app, repo, project, personal, system, other }

/// Whether an `agentChat.skills` answer is the agent's list.
enum AgentChatSkillsStatus {
  /// [AgentChatSkillList.skills] is the agent's list.
  ready,

  /// The agent reports skills only once its session starts.
  pending,

  /// Discovery did not answer; [AgentChatSkillList.error] says why.
  failed,
}

/// An `agentChat.skills` answer.
final class const AgentChatSkillList({
  final List<AgentChatProviderSkill> skills = const <AgentChatProviderSkill>[],
  final AgentChatSkillsStatus status = AgentChatSkillsStatus.ready,
  final String? error,
}) {
  static const AgentChatSkillList empty = AgentChatSkillList();

  factory AgentChatSkillList.fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    return AgentChatSkillList(
      skills: agentChatProviderSkillsFromJson(json['skills']),
      status: switch (agentChatJsonString(json['status'])) {
        'pending' => AgentChatSkillsStatus.pending,
        'failed' => AgentChatSkillsStatus.failed,
        _ => AgentChatSkillsStatus.ready,
      },
      error: agentChatJsonString(json['error']),
    );
  }

  /// The skills a person can pick, one per name compared without case, as
  /// T3 Code's `searchProviderSkills` offers them.
  List<AgentChatProviderSkill> get invocable =>
      agentChatDedupeSkillsByName(<AgentChatProviderSkill>[
        for (final skill in skills)
          if (skill.isUserInvocable) skill,
      ]);
}

/// The skills of a `skills` list, one per exact name.
List<AgentChatProviderSkill> agentChatProviderSkillsFromJson(Object? value) {
  final seen = <String>{};
  return <AgentChatProviderSkill>[
    for (final entry in agentChatJsonList(value))
      if (AgentChatProviderSkill.tryParse(entry) case final skill?)
        if (seen.add(skill.name)) skill,
  ];
}

/// T3 Code's `dedupeProviderSkillsByName`: the first of each name, compared
/// without case.
List<AgentChatProviderSkill> agentChatDedupeSkillsByName(
  Iterable<AgentChatProviderSkill> skills,
) {
  final seen = <String>{};
  return <AgentChatProviderSkill>[
    for (final skill in skills)
      if (seen.add(skill.name.trim().toLowerCase())) skill,
  ];
}
