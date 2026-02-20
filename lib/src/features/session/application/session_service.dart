import 'dart:async';

import 'package:alera/src/features/agents/application/agent_orchestrator.dart';
import 'package:alera/src/features/agents/application/agent_orchestrator_event.dart';
import 'package:alera/src/features/approvals/application/approval_service.dart';
import 'package:alera/src/features/commands/application/slash_command_registry.dart';
import 'package:alera/src/features/projects/application/project_service.dart';
import 'package:alera/src/features/session/application/session_runtime_event.dart';
import 'package:alera/src/features/worktree/application/worktree_service.dart';
import 'package:alera/src/shared/models/contracts.dart';
import 'package:uuid/uuid.dart';

class SessionService {
  SessionService({
    required AgentOrchestrator orchestrator,
    required ProjectService projectService,
    required WorktreeService worktreeService,
    required ApprovalService approvalService,
    required SlashCommandRegistry commandRegistry,
  })  : _orchestrator = orchestrator,
        _projectService = projectService,
        _worktreeService = worktreeService,
        _approvalService = approvalService,
        _commandRegistry = commandRegistry;

  final AgentOrchestrator _orchestrator;
  final ProjectService _projectService;
  final WorktreeService _worktreeService;
  final ApprovalService _approvalService;
  final SlashCommandRegistry _commandRegistry;
  final Uuid _uuid = const Uuid();

  final Map<String, AleraSession> _sessions = <String, AleraSession>{};
  final StreamController<SessionRuntimeEvent> _eventsController =
      StreamController<SessionRuntimeEvent>.broadcast();

  StreamSubscription<AgentOrchestratorEvent>? _orchestratorSub;
  var _orchestratorReady = false;

  List<AleraSession> get sessions => _sessions.values.toList(growable: false);
  Stream<SessionRuntimeEvent> get events => _eventsController.stream;

  Future<AleraSession> createSession(SessionCreateRequest request) async {
    final isGitRepo = await _projectService.isGitRepository(request.projectPath);
    if (!isGitRepo) {
      throw StateError('projectPath must be a git repository');
    }

    WorktreeSpec? worktreeSpec;
    var workspacePath = request.projectPath;

    if (request.workspaceMode == SessionWorkspaceMode.worktree) {
      worktreeSpec = await _worktreeService.createWorktree(
        repoPath: request.projectPath,
        firstPrompt: request.firstPrompt,
        baseBranch: request.baseBranch,
        autoPull: request.autoPullBaseBranch,
      );
      workspacePath = worktreeSpec.worktreePath;
    }

    if (!_orchestratorReady) {
      await _orchestrator.boot();
      _orchestratorSub = _orchestrator.events.listen(_onOrchestratorEvent);
      _orchestratorReady = true;
    }

    final threadId = await _orchestrator.ensureThread(cwd: workspacePath);

    final session = AleraSession(
      id: _uuid.v4(),
      request: request,
      workspacePath: workspacePath,
      worktreeSpec: worktreeSpec,
      threadId: threadId,
    );

    _sessions[session.id] = session;
    return session;
  }

  Future<void> runInput({
    required String sessionId,
    required String rawInput,
  }) async {
    final session = _sessions[sessionId];
    if (session == null) {
      throw StateError('session not found: $sessionId');
    }

    final commandResult = await _commandRegistry.execute(rawInput);

    if (session.threadId == null) {
      throw StateError('session has no thread id');
    }

    if (commandResult != null && commandResult.metadata['command'] == '/review') {
      final turnId = await _orchestrator.startReview(
        threadId: session.threadId!,
        delivery: 'inline',
      );
      _sessions[sessionId] = session.copyWith(activeTurnId: turnId);
      return;
    }

    final prompt = commandResult?.prompt ?? rawInput;

    final turnId = await _orchestrator.runTurn(
      threadId: session.threadId!,
      prompt: prompt,
      plannerModel: session.request.plannerModel,
      executorModel: session.request.executorModel,
      mode: session.request.executionMode,
      fullAccess: session.request.fullAccess,
      cwd: session.workspacePath,
    );

    _sessions[sessionId] = session.copyWith(activeTurnId: turnId);
  }

  Future<CommandApprovalDecision> evaluateApproval({
    required String sessionId,
    required String projectPath,
    required CommandApprovalRequest request,
    required ApprovalPolicy policy,
  }) {
    return _approvalService.evaluate(
      sessionId: sessionId,
      projectPath: projectPath,
      request: request,
      policy: policy,
    );
  }

  Future<void> allowCommand({
    required AllowScope scope,
    required String sessionId,
    required String projectPath,
    required String commandPattern,
  }) {
    return _approvalService.allowCommand(
      scope: scope,
      commandPattern: commandPattern,
      sessionId: sessionId,
      projectPath: projectPath,
    );
  }

  Future<void> resolveApproval({
    required PendingApproval approval,
    required ApprovalDecisionType decision,
    AllowScope? allowScope,
  }) async {
    AleraSession? session;
    for (final candidate in _sessions.values) {
      if (candidate.threadId == approval.threadId) {
        session = candidate;
        break;
      }
    }

    if (decision == ApprovalDecisionType.accept &&
        allowScope != null &&
        approval.command != null &&
        session != null) {
      await allowCommand(
        scope: allowScope,
        sessionId: session.id,
        projectPath: session.request.projectPath,
        commandPattern: approval.command!,
      );
    }

    await _orchestrator.resolveApproval(
      approval: approval,
      decision: decision,
      allowScope: allowScope,
    );
  }

  Future<AleraSession> promoteToWorktree(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null) {
      throw StateError('session not found: $sessionId');
    }

    if (session.worktreeSpec != null) {
      return session;
    }

    final worktreeSpec = await _worktreeService.createWorktree(
      repoPath: session.request.projectPath,
      firstPrompt: session.request.firstPrompt,
      baseBranch: session.request.baseBranch,
      autoPull: session.request.autoPullBaseBranch,
    );

    final updated = session.copyWith(
      workspacePath: worktreeSpec.worktreePath,
      worktreeSpec: worktreeSpec,
    );

    _sessions[sessionId] = updated;
    return updated;
  }

  Future<void> closeSession({
    required String sessionId,
    required bool removeWorktree,
  }) async {
    final session = _sessions.remove(sessionId);
    if (session == null) {
      return;
    }

    if (removeWorktree && session.worktreeSpec != null) {
      await _worktreeService.removeWorktree(
        repoPath: session.request.projectPath,
        worktreePath: session.worktreeSpec!.worktreePath,
        force: true,
      );
    }
  }

  Future<void> shutdown() async {
    await _orchestratorSub?.cancel();
    await _eventsController.close();
    await _orchestrator.close();
  }

  void _onOrchestratorEvent(AgentOrchestratorEvent event) {
    if (event is AgentApprovalRequestEvent) {
      _eventsController.add(SessionApprovalRequestedEvent(event.approval));
      return;
    }

    if (event is AgentNotificationEvent) {
      _updateSessionTurnStateFromNotification(event);
      _eventsController.add(
        SessionNotificationEvent(
          method: event.method,
          payload: event.payload,
        ),
      );
      return;
    }
  }

  void _updateSessionTurnStateFromNotification(AgentNotificationEvent event) {
    if (event.method != 'turn/started' && event.method != 'turn/completed') {
      return;
    }

    final params = event.payload['params'];
    if (params is! Map<String, dynamic>) {
      return;
    }
    final turn = params['turn'];
    if (turn is! Map<String, dynamic>) {
      return;
    }

    final turnId = turn['id']?.toString();
    final threadId = turn['threadId']?.toString();
    if (turnId == null || threadId == null) {
      return;
    }

    for (final entry in _sessions.entries) {
      if (entry.value.threadId == threadId) {
        _sessions[entry.key] = entry.value.copyWith(activeTurnId: turnId);
      }
    }
  }
}
