part of 'mobile_codex_controller.dart';

// These extensions are split from the notifier only to keep the source files small.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

extension MobileCodexControllerSessions on MobileCodexController {
  Future<MobileCodexThreadPage> loadThreads({
    String? workspaceId,
    String? searchTerm,
    String? cursor,
  }) async {
    final client = _client;
    if (client == null) return const MobileCodexThreadPage();
    final response = await client.codexRequest(
      'codex.thread.list',
      <String, Object?>{
        'scope': workspaceId == null ? 'all' : 'workspace',
        'workspaceId': ?workspaceId,
        'searchTerm': ?searchTerm,
        'cursor': ?cursor,
        'limit': 20,
      },
    );
    return MobileCodexThreadPage.fromJson(response);
  }

  Future<Map<String, Object?>> resumeThread(
    MobileCodexThreadSummary thread, {
    String? cwd,
  }) async {
    final client = _client;
    if (client == null) return const <String, Object?>{};
    _beginMobileSessionTransition();
    try {
      final response = await client.codexRequest(
        'codex.thread.resume',
        <String, Object?>{
          'tabId': tabId,
          'threadId': thread.id,
          'cwd': ?cwd,
          'limit': 20,
        },
      );
      if (!ref.mounted) return response;
      if (response['alreadyBound'] == true) {
        return response;
      }
      _sessionTransitionSucceeded = true;
      _threadId = _string(response['threadId']);
      _threadGeneration += 1;
      _update(
        (current) =>
            _replaceMobileSessionState(current, response, fallbackCwd: cwd),
      );
      await _reloadMobileSessionCatalogues(client);
      return response;
    } catch (error, stackTrace) {
      if (!ref.mounted) return const <String, Object?>{};
      _setError(error, stackTrace);
      rethrow;
    } finally {
      _finishMobileSessionTransition();
    }
  }

  Future<void> loadHistory({String? cursor}) async {
    if (state.isLoading ||
        state.hasError ||
        state.value?.historyOutdated == true) {
      return;
    }
    if (_historyLoading || cursor == null || cursor.trim().isEmpty) return;
    final client = _client;
    if (client == null) return;
    _historyLoading = true;
    final requestedGeneration = _threadGeneration;
    final requestedThreadId = _threadId;
    try {
      final response = await client.codexRequest(
        'codex.thread.history',
        <String, Object?>{'tabId': tabId, 'cursor': cursor, 'limit': 20},
      );
      if (!ref.mounted ||
          requestedGeneration != _threadGeneration ||
          requestedThreadId != _threadId) {
        return;
      }
      final page = MobileCodexThreadHistoryPage.fromJson(response);
      _update(
        (current) => _mergeMobileHistory(current, page.snapshot).copyWith(
          activeCwd: _string(response['cwd']) ?? current.activeCwd,
          historyNextCursor: page.nextCursor,
          error: null,
        ),
      );
    } catch (error, stackTrace) {
      if (!ref.mounted || requestedGeneration != _threadGeneration) return;
      _setError(error, stackTrace);
    } finally {
      _historyLoading = false;
    }
  }

  Future<bool> newThread() => _sessionRequest('codex.thread.new');

  Future<bool> clearThread() => _sessionRequest('codex.thread.clear');

  Future<bool> _sessionRequest(String request) async {
    final client = _client;
    if (client == null) return false;
    _beginMobileSessionTransition();
    try {
      final response = await client.codexRequest(request, <String, Object?>{
        'tabId': tabId,
      });
      if (!ref.mounted) return false;
      _sessionTransitionSucceeded = true;
      _threadId = _string(response['threadId']);
      _threadGeneration += 1;
      _update((current) => _replaceMobileSessionState(current, response));
      await _reloadMobileSessionCatalogues(client);
      return true;
    } catch (error, stackTrace) {
      if (!ref.mounted) return false;
      _setError(error, stackTrace);
      return false;
    } finally {
      _finishMobileSessionTransition();
    }
  }

  Future<void> _reloadMobileSessionCatalogues(MobileCodexClient client) async {
    if (!ref.mounted) return;
    final current = state.value;
    if (current == null) return;
    final accountRevision = _accountCatalogueRevision;
    final loaded = await _loadCatalogues(client, current);
    if (!ref.mounted) return;
    _update(
      (latest) => _mergeMobileSessionCatalogues(
        latest,
        loaded,
        includeAccountCatalogues: accountRevision == _accountCatalogueRevision,
      ),
    );
  }

  void _beginMobileSessionTransition() {
    _threadGeneration += 1;
    final firstTransition = _sessionTransitionCount == 0;
    _sessionTransitionCount += 1;
    if (firstTransition) {
      _sessionTransitionSucceeded = false;
      if (state.value?.supportsSharedQueue != true) {
        _suspendedSessionQueue =
            state.value?.queuedMessages ?? const <Map<String, Object?>>[];
        _update(
          (current) =>
              current.copyWith(queuedMessages: const <Map<String, Object?>>[]),
        );
      }
    }
  }

  void _restoreMobileSuspendedQueue() {
    _update(
      (current) => current.copyWith(
        queuedMessages: <Map<String, Object?>>[
          ..._suspendedSessionQueue,
          ...current.queuedMessages,
        ],
      ),
    );
  }

  void _finishMobileSessionTransition() {
    if (_sessionTransitionCount > 0) _sessionTransitionCount -= 1;
    if (_sessionTransitionInProgress) return;
    if (!ref.mounted) {
      _suspendedSessionQueue = const <Map<String, Object?>>[];
      _sessionTransitionSucceeded = false;
      return;
    }
    if (!_sessionTransitionSucceeded && _suspendedSessionQueue.isNotEmpty) {
      _restoreMobileSuspendedQueue();
    }
    _suspendedSessionQueue = const <Map<String, Object?>>[];
    _sessionTransitionSucceeded = false;
    final current = state.value;
    if (current == null ||
        current.supportsSharedQueue ||
        current.queuePaused ||
        current.busy ||
        current.queuedMessages.isEmpty) {
      return;
    }
    final message = current.queuedMessages.first;
    _update(
      (value) => value.copyWith(
        queuedMessages: value.queuedMessages.skip(1).toList(growable: false),
      ),
    );
    unawaited(_sendNow(message));
  }
}

MobileCodexState _mergeMobileSessionCatalogues(
  MobileCodexState current,
  MobileCodexState loaded, {
  bool includeAccountCatalogues = true,
  bool includeSkillsAndApps = true,
}) {
  final models = includeAccountCatalogues ? loaded.models : current.models;
  final selectedModel = models.any((model) => model.id == current.selectedModel)
      ? current.selectedModel
      : includeAccountCatalogues
      ? loaded.selectedModel
      : current.selectedModel;
  final selectedOption = models
      .where((model) => model.id == selectedModel)
      .firstOrNull;
  return current.copyWith(
    models: models,
    collaborationModes: includeAccountCatalogues
        ? loaded.collaborationModes
        : current.collaborationModes,
    skills: includeSkillsAndApps ? loaded.skills : current.skills,
    apps: includeSkillsAndApps ? loaded.apps : current.apps,
    selectedModel: selectedModel,
    reasoningEffort: _supportedEffort(selectedOption, current.reasoningEffort),
    speedMode: selectedOption?.supportsFastMode == false
        ? 'normal'
        : current.speedMode,
  );
}

MobileCodexState _replaceMobileSessionState(
  MobileCodexState current,
  Map<String, Object?> response, {
  String? fallbackCwd,
}) {
  final replacement = MobileCodexState.fromSnapshot(response['snapshot'])
      .copyWith(
        models: current.models,
        collaborationModes: current.collaborationModes,
        skills: current.skills,
        apps: current.apps,
        selectedModel: current.selectedModel,
        reasoningEffort: current.reasoningEffort,
        speedMode: current.speedMode,
        permissionMode: current.permissionMode,
        planMode: current.planMode,
        collaborationMode: current.collaborationMode,
        queuedMessages: current.queuedMessages,
        activeCwd: _string(response['cwd']) ?? fallbackCwd,
        historyNextCursor: _string(response['historyNextCursor']),
        recovery: response['recovery'] == null
            ? null
            : MobileCodexThreadRecovery.fromJson(response['recovery']),
      );
  final configured = _applyMobileConfiguration(
    replacement.copyWith(
      chatFeatures:
          (response['chatFeatures'] as List?)?.whereType<String>().toSet() ??
          current.chatFeatures,
      historyRevision: response['historyRevision'] as int? ?? 0,
      queueState: const {},
      queuedMessages: current.supportsSharedQueue
          ? const []
          : current.queuedMessages,
    ),
    response['configuration'],
  );
  return response['queue'] is Map
      ? _withSharedQueue(
          configured,
          Map<String, Object?>.from(response['queue']! as Map),
        )
      : configured;
}

MobileCodexState _mergeMobileHistory(
  MobileCodexState current,
  MobileCodexState page,
) {
  final eventKeys = <String>{
    for (final event in page.events) jsonEncode(event),
  };
  final cellKeys = <String>{for (final cell in page.timelineCells) cell.id};
  final mergedCells = <MobileCodexTimelineCell>[
    ...page.timelineCells,
    for (final cell in current.timelineCells)
      if (cellKeys.add(cell.id)) cell,
  ];
  final paginatedHistoryCellIds = Set<String>.unmodifiable(<String>{
    ...current.paginatedHistoryCellIds,
    for (final cell in page.timelineCells) cell.id,
  });
  return current.copyWith(
    events: <Map<String, Object?>>[
      ...page.events,
      for (final event in current.events)
        if (eventKeys.add(jsonEncode(event))) event,
    ],
    timelineCells: mergedCells,
    paginatedHistoryCellIds: paginatedHistoryCellIds,
    promptHistory: mobileCodexPromptHistory(mergedCells),
    activeTurnId: current.activeTurnId,
    hasCompletedTurns: current.hasCompletedTurns ?? page.hasCompletedTurns,
    title: current.title ?? page.title,
  );
}

MobileCodexState _mergeMobileSameThreadSnapshot(
  MobileCodexState current,
  MobileCodexState incoming,
) {
  final eventKeys = <String>{
    for (final event in incoming.events) jsonEncode(event),
  };
  final historyCells = <MobileCodexTimelineCell>[
    for (final cell in current.timelineCells)
      if (current.paginatedHistoryCellIds.contains(cell.id)) cell,
  ];
  final incomingLive = _mobileCellsWithoutClaimedMatches(
    incoming.timelineCells,
    historyCells,
    replacedByExactHistory: (candidate) => _mobileHistoryContainsExactIdentity(
      current.paginatedHistoryCellIds,
      candidate,
    ),
  );
  final currentLive = _mobileCellsWithoutClaimedMatches(
    <MobileCodexTimelineCell>[
      for (final cell in current.timelineCells)
        if (!current.paginatedHistoryCellIds.contains(cell.id)) cell,
    ],
    historyCells,
    replacedByExactHistory: (candidate) => _mobileHistoryContainsExactIdentity(
      current.paginatedHistoryCellIds,
      candidate,
    ),
  );
  final mergedCells = <MobileCodexTimelineCell>[
    ...historyCells,
    ..._mobileCellsWithoutClaimedMatches(currentLive, incomingLive),
    ...incomingLive,
  ];
  return current.copyWith(
    events: <Map<String, Object?>>[
      for (final event in current.events)
        if (!eventKeys.contains(jsonEncode(event))) event,
      ...incoming.events,
    ],
    timelineCells: mergedCells,
    promptHistory: mobileCodexPromptHistory(mergedCells),
    pendingRequests: incoming.pendingRequests,
    activeTurnId: incoming.activeTurnId,
    hasCompletedTurns: incoming.hasCompletedTurns ?? current.hasCompletedTurns,
    contextUsed: incoming.contextUsed,
    contextLimit: incoming.contextLimit,
    title: incoming.title,
    mcpInitializing: incoming.mcpInitializing,
    goal: incoming.goal,
  );
}

MobileCodexState _reconcileMobileSameThreadSnapshot(
  MobileCodexState current,
  MobileCodexState incoming,
  Map<dynamic, dynamic> delta,
) {
  final updated = current.applySnapshotDelta(delta, deriveTimeline: false);
  final historyCells = <MobileCodexTimelineCell>[
    for (final cell in updated.timelineCells)
      if (updated.paginatedHistoryCellIds.contains(cell.id)) cell,
  ];
  final incomingLive = _mobileCellsWithoutClaimedMatches(
    incoming.timelineCells,
    historyCells,
    replacedByExactHistory: (candidate) => _mobileHistoryContainsExactIdentity(
      updated.paginatedHistoryCellIds,
      candidate,
    ),
  );
  final updatedLive = _mobileCellsWithoutClaimedMatches(
    <MobileCodexTimelineCell>[
      for (final cell in updated.timelineCells)
        if (!updated.paginatedHistoryCellIds.contains(cell.id)) cell,
    ],
    historyCells,
    replacedByExactHistory: (candidate) => _mobileHistoryContainsExactIdentity(
      updated.paginatedHistoryCellIds,
      candidate,
    ),
  );
  final currentLiveIds = <String>{
    for (final cell in current.timelineCells)
      if (!current.paginatedHistoryCellIds.contains(cell.id)) cell.id,
  };
  final incomingIds = <String>{for (final cell in incomingLive) cell.id};
  final liveCells = <MobileCodexTimelineCell>[
    ..._mobileCellsWithoutClaimedMatches(<MobileCodexTimelineCell>[
      for (final cell in updatedLive)
        if (!(incomingIds.contains(cell.id) &&
            !currentLiveIds.contains(cell.id)))
          cell,
    ], incomingLive),
    ...incomingLive,
  ];
  const retainedLiveCellLimit = 480;
  final boundedLiveCells = liveCells.length <= retainedLiveCellLimit
      ? liveCells
      : liveCells.sublist(liveCells.length - retainedLiveCellLimit);
  final retainedCells = List<MobileCodexTimelineCell>.unmodifiableOf(
    <MobileCodexTimelineCell>[...historyCells, ...boundedLiveCells],
  );
  final paginatedHistoryCellIds =
      historyCells.length == updated.paginatedHistoryCellIds.length
      ? updated.paginatedHistoryCellIds
      : Set<String>.unmodifiable(historyCells.map((cell) => cell.id));
  final activeTurnId = incoming.activeTurnId;
  return updated.copyWith(
    timelineCells: retainedCells,
    paginatedHistoryCellIds: paginatedHistoryCellIds,
    promptHistory: mobileCodexPromptHistory(retainedCells),
    pendingRequests: incoming.pendingRequests,
    activeTurnId: activeTurnId,
    hasCompletedTurns: incoming.hasCompletedTurns ?? updated.hasCompletedTurns,
    contextUsed: incoming.contextUsed,
    contextLimit: incoming.contextLimit,
    title: incoming.title,
    mcpInitializing: mobileCodexHasInitializingMcp(retainedCells),
    goal: incoming.goal,
    presentationRows: MobileCodexTimelineProjection.project(
      retainedCells,
      activeTurnId: activeTurnId,
    ),
  );
}

bool _mobileHistoryContainsExactIdentity(
  Set<String> historyCellIds,
  MobileCodexTimelineCell candidate,
) {
  if (historyCellIds.contains(candidate.id)) return true;
  final itemId = candidate.itemId;
  return itemId != null &&
      itemId.isNotEmpty &&
      historyCellIds.contains('item-$itemId');
}
