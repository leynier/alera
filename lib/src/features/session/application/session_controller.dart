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
import 'package:alera/src/features/session/domain/codex_model_catalog.dart';
import 'package:alera/src/features/session/domain/composer_attachment.dart';
import 'package:alera/src/features/session/domain/pending_approval.dart';
import 'package:alera/src/features/session/domain/pending_message.dart';
import 'package:alera/src/features/session/domain/pending_user_input.dart';
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
  Timer? _commitTickTimer;

  var _bootstrapped = false;
  static const String _localPlanFallbackQuestionId = 'implement_plan';
  static const String _localPlanFallbackPrompt = 'Implement this plan?';
  static const String _localPlanFallbackYesLabel = 'Yes, implement this plan';
  static const String _localPlanFallbackOtherLabel =
      'No, and tell Alera what to do differently';
  static const String _localPlanFallbackAutoInput = 'Implement plan';
  static const int _maxTrackedResolvedPlanTurns = 120;
  static const int _maxTrackedCompletedPlanTurns = 120;

  final Set<String> _planModeRequestedTurnIds = <String>{};
  final Set<String> _turnsWithPlanActivity = <String>{};
  final Set<String> _turnsWithUserInputRequest = <String>{};
  final Set<String> _turnsWithResolvedPlanDecision = <String>{};
  final Set<String> _completedTurnIds = <String>{};
  final List<String> _resolvedPlanTurnOrder = <String>[];
  final List<String> _completedTurnOrder = <String>[];
  final Map<String, String> _resolvedReasonByTurn = <String, String>{};

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
        isBusy: existing != null ? false : true,
        selectedWorkspacePath: normalized,
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

  void togglePlanMode() {
    state = state.copyWith(planModeEnabled: !state.planModeEnabled);
  }

  void togglePermissionMode() {
    final next = state.permissionMode == PermissionMode.defaultMode
        ? PermissionMode.fullAccess
        : PermissionMode.defaultMode;
    state = state.copyWith(permissionMode: next);
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
    state = state.copyWith(
      pendingMessages: state.pendingMessages
          .where((m) => m.id != id)
          .toList(growable: false),
    );
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
    if (state.runningTurnCount > 0 || state.isInterrupting) {
      final queued = PendingMessage(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        text: text,
        attachments: List<ComposerAttachment>.of(state.composerAttachments),
        planModeEnabled: state.planModeEnabled,
        forceDefaultCollaborationMode: false,
      );
      state = state.copyWith(
        pendingMessages: <PendingMessage>[...state.pendingMessages, queued],
        composerAttachments: const <ComposerAttachment>[],
      );
      return;
    }
    final attachments = List<ComposerAttachment>.of(state.composerAttachments);
    final planMode = state.planModeEnabled;
    state = state.copyWith(composerAttachments: const <ComposerAttachment>[]);
    await _executeInput(text, attachments, planMode);
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

  Future<void> _processNextQueuedMessage() async {
    if (state.pendingMessages.isEmpty) {
      return;
    }
    if (state.runningTurnCount > 0 || state.isInterrupting) {
      return;
    }
    final next = state.pendingMessages.first;
    final remaining = state.pendingMessages.skip(1).toList(growable: false);
    state = state.copyWith(pendingMessages: remaining);
    await _executeInput(
      next.text,
      next.attachments,
      next.planModeEnabled,
      forceDefaultCollaborationMode: next.forceDefaultCollaborationMode,
    );
  }

  Future<void> _executeInput(
    String text,
    List<ComposerAttachment> attachments,
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
      final extraInputItems = <Map<String, dynamic>>[
        ...await _buildAttachmentInputItems(attachments),
        ...mentionItems,
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
      await _sessionService.interruptActiveTurn(sessionId: session.id);
    } catch (error) {
      state = state.copyWith(
        isInterrupting: false,
        error: error.toString(),
        connectionState: AppServerConnectionState.error,
      );
    }
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

      _trackPlanActivityFromNotification(event);
      final reduced = reduceNotification(state, event);
      final ticked = reduceCommitTick(reduced);
      final runningTurnCount = _computeRunningTurnCount(
        current: ticked.runningTurnCount,
        method: event.method,
      );
      final shouldClearInterrupting =
          ticked.isInterrupting &&
          (event.method == 'turn/completed' || event.method == 'turn/failed');

      state = ticked.copyWith(
        sessions: _sessionService.sessions,
        runningTurnCount: runningTurnCount,
        isInterrupting: shouldClearInterrupting ? false : ticked.isInterrupting,
      );

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
      final next = reduceCommitTick(current);
      if (!_isCommitTickNoop(current, next)) {
        state = next;
      }
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
