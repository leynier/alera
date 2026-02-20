import 'package:alera/src/features/terminal/application/terminal_session.dart';
import 'package:alera/src/shared/models/contracts.dart';

class SessionState {
  const SessionState({
    this.sessions = const <AleraSession>[],
    this.activeSessionId,
    this.terminalSession,
    this.pendingApprovals = const <PendingApproval>[],
    this.activityLog = const <String>[],
    this.mcpServers = const <McpServerConfig>[],
    this.lastOauthUrl,
    this.error,
    this.isBusy = false,
  });

  final List<AleraSession> sessions;
  final String? activeSessionId;
  final TerminalSession? terminalSession;
  final List<PendingApproval> pendingApprovals;
  final List<String> activityLog;
  final List<McpServerConfig> mcpServers;
  final String? lastOauthUrl;
  final String? error;
  final bool isBusy;

  AleraSession? get activeSession {
    if (activeSessionId == null) {
      return null;
    }
    for (final session in sessions) {
      if (session.id == activeSessionId) {
        return session;
      }
    }
    return null;
  }

  SessionState copyWith({
    List<AleraSession>? sessions,
    String? activeSessionId,
    TerminalSession? terminalSession,
    List<PendingApproval>? pendingApprovals,
    List<String>? activityLog,
    List<McpServerConfig>? mcpServers,
    String? lastOauthUrl,
    String? error,
    bool? isBusy,
    bool clearError = false,
    bool clearOauthUrl = false,
  }) {
    return SessionState(
      sessions: sessions ?? this.sessions,
      activeSessionId: activeSessionId ?? this.activeSessionId,
      terminalSession: terminalSession ?? this.terminalSession,
      pendingApprovals: pendingApprovals ?? this.pendingApprovals,
      activityLog: activityLog ?? this.activityLog,
      mcpServers: mcpServers ?? this.mcpServers,
      lastOauthUrl: clearOauthUrl ? null : (lastOauthUrl ?? this.lastOauthUrl),
      error: clearError ? null : (error ?? this.error),
      isBusy: isBusy ?? this.isBusy,
    );
  }
}
