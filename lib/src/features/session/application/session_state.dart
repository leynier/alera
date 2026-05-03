import 'package:alera/src/features/session/application/streaming/adaptive_chunking_policy.dart';
import 'package:alera/src/features/session/application/streaming/commit_tick_engine.dart';
import 'package:alera/src/features/session/application/streaming/markdown_stream_collector.dart';
import 'package:alera/src/features/session/domain/chat_timeline.dart';
import 'package:alera/src/features/session/domain/codex_model_catalog.dart';
import 'package:alera/src/features/session/domain/collab_agent.dart';
import 'package:alera/src/features/session/domain/composer_attachment.dart';
import 'package:alera/src/features/session/domain/composer_draft_item.dart';
import 'package:alera/src/features/session/domain/context_usage.dart';
import 'package:alera/src/features/session/domain/pending_approval.dart';
import 'package:alera/src/features/session/domain/pending_message.dart';
import 'package:alera/src/features/session/domain/pending_user_input.dart';
import 'package:alera/src/features/session/domain/commands/alera_command.dart';
import 'package:alera/src/shared/models/contracts.dart';

class SessionState {
  const SessionState({
    this.selectedWorkspacePath,
    this.preSessionModelId,
    this.preSessionReasoningEffort,
    this.preSessionSpeedMode,
    this.preSessionMarkdownEnabled,
    this.sessions = const <AleraSession>[],
    this.activeSessionId,
    this.availableModels = codexModelSnapshot,
    this.timelineCells = const <TimelineCell>[],
    this.activeStreamingAssistantCellId,
    this.activeTurnId,
    this.activityLog = const <String>[],
    this.connectionState = AppServerConnectionState.disconnected,
    this.runningTurnCount = 0,
    this.isInterrupting = false,
    this.statusHeader,
    this.pendingStatusRestore = false,
    this.streamCollector = const MarkdownStreamCollectorState(),
    this.streamQueue = const <StreamQueuedLine>[],
    this.chunkingPolicy = const AdaptiveChunkingPolicyState(),
    this.streamQueueDepth = 0,
    this.streamOldestAgeMs,
    this.activeAgentStreamItemId,
    this.activeAgentStreamTurnId,
    this.activeAgentStreamPhase,
    this.activeAgentStreamLastDeltaAtMs,
    this.agentMessagePhaseByItemId = const <String, String>{},
    this.finalAnswerItemIdByTurn = const <String, String>{},
    this.activeExecCellId,
    this.activePlanCellId,
    this.turnHadWorkActivity = false,
    this.turnRuntimeMetrics = const <String, dynamic>{},
    this.reasoningBufferByItemId = const <String, String>{},
    this.composerAttachments = const <ComposerAttachment>[],
    this.composerDraftItems = const <ComposerDraftItem>[],
    this.availableCommands = const <AleraCommand>[],
    this.pendingMessages = const <PendingMessage>[],
    this.editingPendingMessageId,
    this.lastTurnDiff,
    this.planModeEnabled = false,
    this.permissionMode = PermissionMode.defaultMode,
    this.pendingApprovals = const <PendingApproval>[],
    this.pendingUserInput,
    this.contextUsage = ContextUsage.empty,
    this.collabAgents = const <CollabAgentEntry>[],
    this.error,
    this.isBusy = false,
  });

  final String? selectedWorkspacePath;
  final String? preSessionModelId;
  final String? preSessionReasoningEffort;
  final String? preSessionSpeedMode;
  final bool? preSessionMarkdownEnabled;
  final List<AleraSession> sessions;
  final String? activeSessionId;
  final List<CodexModelOption> availableModels;
  final List<TimelineCell> timelineCells;
  final String? activeStreamingAssistantCellId;
  final String? activeTurnId;
  final List<String> activityLog;
  final AppServerConnectionState connectionState;
  final int runningTurnCount;
  final bool isInterrupting;
  final String? statusHeader;
  final bool pendingStatusRestore;
  final MarkdownStreamCollectorState streamCollector;
  final List<StreamQueuedLine> streamQueue;
  final AdaptiveChunkingPolicyState chunkingPolicy;
  final int streamQueueDepth;
  final int? streamOldestAgeMs;
  final String? activeAgentStreamItemId;
  final String? activeAgentStreamTurnId;
  final String? activeAgentStreamPhase;
  final int? activeAgentStreamLastDeltaAtMs;
  final Map<String, String> agentMessagePhaseByItemId;
  final Map<String, String> finalAnswerItemIdByTurn;
  final String? activeExecCellId;
  final String? activePlanCellId;
  final bool turnHadWorkActivity;
  final Map<String, dynamic> turnRuntimeMetrics;
  final Map<String, String> reasoningBufferByItemId;
  final List<ComposerAttachment> composerAttachments;
  final List<ComposerDraftItem> composerDraftItems;
  final List<AleraCommand> availableCommands;
  // Messages queued while a turn is running, processed in order.
  final List<PendingMessage> pendingMessages;
  // ID of the message currently being edited in the queue.
  final String? editingPendingMessageId;
  // Latest unified diff from turn/diff/updated events.
  final String? lastTurnDiff;
  // Whether plan mode (collaborative mode) is enabled for the next turn.
  final bool planModeEnabled;
  // Current permission mode: default (ask) or fullAccess (auto-accept).
  final PermissionMode permissionMode;
  // Approval requests waiting for user decision.
  final List<PendingApproval> pendingApprovals;
  // User input request from plan mode (request_user_input tool).
  final PendingUserInput? pendingUserInput;

  /// Aggregated context usage (token counts, context window, rate limits).
  final ContextUsage contextUsage;

  /// Active collaborative sub-agents (multi-agent feature).
  final List<CollabAgentEntry> collabAgents;
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
    final draft = preSessionModelId;
    if (draft != null && codexModelExists(draft)) {
      return draft;
    }
    return codexDefaultModelId();
  }

  String get activeReasoningEffort {
    final draft = preSessionReasoningEffort;
    final normalized = draft != null && codexReasoningEffortExists(draft)
        ? draft
        : codexDefaultReasoningEffort();
    return closestSupportedReasoningEffort(
      modelId: activeModelId,
      effort: normalized,
    );
  }

  String get activeSpeedMode {
    final draft = preSessionSpeedMode;
    final normalized = draft != null && codexSpeedModeExists(draft)
        ? draft
        : codexDefaultSpeedMode();
    return closestSupportedSpeedMode(
      modelId: activeModelId,
      speedMode: normalized,
    );
  }

  bool get activeMarkdownEnabled => preSessionMarkdownEnabled ?? true;

  SessionState copyWith({
    String? selectedWorkspacePath,
    String? preSessionModelId,
    String? preSessionReasoningEffort,
    String? preSessionSpeedMode,
    bool? preSessionMarkdownEnabled,
    List<AleraSession>? sessions,
    String? activeSessionId,
    List<CodexModelOption>? availableModels,
    List<TimelineCell>? timelineCells,
    String? activeStreamingAssistantCellId,
    bool clearActiveStreamingAssistantCellId = false,
    String? activeTurnId,
    bool clearActiveTurnId = false,
    List<String>? activityLog,
    AppServerConnectionState? connectionState,
    int? runningTurnCount,
    bool? isInterrupting,
    String? statusHeader,
    bool clearStatusHeader = false,
    bool? pendingStatusRestore,
    MarkdownStreamCollectorState? streamCollector,
    List<StreamQueuedLine>? streamQueue,
    AdaptiveChunkingPolicyState? chunkingPolicy,
    int? streamQueueDepth,
    int? streamOldestAgeMs,
    bool clearStreamOldestAgeMs = false,
    String? activeAgentStreamItemId,
    bool clearActiveAgentStreamItemId = false,
    String? activeAgentStreamTurnId,
    bool clearActiveAgentStreamTurnId = false,
    String? activeAgentStreamPhase,
    bool clearActiveAgentStreamPhase = false,
    int? activeAgentStreamLastDeltaAtMs,
    bool clearActiveAgentStreamLastDeltaAtMs = false,
    Map<String, String>? agentMessagePhaseByItemId,
    Map<String, String>? finalAnswerItemIdByTurn,
    String? activeExecCellId,
    bool clearActiveExecCellId = false,
    String? activePlanCellId,
    bool clearActivePlanCellId = false,
    bool? turnHadWorkActivity,
    Map<String, dynamic>? turnRuntimeMetrics,
    Map<String, String>? reasoningBufferByItemId,
    List<ComposerAttachment>? composerAttachments,
    List<ComposerDraftItem>? composerDraftItems,
    List<AleraCommand>? availableCommands,
    List<PendingMessage>? pendingMessages,
    String? editingPendingMessageId,
    bool clearEditingPendingMessageId = false,
    String? lastTurnDiff,
    bool clearLastTurnDiff = false,
    bool? planModeEnabled,
    PermissionMode? permissionMode,
    List<PendingApproval>? pendingApprovals,
    PendingUserInput? pendingUserInput,
    bool clearPendingUserInput = false,
    ContextUsage? contextUsage,
    List<CollabAgentEntry>? collabAgents,
    String? error,
    bool? isBusy,
    bool clearError = false,
    bool clearSelectedWorkspacePath = false,
    bool clearPreSessionModelId = false,
    bool clearPreSessionReasoningEffort = false,
    bool clearPreSessionSpeedMode = false,
    bool clearPreSessionMarkdownEnabled = false,
    bool clearActiveSessionId = false,
  }) {
    return SessionState(
      selectedWorkspacePath: clearSelectedWorkspacePath
          ? null
          : (selectedWorkspacePath ?? this.selectedWorkspacePath),
      preSessionModelId: clearPreSessionModelId
          ? null
          : (preSessionModelId ?? this.preSessionModelId),
      preSessionReasoningEffort: clearPreSessionReasoningEffort
          ? null
          : (preSessionReasoningEffort ?? this.preSessionReasoningEffort),
      preSessionSpeedMode: clearPreSessionSpeedMode
          ? null
          : (preSessionSpeedMode ?? this.preSessionSpeedMode),
      preSessionMarkdownEnabled: clearPreSessionMarkdownEnabled
          ? null
          : (preSessionMarkdownEnabled ?? this.preSessionMarkdownEnabled),
      sessions: sessions ?? this.sessions,
      activeSessionId: clearActiveSessionId
          ? null
          : (activeSessionId ?? this.activeSessionId),
      availableModels: availableModels ?? this.availableModels,
      timelineCells: timelineCells ?? this.timelineCells,
      activeStreamingAssistantCellId: clearActiveStreamingAssistantCellId
          ? null
          : (activeStreamingAssistantCellId ??
                this.activeStreamingAssistantCellId),
      activeTurnId: clearActiveTurnId
          ? null
          : (activeTurnId ?? this.activeTurnId),
      activityLog: activityLog ?? this.activityLog,
      connectionState: connectionState ?? this.connectionState,
      runningTurnCount: runningTurnCount ?? this.runningTurnCount,
      isInterrupting: isInterrupting ?? this.isInterrupting,
      statusHeader: clearStatusHeader
          ? null
          : (statusHeader ?? this.statusHeader),
      pendingStatusRestore: pendingStatusRestore ?? this.pendingStatusRestore,
      streamCollector: streamCollector ?? this.streamCollector,
      streamQueue: streamQueue ?? this.streamQueue,
      chunkingPolicy: chunkingPolicy ?? this.chunkingPolicy,
      streamQueueDepth: streamQueueDepth ?? this.streamQueueDepth,
      streamOldestAgeMs: clearStreamOldestAgeMs
          ? null
          : (streamOldestAgeMs ?? this.streamOldestAgeMs),
      activeAgentStreamItemId: clearActiveAgentStreamItemId
          ? null
          : (activeAgentStreamItemId ?? this.activeAgentStreamItemId),
      activeAgentStreamTurnId: clearActiveAgentStreamTurnId
          ? null
          : (activeAgentStreamTurnId ?? this.activeAgentStreamTurnId),
      activeAgentStreamPhase: clearActiveAgentStreamPhase
          ? null
          : (activeAgentStreamPhase ?? this.activeAgentStreamPhase),
      activeAgentStreamLastDeltaAtMs: clearActiveAgentStreamLastDeltaAtMs
          ? null
          : (activeAgentStreamLastDeltaAtMs ??
                this.activeAgentStreamLastDeltaAtMs),
      agentMessagePhaseByItemId:
          agentMessagePhaseByItemId ?? this.agentMessagePhaseByItemId,
      finalAnswerItemIdByTurn:
          finalAnswerItemIdByTurn ?? this.finalAnswerItemIdByTurn,
      activeExecCellId: clearActiveExecCellId
          ? null
          : (activeExecCellId ?? this.activeExecCellId),
      activePlanCellId: clearActivePlanCellId
          ? null
          : (activePlanCellId ?? this.activePlanCellId),
      turnHadWorkActivity: turnHadWorkActivity ?? this.turnHadWorkActivity,
      turnRuntimeMetrics: turnRuntimeMetrics ?? this.turnRuntimeMetrics,
      reasoningBufferByItemId:
          reasoningBufferByItemId ?? this.reasoningBufferByItemId,
      composerAttachments: composerAttachments ?? this.composerAttachments,
      composerDraftItems: composerDraftItems ?? this.composerDraftItems,
      availableCommands: availableCommands ?? this.availableCommands,
      pendingMessages: pendingMessages ?? this.pendingMessages,
      editingPendingMessageId: clearEditingPendingMessageId
          ? null
          : (editingPendingMessageId ?? this.editingPendingMessageId),
      lastTurnDiff: clearLastTurnDiff
          ? null
          : (lastTurnDiff ?? this.lastTurnDiff),
      planModeEnabled: planModeEnabled ?? this.planModeEnabled,
      permissionMode: permissionMode ?? this.permissionMode,
      pendingApprovals: pendingApprovals ?? this.pendingApprovals,
      pendingUserInput: clearPendingUserInput
          ? null
          : (pendingUserInput ?? this.pendingUserInput),
      contextUsage: contextUsage ?? this.contextUsage,
      collabAgents: collabAgents ?? this.collabAgents,
      error: clearError ? null : (error ?? this.error),
      isBusy: isBusy ?? this.isBusy,
    );
  }
}
