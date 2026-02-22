import 'package:alera/src/features/session/domain/codex_model_catalog.dart';
import 'package:alera/src/features/session/domain/chat_timeline.dart';
import 'package:alera/src/shared/models/contracts.dart';

class SessionState {
  const SessionState({
    this.selectedWorkspacePath,
    this.sessions = const <AleraSession>[],
    this.activeSessionId,
    this.availableModels = codexModelSnapshot,
    this.timelineMessages = const <TimelineMessage>[],
    this.timelineActivities = const <TimelineActivityItem>[],
    this.turnGroups = const <TimelineTurnGroup>[],
    this.activeStreamingAssistantMessageId,
    this.activeTurnId,
    this.activityLog = const <String>[],
    this.connectionState = AppServerConnectionState.disconnected,
    this.runningTurnCount = 0,
    this.error,
    this.isBusy = false,
  });

  final String? selectedWorkspacePath;
  final List<AleraSession> sessions;
  final String? activeSessionId;
  final List<CodexModelOption> availableModels;
  final List<TimelineMessage> timelineMessages;
  final List<TimelineActivityItem> timelineActivities;
  final List<TimelineTurnGroup> turnGroups;
  final String? activeStreamingAssistantMessageId;
  final String? activeTurnId;
  final List<String> activityLog;
  final AppServerConnectionState connectionState;
  final int runningTurnCount;
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

  String get activeModelId {
    final active = activeSession;
    if (active != null) {
      return active.model;
    }
    return codexDefaultModelId();
  }

  SessionState copyWith({
    String? selectedWorkspacePath,
    List<AleraSession>? sessions,
    String? activeSessionId,
    List<CodexModelOption>? availableModels,
    List<TimelineMessage>? timelineMessages,
    List<TimelineActivityItem>? timelineActivities,
    List<TimelineTurnGroup>? turnGroups,
    String? activeStreamingAssistantMessageId,
    bool clearActiveStreamingAssistantMessageId = false,
    String? activeTurnId,
    bool clearActiveTurnId = false,
    List<String>? activityLog,
    AppServerConnectionState? connectionState,
    int? runningTurnCount,
    String? error,
    bool? isBusy,
    bool clearError = false,
    bool clearSelectedWorkspacePath = false,
    bool clearActiveSessionId = false,
  }) {
    return SessionState(
      selectedWorkspacePath: clearSelectedWorkspacePath
          ? null
          : (selectedWorkspacePath ?? this.selectedWorkspacePath),
      sessions: sessions ?? this.sessions,
      activeSessionId: clearActiveSessionId
          ? null
          : (activeSessionId ?? this.activeSessionId),
      availableModels: availableModels ?? this.availableModels,
      timelineMessages: timelineMessages ?? this.timelineMessages,
      timelineActivities: timelineActivities ?? this.timelineActivities,
      turnGroups: turnGroups ?? this.turnGroups,
      activeStreamingAssistantMessageId: clearActiveStreamingAssistantMessageId
          ? null
          : (activeStreamingAssistantMessageId ??
                this.activeStreamingAssistantMessageId),
      activeTurnId: clearActiveTurnId ? null : (activeTurnId ?? this.activeTurnId),
      activityLog: activityLog ?? this.activityLog,
      connectionState: connectionState ?? this.connectionState,
      runningTurnCount: runningTurnCount ?? this.runningTurnCount,
      error: clearError ? null : (error ?? this.error),
      isBusy: isBusy ?? this.isBusy,
    );
  }
}
