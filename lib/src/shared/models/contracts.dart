import 'dart:convert';

enum SessionWorkspaceMode { repository, worktree }

enum ExecutionMode { normal, plan }

enum ApprovalPolicy { ask, autoApproveAllowed, denyAll }

enum AllowScope { session, project, global }

enum CommandAction {
  filesystemRead,
  filesystemWrite,
  network,
  processExecution,
}

enum ApprovalItemType { commandExecution, fileChange }

enum ApprovalDecisionType { accept, decline }

class SessionCreateRequest {
  const SessionCreateRequest({
    required this.projectPath,
    this.workspaceMode = SessionWorkspaceMode.repository,
    this.baseBranch,
    this.autoPullBaseBranch = false,
    required this.firstPrompt,
    this.fullAccess = false,
    this.executionMode = ExecutionMode.normal,
    required this.plannerModel,
    required this.executorModel,
  });

  final String projectPath;
  final SessionWorkspaceMode workspaceMode;
  final String? baseBranch;
  final bool autoPullBaseBranch;
  final String firstPrompt;
  final bool fullAccess;
  final ExecutionMode executionMode;
  final String plannerModel;
  final String executorModel;
}

class WorktreeSpec {
  const WorktreeSpec({
    required this.branchName,
    required this.worktreePath,
    required this.baseBranch,
  });

  final String branchName;
  final String worktreePath;
  final String baseBranch;
}

class CommandApprovalRequest {
  const CommandApprovalRequest({
    required this.command,
    required this.cwd,
    required this.mode,
    required this.fullAccess,
    this.actions = const <CommandAction>{},
  });

  final String command;
  final String cwd;
  final ExecutionMode mode;
  final bool fullAccess;
  final Set<CommandAction> actions;
}

class CommandApprovalDecision {
  const CommandApprovalDecision({
    required this.approved,
    this.allowScope,
    this.reason,
  });

  final bool approved;
  final AllowScope? allowScope;
  final String? reason;
}

class McpServerConfig {
  const McpServerConfig({
    required this.id,
    required this.transport,
    required this.payload,
    this.enabled = true,
  });

  final String id;
  final String transport;
  final Map<String, dynamic> payload;
  final bool enabled;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'transport': transport,
      'payload': payload,
      'enabled': enabled,
    };
  }

  @override
  String toString() => jsonEncode(toJson());
}

class AleraSession {
  const AleraSession({
    required this.id,
    required this.request,
    required this.workspacePath,
    this.worktreeSpec,
    this.threadId,
    this.activeTurnId,
  });

  final String id;
  final SessionCreateRequest request;
  final String workspacePath;
  final WorktreeSpec? worktreeSpec;
  final String? threadId;
  final String? activeTurnId;

  AleraSession copyWith({
    String? threadId,
    String? workspacePath,
    WorktreeSpec? worktreeSpec,
    String? activeTurnId,
  }) {
    return AleraSession(
      id: id,
      request: request,
      workspacePath: workspacePath ?? this.workspacePath,
      worktreeSpec: worktreeSpec ?? this.worktreeSpec,
      threadId: threadId ?? this.threadId,
      activeTurnId: activeTurnId ?? this.activeTurnId,
    );
  }
}

class PendingApproval {
  const PendingApproval({
    required this.requestId,
    required this.itemType,
    required this.threadId,
    required this.turnId,
    required this.itemId,
    this.approvalId,
    this.reason,
    this.command,
    this.cwd,
    this.commandActions = const <String>[],
  });

  final Object requestId;
  final ApprovalItemType itemType;
  final String threadId;
  final String turnId;
  final String itemId;
  final String? approvalId;
  final String? reason;
  final String? command;
  final String? cwd;
  final List<String> commandActions;

  bool matchesSession(AleraSession session) {
    return session.threadId == threadId;
  }
}
