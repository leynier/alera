import 'package:alera_agent_chat/src/agent_chat_json.dart';

/// How a new workspace for a task gets its files: its own Git worktree, or
/// the project folder shared with other workspaces.
enum AgentChatWorkspaceMode(final String wire) {
  worktree('worktree'),
  shared('shared');

  static AgentChatWorkspaceMode? tryParse(Object? value) {
    final token = agentChatWireToken(value);
    for (final mode in values) {
      if (mode.wire == token) return mode;
    }
    return null;
  }
}

/// When a new workspace's setup runs: before the agent starts, or in the
/// workspace's Setup tab while the agent already works.
enum AgentChatWorkspaceSetup(final String wire) {
  inline('inline'),
  deferred('deferred');

  static AgentChatWorkspaceSetup? tryParse(Object? value) {
    final token = agentChatWireToken(value);
    for (final setup in values) {
      if (setup.wire == token) return setup;
    }
    return null;
  }
}

/// The host id the runtime uses for this machine.
const String agentChatLocalHostId = 'local';

/// Where a delegated task runs. Every delegation names one explicitly; the
/// runtime never picks a chat or workspace on its own.
sealed class const AgentChatTaskTarget() {
  AgentChatJson toJson();

  /// Reads `{chat}`, `{workspace}` or `{newWorkspace}`; anything else is
  /// `null` so an unknown future target never breaks a task row.
  static AgentChatTaskTarget? fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    final chat = agentChatJsonString(agentChatJsonMap(json['chat'])['chatId']);
    if (chat != null) return AgentChatTaskChatTarget(chat);
    final workspace = agentChatJsonString(
      agentChatJsonMap(json['workspace'])['workspaceId'],
    );
    if (workspace != null) return AgentChatTaskWorkspaceTarget(workspace);
    final created = agentChatJsonMap(json['newWorkspace']);
    final projectId = agentChatJsonString(created['projectId']);
    if (projectId == null) return null;
    return AgentChatTaskNewWorkspaceTarget(
      projectId: projectId,
      hostId: agentChatJsonString(created['hostId']) ?? agentChatLocalHostId,
      mode:
          AgentChatWorkspaceMode.tryParse(created['mode']) ??
          AgentChatWorkspaceMode.worktree,
      branch: agentChatJsonString(created['branch']),
      sourceBranch: agentChatJsonString(created['sourceBranch']),
      reuseExistingBranch: agentChatJsonBool(created['reuseExistingBranch']),
      name: agentChatJsonString(created['name']),
      parentWorkspaceId: agentChatJsonString(created['parentWorkspaceId']),
      setup:
          AgentChatWorkspaceSetup.tryParse(created['setup']) ??
          AgentChatWorkspaceSetup.inline,
    );
  }
}

/// A new turn in an existing chat, which keeps its provider and history.
final class const AgentChatTaskChatTarget(final String chatId)
    extends AgentChatTaskTarget {
  @override
  AgentChatJson toJson() => <String, Object?>{
    'chat': <String, Object?>{'chatId': chatId},
  };
}

/// A new chat in an existing workspace.
final class const AgentChatTaskWorkspaceTarget(final String workspaceId)
    extends AgentChatTaskTarget {
  @override
  AgentChatJson toJson() => <String, Object?>{
    'workspace': <String, Object?>{'workspaceId': workspaceId},
  };
}

/// A new chat in a workspace the runtime creates first, through the same
/// managed or shared workspace flow New Workspace uses.
final class const AgentChatTaskNewWorkspaceTarget({
  required final String projectId,
  required final String hostId,
  required final AgentChatWorkspaceMode mode,
  final String? branch,
  final String? sourceBranch,
  final bool reuseExistingBranch = false,
  final String? name,
  final String? parentWorkspaceId,
  final AgentChatWorkspaceSetup setup = AgentChatWorkspaceSetup.inline,
}) extends AgentChatTaskTarget {
  @override
  AgentChatJson toJson() => <String, Object?>{
    'newWorkspace': <String, Object?>{
      'projectId': projectId,
      'hostId': hostId,
      'mode': mode.wire,
      'branch': ?branch,
      'sourceBranch': ?sourceBranch,
      if (reuseExistingBranch) 'reuseExistingBranch': true,
      'name': ?name,
      'parentWorkspaceId': ?parentWorkspaceId,
      'setup': setup.wire,
    },
  };
}
