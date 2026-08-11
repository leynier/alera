part of 'codex_chat_controller.dart';

// These extensions are split from the notifier only to keep the source files small.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

extension CodexChatControllerSessions on CodexChatController {
  Future<CodexThreadPage> loadThreads({
    String? workspaceId,
    String? searchTerm,
    String? cursor,
  }) async {
    final response = await _host.listThreads(
      workspaceId: workspaceId,
      searchTerm: searchTerm,
      cursor: cursor,
    );
    return CodexThreadPage.fromJson(response);
  }

  Future<Map<String, Object?>> resumeThread(
    CodexThreadSummary thread, {
    String? cwd,
  }) async {
    _beginSessionTransition();
    try {
      final response = await _host.resumeThread(
        tabId,
        thread.id,
        cwd: cwd ?? thread.cwd,
      );
      if (!ref.mounted) return response;
      if (response['alreadyBound'] == true) {
        return response;
      }
      _sessionTransitionSucceeded = true;
      _threadId = _string(response['threadId']);
      _threadGeneration += 1;
      state = _applyConfiguration(
        state.copyWith(
          snapshot: CodexChatSnapshot.fromJson(response['snapshot']),
          activeCwd: _string(response['cwd']) ?? cwd ?? thread.cwd,
          historyNextCursor: _string(response['historyNextCursor']),
          recovery: response['recovery'] == null
              ? null
              : CodexThreadRecovery.fromJson(response['recovery']),
          error: null,
        ),
        response['configuration'],
      );
      await _loadCatalogues();
      return response;
    } catch (error) {
      if (ref.mounted) {
        state = state.copyWith(error: _safeError(error));
      }
      rethrow;
    } finally {
      _finishSessionTransition();
    }
  }

  Future<void> loadHistory({String? cursor}) async {
    if (_historyLoading || cursor == null || cursor.trim().isEmpty) return;
    _historyLoading = true;
    final requestedGeneration = _threadGeneration;
    try {
      final response = await _host.history(tabId, cursor: cursor);
      if (!ref.mounted || requestedGeneration != _threadGeneration) return;
      final page = CodexThreadHistoryPage.fromJson(response);
      state = state.copyWith(
        snapshot: _mergeHistory(state.snapshot, page.snapshot),
        activeCwd: _string(response['cwd']) ?? state.activeCwd,
        historyNextCursor: page.nextCursor,
        error: null,
      );
    } catch (error) {
      if (ref.mounted) state = state.copyWith(error: _safeError(error));
    } finally {
      _historyLoading = false;
    }
  }

  Future<bool> newThread() async => _runSessionCommand(_host.newThread);

  Future<bool> clearThread() async => _runSessionCommand(_host.clearThread);

  Future<bool> _runSessionCommand(
    Future<Map<String, Object?>> Function(String tabId) command,
  ) async {
    _beginSessionTransition();
    try {
      final response = await command(tabId);
      if (!ref.mounted) return false;
      _sessionTransitionSucceeded = true;
      _threadId = _string(response['threadId']);
      _threadGeneration += 1;
      state = _applyConfiguration(
        state.copyWith(
          snapshot: CodexChatSnapshot.fromJson(response['snapshot']),
          activeCwd: _string(response['cwd']) ?? state.activeCwd,
          historyNextCursor: null,
          recovery: null,
          error: null,
          sending: false,
          interrupting: false,
        ),
        response['configuration'],
      );
      await _loadCatalogues();
      return true;
    } catch (error) {
      if (ref.mounted) {
        state = state.copyWith(error: _safeError(error));
      }
      return false;
    } finally {
      _finishSessionTransition();
    }
  }

  void _beginSessionTransition() {
    final firstTransition = _sessionTransitionCount == 0;
    _sessionTransitionCount += 1;
    if (firstTransition) {
      _suspendedSessionQueue = state.queuedMessages;
      _sessionTransitionSucceeded = false;
      state = state.copyWith(queuedMessages: const <CodexQueuedMessage>[]);
    }
  }

  void _restoreSuspendedQueue() {
    state = state.copyWith(
      queuedMessages: <CodexQueuedMessage>[
        ..._suspendedSessionQueue,
        ...state.queuedMessages,
      ],
    );
  }

  void _finishSessionTransition() {
    if (_sessionTransitionCount > 0) _sessionTransitionCount -= 1;
    if (_sessionTransitionInProgress) return;
    if (!_sessionTransitionSucceeded &&
        ref.mounted &&
        _suspendedSessionQueue.isNotEmpty) {
      _restoreSuspendedQueue();
    }
    _suspendedSessionQueue = const <CodexQueuedMessage>[];
    _sessionTransitionSucceeded = false;
    _drainQueuedMessageIfIdle();
  }
}

CodexChatSnapshot _mergeHistory(
  CodexChatSnapshot current,
  CodexChatSnapshot page,
) {
  final currentEventKeys = <String>{
    for (final event in current.events) event.deduplicationKey,
  };
  final mergedEvents = <CodexTimelineEvent>[];
  final eventKeys = <String>{};
  for (final event in page.events) {
    if (currentEventKeys.contains(event.deduplicationKey)) continue;
    if (eventKeys.add(event.deduplicationKey)) mergedEvents.add(event);
  }
  for (final event in current.events) {
    if (eventKeys.add(event.deduplicationKey)) mergedEvents.add(event);
  }
  const eventLimit = 160;
  final boundedEvents = mergedEvents.length <= eventLimit
      ? mergedEvents
      : mergedEvents.sublist(mergedEvents.length - eventLimit);
  final currentSegments = current.timelineCells is CodexTimelineCells
      ? current.timelineCells as CodexTimelineCells
      : null;
  final cellKeys = <String>{for (final cell in page.timelineCells) cell.id};
  final mergedHistory = <CodexTimelineCell>[
    ...page.timelineCells,
    for (final cell in currentSegments?.history ?? const <CodexTimelineCell>[])
      if (cellKeys.add(cell.id)) cell,
  ];
  final mergedLive = <CodexTimelineCell>[
    for (final cell in currentSegments?.live ?? current.timelineCells)
      if (cellKeys.add(cell.id)) cell,
  ];
  final mergedCells = CodexTimelineCells.segmented(
    history: mergedHistory,
    live: mergedLive,
  );
  return CodexChatSnapshot(
    events: List<CodexTimelineEvent>.unmodifiable(boundedEvents),
    timelineCells: mergedCells,
    pendingRequests: current.pendingRequests,
    promptHistory: List<String>.unmodifiable(<String>[
      for (final cell in mergedCells)
        if (cell.kind == CodexTimelineKind.userMessage &&
            cell.metadata[CodexTimelineMetadata.isSteering] != true &&
            (cell.markdownText ?? '').trim().isNotEmpty)
          cell.markdownText!.trim(),
    ]),
    mcpInitializing: current.mcpInitializing,
    activeTurnId: current.activeTurnId,
    contextUsed: current.contextUsed,
    contextLimit: current.contextLimit,
    title: current.title ?? page.title,
  );
}

CodexChatSnapshot _mergeSameThreadSnapshot(
  CodexChatSnapshot current,
  CodexChatSnapshot incoming,
) {
  final currentSegments = current.timelineCells is CodexTimelineCells
      ? current.timelineCells as CodexTimelineCells
      : null;
  if (currentSegments == null || currentSegments.history.isEmpty) {
    return incoming;
  }
  final incomingLive = incoming.timelineCells is CodexTimelineCells
      ? (incoming.timelineCells as CodexTimelineCells).live
      : incoming.timelineCells;
  final incomingWithoutHistory = codexTimelineCellsWithoutClaimedMatches(
    incomingLive,
    currentSegments.history,
    replacedByExactHistory: currentSegments.historyContainsExactIdentity,
  );
  final currentWithoutHistory = codexTimelineCellsWithoutClaimedMatches(
    currentSegments.live,
    currentSegments.history,
    replacedByExactHistory: currentSegments.historyContainsExactIdentity,
  );
  final live = _boundedCodexLive(<CodexTimelineCell>[
    ...codexTimelineCellsWithoutClaimedMatches(
      currentWithoutHistory,
      incomingWithoutHistory,
    ),
    ...incomingWithoutHistory,
  ]);
  final mergedCells = currentSegments.withLive(live);
  return CodexChatSnapshot(
    events: incoming.events,
    timelineCells: mergedCells,
    pendingRequests: incoming.pendingRequests,
    promptHistory: currentSegments.promptHistoryWithLive(live),
    mcpInitializing: incoming.mcpInitializing,
    activeTurnId: incoming.activeTurnId,
    contextUsed: incoming.contextUsed,
    contextLimit: incoming.contextLimit,
    title: incoming.title,
  );
}

CodexChatSnapshot _reconcileSameThreadSnapshot(
  CodexChatSnapshot current,
  CodexChatSnapshot incoming,
  Map<dynamic, dynamic> delta,
) {
  final updated = current.applyDelta(delta);
  final segments = updated.timelineCells is CodexTimelineCells
      ? updated.timelineCells as CodexTimelineCells
      : null;
  final incomingLive = incoming.timelineCells is CodexTimelineCells
      ? (incoming.timelineCells as CodexTimelineCells).live
      : incoming.timelineCells;
  final history = segments?.history ?? const <CodexTimelineCell>[];
  final incomingWithoutHistory = codexTimelineCellsWithoutClaimedMatches(
    incomingLive,
    history,
    replacedByExactHistory: segments?.historyContainsExactIdentity,
  );
  final updatedWithoutHistory = codexTimelineCellsWithoutClaimedMatches(
    segments?.live ?? updated.timelineCells,
    history,
    replacedByExactHistory: segments?.historyContainsExactIdentity,
  );
  final currentLive = current.timelineCells is CodexTimelineCells
      ? (current.timelineCells as CodexTimelineCells).live
      : current.timelineCells;
  final currentLiveIds = <String>{for (final cell in currentLive) cell.id};
  final incomingIds = <String>{
    for (final cell in incomingWithoutHistory) cell.id,
  };
  final updatedWithoutDeltaArtifacts = <CodexTimelineCell>[
    for (final cell in updatedWithoutHistory)
      if (!(incomingIds.contains(cell.id) && !currentLiveIds.contains(cell.id)))
        cell,
  ];
  final boundedLive = _boundedCodexLive(<CodexTimelineCell>[
    ...codexTimelineCellsWithoutClaimedMatches(
      updatedWithoutDeltaArtifacts,
      incomingWithoutHistory,
    ),
    ...incomingWithoutHistory,
  ]);
  final mergedCells = segments == null
      ? boundedLive
      : segments.withLive(boundedLive);
  final mergedPromptHistory = segments == null
      ? List<String>.unmodifiable(<String>[
          for (final cell in boundedLive)
            if (cell.kind == CodexTimelineKind.userMessage &&
                cell.metadata[CodexTimelineMetadata.isSteering] != true &&
                (cell.markdownText ?? '').trim().isNotEmpty)
              cell.markdownText!.trim(),
        ])
      : segments.promptHistoryWithLive(boundedLive);
  return CodexChatSnapshot(
    events: updated.events,
    timelineCells: mergedCells,
    pendingRequests: incoming.pendingRequests,
    promptHistory: mergedPromptHistory,
    mcpInitializing: incoming.mcpInitializing,
    activeTurnId: incoming.activeTurnId,
    contextUsed: incoming.contextUsed,
    contextLimit: incoming.contextLimit,
    title: incoming.title,
  );
}

List<CodexTimelineCell> _boundedCodexLive(List<CodexTimelineCell> cells) {
  const retainedLiveLimit = 480;
  return List<CodexTimelineCell>.unmodifiable(
    cells.length <= retainedLiveLimit
        ? cells
        : cells.sublist(cells.length - retainedLiveLimit),
  );
}
