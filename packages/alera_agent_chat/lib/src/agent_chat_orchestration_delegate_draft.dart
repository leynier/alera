import 'dart:convert';

import 'package:alera_agent_chat/src/agent_chat_modes.dart';
import 'package:alera_agent_chat/src/agent_chat_orchestration_inputs.dart';
import 'package:alera_agent_chat/src/agent_chat_orchestration_target.dart';

/// The three ways a person can place a task. Each is an explicit choice:
/// the form never guesses a chat or a workspace.
enum AgentChatTaskTargetKind(final String label) {
  chat('Existing Chat'),
  workspace('New Chat'),
  newWorkspace('New Workspace'),
}

const Object _keep = Object();

/// A change to the form, applied to its latest draft rather than to the one a
/// widget saw when it last built, so two quick edits never undo each other.
typedef AgentChatDelegateDraftEdit = AgentChatDelegateDraft Function(
  AgentChatDelegateDraft draft,
);

/// What the Delegate Task form holds on both apps, and the rules that make
/// it sendable. Text fields are kept as typed; [toInput] trims them.
class const AgentChatDelegateDraft({
  final AgentChatTaskTargetKind targetKind = AgentChatTaskTargetKind.workspace,
  final String task = '',
  final String title = '',
  final String? chatId,
  final String? workspaceId,
  final String? projectId,
  final String hostId = agentChatLocalHostId,
  final AgentChatWorkspaceMode mode = AgentChatWorkspaceMode.worktree,
  final String branch = '',
  final String sourceBranch = '',
  final String workspaceName = '',
  final String? parentWorkspaceId,
  final AgentChatWorkspaceSetup setup = AgentChatWorkspaceSetup.inline,
  final String? providerInstanceId,
  final String? model,
  final AgentChatRuntimeMode? runtimeMode,
  final bool plan = false,
}) {
  /// Nullable fields take `null` to clear them; omitted ones are kept.
  AgentChatDelegateDraft copyWith({
    AgentChatTaskTargetKind? targetKind,
    String? task,
    String? title,
    Object? chatId = _keep,
    Object? workspaceId = _keep,
    Object? projectId = _keep,
    String? hostId,
    AgentChatWorkspaceMode? mode,
    String? branch,
    String? sourceBranch,
    String? workspaceName,
    Object? parentWorkspaceId = _keep,
    AgentChatWorkspaceSetup? setup,
    Object? providerInstanceId = _keep,
    Object? model = _keep,
    Object? runtimeMode = _keep,
    bool? plan,
  }) => AgentChatDelegateDraft(
    targetKind: targetKind ?? this.targetKind,
    task: task ?? this.task,
    title: title ?? this.title,
    chatId: identical(chatId, _keep) ? this.chatId : chatId as String?,
    workspaceId: identical(workspaceId, _keep)
        ? this.workspaceId
        : workspaceId as String?,
    projectId: identical(projectId, _keep)
        ? this.projectId
        : projectId as String?,
    hostId: hostId ?? this.hostId,
    mode: mode ?? this.mode,
    branch: branch ?? this.branch,
    sourceBranch: sourceBranch ?? this.sourceBranch,
    workspaceName: workspaceName ?? this.workspaceName,
    parentWorkspaceId: identical(parentWorkspaceId, _keep)
        ? this.parentWorkspaceId
        : parentWorkspaceId as String?,
    setup: setup ?? this.setup,
    providerInstanceId: identical(providerInstanceId, _keep)
        ? this.providerInstanceId
        : providerInstanceId as String?,
    model: identical(model, _keep) ? this.model : model as String?,
    runtimeMode: identical(runtimeMode, _keep)
        ? this.runtimeMode
        : runtimeMode as AgentChatRuntimeMode?,
    plan: plan ?? this.plan,
  );

  /// A new chat starts with the chosen agent; an existing chat keeps its own.
  bool get startsChat => targetKind != AgentChatTaskTargetKind.chat;

  /// The first thing missing, as a sentence, or `null` when sendable.
  String? get problem {
    if (task.trim().isEmpty) return 'Describe the task.';
    switch (targetKind) {
      case AgentChatTaskTargetKind.chat when chatId == null:
        return 'Choose a chat.';
      case AgentChatTaskTargetKind.workspace when workspaceId == null:
        return 'Choose a workspace.';
      case AgentChatTaskTargetKind.newWorkspace when projectId == null:
        return 'Choose a project.';
      default:
        break;
    }
    if (startsChat && providerInstanceId == null) return 'Choose an agent.';
    return null;
  }

  AgentChatTaskTarget? get target => switch (targetKind) {
    AgentChatTaskTargetKind.chat => switch (chatId) {
      final id? => AgentChatTaskChatTarget(id),
      null => null,
    },
    AgentChatTaskTargetKind.workspace => switch (workspaceId) {
      final id? => AgentChatTaskWorkspaceTarget(id),
      null => null,
    },
    AgentChatTaskTargetKind.newWorkspace => switch (projectId) {
      final id? => AgentChatTaskNewWorkspaceTarget(
        projectId: id,
        hostId: hostId,
        mode: mode,
        branch: _text(branch),
        sourceBranch: _text(sourceBranch),
        name: _text(workspaceName),
        parentWorkspaceId: parentWorkspaceId,
        setup: setup,
      ),
      null => null,
    },
  };

  /// The delegation this draft describes; only valid without a [problem].
  AgentChatDelegateInput toInput(String requestId) {
    final target = this.target;
    if (problem != null || target == null) {
      throw StateError(problem ?? 'The task has no target.');
    }
    return AgentChatDelegateInput(
      requestId: requestId,
      task: task.trim(),
      target: target,
      title: _text(title),
      agent: startsChat
          ? AgentChatTaskAgent(
              providerInstanceId: providerInstanceId!,
              model: model,
            )
          : null,
      runtimeMode: startsChat ? runtimeMode : null,
      interactionMode: startsChat && plan
          ? AgentChatInteractionMode.plan
          : null,
    );
  }

  /// What identifies the request apart from its id.
  String get fingerprint {
    final payload = toInput('').toJson()..remove('requestId');
    return jsonEncode(payload);
  }

  static String? _text(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

/// One request id per distinct action: retrying an unchanged action after a
/// dropped connection replays the runtime's receipt, while an edited one is
/// a new request instead of a `request_conflict`.
final class AgentChatRequestIds {
  AgentChatRequestIds(this._allocate);

  final String Function() _allocate;
  String? _fingerprint;
  String? _id;

  String idFor(String fingerprint) {
    if (fingerprint != _fingerprint || _id == null) {
      _fingerprint = fingerprint;
      _id = _allocate();
    }
    return _id!;
  }

  /// After a success the next action is a new request even when unchanged.
  void reset() {
    _fingerprint = null;
    _id = null;
  }
}
