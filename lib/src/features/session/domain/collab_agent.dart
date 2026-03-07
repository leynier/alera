/// Collaborative agent lifecycle status.
///
/// Mirrors `AgentStatus` from the Codex App Server v2 protocol.
enum CollabAgentStatus {
  pendingInit,
  running,
  completed,
  errored,
  shutdown,
  notFound;

  static CollabAgentStatus fromString(String? raw) {
    if (raw == null || raw.isEmpty) return pendingInit;
    final normalized = raw.toLowerCase().trim();
    switch (normalized) {
      case 'pending_init':
      case 'pendinginit':
        return pendingInit;
      case 'running':
        return running;
      case 'completed':
        return completed;
      case 'errored':
        return errored;
      case 'shutdown':
        return shutdown;
      case 'not_found':
      case 'notfound':
        return notFound;
      default:
        return pendingInit;
    }
  }

  /// True when the agent has finished (successfully or with error).
  bool get isTerminal =>
      this == completed ||
      this == errored ||
      this == shutdown ||
      this == notFound;
}

/// Reference to a collaborative sub-agent.
class CollabAgentRef {
  const CollabAgentRef({
    required this.threadId,
    this.agentNickname,
    this.agentRole,
  });

  final String threadId;
  final String? agentNickname;
  final String? agentRole;

  /// Human-readable display name: nickname, role, or truncated thread ID.
  String get displayName {
    if (agentNickname != null && agentNickname!.isNotEmpty) {
      return agentNickname!;
    }
    if (agentRole != null && agentRole!.isNotEmpty) {
      return agentRole!;
    }
    if (threadId.length > 8) {
      return 'Agent ${threadId.substring(0, 8)}…';
    }
    return 'Agent $threadId';
  }

  factory CollabAgentRef.fromMap(Map<String, dynamic> map) {
    return CollabAgentRef(
      threadId:
          (map['thread_id'] as String?) ?? (map['threadId'] as String?) ?? '',
      agentNickname:
          (map['agent_nickname'] as String?) ??
          (map['agentNickname'] as String?) ??
          (map['new_agent_nickname'] as String?),
      agentRole:
          (map['agent_role'] as String?) ??
          (map['agentRole'] as String?) ??
          (map['new_agent_role'] as String?),
    );
  }
}

/// A collaborative sub-agent with lifecycle status.
class CollabAgentEntry {
  const CollabAgentEntry({
    required this.callId,
    required this.ref,
    required this.status,
    this.prompt,
    this.message,
    this.senderThreadId,
  });

  /// The call_id that spawned this agent.
  final String callId;

  /// Reference to the agent (thread ID, nickname, role).
  final CollabAgentRef ref;

  /// Current lifecycle status.
  final CollabAgentStatus status;

  /// The prompt given when spawning the agent (may be truncated).
  final String? prompt;

  /// Completion/error message from the agent.
  final String? message;

  /// Thread ID of the parent that spawned this agent.
  final String? senderThreadId;

  CollabAgentEntry copyWith({
    CollabAgentRef? ref,
    CollabAgentStatus? status,
    String? message,
  }) {
    return CollabAgentEntry(
      callId: callId,
      ref: ref ?? this.ref,
      status: status ?? this.status,
      prompt: prompt,
      message: message ?? this.message,
      senderThreadId: senderThreadId,
    );
  }
}

/// Names of collaborative tool calls that should be treated specially.
const collabToolNames = <String>{
  'SpawnAgent',
  'WaitForAgents',
  'CloseAgent',
  'SendInput',
};

/// Returns true if the tool call name is a collab (multi-agent) tool.
bool isCollabToolCall(String toolName) => collabToolNames.contains(toolName);

// Sub-agent tool name constants.
const toolNameRemoteAgent = 'remote_agent';
const toolNameSubAgent = 'sub_agent';
const toolNameSpawnAgent = 'spawnAgent';
const toolNameWait = 'wait';

/// Names of sub-agent tools.
const subAgentToolNames = <String>{
  toolNameRemoteAgent,
  toolNameSubAgent,
  toolNameSpawnAgent,
  toolNameWait,
};

/// Parses a raw status value from a Codex event.
///
/// Handles both string values ("running") and map values ({ "completed": "..." }).
CollabAgentStatus parseAgentStatus(Object? raw) {
  if (raw is String) {
    return CollabAgentStatus.fromString(raw);
  }
  if (raw is Map) {
    if (raw.containsKey('completed')) return CollabAgentStatus.completed;
    if (raw.containsKey('errored')) return CollabAgentStatus.errored;
  }
  return CollabAgentStatus.pendingInit;
}

/// Extracts the message from an AgentStatus value.
///
/// For `{ "completed": "summary" }` returns "summary".
/// For `{ "errored": "reason" }` returns "reason".
String? parseAgentStatusMessage(Object? raw) {
  if (raw is Map) {
    final completed = raw['completed'];
    if (completed is String && completed.isNotEmpty) return completed;
    final errored = raw['errored'];
    if (errored is String && errored.isNotEmpty) return errored;
  }
  return null;
}
