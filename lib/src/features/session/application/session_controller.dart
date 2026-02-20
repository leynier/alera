import 'dart:async';

import 'package:alera/src/features/mcp/application/mcp_service.dart';
import 'package:alera/src/features/session/application/session_runtime_event.dart';
import 'package:alera/src/features/session/application/session_service.dart';
import 'package:alera/src/features/session/application/session_state.dart';
import 'package:alera/src/features/settings/application/settings_service.dart';
import 'package:alera/src/features/terminal/application/terminal_manager.dart';
import 'package:alera/src/shared/models/contracts.dart';
import 'package:flutter_riverpod/legacy.dart';

class SessionController extends StateNotifier<SessionState> {
  SessionController({
    required SessionService sessionService,
    required TerminalManager terminalManager,
    required McpService mcpService,
    required SettingsService settingsService,
  })  : _sessionService = sessionService,
        _terminalManager = terminalManager,
        _mcpService = mcpService,
        _settingsService = settingsService,
        super(const SessionState()) {
    _eventsSub = _sessionService.events.listen(_onSessionEvent);
    unawaited(loadMcpServers());
  }

  final SessionService _sessionService;
  final TerminalManager _terminalManager;
  final McpService _mcpService;
  final SettingsService _settingsService;
  StreamSubscription<SessionRuntimeEvent>? _eventsSub;

  Future<void> createSession(SessionCreateRequest request) async {
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      final session = await _sessionService.createSession(request);
      final terminal = await _terminalManager.create(cwd: session.workspacePath);

      state = state.copyWith(
        isBusy: false,
        sessions: _sessionService.sessions,
        activeSessionId: session.id,
        terminalSession: terminal,
      );

      await _settingsService.save(
        SettingsSnapshot(
          plannerModel: request.plannerModel,
          executorModel: request.executorModel,
          approvalPolicy: request.fullAccess
              ? ApprovalPolicy.autoApproveAllowed
              : ApprovalPolicy.ask,
        ),
      );
    } catch (error) {
      state = state.copyWith(isBusy: false, error: error.toString());
    }
  }

  Future<void> sendInput(String rawInput) async {
    final session = state.activeSession;
    if (session == null) {
      return;
    }

    state = state.copyWith(isBusy: true, clearError: true);
    try {
      await _sessionService.runInput(sessionId: session.id, rawInput: rawInput);
      state = state.copyWith(
        isBusy: false,
        sessions: _sessionService.sessions,
      );
    } catch (error) {
      state = state.copyWith(isBusy: false, error: error.toString());
    }
  }

  Future<void> promoteActiveToWorktree() async {
    final session = state.activeSession;
    if (session == null) {
      return;
    }

    state = state.copyWith(isBusy: true, clearError: true);

    try {
      await _sessionService.promoteToWorktree(session.id);
      state = state.copyWith(
        isBusy: false,
        sessions: _sessionService.sessions,
      );
    } catch (error) {
      state = state.copyWith(isBusy: false, error: error.toString());
    }
  }

  Future<void> closeActiveSession({required bool removeWorktree}) async {
    final session = state.activeSession;
    if (session == null) {
      return;
    }

    state = state.copyWith(isBusy: true, clearError: true);

    try {
      await state.terminalSession?.dispose();
      await _sessionService.closeSession(
        sessionId: session.id,
        removeWorktree: removeWorktree,
      );
      state = state.copyWith(
        isBusy: false,
        sessions: _sessionService.sessions,
        activeSessionId: _sessionService.sessions.isNotEmpty
            ? _sessionService.sessions.first.id
            : null,
        terminalSession: null,
      );
    } catch (error) {
      state = state.copyWith(isBusy: false, error: error.toString());
    }
  }

  Future<void> decideApproval({
    required PendingApproval approval,
    required ApprovalDecisionType decision,
    AllowScope? allowScope,
  }) async {
    try {
      await _sessionService.resolveApproval(
        approval: approval,
        decision: decision,
        allowScope: allowScope,
      );

      final updated = state.pendingApprovals
          .where((candidate) => candidate.requestId != approval.requestId)
          .toList(growable: false);

      state = state.copyWith(pendingApprovals: updated);
    } catch (error) {
      state = state.copyWith(error: error.toString());
    }
  }

  Future<void> loadMcpServers() async {
    try {
      final servers = await _mcpService.listServers();
      state = state.copyWith(mcpServers: servers);
    } catch (_) {
      // mcp listing can fail when app-server is offline; keep UI usable.
    }
  }

  Future<void> addMcpServer({
    required String id,
    required String command,
  }) async {
    state = state.copyWith(isBusy: true, clearError: true, clearOauthUrl: true);
    try {
      await _mcpService.setServerConfig(
        serverId: id,
        config: <String, dynamic>{
          'command': command,
        },
      );
      await _mcpService.reloadConfig();
      await loadMcpServers();
      state = state.copyWith(isBusy: false);
    } catch (error) {
      state = state.copyWith(isBusy: false, error: error.toString());
    }
  }

  Future<void> removeMcpServer(String id) async {
    state = state.copyWith(isBusy: true, clearError: true, clearOauthUrl: true);
    try {
      await _mcpService.removeServerConfig(id);
      await _mcpService.reloadConfig();
      await loadMcpServers();
      state = state.copyWith(isBusy: false);
    } catch (error) {
      state = state.copyWith(isBusy: false, error: error.toString());
    }
  }

  Future<void> loginMcpServer(String id) async {
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      final url = await _mcpService.startOauthLogin(id);
      state = state.copyWith(isBusy: false, lastOauthUrl: url);
    } catch (error) {
      state = state.copyWith(isBusy: false, error: error.toString());
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
    if (event is SessionApprovalRequestedEvent) {
      final exists = state.pendingApprovals
          .any((candidate) => candidate.requestId == event.approval.requestId);
      if (!exists) {
        state = state.copyWith(
          pendingApprovals: <PendingApproval>[
            ...state.pendingApprovals,
            event.approval,
          ],
        );
      }
      return;
    }

    if (event is SessionNotificationEvent) {
      final text = '${event.method}: ${event.payload['params'] ?? ''}';
      final nextLog = <String>[...state.activityLog, text];
      final clipped = nextLog.length <= 200
          ? nextLog
          : nextLog.sublist(nextLog.length - 200);

      state = state.copyWith(
        sessions: _sessionService.sessions,
        activityLog: clipped,
      );
    }
  }
}
