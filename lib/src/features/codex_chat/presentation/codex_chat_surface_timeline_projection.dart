part of 'codex_chat_surface.dart';

enum _CodexTimelineEntryKind { cell, turn, event, request }

class const _CodexTimelineViewState({
  required final bool loading,
  required final CodexChatSnapshot snapshot,
  required final String? activeCwd,
  required final String? historyNextCursor,
  required final String? error,
}) {
  factory from(CodexChatState state) => _CodexTimelineViewState(
    loading: state.loading,
    snapshot: state.snapshot,
    activeCwd: state.activeCwd,
    historyNextCursor: state.historyNextCursor,
    error: state.error,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _CodexTimelineViewState &&
          loading == other.loading &&
          identical(snapshot, other.snapshot) &&
          activeCwd == other.activeCwd &&
          historyNextCursor == other.historyNextCursor &&
          error == other.error;

  @override
  int get hashCode => Object.hash(
    loading,
    identityHashCode(snapshot),
    activeCwd,
    historyNextCursor,
    error,
  );
}

class const _CodexFooterViewState({
  required final CodexChatState state,
  required final List<CodexPendingRequest> pendingQuestions,
  required final bool hasBlockingQuestion,
  required final bool showLocalPlanQuestion,
  required final String? actionablePlanId,
  required final _CodexPlanProgressProjection? planProgress,
  required final bool mcpInitializing,
}) {
  factory from(CodexChatState state) {
    final pendingQuestions = state.snapshot.pendingRequests
        .where((request) => request.isQuestion)
        .toList(growable: false);
    return _CodexFooterViewState(
      state: state,
      pendingQuestions: pendingQuestions,
      hasBlockingQuestion: pendingQuestions.any(
        (request) => request.isBlocking,
      ),
      showLocalPlanQuestion:
          pendingQuestions.isEmpty &&
          state.planMode &&
          state.snapshot.shouldShowImplementPlan,
      actionablePlanId: state.snapshot.latestActionablePlan?.id,
      planProgress: _CodexPlanProgressProjection.fromSnapshot(state.snapshot),
      mcpInitializing: state.snapshot.mcpInitializing,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _CodexFooterViewState &&
          state.loading == other.state.loading &&
          state.sending == other.state.sending &&
          state.interrupting == other.state.interrupting &&
          state.supportsSessions == other.state.supportsSessions &&
          state.supportsAutoReview == other.state.supportsAutoReview &&
          state.supportsGoals == other.state.supportsGoals &&
          identical(state.models, other.state.models) &&
          identical(state.collaborationModes, other.state.collaborationModes) &&
          identical(state.skills, other.state.skills) &&
          identical(state.apps, other.state.apps) &&
          state.selectedModel == other.state.selectedModel &&
          state.reasoningEffort == other.state.reasoningEffort &&
          state.speedMode == other.state.speedMode &&
          state.permissionMode == other.state.permissionMode &&
          state.planMode == other.state.planMode &&
          state.collaborationMode == other.state.collaborationMode &&
          state.activeCwd == other.state.activeCwd &&
          state.recovery?.kind == other.state.recovery?.kind &&
          state.recovery?.message == other.state.recovery?.message &&
          identical(state.queuedMessages, other.state.queuedMessages) &&
          state.error == other.state.error &&
          state.snapshot.activeTurnId == other.state.snapshot.activeTurnId &&
          state.snapshot.contextUsed == other.state.snapshot.contextUsed &&
          state.snapshot.contextLimit == other.state.snapshot.contextLimit &&
          state.snapshot.goal == other.state.snapshot.goal &&
          identical(
            state.snapshot.promptHistory,
            other.state.snapshot.promptHistory,
          ) &&
          listEquals(pendingQuestions, other.pendingQuestions) &&
          hasBlockingQuestion == other.hasBlockingQuestion &&
          showLocalPlanQuestion == other.showLocalPlanQuestion &&
          actionablePlanId == other.actionablePlanId &&
          planProgress == other.planProgress &&
          mcpInitializing == other.mcpInitializing;

  @override
  int get hashCode => Object.hashAll(<Object?>[
    state.loading,
    state.sending,
    state.interrupting,
    state.supportsSessions,
    state.supportsAutoReview,
    state.supportsGoals,
    identityHashCode(state.models),
    identityHashCode(state.collaborationModes),
    identityHashCode(state.skills),
    identityHashCode(state.apps),
    state.selectedModel,
    state.reasoningEffort,
    state.speedMode,
    state.permissionMode,
    state.planMode,
    state.collaborationMode,
    state.activeCwd,
    state.recovery?.kind,
    state.recovery?.message,
    identityHashCode(state.queuedMessages),
    state.error,
    state.snapshot.activeTurnId,
    state.snapshot.contextUsed,
    state.snapshot.contextLimit,
    state.snapshot.goal,
    identityHashCode(state.snapshot.promptHistory),
    Object.hashAll(pendingQuestions),
    hasBlockingQuestion,
    showLocalPlanQuestion,
    actionablePlanId,
    planProgress,
    mcpInitializing,
  ]);
}

class _CodexTimelineEntry {
  const new cell(this.cell)
    : kind = _CodexTimelineEntryKind.cell,
      turn = null,
      event = null,
      request = null;

  const new turn(this.turn)
    : kind = _CodexTimelineEntryKind.turn,
      cell = null,
      event = null,
      request = null;

  const new event(this.event)
    : kind = _CodexTimelineEntryKind.event,
      cell = null,
      turn = null,
      request = null;

  const new request(this.request)
    : kind = _CodexTimelineEntryKind.request,
      cell = null,
      turn = null,
      event = null;

  final _CodexTimelineEntryKind kind;
  final CodexTimelineCell? cell;
  final _CodexTurnProjection? turn;
  final CodexTimelineEvent? event;
  final CodexPendingRequest? request;

  Object get source => switch (kind) {
    _CodexTimelineEntryKind.cell => cell!,
    _CodexTimelineEntryKind.turn => turn!,
    _CodexTimelineEntryKind.event => event!,
    _CodexTimelineEntryKind.request => request!,
  };

  String get key => switch (kind) {
    _CodexTimelineEntryKind.cell => 'cell-${cell!.id}',
    _CodexTimelineEntryKind.turn => 'turn-${turn!.turnId}',
    _CodexTimelineEntryKind.event =>
      'event-${event!.method}-${identityHashCode(event)}',
    _CodexTimelineEntryKind.request => 'request-${jsonEncode(request!.id)}',
  };
}

class const _CodexTimelineProjection({
  required final _CodexTimelineEntries entries,
  required final String? latestPlanId,
  required final _CodexTimelineSegmentProjection history,
  required final _CodexTimelineSegmentProjection live,
}) {
  factory fromSnapshot(
    CodexChatSnapshot snapshot, {
    required bool showRawLogs,
    _CodexTimelineProjection? previous,
    List<CodexTimelineCell>? liveCellsOverride,
  }) {
    final cells = snapshot.timelineCells;
    final _CodexTimelineSegmentProjection history;
    final _CodexTimelineSegmentProjection live;
    if (cells case final CodexTimelineCells segmented) {
      history = identical(previous?.history.sourceCells, segmented.history)
          ? previous!.history
          : _CodexTimelineSegmentProjection.fromCells(segmented.history);
      live = _CodexTimelineSegmentProjection.fromCells(
        liveCellsOverride ?? segmented.live,
        workingTurnId: snapshot.activeTurnId,
        previous: previous?.live,
      );
    } else {
      history = _CodexTimelineSegmentProjection.empty;
      live = _CodexTimelineSegmentProjection.fromCells(
        liveCellsOverride ?? cells,
        workingTurnId: snapshot.activeTurnId,
        previous: previous?.live,
      );
    }
    final boundary = _mergeCodexTimelineBoundary(
      history,
      live,
      workingTurnId: snapshot.activeTurnId,
      previous: previous?.entries.boundary,
    );
    final rawEvents = showRawLogs
        ? <_CodexTimelineEntry>[
            for (final event in snapshot.events)
              _CodexTimelineEntry.event(event),
          ]
        : const <_CodexTimelineEntry>[];
    final requests = <_CodexTimelineEntry>[
      for (final request in snapshot.pendingRequests)
        if (!request.isQuestion) _CodexTimelineEntry.request(request),
    ];
    final topNotices = <String, _CodexTimelineEntry>{
      for (final entry in history.topNotices) entry.key: entry,
      for (final entry in live.topNotices) entry.key: entry,
    }.values.toList(growable: false);
    final entries = _CodexTimelineEntries(
      topNotices: topNotices,
      history: history,
      live: live,
      boundary: boundary,
      rawEvents: rawEvents,
      requests: requests,
    );
    return _CodexTimelineProjection(
      entries: entries,
      latestPlanId: live.latestPlanId ?? history.latestPlanId,
      history: history,
      live: live,
    );
  }
}

class const _CodexTimelineSegmentProjection({
  required final List<CodexTimelineCell> sourceCells,
  required final List<_CodexTimelineEntry> topNotices,
  required final List<_CodexTimelineEntry> entries,
  required final Set<String> entryKeys,
  required final String? latestPlanId,
}) {
  static const empty = _CodexTimelineSegmentProjection(
    sourceCells: <CodexTimelineCell>[],
    topNotices: <_CodexTimelineEntry>[],
    entries: <_CodexTimelineEntry>[],
    entryKeys: <String>{},
    latestPlanId: null,
  );

  factory fromCells(
    List<CodexTimelineCell> cells, {
    String? workingTurnId,
    _CodexTimelineSegmentProjection? previous,
  }) {
    final turns = <String, List<CodexTimelineCell>>{};
    final order = <Object>[];
    final topNotices = <_CodexTimelineEntry>[];
    final seenTurns = <String>{};
    for (final cell in cells) {
      if (_isCodexTopNotice(cell)) {
        topNotices.add(.cell(cell));
        continue;
      }
      final turnId = cell.turnId;
      if (turnId == null || turnId.isEmpty) {
        if (cell.kind != CodexTimelineKind.turnSeparator &&
            cell.kind != CodexTimelineKind.reasoning) {
          order.add(cell);
        }
        continue;
      }
      turns.putIfAbsent(turnId, () => <CodexTimelineCell>[]).add(cell);
      if (seenTurns.add(turnId)) order.add(turnId);
    }
    final previousTurns = <String, _CodexTurnProjection>{
      for (final entry in previous?.entries ?? const <_CodexTimelineEntry>[])
        if (entry.turn case final _CodexTurnProjection turn) turn.turnId: turn,
    };
    final entries = List<_CodexTimelineEntry>.unmodifiable(
      <_CodexTimelineEntry>[
        for (final item in order)
          if (item is String)
            _CodexTimelineEntry.turn(
              .reuseOrCreate(
                previousTurns[item],
                turns[item]!,
                working: workingTurnId == item,
              ),
            )
          else
            _CodexTimelineEntry.cell(item as CodexTimelineCell),
      ],
    );
    return _CodexTimelineSegmentProjection(
      sourceCells: cells,
      topNotices: List<_CodexTimelineEntry>.unmodifiable(topNotices),
      entries: entries,
      entryKeys: Set<String>.unmodifiable(<String>{
        for (final entry in entries) entry.key,
      }),
      latestPlanId: _latestAuthoredPlanId(cells),
    );
  }
}

_CodexTimelineEntry? _mergeCodexTimelineBoundary(
  _CodexTimelineSegmentProjection history,
  _CodexTimelineSegmentProjection live, {
  required String? workingTurnId,
  _CodexTimelineEntry? previous,
}) {
  final before = history.entries.lastOrNull?.turn;
  final after = live.entries.firstOrNull?.turn;
  if (before == null || after == null || before.turnId != after.turnId) {
    return null;
  }
  return _CodexTimelineEntry.turn(
    .reuseOrCreate(previous?.turn, <CodexTimelineCell>[
      ...before.sourceCells,
      ...after.sourceCells,
    ], working: before.turnId == workingTurnId),
  );
}

class _CodexTimelineEntries({
  required final List<_CodexTimelineEntry> topNotices,
  required final _CodexTimelineSegmentProjection history,
  required final _CodexTimelineSegmentProjection live,
  required final _CodexTimelineEntry? boundary,
  required final List<_CodexTimelineEntry> rawEvents,
  required final List<_CodexTimelineEntry> requests,
}) extends ListBase<_CodexTimelineEntry> {
  late final Set<String> _rawEventKeys = <String>{
    for (final entry in rawEvents) entry.key,
  };
  late final Set<String> _requestKeys = <String>{
    for (final entry in requests) entry.key,
  };
  late final Set<String> _topNoticeKeys = <String>{
    for (final entry in topNotices) entry.key,
  };
  late final Map<String, int> _indexesByKey = <String, int>{
    for (var index = 0; index < length; index += 1) this[index].key: index,
  };

  bool containsKey(String key) =>
      _topNoticeKeys.contains(key) ||
      history.entryKeys.contains(key) ||
      live.entryKeys.contains(key) ||
      boundary?.key == key ||
      _rawEventKeys.contains(key) ||
      _requestKeys.contains(key);

  int? indexOfKey(String key) => _indexesByKey[key];

  int get _historyEntryCount =>
      history.entries.length - (boundary == null ? 0 : 1);
  int get _liveEntryCount => live.entries.length - (boundary == null ? 0 : 1);

  @override
  int get length =>
      topNotices.length +
      _historyEntryCount +
      (boundary == null ? 0 : 1) +
      _liveEntryCount +
      rawEvents.length +
      requests.length;

  @override
  set length(int value) =>
      throw UnsupportedError('Timeline projections are immutable.');

  @override
  _CodexTimelineEntry operator [](int index) {
    RangeError.checkValidIndex(index, this);
    var offset = index;
    if (offset < topNotices.length) return topNotices[offset];
    offset -= topNotices.length;
    if (offset < _historyEntryCount) return history.entries[offset];
    offset -= _historyEntryCount;
    if (boundary case final boundary?) {
      if (offset == 0) return boundary;
      offset -= 1;
    }
    if (offset < _liveEntryCount) {
      return live.entries[offset + (boundary == null ? 0 : 1)];
    }
    offset -= _liveEntryCount;
    if (offset < rawEvents.length) return rawEvents[offset];
    return requests[offset - rawEvents.length];
  }

  @override
  void operator []=(int index, _CodexTimelineEntry value) =>
      throw UnsupportedError('Timeline projections are immutable.');
}

String? _latestAuthoredPlanId(List<CodexTimelineCell> cells) {
  for (final cell in cells.reversed) {
    if (cell.kind == CodexTimelineKind.plan && cell.metadata['plan'] is! List) {
      return cell.id;
    }
  }
  return null;
}
