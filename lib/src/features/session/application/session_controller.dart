import 'dart:async';
import 'dart:io';

import 'package:alera/src/features/projects/application/project_service.dart';
import 'package:alera/src/features/session/application/session_runtime_event.dart';
import 'package:alera/src/features/session/application/session_service.dart';
import 'package:alera/src/features/session/application/session_state.dart';
import 'package:alera/src/features/session/application/session_timeline_reducer.dart';
import 'package:alera/src/features/session/application/streaming/adaptive_chunking_policy.dart';
import 'package:alera/src/features/session/application/streaming/commit_tick_engine.dart';
import 'package:alera/src/features/session/application/streaming/markdown_stream_collector.dart';
import 'package:alera/src/features/session/domain/chat_timeline.dart';
import 'package:alera/src/features/session/domain/commands/alera_command.dart';
import 'package:alera/src/features/session/domain/commands/command_parser.dart';
import 'package:alera/src/features/session/domain/commands/command_registry.dart';
import 'package:alera/src/features/session/domain/commands/custom_command_expander.dart';
import 'package:alera/src/features/session/domain/codex_model_catalog.dart';
import 'package:alera/src/features/session/domain/composer_attachment.dart';
import 'package:alera/src/features/session/domain/composer_draft_item.dart';
import 'package:alera/src/features/session/domain/context_usage.dart';
import 'package:alera/src/features/session/domain/pending_approval.dart';
import 'package:alera/src/features/session/domain/pending_message.dart';
import 'package:alera/src/features/session/domain/pending_user_input.dart';
import 'package:alera/src/features/session/domain/review_preset_selection.dart';
import 'package:alera/src/features/settings/application/settings_service.dart';
import 'package:alera/src/shared/models/contracts.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:path/path.dart' as p;

class SessionController extends StateNotifier<SessionState> {
  SessionController({
    required SessionService sessionService,
    required ProjectService projectService,
    required SettingsService settingsService,
    DateTime Function()? now,
    Duration assistantStreamWarningGrace = const Duration(seconds: 5),
  }) : _sessionService = sessionService,
       _projectService = projectService,
       _settingsService = settingsService,
       _now = now ?? _defaultNow,
       _assistantStreamWarningGrace = assistantStreamWarningGrace,
       super(const SessionState()) {
    _eventsSub = _sessionService.events.listen(_onSessionEvent);
  }

  // Callback to get steer context from SteerController.
  String? Function()? getSteerContext;

  final SessionService _sessionService;
  final ProjectService _projectService;
  final SettingsService _settingsService;
  final DateTime Function() _now;
  final Duration _assistantStreamWarningGrace;
  final CommandRegistry _commandRegistry = const CommandRegistry();
  StreamSubscription<SessionRuntimeEvent>? _eventsSub;
  Timer? _commitTickTimer;
  Timer? _interruptSafetyTimer;

  var _bootstrapped = false;
  static const String _localPlanFallbackQuestionId = 'implement_plan';
  static const String _localPlanFallbackPrompt = 'Implement this plan?';
  static const String _localPlanFallbackYesLabel = 'Yes, implement this plan';
  static const String _localPlanFallbackOtherLabel =
      'No, and tell Alera what to do differently';
  static const String _localPlanFallbackAutoInput = 'Implement plan';
  static const int _maxTrackedResolvedPlanTurns = 120;
  static const int _maxTrackedCompletedPlanTurns = 120;

  static DateTime _defaultNow() => DateTime.now().toUtc();

  final Set<String> _planModeRequestedTurnIds = <String>{};
  final Set<String> _turnsWithPlanActivity = <String>{};
  final Set<String> _turnsWithUserInputRequest = <String>{};
  final Set<String> _turnsWithResolvedPlanDecision = <String>{};
  final Set<String> _completedTurnIds = <String>{};
  final List<String> _resolvedPlanTurnOrder = <String>[];
  final List<String> _completedTurnOrder = <String>[];
  final Map<String, String> _resolvedReasonByTurn = <String, String>{};
  final Map<String, _AssistantTerminalSignal> _assistantTerminalSignalsByTurn =
      <String, _AssistantTerminalSignal>{};
  final Set<String> _assistantStreamStallWarnings = <String>{};
  final Set<String> _assistantMissingTurnCompletionWarnings = <String>{};

  Future<void> bootstrap() async {
    if (_bootstrapped) {
      return;
    }

    final defaults = await _settingsService.load();
    final normalizedDefault = codexModelExists(defaults.selectedModel)
        ? defaults.selectedModel
        : codexDefaultModelId();
    final normalizedReasoningEffort = closestSupportedReasoningEffort(
      modelId: normalizedDefault,
      effort: defaults.selectedReasoningEffort,
    );

    if (normalizedDefault != defaults.selectedModel ||
        normalizedReasoningEffort != defaults.selectedReasoningEffort) {
      await _settingsService.save(
        SettingsSnapshot(
          selectedModel: normalizedDefault,
          selectedReasoningEffort: normalizedReasoningEffort,
          markdownEnabled: defaults.markdownEnabled,
        ),
      );
    }

    state = state.copyWith(
      sessions: _sessionService.sessions,
      connectionState: AppServerConnectionState.disconnected,
      availableModels: codexModelSnapshot,
      availableCommands: builtinAleraCommands(),
      preSessionModelId: normalizedDefault,
      preSessionReasoningEffort: normalizedReasoningEffort,
      preSessionMarkdownEnabled: defaults.markdownEnabled,
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
      _stopCommitTicker();
      _resetAssistantStreamTracking();
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
      final availableCommands = await _commandRegistry.loadForWorkspace(
        normalized,
      );
      state = state.copyWith(
        isBusy: existing != null ? false : true,
        selectedWorkspacePath: normalized,
        availableCommands: availableCommands,
        sessions: _sessionService.sessions,
        activeSessionId: existing?.id,
        timelineCells: const <TimelineCell>[],
        clearActiveStreamingAssistantCellId: true,
        clearActiveTurnId: true,
        clearError: true,
        activityLog: const <String>[],
        runningTurnCount: 0,
        isInterrupting: false,
        clearStatusHeader: true,
        pendingStatusRestore: false,
        streamCollector: const MarkdownStreamCollectorState(),
        streamQueue: const <StreamQueuedLine>[],
        chunkingPolicy: const AdaptiveChunkingPolicyState(),
        streamQueueDepth: 0,
        clearStreamOldestAgeMs: true,
        clearActiveAgentStreamItemId: true,
        clearActiveAgentStreamTurnId: true,
        clearActiveAgentStreamPhase: true,
        clearActiveAgentStreamLastDeltaAtMs: true,
        connectionState: AppServerConnectionState.starting,
        pendingApprovals: const <PendingApproval>[],
      );

      if (existing != null) {
        await activateSession(existing.id);
      } else {
        await _sessionService.ensureConnected();
        state = state.copyWith(
          isBusy: false,
          sessions: _sessionService.sessions,
          activeSessionId: null,
          connectionState: AppServerConnectionState.connected,
          isInterrupting: false,
        );
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

    _stopCommitTicker();
    _resetAssistantStreamTracking();
    state = state.copyWith(
      isBusy: true,
      clearError: true,
      connectionState: AppServerConnectionState.starting,
      availableCommands: await _commandRegistry.loadForWorkspace(
        target.workspacePath,
      ),
      activeSessionId: sessionId,
      selectedWorkspacePath: target.workspacePath,
      timelineCells: const <TimelineCell>[],
      clearActiveStreamingAssistantCellId: true,
      clearActiveTurnId: true,
      activityLog: const <String>[],
      runningTurnCount: 0,
      isInterrupting: false,
      clearStatusHeader: true,
      pendingStatusRestore: false,
      streamCollector: const MarkdownStreamCollectorState(),
      streamQueue: const <StreamQueuedLine>[],
      chunkingPolicy: const AdaptiveChunkingPolicyState(),
      streamQueueDepth: 0,
      clearStreamOldestAgeMs: true,
      clearActiveAgentStreamItemId: true,
      clearActiveAgentStreamTurnId: true,
      clearActiveAgentStreamPhase: true,
      clearActiveAgentStreamLastDeltaAtMs: true,
      pendingApprovals: const <PendingApproval>[],
    );

    try {
      await _sessionService.setActiveSession(sessionId);
      state = state.copyWith(
        isBusy: false,
        sessions: _sessionService.sessions,
        activeSessionId: sessionId,
        selectedWorkspacePath: target.workspacePath,
        preSessionModelId: target.model,
        preSessionReasoningEffort: closestSupportedReasoningEffort(
          modelId: target.model,
          effort: state.activeReasoningEffort,
        ),
        connectionState: AppServerConnectionState.connected,
        isInterrupting: false,
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
    _stopCommitTicker();
    _resetAssistantStreamTracking();
    state = state.copyWith(
      isBusy: true,
      clearError: true,
      connectionState: AppServerConnectionState.starting,
      timelineCells: const <TimelineCell>[],
      clearActiveStreamingAssistantCellId: true,
      clearActiveTurnId: true,
      activityLog: const <String>[],
      runningTurnCount: 0,
      isInterrupting: false,
      clearStatusHeader: true,
      pendingStatusRestore: false,
      streamCollector: const MarkdownStreamCollectorState(),
      streamQueue: const <StreamQueuedLine>[],
      chunkingPolicy: const AdaptiveChunkingPolicyState(),
      streamQueueDepth: 0,
      clearStreamOldestAgeMs: true,
      clearActiveAgentStreamItemId: true,
      clearActiveAgentStreamTurnId: true,
      clearActiveAgentStreamPhase: true,
      clearActiveAgentStreamLastDeltaAtMs: true,
    );
    try {
      final session = await _sessionService.createSession(request);
      final adjustedReasoningEffort = closestSupportedReasoningEffort(
        modelId: session.model,
        effort: state.activeReasoningEffort,
      );
      state = state.copyWith(
        isBusy: false,
        sessions: _sessionService.sessions,
        selectedWorkspacePath: session.workspacePath,
        activeSessionId: session.id,
        preSessionModelId: session.model,
        preSessionReasoningEffort: adjustedReasoningEffort,
        connectionState: AppServerConnectionState.connected,
        isInterrupting: false,
      );

      await _settingsService.save(
        SettingsSnapshot(
          selectedModel: session.model,
          selectedReasoningEffort: adjustedReasoningEffort,
          markdownEnabled: state.activeMarkdownEnabled,
        ),
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
    final adjustedReasoningEffort = closestSupportedReasoningEffort(
      modelId: modelId,
      effort: state.activeReasoningEffort,
    );
    final session = state.activeSession;
    if (session == null) {
      state = state.copyWith(
        preSessionModelId: modelId,
        preSessionReasoningEffort: adjustedReasoningEffort,
        clearError: true,
      );
      await _settingsService.save(
        SettingsSnapshot(
          selectedModel: modelId,
          selectedReasoningEffort: adjustedReasoningEffort,
          markdownEnabled: state.activeMarkdownEnabled,
        ),
      );
      return;
    }

    try {
      await _sessionService.updateSessionModel(
        sessionId: session.id,
        modelId: modelId,
      );
      await _settingsService.save(
        SettingsSnapshot(
          selectedModel: modelId,
          selectedReasoningEffort: adjustedReasoningEffort,
          markdownEnabled: state.activeMarkdownEnabled,
        ),
      );
      state = state.copyWith(
        sessions: _sessionService.sessions,
        preSessionModelId: modelId,
        preSessionReasoningEffort: adjustedReasoningEffort,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(error: error.toString());
    }
  }

  Future<void> updateReasoningEffort(String effortId) async {
    if (!codexReasoningEffortExists(effortId)) {
      return;
    }
    final modelId = state.activeModelId;
    final adjusted = closestSupportedReasoningEffort(
      modelId: modelId,
      effort: effortId,
    );
    try {
      state = state.copyWith(
        preSessionReasoningEffort: adjusted,
        clearError: true,
      );
      await _settingsService.save(
        SettingsSnapshot(
          selectedModel: modelId,
          selectedReasoningEffort: adjusted,
          markdownEnabled: state.activeMarkdownEnabled,
        ),
      );
    } catch (error) {
      state = state.copyWith(error: error.toString());
    }
  }

  Future<void> updateMarkdownEnabled(bool enabled) async {
    try {
      state = state.copyWith(
        preSessionMarkdownEnabled: enabled,
        clearError: true,
      );
      await _settingsService.save(
        SettingsSnapshot(
          selectedModel: state.activeModelId,
          selectedReasoningEffort: state.activeReasoningEffort,
          markdownEnabled: enabled,
        ),
      );
    } catch (error) {
      state = state.copyWith(error: error.toString());
    }
  }

  void addAttachment(ComposerAttachment attachment) {
    state = state.copyWith(
      composerAttachments: <ComposerAttachment>[
        ...state.composerAttachments,
        attachment,
      ],
    );
  }

  void removeAttachment(String id) {
    state = state.copyWith(
      composerAttachments: state.composerAttachments
          .where((a) => a.id != id)
          .toList(growable: false),
    );
  }

  void clearAttachments() {
    state = state.copyWith(composerAttachments: const <ComposerAttachment>[]);
  }

  void addComposerDraftItem(ComposerDraftItem item) {
    state = state.copyWith(
      composerDraftItems: <ComposerDraftItem>[
        ...state.composerDraftItems.where((candidate) {
          return candidate.kind != item.kind ||
              candidate.path != item.path ||
              candidate.name != item.name;
        }),
        item,
      ],
    );
  }

  void removeComposerDraftItem(String id) {
    state = state.copyWith(
      composerDraftItems: state.composerDraftItems
          .where((item) => item.id != id)
          .toList(growable: false),
    );
  }

  void clearComposerDraftItems() {
    state = state.copyWith(composerDraftItems: const <ComposerDraftItem>[]);
  }

  void togglePlanMode() {
    state = state.copyWith(planModeEnabled: !state.planModeEnabled);
  }

  void togglePermissionMode() {
    final next = state.permissionMode == PermissionMode.defaultMode
        ? PermissionMode.fullAccess
        : PermissionMode.defaultMode;
    state = state.copyWith(permissionMode: next);
  }

  void setPermissionMode(PermissionMode mode) {
    state = state.copyWith(permissionMode: mode);
  }

  Future<List<CodexSkillMetadata>> listAvailableSkills() async {
    final workspacePath = state.selectedWorkspacePath;
    if (workspacePath == null || workspacePath.isEmpty) {
      return const <CodexSkillMetadata>[];
    }
    final entries = await _sessionService.listSkills(
      cwds: <String>[workspacePath],
    );
    final skills = <CodexSkillMetadata>[];
    for (final entry in entries) {
      skills.addAll(entry.skills.where((skill) => skill.enabled));
    }
    return skills;
  }

  Future<List<CodexAppInfo>> listAvailableApps() async {
    final page = await _sessionService.listApps(
      sessionId: state.activeSessionId,
      limit: 50,
    );
    return page.data
        .where((app) => app.isAccessible && app.isEnabled)
        .toList(growable: false);
  }

  Future<List<String>> listReviewBranches() async {
    final workspacePath = state.selectedWorkspacePath;
    if (workspacePath == null || workspacePath.isEmpty) {
      return const <String>[];
    }
    return _projectService.listGitBranches(workspacePath);
  }

  Future<void> startReviewFromPreset(
    ReviewPresetSelection preset, {
    String? value,
  }) async {
    switch (preset) {
      case ReviewPresetSelection.uncommittedChanges:
        await _startReviewWithTarget(
          const CodexReviewUncommittedChangesTarget(),
        );
        return;
      case ReviewPresetSelection.baseBranch:
        final branch = value?.trim();
        if (branch == null || branch.isEmpty) {
          return;
        }
        await _startReviewWithTarget(
          CodexReviewBaseBranchTarget(branch: branch),
        );
        return;
      case ReviewPresetSelection.commit:
        final sha = value?.trim();
        if (sha == null || sha.isEmpty) {
          return;
        }
        await _startReviewWithTarget(CodexReviewCommitTarget(sha: sha));
        return;
      case ReviewPresetSelection.customInstructions:
        final instructions = value?.trim();
        if (instructions == null || instructions.isEmpty) {
          return;
        }
        await _startReviewWithTarget(
          CodexReviewCustomTarget(instructions: instructions),
        );
        return;
    }
  }

  Future<void> approveRequest(
    Object requestId, {
    bool forSession = false,
  }) async {
    try {
      await _sessionService.approveRequest(requestId, forSession: forSession);
      // Only dismiss after the RPC succeeds so the card stays visible on failure.
      state = state.copyWith(
        pendingApprovals: state.pendingApprovals
            .where((a) => a.requestId != requestId)
            .toList(growable: false),
      );
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> declineRequest(Object requestId) async {
    try {
      await _sessionService.declineRequest(requestId);
      state = state.copyWith(
        pendingApprovals: state.pendingApprovals
            .where((a) => a.requestId != requestId)
            .toList(growable: false),
      );
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> submitUserInput(Map<String, dynamic> answers) async {
    final pending = state.pendingUserInput;
    if (pending == null) {
      return;
    }
    final pendingTurnId = _normalizeOptionalId(
      pending.localPlanTurnId ?? pending.turnId,
    );
    if (pending.source == PendingUserInputSource.localPlanFallback) {
      final decision = _extractLocalPlanFallbackDecision(answers);
      _appendRuntimeLog(
        'runtime/userInput submit '
        'source=${pending.source.name} '
        'turnId=${pendingTurnId ?? "<null>"} '
        'answersCount=${decision.answersCount} '
        'accepted=${decision.isValid}',
      );
      if (!decision.isValid) {
        _appendRuntimeLog(
          'runtime/userInput submitIgnored empty '
          'source=${pending.source.name} '
          'turnId=${pendingTurnId ?? "<null>"}',
        );
        return;
      }
      state = state.copyWith(clearPendingUserInput: true);
      if (pendingTurnId != null) {
        final reason = decision.accepted
            ? 'local_submit_yes'
            : 'local_submit_refine';
        _rememberResolvedPlanDecision(pendingTurnId, reason: reason);
        _appendRuntimeLog(
          'runtime/userInput resolved '
          'source=${pending.source.name} '
          'action=submit '
          'turnId=$pendingTurnId',
        );
      }
      await _applyLocalPlanFallbackDecision(
        turnId: pendingTurnId,
        decision: decision,
      );
      return;
    }
    final answersCount = _countProvidedUserInputAnswers(answers);
    final accepted = answersCount > 0;
    _appendRuntimeLog(
      'runtime/userInput submit '
      'source=${pending.source.name} '
      'turnId=${pendingTurnId ?? "<null>"} '
      'answersCount=$answersCount '
      'accepted=$accepted',
    );
    if (!accepted) {
      _appendRuntimeLog(
        'runtime/userInput submitIgnored empty '
        'source=${pending.source.name} '
        'turnId=${pendingTurnId ?? "<null>"}',
      );
      return;
    }
    try {
      await _sessionService.respondUserInput(pending.requestId, answers);
      if (pendingTurnId != null) {
        _rememberResolvedPlanDecision(pendingTurnId, reason: 'backend_submit');
        _appendRuntimeLog(
          'runtime/userInput resolved '
          'source=${pending.source.name} '
          'action=submit '
          'turnId=$pendingTurnId',
        );
      }
      state = state.copyWith(clearPendingUserInput: true);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  void dismissUserInput() {
    final pending = state.pendingUserInput;
    if (pending == null) {
      return;
    }
    final pendingTurnId = _normalizeOptionalId(
      pending.localPlanTurnId ?? pending.turnId,
    );
    state = state.copyWith(clearPendingUserInput: true);
    if (pending.source == PendingUserInputSource.localPlanFallback) {
      if (pendingTurnId != null) {
        _rememberResolvedPlanDecision(pendingTurnId, reason: 'local_dismiss');
        _appendRuntimeLog(
          'runtime/userInput resolved '
          'source=${pending.source.name} '
          'action=dismiss '
          'turnId=$pendingTurnId',
        );
      }
      _appendRuntimeLog(
        'runtime/planFallback dismissed '
        'turnId=${pendingTurnId ?? "<null>"}',
      );
      return;
    }
    if (pendingTurnId != null) {
      _rememberResolvedPlanDecision(pendingTurnId, reason: 'backend_dismiss');
      _appendRuntimeLog(
        'runtime/userInput resolved '
        'source=${pending.source.name} '
        'action=dismiss '
        'turnId=$pendingTurnId',
      );
    }
    unawaited(
      _sessionService.respondUserInput(
        pending.requestId,
        const <String, dynamic>{},
      ),
    );
  }

  void removeFromQueue(String id) {
    final wasEditing = state.editingPendingMessageId == id;
    state = state.copyWith(
      pendingMessages: state.pendingMessages
          .where((m) => m.id != id)
          .toList(growable: false),
      clearEditingPendingMessageId: wasEditing,
    );
    // If we were editing this message and it's now deleted, process the queue.
    if (wasEditing) {
      unawaited(_processNextQueuedMessage());
    }
  }

  Future<void> steerQueuedMessage(String messageId) async {
    final message = state.pendingMessages.firstWhere(
      (m) => m.id == messageId,
      orElse: () => throw StateError('queued message not found: $messageId'),
    );
    final activeTurnId = state.activeTurnId;
    final activeSessionId = state.activeSessionId;
    if (activeTurnId == null || activeSessionId == null) {
      return;
    }

    // Remove from queue.
    state = state.copyWith(
      pendingMessages: state.pendingMessages
          .where((m) => m.id != messageId)
          .toList(growable: false),
    );

    // Append optimistic user message with steering metadata.
    final now = DateTime.now().toUtc();
    final cell = TimelineCell(
      id: 'user-steer-${now.microsecondsSinceEpoch}',
      kind: TimelineCellKind.userMessage,
      status: TimelineCellStatus.inProgress,
      createdAt: now,
      updatedAt: now,
      markdownText: message.text,
      metadata: const <String, dynamic>{
        TimelineCellMetadata.isSteeringKey: true,
      },
    );
    state = state.copyWith(
      timelineCells: <TimelineCell>[...state.timelineCells, cell],
    );

    // Build extra input items (attachments + steer rules).
    final attachmentItems = await _buildAttachmentInputItems(
      message.attachments,
    );
    final steerItems = _buildSteerInputItems();
    final extraItems = <Map<String, dynamic>>[
      ...attachmentItems,
      ...steerItems,
    ];

    try {
      final returnedTurnId = await _sessionService
          .steerActiveTurn(
            sessionId: activeSessionId,
            rawInput: message.text,
            expectedTurnId: activeTurnId,
            extraInputItems: extraItems,
          )
          .timeout(const Duration(seconds: 15));
      // Mark the steering cell as completed and assign it to the turn.
      _updateTimelineCell(
        cell.id,
        (c) => c.copyWith(
          status: TimelineCellStatus.completed,
          turnId: returnedTurnId,
          updatedAt: DateTime.now().toUtc(),
        ),
      );
    } catch (e) {
      // Update the steering cell to failed status.
      _updateTimelineCell(
        cell.id,
        (c) => c.copyWith(status: TimelineCellStatus.failed),
      );
      state = state.copyWith(error: e.toString());
    }
  }

  void _updateTimelineCell(
    String cellId,
    TimelineCell Function(TimelineCell) transform,
  ) {
    final cells = <TimelineCell>[...state.timelineCells];
    final idx = cells.findIndexById(cellId);
    if (idx != -1) {
      cells[idx] = transform(cells[idx]);
      state = state.copyWith(timelineCells: cells);
    }
  }

  void startEditingPendingMessage(String id) {
    state = state.copyWith(editingPendingMessageId: id);
  }

  void finishEditingPendingMessage() {
    state = state.copyWith(clearEditingPendingMessageId: true);
    // Trigger queue processing in case messages were waiting.
    unawaited(_processNextQueuedMessage());
  }

  void updatePendingMessage(
    String id,
    String text,
    List<ComposerAttachment> attachments,
  ) {
    final updated = state.pendingMessages
        .map((m) {
          if (m.id == id) {
            return m.copyWith(text: text, attachments: attachments);
          }
          return m;
        })
        .toList(growable: false);
    state = state.copyWith(pendingMessages: updated);
  }

  Future<void> sendInput(String rawInput) async {
    final workspacePath = state.selectedWorkspacePath;
    if (workspacePath == null || workspacePath.isEmpty) {
      return;
    }
    final text = rawInput.trim();
    if (text.isEmpty) {
      return;
    }
    final parsedSlash = parseSlashCommand(text);
    final resolvedCommand = parsedSlash == null
        ? null
        : _commandRegistry.findExact(state.availableCommands, parsedSlash.name);
    if (resolvedCommand != null) {
      await _dispatchResolvedCommand(
        resolvedCommand,
        parsedSlash!,
        workspacePath: workspacePath,
      );
      return;
    }
    if (state.runningTurnCount > 0 || state.isInterrupting) {
      final queued = PendingMessage(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        text: text,
        attachments: List<ComposerAttachment>.of(state.composerAttachments),
        draftItems: List<ComposerDraftItem>.of(state.composerDraftItems),
        planModeEnabled: state.planModeEnabled,
        forceDefaultCollaborationMode: false,
      );
      state = state.copyWith(
        pendingMessages: <PendingMessage>[...state.pendingMessages, queued],
        composerAttachments: const <ComposerAttachment>[],
        composerDraftItems: const <ComposerDraftItem>[],
      );
      return;
    }
    final attachments = List<ComposerAttachment>.of(state.composerAttachments);
    final draftItems = List<ComposerDraftItem>.of(state.composerDraftItems);
    final planMode = state.planModeEnabled;
    state = state.copyWith(
      composerAttachments: const <ComposerAttachment>[],
      composerDraftItems: const <ComposerDraftItem>[],
    );
    await _executeInput(text, attachments, draftItems, planMode);
  }

  Future<void> _dispatchResolvedCommand(
    AleraCommand command,
    ParsedSlashCommand parsed, {
    required String workspacePath,
  }) async {
    if (command.isCustom) {
      final expanded = expandCustomCommand(command, parsed.rawArgs);
      final resolvedText = _mergeExpandedCommandText(
        expanded.text,
        parsed.remainingText,
      );
      if (resolvedText.isEmpty) {
        return;
      }
      await _sendResolvedInput(
        resolvedText,
        planModeEnabled: state.planModeEnabled,
      );
      return;
    }
    switch (command.builtinId) {
      case BuiltinCommandId.newChat:
      case BuiltinCommandId.clear:
        _startNewChat();
      case BuiltinCommandId.compact:
        await compactContext();
      case BuiltinCommandId.review:
        await _runReviewCommand(parsed);
      case BuiltinCommandId.plan:
        await _runPlanCommand(parsed);
      case BuiltinCommandId.rename:
        await _runRenameCommand(parsed);
      case BuiltinCommandId.status:
        return;
      case BuiltinCommandId.model:
      case BuiltinCommandId.permissions:
      case BuiltinCommandId.mention:
      case BuiltinCommandId.skills:
      case BuiltinCommandId.apps:
        _appendSystemNotice(
          title: 'Command handled in the composer',
          message: 'Run /${command.name} from the composer UI action path.',
        );
      case null:
        return;
    }
  }

  Future<void> _sendResolvedInput(
    String text, {
    required bool planModeEnabled,
    bool forceDefaultCollaborationMode = false,
  }) async {
    if (state.runningTurnCount > 0 || state.isInterrupting) {
      final queued = PendingMessage(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        text: text,
        attachments: List<ComposerAttachment>.of(state.composerAttachments),
        draftItems: List<ComposerDraftItem>.of(state.composerDraftItems),
        planModeEnabled: planModeEnabled,
        forceDefaultCollaborationMode: forceDefaultCollaborationMode,
      );
      state = state.copyWith(
        pendingMessages: <PendingMessage>[...state.pendingMessages, queued],
        composerAttachments: const <ComposerAttachment>[],
        composerDraftItems: const <ComposerDraftItem>[],
      );
      return;
    }
    final attachments = List<ComposerAttachment>.of(state.composerAttachments);
    final draftItems = List<ComposerDraftItem>.of(state.composerDraftItems);
    state = state.copyWith(
      composerAttachments: const <ComposerAttachment>[],
      composerDraftItems: const <ComposerDraftItem>[],
    );
    await _executeInput(
      text,
      attachments,
      draftItems,
      planModeEnabled,
      forceDefaultCollaborationMode: forceDefaultCollaborationMode,
    );
  }

  void _startNewChat() {
    _stopCommitTicker();
    _resetAssistantStreamTracking();
    state = state.copyWith(
      clearActiveSessionId: true,
      timelineCells: const <TimelineCell>[],
      clearActiveStreamingAssistantCellId: true,
      clearActiveTurnId: true,
      activityLog: const <String>[],
      runningTurnCount: 0,
      isInterrupting: false,
      clearStatusHeader: true,
      pendingStatusRestore: false,
      streamCollector: const MarkdownStreamCollectorState(),
      streamQueue: const <StreamQueuedLine>[],
      chunkingPolicy: const AdaptiveChunkingPolicyState(),
      streamQueueDepth: 0,
      clearStreamOldestAgeMs: true,
      clearActiveAgentStreamItemId: true,
      clearActiveAgentStreamTurnId: true,
      clearActiveAgentStreamPhase: true,
      clearActiveAgentStreamLastDeltaAtMs: true,
      pendingApprovals: const <PendingApproval>[],
      clearPendingUserInput: true,
      composerAttachments: const <ComposerAttachment>[],
      composerDraftItems: const <ComposerDraftItem>[],
      pendingMessages: const <PendingMessage>[],
      contextUsage: ContextUsage.empty,
      clearError: true,
    );
  }

  Future<void> _runReviewCommand(ParsedSlashCommand parsed) async {
    await _startReviewWithTarget(
      parsed.hasArgs
          ? CodexReviewCustomTarget(instructions: parsed.rawArgs)
          : const CodexReviewUncommittedChangesTarget(),
    );
  }

  Future<void> _runPlanCommand(ParsedSlashCommand parsed) async {
    state = state.copyWith(planModeEnabled: true);
    if (!parsed.hasArgs) {
      _appendSystemNotice(
        title: 'Plan mode enabled',
        message: 'Your next message will run in plan mode.',
      );
      return;
    }
    await _sendResolvedInput(parsed.rawArgs, planModeEnabled: true);
  }

  Future<void> _runRenameCommand(ParsedSlashCommand parsed) async {
    final session = state.activeSession;
    if (session == null) {
      _appendSystemNotice(
        title: 'Rename unavailable',
        message: 'Start a chat before renaming the current thread.',
      );
      return;
    }
    final nextName = parsed.rawArgs.trim();
    if (nextName.isEmpty) {
      _appendSystemNotice(
        title: 'Rename usage',
        message: 'Use /rename <name>.',
      );
      return;
    }
    try {
      await _sessionService.renameSessionThread(
        sessionId: session.id,
        name: nextName,
      );
      state = state.copyWith(sessions: _sessionService.sessions);
      _appendSystemNotice(
        title: 'Thread renamed',
        message: 'Thread renamed to $nextName.',
      );
    } catch (error) {
      state = state.copyWith(error: error.toString());
    }
  }

  Future<AleraSession?> _ensureActiveSessionForCommand(
    String fallbackPrompt,
  ) async {
    final current = state.activeSession;
    if (current != null) {
      return current;
    }
    final workspacePath = state.selectedWorkspacePath;
    if (workspacePath == null || workspacePath.isEmpty) {
      return null;
    }
    final model = state.activeModelId;
    final reasoningEffort = state.activeReasoningEffort;
    final created = await _sessionService.createSession(
      SessionCreateRequest(
        projectPath: workspacePath,
        firstPrompt: fallbackPrompt,
        model: model,
      ),
    );
    await _settingsService.save(
      SettingsSnapshot(
        selectedModel: model,
        selectedReasoningEffort: reasoningEffort,
        markdownEnabled: state.activeMarkdownEnabled,
      ),
    );
    state = state.copyWith(
      sessions: _sessionService.sessions,
      activeSessionId: created.id,
      preSessionModelId: model,
      preSessionReasoningEffort: reasoningEffort,
      connectionState: AppServerConnectionState.connected,
      isInterrupting: false,
      clearError: true,
    );
    return created;
  }

  String _mergeExpandedCommandText(String expandedText, String remainingText) {
    final normalizedExpanded = expandedText.trim();
    final normalizedRemaining = remainingText.trim();
    if (normalizedExpanded.isEmpty) {
      return normalizedRemaining;
    }
    if (normalizedRemaining.isEmpty) {
      return normalizedExpanded;
    }
    return '$normalizedExpanded\n\n$normalizedRemaining';
  }

  Future<void> _startReviewWithTarget(CodexReviewTarget target) async {
    final session = await _ensureActiveSessionForCommand('/review');
    if (session == null) {
      return;
    }
    try {
      await _sessionService.startReview(sessionId: session.id, target: target);
    } catch (error) {
      state = state.copyWith(error: error.toString());
    }
  }

  void _appendSystemNotice({required String title, required String message}) {
    final timestamp = DateTime.now().toUtc();
    final cell = TimelineCell(
      id: 'system-${timestamp.microsecondsSinceEpoch}',
      kind: TimelineCellKind.systemNotice,
      status: TimelineCellStatus.info,
      createdAt: timestamp,
      updatedAt: timestamp,
      title: title,
      markdownText: message,
      metadata: const <String, dynamic>{
        TimelineCellMetadata.uiPlacementKey: TimelineCellMetadata.outsideWorked,
      },
    );
    state = state.copyWith(
      timelineCells: <TimelineCell>[...state.timelineCells, cell],
    );
  }

  Future<void> implementPlanFromChatAction() async {
    final workspacePath = state.selectedWorkspacePath;
    if (workspacePath == null || workspacePath.isEmpty) {
      return;
    }
    state = state.copyWith(
      planModeEnabled: false,
      composerAttachments: const <ComposerAttachment>[],
    );
    if (state.runningTurnCount > 0 || state.isInterrupting) {
      final queued = PendingMessage(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        text: _localPlanFallbackAutoInput,
        attachments: const <ComposerAttachment>[],
        draftItems: const <ComposerDraftItem>[],
        planModeEnabled: false,
        forceDefaultCollaborationMode: true,
      );
      state = state.copyWith(
        pendingMessages: <PendingMessage>[...state.pendingMessages, queued],
      );
      return;
    }
    await _executeInput(
      _localPlanFallbackAutoInput,
      const <ComposerAttachment>[],
      const <ComposerDraftItem>[],
      false,
      forceDefaultCollaborationMode: true,
    );
  }

  Future<List<Map<String, dynamic>>> _buildAttachmentInputItems(
    List<ComposerAttachment> attachments,
  ) async {
    if (attachments.isEmpty) {
      return const <Map<String, dynamic>>[];
    }
    final items = <Map<String, dynamic>>[];
    for (final att in attachments) {
      final file = File(att.path);
      if (!file.existsSync()) {
        continue;
      }
      if (att.kind == AttachmentKind.image) {
        // Use Codex app-server v2 native localImage type — avoids base64
        // encoding large images in-memory.
        items.add(<String, dynamic>{'type': 'localImage', 'path': att.path});
      } else {
        // Non-image files: instruct the model to use the Read tool.
        // This safely handles binary files (PDFs, DOCX, etc.) without
        // attempting to decode them as UTF-8.
        items.add(<String, dynamic>{
          'type': 'text',
          'text': '[File: ${att.path} - Use the Read tool to view this file]',
        });
      }
    }
    return items;
  }

  // Build steer context input items from active steer rules.
  List<Map<String, dynamic>> _buildSteerInputItems() {
    final steerContext = getSteerContext?.call();
    if (steerContext == null || steerContext.isEmpty) {
      return const <Map<String, dynamic>>[];
    }
    return <Map<String, dynamic>>[
      <String, dynamic>{
        'type': 'text',
        'text': '[Steering instructions: $steerContext]',
      },
    ];
  }

  Future<void> _processNextQueuedMessage() async {
    if (state.pendingMessages.isEmpty) {
      return;
    }
    if (state.runningTurnCount > 0 || state.isInterrupting) {
      return;
    }
    final next = state.pendingMessages.first;
    // Check if message is being edited - wait for edit to complete.
    if (state.editingPendingMessageId == next.id) {
      return;
    }
    final remaining = state.pendingMessages.skip(1).toList(growable: false);
    state = state.copyWith(pendingMessages: remaining);
    await _executeInput(
      next.text,
      next.attachments,
      next.draftItems,
      next.planModeEnabled,
      forceDefaultCollaborationMode: next.forceDefaultCollaborationMode,
    );
  }

  Future<void> _executeInput(
    String text,
    List<ComposerAttachment> attachments,
    List<ComposerDraftItem> draftItems,
    bool planModeEnabled, {
    bool forceDefaultCollaborationMode = false,
  }) async {
    final workspacePath = state.selectedWorkspacePath;
    if (workspacePath == null || workspacePath.isEmpty) {
      return;
    }
    state = appendOptimisticUserMessage(
      state,
      text: text,
      attachments: attachments,
      draftItems: draftItems,
    ).copyWith(isBusy: true, clearError: true);
    try {
      var session = state.activeSession;
      if (session == null) {
        final model = state.activeModelId;
        final reasoningEffort = state.activeReasoningEffort;
        final created = await _sessionService.createSession(
          SessionCreateRequest(
            projectPath: workspacePath,
            firstPrompt: text,
            model: model,
          ),
        );
        await _settingsService.save(
          SettingsSnapshot(
            selectedModel: model,
            selectedReasoningEffort: reasoningEffort,
            markdownEnabled: state.activeMarkdownEnabled,
          ),
        );
        state = state.copyWith(
          sessions: _sessionService.sessions,
          selectedWorkspacePath: created.workspacePath,
          activeSessionId: created.id,
          preSessionModelId: model,
          preSessionReasoningEffort: reasoningEffort,
          connectionState: AppServerConnectionState.connected,
          isInterrupting: false,
          clearError: true,
        );
        session = created;
      }
      final mentionItems = await _buildMentionInputItems(text, workspacePath);
      final steerItems = _buildSteerInputItems();
      final extraInputItems = <Map<String, dynamic>>[
        ...await _buildAttachmentInputItems(attachments),
        ..._buildDraftItemInputItems(draftItems),
        ...mentionItems,
        ...steerItems,
      ];
      final approvalPolicy = state.permissionMode == PermissionMode.fullAccess
          ? 'never'
          : 'untrusted';
      await _sessionService.runInput(
        sessionId: session.id,
        rawInput: text,
        reasoningEffort: state.activeReasoningEffort,
        extraInputItems: extraInputItems,
        planModeEnabled: planModeEnabled,
        forceDefaultCollaborationMode: forceDefaultCollaborationMode,
        approvalPolicy: approvalPolicy,
      );
      AleraSession? updatedSession;
      for (final candidate in _sessionService.sessions) {
        if (candidate.id == session.id) {
          updatedSession = candidate;
          break;
        }
      }
      final startedTurnId = _normalizeOptionalId(updatedSession?.lastTurnId);
      if (startedTurnId != null) {
        _trackTurnStart(startedTurnId, planModeEnabled: planModeEnabled);
        if (planModeEnabled && _completedTurnIds.contains(startedTurnId)) {
          final didShowFallback = _maybeShowLocalPlanFallback(
            startedTurnId,
            isLateArm: true,
          );
          if (!didShowFallback) {
            _appendRuntimeLog(
              'runtime/planFallback late-arm not shown '
              'turnId=$startedTurnId',
            );
            _forgetInFlightPlanTracking(startedTurnId);
          }
        }
      }
      state = state.copyWith(
        isBusy: false,
        sessions: _sessionService.sessions,
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

  Future<List<Map<String, dynamic>>> _buildMentionInputItems(
    String text,
    String workspacePath,
  ) async {
    final matches = RegExp(r'@(\S+)').allMatches(text);
    if (matches.isEmpty) {
      return const <Map<String, dynamic>>[];
    }
    final canonicalRoot = p.canonicalize(workspacePath);
    final items = <Map<String, dynamic>>[];
    for (final match in matches) {
      final rel = match.group(1)!;
      final fullPath = p.canonicalize(p.join(workspacePath, rel));
      // Reject paths that resolve outside the workspace root.
      if (!fullPath.startsWith('$canonicalRoot${p.separator}') &&
          fullPath != canonicalRoot) {
        continue;
      }
      final file = File(fullPath);
      if (!file.existsSync()) {
        continue;
      }
      final content = await file.readAsString();
      items.add(<String, dynamic>{
        'type': 'text',
        'text': '--- File: $fullPath ---\n$content',
      });
    }
    return items;
  }

  List<Map<String, dynamic>> _buildDraftItemInputItems(
    List<ComposerDraftItem> draftItems,
  ) {
    if (draftItems.isEmpty) {
      return const <Map<String, dynamic>>[];
    }
    return draftItems
        .map((item) {
          switch (item.kind) {
            case ComposerDraftItemKind.skill:
              return <String, dynamic>{
                'type': 'skill',
                'name': item.name,
                'path': item.path,
              };
            case ComposerDraftItemKind.mention:
              return <String, dynamic>{
                'type': 'mention',
                'name': item.name,
                'path': item.path,
              };
          }
        })
        .toList(growable: false);
  }

  Future<void> interruptActiveTurn() async {
    final session = state.activeSession;
    if (session == null) {
      return;
    }
    if (state.runningTurnCount <= 0 || state.isInterrupting) {
      return;
    }

    state = state.copyWith(isInterrupting: true, clearError: true);
    try {
      await _sessionService.interruptActiveTurn(
        sessionId: session.id,
        turnIdOverride: state.activeTurnId,
      );
      _scheduleInterruptSafetyTimeout();
    } catch (error) {
      state = state.copyWith(
        isInterrupting: false,
        error: error.toString(),
        connectionState: AppServerConnectionState.error,
      );
    }
  }

  void _scheduleInterruptSafetyTimeout() {
    _interruptSafetyTimer?.cancel();
    _interruptSafetyTimer = Timer(const Duration(seconds: 10), () {
      if (state.isInterrupting) {
        state = state.copyWith(isInterrupting: false);
      }
    });
  }

  /// Requests manual context compaction for the active session.
  Future<void> compactContext() async {
    final session = state.activeSession;
    if (session == null) {
      return;
    }
    if (state.contextUsage.isCompacting) {
      return;
    }
    state = state.copyWith(
      contextUsage: state.contextUsage.copyWith(isCompacting: true),
      clearError: true,
    );
    try {
      await _sessionService.compactContext(sessionId: session.id);
    } catch (error) {
      state = state.copyWith(
        contextUsage: state.contextUsage.copyWith(isCompacting: false),
        error: error.toString(),
      );
    }
  }

  Future<SettingsSnapshot> loadSettingsDefaults() {
    return _settingsService.load();
  }

  @override
  void dispose() {
    _stopCommitTicker();
    _interruptSafetyTimer?.cancel();
    unawaited(_eventsSub?.cancel());
    super.dispose();
  }

  void _onSessionEvent(SessionRuntimeEvent event) {
    if (event is SessionApprovalRequestEvent) {
      if (!_matchesApprovalRequestSession(event)) {
        return;
      }
      if (state.permissionMode == PermissionMode.fullAccess) {
        unawaited(
          _sessionService.approveRequest(event.requestId, forSession: true),
        );
      } else {
        final approval = PendingApproval(
          requestId: event.requestId,
          method: event.method,
          description: event.description,
        );
        state = state.copyWith(
          pendingApprovals: <PendingApproval>[
            ...state.pendingApprovals,
            approval,
          ],
        );
      }
      return;
    }
    if (event is SessionUserInputRequestEvent) {
      final requestThreadId = _normalizeOptionalId(event.threadId);
      final requestTurnId = _normalizeOptionalId(event.turnId);
      _appendRuntimeLog(
        'runtime/requestUserInput received '
        'threadId=${requestThreadId ?? "<null>"} '
        'turnId=${requestTurnId ?? "<null>"} '
        'itemId=${event.itemId} '
        'questions=${event.questions.length}',
      );
      if (requestTurnId != null &&
          _shouldIgnoreLatePlanRequest(requestTurnId)) {
        _appendRuntimeLog(
          'runtime/planFallback ignored late backend request '
          'turnId=$requestTurnId',
        );
        _autoRespondToEmptyUserInput(event.requestId);
        return;
      }
      if (!_matchesUserInputRequestSession(event)) {
        _appendRuntimeLog(
          'runtime/requestUserInput dropped '
          '(session mismatch) '
          'threadId=${requestThreadId ?? "<null>"} '
          'turnId=${requestTurnId ?? "<null>"}',
        );
        return;
      }
      final parsedQuestions = _parseUserInputQuestions(event.questions);
      _appendRuntimeLog(
        'runtime/requestUserInput parsed '
        'turnId=${requestTurnId ?? "<null>"} '
        'rawQuestions=${event.questions.length} '
        'validQuestions=${parsedQuestions.questions.length} '
        'usedAliases=${parsedQuestions.usedAliases}',
      );
      if (parsedQuestions.questions.isEmpty) {
        _appendRuntimeLog(
          'runtime/requestUserInput invalid -> auto-answered '
          'turnId=${requestTurnId ?? "<null>"} '
          'itemId=${event.itemId}',
        );
        _autoRespondToEmptyUserInput(event.requestId);
        return;
      }
      if (requestTurnId != null) {
        _turnsWithUserInputRequest.add(requestTurnId);
      }
      _appendRuntimeLog(
        'runtime/requestUserInput valid -> backend UI '
        'turnId=${requestTurnId ?? "<null>"}',
      );
      state = state.copyWith(
        pendingUserInput: PendingUserInput(
          requestId: event.requestId,
          threadId: event.threadId,
          turnId: event.turnId,
          itemId: event.itemId,
          questions: parsedQuestions.questions,
          source: PendingUserInputSource.backend,
        ),
      );
      return;
    }
    if (event is SessionNotificationEvent) {
      final active = state.activeSession;
      if (active != null && !_notificationMatchesSession(event, active)) {
        return;
      }

      final eventNow = _now();
      _trackPlanActivityFromNotification(event);
      final reduced = reduceNotification(state, event, now: eventNow);
      final ticked = reduceCommitTick(reduced, now: eventNow);
      final runningTurnCount = _computeRunningTurnCount(
        current: ticked.runningTurnCount,
        method: event.method,
      );
      final shouldClearInterrupting =
          ticked.isInterrupting &&
          (event.method == 'turn/completed' || event.method == 'turn/failed');
      if (shouldClearInterrupting) {
        _interruptSafetyTimer?.cancel();
        _interruptSafetyTimer = null;
      }

      state = ticked.copyWith(
        sessions: _sessionService.sessions,
        runningTurnCount: runningTurnCount,
        isInterrupting: shouldClearInterrupting ? false : ticked.isInterrupting,
      );
      _trackAssistantTerminalSignal(event, at: eventNow);

      final completedTurnId = _extractCompletedTurnId(event);
      if (completedTurnId != null) {
        _rememberCompletedTurn(completedTurnId);
        final wasRequested = _planModeRequestedTurnIds.contains(
          completedTurnId,
        );
        final didShowFallback = _maybeShowLocalPlanFallback(completedTurnId);
        if (!didShowFallback) {
          final shouldKeepForLateArm =
              !wasRequested && _turnsWithPlanActivity.contains(completedTurnId);
          if (shouldKeepForLateArm) {
            _appendRuntimeLog(
              'runtime/planFallback awaiting late arm '
              'turnId=$completedTurnId',
            );
          } else {
            _forgetInFlightPlanTracking(completedTurnId);
          }
        }
      }

      _maybeLogAssistantStreamWarnings(at: eventNow);
      _updateCommitTicker();
      if (runningTurnCount == 0 &&
          (event.method == 'turn/completed' || event.method == 'turn/failed') &&
          state.pendingUserInput == null) {
        unawaited(_processNextQueuedMessage());
      }
    }
  }

  Future<void> _applyLocalPlanFallbackDecision({
    required String? turnId,
    required _LocalPlanFallbackDecision decision,
  }) async {
    if (decision.accepted) {
      _appendRuntimeLog(
        'runtime/planFallback yes -> auto send "$_localPlanFallbackAutoInput" '
        'turnId=${turnId ?? "<null>"}',
      );
      state = state.copyWith(planModeEnabled: false);
      await _executeInput(
        _localPlanFallbackAutoInput,
        const <ComposerAttachment>[],
        const <ComposerDraftItem>[],
        false,
      );
      return;
    }
    _appendRuntimeLog(
      'runtime/planFallback no -> refine in plan mode '
      'turnId=${turnId ?? "<null>"}',
    );
    state = state.copyWith(planModeEnabled: true);
    await _executeInput(
      decision.refinement!,
      const <ComposerAttachment>[],
      const <ComposerDraftItem>[],
      true,
    );
  }

  void _autoRespondToEmptyUserInput(Object requestId) {
    unawaited(() async {
      try {
        await _sessionService.respondUserInput(
          requestId,
          const <String, dynamic>{},
        );
      } catch (error) {
        state = state.copyWith(error: error.toString());
      }
    }());
  }

  String? _normalizeOptionalId(String? value) {
    final raw = value?.trim();
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return raw;
  }

  _ParsedUserInputQuestions _parseUserInputQuestions(
    List<Map<String, dynamic>> rawQuestions,
  ) {
    var usedAliases = false;
    final questions = <UserInputQuestion>[];
    for (final rawQuestion in rawQuestions) {
      final id = _pickStringValue(
        source: rawQuestion,
        canonicalKey: 'id',
        aliasKeys: const <String>['questionId'],
        onAliasUsed: () => usedAliases = true,
      );
      final question = _pickStringValue(
        source: rawQuestion,
        canonicalKey: 'question',
        aliasKeys: const <String>['prompt', 'text'],
        onAliasUsed: () => usedAliases = true,
      );
      if (id == null || question == null) {
        continue;
      }
      final header =
          _pickStringValue(
            source: rawQuestion,
            canonicalKey: 'header',
            aliasKeys: const <String>['title'],
            onAliasUsed: () => usedAliases = true,
          ) ??
          '';
      final otherLabel = _pickStringValue(
        source: rawQuestion,
        canonicalKey: 'otherLabel',
        aliasKeys: const <String>['other_label'],
        onAliasUsed: () => usedAliases = true,
      );
      final rawOptions = _pickListValue(
        source: rawQuestion,
        canonicalKey: 'options',
        aliasKeys: const <String>['choices'],
        onAliasUsed: () => usedAliases = true,
      );
      List<UserInputOption>? options;
      if (rawOptions != null) {
        final parsedOptions = <UserInputOption>[];
        for (final rawOption in rawOptions) {
          if (rawOption is! Map) {
            continue;
          }
          final label = _pickStringValue(
            source: rawOption,
            canonicalKey: 'label',
            aliasKeys: const <String>['value', 'title'],
            onAliasUsed: () => usedAliases = true,
          );
          if (label == null) {
            continue;
          }
          final description =
              _pickStringValue(
                source: rawOption,
                canonicalKey: 'description',
                aliasKeys: const <String>['hint'],
                onAliasUsed: () => usedAliases = true,
              ) ??
              '';
          parsedOptions.add(
            UserInputOption(label: label, description: description),
          );
        }
        if (parsedOptions.isNotEmpty) {
          options = parsedOptions;
        }
      }
      questions.add(
        UserInputQuestion(
          id: id,
          header: header,
          question: question,
          isOther: rawQuestion['isOther'] == true,
          isSecret: rawQuestion['isSecret'] == true,
          options: options,
          otherLabel: otherLabel,
        ),
      );
    }
    return _ParsedUserInputQuestions(
      questions: questions,
      usedAliases: usedAliases,
    );
  }

  String? _pickStringValue({
    required Map<dynamic, dynamic> source,
    required String canonicalKey,
    List<String> aliasKeys = const <String>[],
    required void Function() onAliasUsed,
  }) {
    final canonical = _normalizeOptionalId(source[canonicalKey]?.toString());
    if (canonical != null) {
      return canonical;
    }
    for (final alias in aliasKeys) {
      final candidate = _normalizeOptionalId(source[alias]?.toString());
      if (candidate != null) {
        onAliasUsed();
        return candidate;
      }
    }
    return null;
  }

  List<dynamic>? _pickListValue({
    required Map<dynamic, dynamic> source,
    required String canonicalKey,
    List<String> aliasKeys = const <String>[],
    required void Function() onAliasUsed,
  }) {
    final canonical = source[canonicalKey];
    if (canonical is List) {
      return canonical;
    }
    for (final alias in aliasKeys) {
      final candidate = source[alias];
      if (candidate is List) {
        onAliasUsed();
        return candidate;
      }
    }
    return null;
  }

  List<String> _extractUserInputAnswers(
    Map<String, dynamic> answers,
    String questionId,
  ) {
    final raw = answers[questionId];
    if (raw is! Map) {
      return const <String>[];
    }
    final rawAnswers = raw['answers'];
    if (rawAnswers is! List) {
      return const <String>[];
    }
    return rawAnswers
        .map((value) => value.toString().trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }

  _LocalPlanFallbackDecision _extractLocalPlanFallbackDecision(
    Map<String, dynamic> answers,
  ) {
    final chosenAnswers = _extractUserInputAnswers(
      answers,
      _localPlanFallbackQuestionId,
    );
    final accepted = chosenAnswers.any((a) => a == _localPlanFallbackYesLabel);
    String? refinement;
    if (!accepted) {
      for (final answer in chosenAnswers) {
        if (answer != _localPlanFallbackYesLabel) {
          refinement = answer;
          break;
        }
      }
    }
    return _LocalPlanFallbackDecision(
      accepted: accepted,
      refinement: refinement,
      answersCount: chosenAnswers.length,
    );
  }

  int _countProvidedUserInputAnswers(Map<String, dynamic> answers) {
    var count = 0;
    for (final rawQuestionAnswer in answers.values) {
      if (rawQuestionAnswer is! Map) {
        continue;
      }
      final rawAnswers = rawQuestionAnswer['answers'];
      if (rawAnswers is! List) {
        continue;
      }
      for (final rawAnswer in rawAnswers) {
        if (_normalizeOptionalId(rawAnswer?.toString()) != null) {
          count += 1;
        }
      }
    }
    return count;
  }

  void _trackTurnStart(String turnId, {required bool planModeEnabled}) {
    if (!planModeEnabled) {
      _planModeRequestedTurnIds.remove(turnId);
      _turnsWithPlanActivity.remove(turnId);
      _turnsWithUserInputRequest.remove(turnId);
      return;
    }
    final isNewTurn = _planModeRequestedTurnIds.add(turnId);
    _turnsWithResolvedPlanDecision.remove(turnId);
    _resolvedPlanTurnOrder.remove(turnId);
    _resolvedReasonByTurn.remove(turnId);
    if (isNewTurn) {
      _appendRuntimeLog('runtime/planFallback armed turnId=$turnId');
    }
  }

  bool _shouldIgnoreLatePlanRequest(String turnId) {
    if (_turnsWithResolvedPlanDecision.contains(turnId)) {
      return true;
    }
    final pending = state.pendingUserInput;
    if (pending == null ||
        pending.source != PendingUserInputSource.localPlanFallback) {
      return false;
    }
    final pendingTurnId = _normalizeOptionalId(
      pending.localPlanTurnId ?? pending.turnId,
    );
    return pendingTurnId == turnId;
  }

  void _trackPlanActivityFromNotification(SessionNotificationEvent event) {
    final params = event.payload['params'];
    if (params is! Map<String, dynamic>) {
      return;
    }
    if (event.method == 'item/plan/delta') {
      final turnId = _normalizeOptionalId(params['turnId']?.toString());
      if (turnId != null) {
        _turnsWithPlanActivity.add(turnId);
      }
      return;
    }
    if (event.method == 'codex/event/plan_delta') {
      final msg = params['msg'];
      if (msg is! Map<String, dynamic>) {
        return;
      }
      final turnId = _normalizeOptionalId(msg['turn_id']?.toString());
      if (turnId != null) {
        _turnsWithPlanActivity.add(turnId);
      }
      return;
    }
    if (event.method == 'item/completed') {
      final item = params['item'];
      if (item is! Map<String, dynamic>) {
        return;
      }
      if (!_isPlanItemType(item['type'])) {
        return;
      }
      final turnId = _normalizeOptionalId(params['turnId']?.toString());
      if (turnId != null) {
        _turnsWithPlanActivity.add(turnId);
      }
      return;
    }
    if (event.method == 'codex/event/item_completed') {
      final msg = params['msg'];
      if (msg is! Map<String, dynamic>) {
        return;
      }
      final item = msg['item'];
      if (item is! Map<String, dynamic>) {
        return;
      }
      if (!_isPlanItemType(item['type'])) {
        return;
      }
      final turnId = _normalizeOptionalId(msg['turn_id']?.toString());
      if (turnId != null) {
        _turnsWithPlanActivity.add(turnId);
      }
    }
  }

  bool _isPlanItemType(Object? rawType) {
    final type = rawType?.toString().trim().toLowerCase();
    return type == 'plan';
  }

  String? _extractCompletedTurnId(SessionNotificationEvent event) {
    if (event.method != 'turn/completed' && event.method != 'turn/failed') {
      return null;
    }
    final params = event.payload['params'];
    if (params is! Map<String, dynamic>) {
      return null;
    }
    final turn = params['turn'];
    if (turn is! Map<String, dynamic>) {
      return null;
    }
    return _normalizeOptionalId(turn['id']?.toString());
  }

  bool _maybeShowLocalPlanFallback(String turnId, {bool isLateArm = false}) {
    final requested = _planModeRequestedTurnIds.contains(turnId);
    final completed = _completedTurnIds.contains(turnId);
    final hasPlanActivity = _turnsWithPlanActivity.contains(turnId);
    final hasBackendRequest = _turnsWithUserInputRequest.contains(turnId);
    final pending = state.pendingUserInput;
    final pendingTurnId = _normalizeOptionalId(
      pending?.localPlanTurnId ?? pending?.turnId,
    );
    final pendingForTurn = pendingTurnId != null && pendingTurnId == turnId;
    final pendingBackendForTurn =
        pendingForTurn && pending?.source == PendingUserInputSource.backend;
    final pendingLocalFallbackForTurn =
        pendingForTurn &&
        pending?.source == PendingUserInputSource.localPlanFallback;
    final resolved = _turnsWithResolvedPlanDecision.contains(turnId);
    final resolvedReason = _resolvedReasonByTurn[turnId] ?? '<none>';
    final planModeOn = state.planModeEnabled;
    _appendRuntimeLog(
      'runtime/planFallback gate '
      'turnId=$turnId '
      'requested=$requested '
      'completed=$completed '
      'hasPlanActivity=$hasPlanActivity '
      'hasBackendRequest=$hasBackendRequest '
      'pending=${pending != null} '
      'pendingForTurn=$pendingForTurn '
      'pendingBackendForTurn=$pendingBackendForTurn '
      'resolved=$resolved '
      'resolvedReason=$resolvedReason '
      'planModeOn=$planModeOn '
      'late=$isLateArm',
    );
    if (pendingBackendForTurn || pendingLocalFallbackForTurn) {
      return false;
    }
    if (!requested) {
      return false;
    }
    if (!completed) {
      return false;
    }
    if (!hasPlanActivity) {
      return false;
    }
    if (resolved) {
      return false;
    }
    if (isLateArm && !planModeOn) {
      return false;
    }
    if (hasBackendRequest && !pendingForTurn) {
      _appendRuntimeLog(
        'runtime/planFallback backendRequestWithoutPending turnId=$turnId',
      );
    }
    final threadId = _normalizeOptionalId(state.activeSession?.threadId);
    state = state.copyWith(
      pendingUserInput: PendingUserInput(
        requestId: 'local-plan-fallback-$turnId',
        threadId: threadId,
        turnId: turnId,
        itemId: '$turnId-local-plan-fallback',
        questions: const <UserInputQuestion>[
          UserInputQuestion(
            id: _localPlanFallbackQuestionId,
            header: 'Implementation',
            question: _localPlanFallbackPrompt,
            isOther: true,
            options: <UserInputOption>[
              UserInputOption(
                label: _localPlanFallbackYesLabel,
                description: 'Proceed with implementation',
              ),
            ],
            otherLabel: _localPlanFallbackOtherLabel,
          ),
        ],
        source: PendingUserInputSource.localPlanFallback,
        localPlanTurnId: turnId,
      ),
    );
    _appendRuntimeLog('runtime/planFallback shown turnId=$turnId');
    return true;
  }

  void _rememberCompletedTurn(String turnId) {
    _completedTurnIds.remove(turnId);
    _completedTurnOrder.remove(turnId);
    _completedTurnIds.add(turnId);
    _completedTurnOrder.add(turnId);
    while (_completedTurnOrder.length > _maxTrackedCompletedPlanTurns) {
      final oldest = _completedTurnOrder.removeAt(0);
      _completedTurnIds.remove(oldest);
    }
  }

  void _forgetInFlightPlanTracking(String turnId) {
    _planModeRequestedTurnIds.remove(turnId);
    _turnsWithPlanActivity.remove(turnId);
    _turnsWithUserInputRequest.remove(turnId);
  }

  void _rememberResolvedPlanDecision(String turnId, {required String reason}) {
    _turnsWithResolvedPlanDecision.remove(turnId);
    _resolvedPlanTurnOrder.remove(turnId);
    _turnsWithResolvedPlanDecision.add(turnId);
    _resolvedPlanTurnOrder.add(turnId);
    _resolvedReasonByTurn[turnId] = reason;
    while (_resolvedPlanTurnOrder.length > _maxTrackedResolvedPlanTurns) {
      final oldest = _resolvedPlanTurnOrder.removeAt(0);
      _turnsWithResolvedPlanDecision.remove(oldest);
      _resolvedReasonByTurn.remove(oldest);
    }
  }

  bool _matchesApprovalRequestSession(SessionApprovalRequestEvent event) {
    final eventThreadId = _normalizeOptionalId(event.threadId);
    final activeThreadId = _normalizeOptionalId(state.activeSession?.threadId);
    if (eventThreadId == null || activeThreadId == null) {
      return true;
    }
    return eventThreadId == activeThreadId;
  }

  bool _matchesUserInputRequestSession(SessionUserInputRequestEvent event) {
    final activeSession = state.activeSession;
    if (activeSession == null) {
      return true;
    }

    final eventThreadId = _normalizeOptionalId(event.threadId);
    final activeThreadId = _normalizeOptionalId(activeSession.threadId);
    if (eventThreadId != null) {
      if (activeThreadId == null) {
        return true;
      }
      return eventThreadId == activeThreadId;
    }

    final eventTurnId = _normalizeOptionalId(event.turnId);
    if (eventTurnId != null) {
      final activeTurnId = _normalizeOptionalId(activeSession.lastTurnId);
      if (activeTurnId == null) {
        return true;
      }
      return eventTurnId == activeTurnId;
    }

    return true;
  }

  void _trackAssistantTerminalSignal(
    SessionNotificationEvent event, {
    required DateTime at,
  }) {
    final params = event.payload['params'];
    if (params is! Map<String, dynamic>) {
      return;
    }

    switch (event.method) {
      case 'turn/started':
      case 'turn/completed':
      case 'turn/failed':
        final turn = params['turn'];
        if (turn is! Map<String, dynamic>) {
          return;
        }
        final turnId = _normalizeOptionalId(turn['id']?.toString());
        if (turnId != null) {
          _clearAssistantStreamTracking(turnId);
        }
        return;
      case 'codex/event/item_completed':
        final msg = params['msg'];
        if (msg is! Map<String, dynamic>) {
          return;
        }
        final item = msg['item'];
        if (item is! Map<String, dynamic>) {
          return;
        }
        final itemType = item['type']?.toString().trim().toLowerCase();
        if (itemType != 'agentmessage' && itemType != 'agent_message') {
          return;
        }
        final turnId = _normalizeOptionalId(msg['turn_id']?.toString());
        if (turnId == null) {
          return;
        }
        final itemId = _normalizeOptionalId(item['id']?.toString());
        final explicitPhase = _normalizeAssistantPhase(
          item['phase']?.toString(),
        );
        final phase = explicitPhase != 'unknown'
            ? explicitPhase
            : (itemId != null &&
                  state.finalAnswerItemIdByTurn[turnId] == itemId)
            ? 'final_answer'
            : (state.activeAgentStreamTurnId == turnId &&
                  state.activeAgentStreamItemId == itemId)
            ? _normalizeAssistantPhase(state.activeAgentStreamPhase)
            : 'unknown';
        if (phase != 'final_answer') {
          return;
        }
        _assistantTerminalSignalsByTurn[turnId] = _AssistantTerminalSignal(
          itemId: itemId,
          phase: phase,
          source: 'legacy_item_completed',
          atMs: at.millisecondsSinceEpoch,
        );
        _assistantMissingTurnCompletionWarnings.remove(turnId);
        return;
      case 'codex/event/task_complete':
        final msg = params['msg'];
        if (msg is! Map<String, dynamic>) {
          return;
        }
        final turnId = _normalizeOptionalId(msg['turn_id']?.toString());
        if (turnId == null) {
          return;
        }
        final itemId =
            _normalizeOptionalId(state.finalAnswerItemIdByTurn[turnId]) ??
            (state.activeAgentStreamTurnId == turnId
                ? _normalizeOptionalId(state.activeAgentStreamItemId)
                : null);
        _assistantTerminalSignalsByTurn[turnId] = _AssistantTerminalSignal(
          itemId: itemId,
          phase: 'final_answer',
          source: 'task_complete',
          atMs: at.millisecondsSinceEpoch,
        );
        _assistantMissingTurnCompletionWarnings.remove(turnId);
        return;
    }
  }

  void _maybeLogAssistantStreamWarnings({required DateTime at}) {
    _maybeLogFinalAnswerStreamStall(at: at);
    _maybeLogMissingTurnCompletionAfterTerminalSignal(at: at);
  }

  void _maybeLogFinalAnswerStreamStall({required DateTime at}) {
    final turnId = _normalizeOptionalId(state.activeAgentStreamTurnId);
    final itemId = _normalizeOptionalId(state.activeAgentStreamItemId);
    final phase = _normalizeAssistantPhase(state.activeAgentStreamPhase);
    final lastDeltaAtMs = state.activeAgentStreamLastDeltaAtMs;
    if (turnId == null ||
        itemId == null ||
        phase != 'final_answer' ||
        lastDeltaAtMs == null) {
      return;
    }

    final idleMs = at.millisecondsSinceEpoch - lastDeltaAtMs;
    if (idleMs < _assistantStreamWarningGrace.inMilliseconds) {
      return;
    }
    if (_assistantTerminalSignalsByTurn.containsKey(turnId)) {
      return;
    }

    final warningKey = '$turnId:$itemId';
    if (_assistantStreamStallWarnings.contains(warningKey)) {
      return;
    }
    _assistantStreamStallWarnings.add(warningKey);
    _appendRuntimeLog(
      'runtime/assistantStream stalled '
      'turnId=$turnId '
      'itemId=$itemId '
      'phase=$phase '
      'signal=none '
      'idleMs=$idleMs',
    );
  }

  void _maybeLogMissingTurnCompletionAfterTerminalSignal({
    required DateTime at,
  }) {
    for (final entry in _assistantTerminalSignalsByTurn.entries.toList()) {
      final turnId = entry.key;
      if (_completedTurnIds.contains(turnId) ||
          _assistantMissingTurnCompletionWarnings.contains(turnId)) {
        continue;
      }

      final idleMs = at.millisecondsSinceEpoch - entry.value.atMs;
      if (idleMs < _assistantStreamWarningGrace.inMilliseconds) {
        continue;
      }

      _assistantMissingTurnCompletionWarnings.add(turnId);
      _appendRuntimeLog(
        'runtime/assistantStream missingTurnCompletion '
        'turnId=$turnId '
        'itemId=${entry.value.itemId ?? "<null>"} '
        'phase=${entry.value.phase} '
        'signal=${entry.value.source} '
        'idleMs=$idleMs',
      );
    }
  }

  void _clearAssistantStreamTracking(String turnId) {
    _assistantTerminalSignalsByTurn.remove(turnId);
    _assistantMissingTurnCompletionWarnings.remove(turnId);
    _assistantStreamStallWarnings.removeWhere(
      (warningKey) => warningKey.startsWith('$turnId:'),
    );
  }

  void _resetAssistantStreamTracking() {
    _assistantTerminalSignalsByTurn.clear();
    _assistantStreamStallWarnings.clear();
    _assistantMissingTurnCompletionWarnings.clear();
  }

  String _normalizeAssistantPhase(String? raw) {
    final normalized = raw?.trim().toLowerCase();
    if (normalized == 'finalanswer') {
      return 'final_answer';
    }
    if (normalized == 'final_answer' || normalized == 'commentary') {
      return normalized!;
    }
    return 'unknown';
  }

  void _appendRuntimeLog(String message) {
    final nextLog = <String>[...state.activityLog, message];
    final clipped = nextLog.length <= 200
        ? nextLog
        : nextLog.sublist(nextLog.length - 200);
    state = state.copyWith(activityLog: clipped);
  }

  void _updateCommitTicker() {
    final shouldRun =
        state.runningTurnCount > 0 || state.streamQueue.isNotEmpty;
    if (!shouldRun) {
      _stopCommitTicker();
      return;
    }

    _commitTickTimer ??= Timer.periodic(const Duration(milliseconds: 80), (_) {
      final current = state;
      final tickNow = _now();
      final next = reduceCommitTick(current, now: tickNow);
      if (!_isCommitTickNoop(current, next)) {
        state = next;
      }
      _maybeLogAssistantStreamWarnings(at: tickNow);
      if (next.runningTurnCount <= 0 && next.streamQueue.isEmpty) {
        _stopCommitTicker();
      }
    });
  }

  void _stopCommitTicker() {
    _commitTickTimer?.cancel();
    _commitTickTimer = null;
  }

  bool _isCommitTickNoop(SessionState current, SessionState next) {
    return current.streamQueueDepth == next.streamQueueDepth &&
        identical(current.timelineCells, next.timelineCells) &&
        current.streamOldestAgeMs == next.streamOldestAgeMs &&
        current.chunkingPolicy.mode == next.chunkingPolicy.mode &&
        current.streamCollector.pendingBuffer ==
            next.streamCollector.pendingBuffer &&
        current.streamCollector.pendingSince ==
            next.streamCollector.pendingSince &&
        current.statusHeader == next.statusHeader &&
        current.pendingStatusRestore == next.pendingStatusRestore;
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

class _AssistantTerminalSignal {
  const _AssistantTerminalSignal({
    required this.itemId,
    required this.phase,
    required this.source,
    required this.atMs,
  });

  final String? itemId;
  final String phase;
  final String source;
  final int atMs;
}

class _ParsedUserInputQuestions {
  const _ParsedUserInputQuestions({
    required this.questions,
    required this.usedAliases,
  });

  final List<UserInputQuestion> questions;
  final bool usedAliases;
}

class _LocalPlanFallbackDecision {
  const _LocalPlanFallbackDecision({
    required this.accepted,
    required this.refinement,
    required this.answersCount,
  });

  final bool accepted;
  final String? refinement;
  final int answersCount;

  bool get isValid =>
      accepted || (refinement != null && refinement!.isNotEmpty);
}
