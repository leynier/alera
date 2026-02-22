import 'dart:async';
import 'dart:io';

import 'package:alera/src/features/projects/application/project_service.dart';
import 'package:alera/src/features/session/application/session_runtime_event.dart';
import 'package:alera/src/features/session/application/session_service.dart';
import 'package:alera/src/features/session/application/session_state.dart';
import 'package:alera/src/features/session/application/session_timeline_reducer.dart';
import 'package:alera/src/features/session/domain/chat_timeline.dart';
import 'package:alera/src/features/session/domain/codex_model_catalog.dart';
import 'package:alera/src/features/settings/application/settings_service.dart';
import 'package:alera/src/shared/models/contracts.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:path/path.dart' as p;

class SessionController extends StateNotifier<SessionState> {
  SessionController({
    required SessionService sessionService,
    required ProjectService projectService,
    required SettingsService settingsService,
  }) : _sessionService = sessionService,
       _projectService = projectService,
       _settingsService = settingsService,
       super(const SessionState()) {
    _eventsSub = _sessionService.events.listen(_onSessionEvent);
  }

  final SessionService _sessionService;
  final ProjectService _projectService;
  final SettingsService _settingsService;
  StreamSubscription<SessionRuntimeEvent>? _eventsSub;

  var _bootstrapped = false;

  Future<void> bootstrap() async {
    if (_bootstrapped) {
      return;
    }

    final defaults = await _settingsService.load();
    final normalizedDefault = codexModelExists(defaults.selectedModel)
        ? defaults.selectedModel
        : codexDefaultModelId();

    if (normalizedDefault != defaults.selectedModel) {
      await _settingsService.save(
        SettingsSnapshot(selectedModel: normalizedDefault),
      );
    }

    state = state.copyWith(
      sessions: _sessionService.sessions,
      connectionState: AppServerConnectionState.disconnected,
      availableModels: codexModelSnapshot,
    );

    _bootstrapped = true;
  }

  Future<bool> selectWorkspaceFromPath(String rawPath) async {
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    final normalized = p.normalize(Directory(trimmed).absolute.path);

    state = state.copyWith(isBusy: true, clearError: true);
    try {
      final validation = await _projectService.validateGitRepository(
        normalized,
      );
      if (!validation.isValidGitRepository) {
        throw StateError(
          validation.message ?? 'selected folder is not a git repository',
        );
      }

      final existing = _sessionService.findLatestSessionForWorkspace(
        normalized,
      );
      state = state.copyWith(
        isBusy: false,
        selectedWorkspacePath: normalized,
        sessions: _sessionService.sessions,
        activeSessionId: existing?.id,
        timelineCells: const <TimelineCell>[],
        clearActiveStreamingAssistantCellId: true,
        clearActiveTurnId: true,
        clearError: true,
        activityLog: const <String>[],
        runningTurnCount: 0,
        connectionState: existing == null
            ? AppServerConnectionState.disconnected
            : AppServerConnectionState.starting,
      );

      if (existing != null) {
        await activateSession(existing.id);
      }
      return true;
    } catch (error) {
      state = state.copyWith(
        isBusy: false,
        error: error.toString(),
        connectionState: AppServerConnectionState.error,
      );
      return false;
    }
  }

  Future<void> activateSession(String sessionId) async {
    final sessions = _sessionService.sessions;
    AleraSession? target;
    for (final entry in sessions) {
      if (entry.id == sessionId) {
        target = entry;
        break;
      }
    }
    if (target == null) {
      return;
    }

    state = state.copyWith(
      isBusy: true,
      clearError: true,
      connectionState: AppServerConnectionState.starting,
      activeSessionId: sessionId,
      selectedWorkspacePath: target.workspacePath,
      timelineCells: const <TimelineCell>[],
      clearActiveStreamingAssistantCellId: true,
      clearActiveTurnId: true,
      activityLog: const <String>[],
      runningTurnCount: 0,
    );

    try {
      await _sessionService.setActiveSession(sessionId);
      state = state.copyWith(
        isBusy: false,
        sessions: _sessionService.sessions,
        activeSessionId: sessionId,
        selectedWorkspacePath: target.workspacePath,
        connectionState: AppServerConnectionState.connected,
      );
    } catch (error) {
      state = state.copyWith(
        isBusy: false,
        error: error.toString(),
        connectionState: AppServerConnectionState.error,
      );
    }
  }

  Future<void> createSession(SessionCreateRequest request) async {
    state = state.copyWith(
      isBusy: true,
      clearError: true,
      connectionState: AppServerConnectionState.starting,
      timelineCells: const <TimelineCell>[],
      clearActiveStreamingAssistantCellId: true,
      clearActiveTurnId: true,
      activityLog: const <String>[],
      runningTurnCount: 0,
    );
    try {
      final session = await _sessionService.createSession(request);
      state = state.copyWith(
        isBusy: false,
        sessions: _sessionService.sessions,
        selectedWorkspacePath: session.workspacePath,
        activeSessionId: session.id,
        connectionState: AppServerConnectionState.connected,
      );

      await _settingsService.save(
        SettingsSnapshot(selectedModel: session.model),
      );
    } catch (error) {
      state = state.copyWith(
        isBusy: false,
        error: error.toString(),
        connectionState: AppServerConnectionState.error,
      );
    }
  }

  Future<void> updateActiveSessionModel(String modelId) async {
    if (!codexModelExists(modelId)) {
      return;
    }
    final session = state.activeSession;
    if (session == null) {
      await _settingsService.save(SettingsSnapshot(selectedModel: modelId));
      return;
    }

    try {
      await _sessionService.updateSessionModel(
        sessionId: session.id,
        modelId: modelId,
      );
      await _settingsService.save(SettingsSnapshot(selectedModel: modelId));
      state = state.copyWith(
        sessions: _sessionService.sessions,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(error: error.toString());
    }
  }

  Future<void> sendInput(String rawInput) async {
    final session = state.activeSession;
    if (session == null) {
      return;
    }
    final text = rawInput.trim();
    if (text.isEmpty) {
      return;
    }

    state = appendOptimisticUserMessage(
      state,
      text: text,
    ).copyWith(isBusy: true, clearError: true);
    try {
      await _sessionService.runInput(sessionId: session.id, rawInput: text);
      state = state.copyWith(isBusy: false, sessions: _sessionService.sessions);
    } catch (error) {
      state = state.copyWith(
        isBusy: false,
        error: error.toString(),
        connectionState: AppServerConnectionState.error,
      );
    }
  }

  Future<SettingsSnapshot> loadSettingsDefaults() {
    return _settingsService.load();
  }

  @override
  void dispose() {
    unawaited(_eventsSub?.cancel());
    super.dispose();
  }

  void _onSessionEvent(SessionRuntimeEvent event) {
    if (event is SessionNotificationEvent) {
      final active = state.activeSession;
      if (active != null && !_notificationMatchesSession(event, active)) {
        return;
      }

      final reduced = reduceNotification(state, event);
      final runningTurnCount = _computeRunningTurnCount(
        current: state.runningTurnCount,
        method: event.method,
      );

      state = reduced.copyWith(
        sessions: _sessionService.sessions,
        runningTurnCount: runningTurnCount,
      );
    }
  }

  bool _notificationMatchesSession(
    SessionNotificationEvent event,
    AleraSession session,
  ) {
    final params = event.payload['params'];
    if (params is! Map<String, dynamic>) {
      return true;
    }

    final threadId = params['threadId']?.toString();
    if (threadId != null && threadId.isNotEmpty) {
      return session.threadId == threadId;
    }

    final turn = params['turn'];
    if (turn is! Map<String, dynamic>) {
      return true;
    }
    final turnThreadId = turn['threadId']?.toString();
    if (turnThreadId == null || turnThreadId.isEmpty) {
      return true;
    }
    return session.threadId == turnThreadId;
  }

  int _computeRunningTurnCount({required int current, required String method}) {
    if (method == 'turn/started') {
      return current + 1;
    }
    if (method == 'turn/completed' || method == 'turn/failed') {
      return current > 0 ? current - 1 : 0;
    }
    return current;
  }
}
