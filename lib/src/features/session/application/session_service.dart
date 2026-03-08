import 'dart:async';

import 'package:alera/src/features/agents/application/agent_orchestrator.dart';
import 'package:alera/src/features/agents/application/agent_orchestrator_event.dart';
import 'package:alera/src/features/projects/application/project_service.dart';
import 'package:alera/src/features/session/application/session_runtime_event.dart';
import 'package:alera/src/shared/models/contracts.dart';
import 'package:uuid/uuid.dart';

class SessionService {
  SessionService({
    required AgentOrchestrator orchestrator,
    required ProjectService projectService,
  }) : _orchestrator = orchestrator,
       _projectService = projectService;

  final AgentOrchestrator _orchestrator;
  final ProjectService _projectService;
  final Uuid _uuid = const Uuid();

  final Map<String, AleraSession> _sessions = <String, AleraSession>{};
  final StreamController<SessionRuntimeEvent> _eventsController =
      StreamController<SessionRuntimeEvent>.broadcast();

  StreamSubscription<AgentOrchestratorEvent>? _orchestratorSub;
  var _orchestratorReady = false;

  List<AleraSession> get sessions {
    final list = _sessions.values.toList(growable: false);
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  AleraSession? findLatestSessionForWorkspace(String workspacePath) {
    final matching = _sessions.values
        .where((session) => session.workspacePath == workspacePath)
        .toList(growable: false);
    if (matching.isEmpty) {
      return null;
    }
    matching.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return matching.first;
  }

  Stream<SessionRuntimeEvent> get events => _eventsController.stream;

  Future<void> ensureConnected() async {
    await _ensureOrchestrator();
  }

  Future<AleraSession> createSession(SessionCreateRequest request) async {
    final isGitRepo = await _projectService.isGitRepository(
      request.projectPath,
    );
    if (!isGitRepo) {
      throw StateError('projectPath must be a git repository');
    }

    await _ensureOrchestrator();
    final threadId = await _orchestrator.ensureThread(cwd: request.projectPath);
    final now = DateTime.now().toUtc();
    final title = _sessionTitle(request.firstPrompt);

    final session = AleraSession(
      id: _uuid.v4(),
      request: request,
      workspacePath: request.projectPath,
      createdAt: now,
      updatedAt: now,
      title: title,
      model: request.model,
      threadId: threadId,
    );

    _sessions[session.id] = session;
    return session;
  }

  Future<AleraSession> setActiveSession(String sessionId) async {
    final existing = _sessions[sessionId];
    if (existing == null) {
      throw StateError('session not found: $sessionId');
    }

    await _ensureOrchestrator();
    final resumedThreadId = await _orchestrator.ensureThread(
      existingThreadId: existing.threadId,
      cwd: existing.workspacePath,
    );

    final updated = existing.copyWith(
      threadId: resumedThreadId,
      updatedAt: DateTime.now().toUtc(),
    );
    _sessions[sessionId] = updated;
    return updated;
  }

  Future<void> updateSessionModel({
    required String sessionId,
    required String modelId,
  }) async {
    final existing = _sessions[sessionId];
    if (existing == null) {
      throw StateError('session not found: $sessionId');
    }
    _sessions[sessionId] = existing.copyWith(
      model: modelId,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  Future<void> runInput({
    required String sessionId,
    required String rawInput,
    required String reasoningEffort,
    List<Map<String, dynamic>> extraInputItems = const <Map<String, dynamic>>[],
    bool planModeEnabled = false,
    bool forceDefaultCollaborationMode = false,
    String approvalPolicy = 'never',
  }) async {
    final session = _sessions[sessionId];
    if (session == null) {
      throw StateError('session not found: $sessionId');
    }
    if (session.threadId == null) {
      throw StateError('session has no thread id');
    }
    await _ensureOrchestrator();
    final input = <Map<String, dynamic>>[
      <String, dynamic>{'type': 'text', 'text': rawInput},
      ...extraInputItems,
    ];
    final CodexCollaborationMode? collaborationMode;
    if (planModeEnabled) {
      collaborationMode = CodexCollaborationMode(
        kind: CodexCollaborationModeKind.plan,
        settings: CodexCollaborationModeSettings(
          model: session.model,
          reasoningEffort: null,
          developerInstructions: null,
        ),
      );
    } else if (forceDefaultCollaborationMode) {
      collaborationMode = CodexCollaborationMode(
        kind: CodexCollaborationModeKind.defaultMode,
        settings: CodexCollaborationModeSettings(
          model: session.model,
          reasoningEffort: null,
          developerInstructions: null,
        ),
      );
    } else {
      collaborationMode = null;
    }
    final turnId = await _orchestrator.runTurn(
      threadId: session.threadId!,
      input: input,
      model: session.model,
      reasoningEffort: reasoningEffort,
      cwd: session.workspacePath,
      approvalPolicy: approvalPolicy,
      collaborationMode: collaborationMode,
    );

    final updated = session.copyWith(
      lastTurnId: turnId,
      updatedAt: DateTime.now().toUtc(),
    );
    _sessions[sessionId] = updated;
  }

  Future<void> interruptActiveTurn({
    required String sessionId,
    String? turnIdOverride,
  }) async {
    final session = _sessions[sessionId];
    if (session == null) {
      throw StateError('session not found: $sessionId');
    }
    final threadId = session.threadId;
    if (threadId == null || threadId.isEmpty) {
      throw StateError('session has no thread id');
    }
    final turnId = turnIdOverride ?? session.lastTurnId;
    if (turnId == null || turnId.isEmpty) {
      throw StateError('session has no active turn id');
    }

    await _ensureOrchestrator();
    await _orchestrator.interrupt(threadId: threadId, turnId: turnId);
  }

  /// Requests manual context compaction for the active session.
  Future<void> compactContext({required String sessionId}) async {
    final session = _sessions[sessionId];
    if (session == null) {
      throw StateError('session not found: $sessionId');
    }
    final threadId = session.threadId;
    if (threadId == null || threadId.isEmpty) {
      throw StateError('session has no thread id');
    }
    await _ensureOrchestrator();
    await _orchestrator.compactThread(threadId: threadId);
  }

  /// Steers the active turn with new user input (redirect mid-turn).
  ///
  /// Returns the new turn ID from the steer response.
  Future<String> steerActiveTurn({
    required String sessionId,
    required String rawInput,
    required String expectedTurnId,
    List<Map<String, dynamic>> extraInputItems = const <Map<String, dynamic>>[],
  }) async {
    final session = _sessions[sessionId];
    if (session == null) {
      throw StateError('session not found: $sessionId');
    }
    final threadId = session.threadId;
    if (threadId == null || threadId.isEmpty) {
      throw StateError('session has no thread id');
    }
    await _ensureOrchestrator();
    final input = <Map<String, dynamic>>[
      <String, dynamic>{'type': 'text', 'text': rawInput},
      ...extraInputItems,
    ];
    final newTurnId = await _orchestrator.steerTurn(
      threadId: threadId,
      input: input,
      expectedTurnId: expectedTurnId,
    );
    final updated = session.copyWith(
      lastTurnId: newTurnId,
      updatedAt: DateTime.now().toUtc(),
    );
    _sessions[sessionId] = updated;
    return newTurnId;
  }

  Future<void> renameSessionThread({
    required String sessionId,
    required String name,
  }) async {
    final session = _sessions[sessionId];
    if (session == null) {
      throw StateError('session not found: $sessionId');
    }
    final threadId = session.threadId;
    if (threadId == null || threadId.isEmpty) {
      throw StateError('session has no thread id');
    }
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw StateError('thread name must not be empty');
    }

    await _ensureOrchestrator();
    await _orchestrator.setThreadName(threadId: threadId, name: normalizedName);
    _sessions[sessionId] = session.copyWith(
      title: normalizedName,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  Future<void> renameThread({required String sessionId, required String name}) {
    return renameSessionThread(sessionId: sessionId, name: name);
  }

  Future<CodexReviewStartResult> startReview({
    required String sessionId,
    required CodexReviewTarget target,
    CodexReviewDelivery? delivery,
  }) async {
    final session = _sessions[sessionId];
    if (session == null) {
      throw StateError('session not found: $sessionId');
    }
    final threadId = session.threadId;
    if (threadId == null || threadId.isEmpty) {
      throw StateError('session has no thread id');
    }

    await _ensureOrchestrator();
    final result = await _orchestrator.startReview(
      threadId: threadId,
      target: target,
      delivery: delivery,
    );

    _sessions[sessionId] = session.copyWith(
      lastTurnId: result.reviewThreadId == threadId ? result.turn.id : null,
      updatedAt: DateTime.now().toUtc(),
    );
    return result;
  }

  Future<List<CodexCollaborationModePreset>> listCollaborationModes() async {
    await _ensureOrchestrator();
    return _orchestrator.listCollaborationModes();
  }

  Future<List<CodexSkillsListEntry>> listSkills({
    List<String>? cwds,
    bool forceReload = false,
    List<CodexSkillsListExtraRootsForCwd>? perCwdExtraUserRoots,
  }) async {
    await _ensureOrchestrator();
    return _orchestrator.listSkills(
      cwds: cwds,
      forceReload: forceReload,
      perCwdExtraUserRoots: perCwdExtraUserRoots,
    );
  }

  Future<CodexAppsPage> listApps({
    String? sessionId,
    String? cursor,
    int? limit,
    bool forceRefetch = false,
  }) async {
    String? threadId;
    if (sessionId != null) {
      final session = _sessions[sessionId];
      if (session == null) {
        throw StateError('session not found: $sessionId');
      }
      threadId = session.threadId;
    }
    await _ensureOrchestrator();
    return _orchestrator.listApps(
      cursor: cursor,
      limit: limit,
      threadId: threadId,
      forceRefetch: forceRefetch,
    );
  }

  Future<void> approveRequest(Object requestId, {bool forSession = false}) {
    return _orchestrator.approveRequest(requestId, forSession: forSession);
  }

  Future<void> declineRequest(Object requestId) {
    return _orchestrator.declineRequest(requestId);
  }

  Future<void> respondUserInput(
    Object requestId,
    Map<String, dynamic> answers,
  ) {
    return _orchestrator.respondUserInput(requestId, answers);
  }

  Future<void> shutdown() async {
    await _orchestratorSub?.cancel();
    await _eventsController.close();
    await _orchestrator.close();
  }

  Future<void> _ensureOrchestrator() async {
    if (_orchestratorReady) {
      return;
    }
    await _orchestrator.boot();
    _orchestratorSub = _orchestrator.events.listen(_onOrchestratorEvent);
    _orchestratorReady = true;
  }

  void _onOrchestratorEvent(AgentOrchestratorEvent event) {
    if (event is AgentNotificationEvent) {
      _updateSessionTurnStateFromNotification(event);
      _updateSessionThreadNameFromNotification(event);
      _eventsController.add(
        SessionNotificationEvent(method: event.method, payload: event.payload),
      );
    } else if (event is AgentApprovalRequestEvent) {
      _eventsController.add(
        SessionApprovalRequestEvent(
          requestId: event.requestId,
          method: event.method,
          description: event.description,
          threadId: event.threadId,
        ),
      );
    } else if (event is AgentUserInputRequestEvent) {
      _eventsController.add(
        SessionUserInputRequestEvent(
          requestId: event.requestId,
          threadId: event.threadId,
          turnId: event.turnId,
          itemId: event.itemId,
          questions: event.questions,
        ),
      );
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
        _sessions[entry.key] = entry.value.copyWith(
          lastTurnId: turnId,
          updatedAt: DateTime.now().toUtc(),
        );
      }
    }
  }

  void _updateSessionThreadNameFromNotification(AgentNotificationEvent event) {
    if (event.method != 'thread/name/updated') {
      return;
    }
    final params = event.payload['params'];
    if (params is! Map<String, dynamic>) {
      return;
    }
    final update = CodexThreadNameUpdatedNotification.fromJson(params);
    final title = update.threadName?.trim();
    if (title == null || title.isEmpty) {
      return;
    }

    for (final entry in _sessions.entries) {
      if (entry.value.threadId == update.threadId) {
        _sessions[entry.key] = entry.value.copyWith(
          title: title,
          updatedAt: DateTime.now().toUtc(),
        );
      }
    }
  }

  String _sessionTitle(String firstPrompt) {
    final compact = firstPrompt.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (compact.isEmpty) {
      return 'new session';
    }
    return compact.length <= 60 ? compact : '${compact.substring(0, 57)}...';
  }
}
