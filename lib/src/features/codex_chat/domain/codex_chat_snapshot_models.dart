part of 'codex_chat_models.dart';

/// Keeps explicitly loaded history separate from the bounded live window.
/// Streaming deltas can replace the live segment without copying or indexing
/// the full conversation on the Flutter isolate.
final class CodexTimelineCells extends ListBase<CodexTimelineCell> {
  new segmented({
    required List<CodexTimelineCell> history,
    required List<CodexTimelineCell> live,
  }) : _history = List<CodexTimelineCell>.unmodifiableOf(history),
       _live = List<CodexTimelineCell>.unmodifiableOf(live),
       _historyPromptHistory = List<String>.unmodifiableOf(
         _codexPromptHistory(history),
       ),
       _historyIndexById = Map<String, int>.unmodifiableOf(<String, int>{
         for (var index = 0; index < history.length; index++)
           history[index].id: index,
       }),
       _historyItemIds = Set<String>.unmodifiable(<String>{
         for (final cell in history)
           if (cell.itemId?.isNotEmpty == true) cell.itemId!,
         for (final cell in history)
           if (cell.id.startsWith('item-') && cell.id.length > 5)
             cell.id.substring(5),
       });

  new _withLive(
    this._history,
    List<CodexTimelineCell> live,
    this._historyPromptHistory,
    this._historyIndexById,
    this._historyItemIds,
  ) : _live = List<CodexTimelineCell>.unmodifiableOf(live);

  final List<CodexTimelineCell> _history;
  final List<CodexTimelineCell> _live;
  final List<String> _historyPromptHistory;
  final Map<String, int> _historyIndexById;
  final Set<String> _historyItemIds;

  List<CodexTimelineCell> get history => _history;
  List<CodexTimelineCell> get live => _live;
  List<String> get historyPromptHistory => _historyPromptHistory;
  Map<String, int> get historyIndexes => _historyIndexById;

  int? historyIndexFor(String id) => _historyIndexById[id];

  bool historyContainsExactIdentity(CodexTimelineCell cell) {
    if (_historyIndexById.containsKey(cell.id)) return true;
    final itemId = cell.itemId?.isNotEmpty == true
        ? cell.itemId
        : cell.id.startsWith('item-') && cell.id.length > 5
        ? cell.id.substring(5)
        : null;
    return itemId != null && _historyItemIds.contains(itemId);
  }

  List<String> promptHistoryWithLive(List<CodexTimelineCell> live) =>
      CodexPromptHistory._withLive(
        _historyPromptHistory,
        _codexPromptHistory(live),
      );

  CodexTimelineCells withLive(List<CodexTimelineCell> live) =>
      CodexTimelineCells._withLive(
        _history,
        live,
        _historyPromptHistory,
        _historyIndexById,
        _historyItemIds,
      );

  @override
  int get length => _history.length + _live.length;

  @override
  set length(int value) =>
      throw UnsupportedError('Timeline cells are immutable.');

  @override
  CodexTimelineCell operator [](int index) {
    RangeError.checkValidIndex(index, this);
    return index < _history.length
        ? _history[index]
        : _live[index - _history.length];
  }

  @override
  void operator []=(int index, CodexTimelineCell value) =>
      throw UnsupportedError('Timeline cells are immutable.');
}

/// Shares the immutable prompt-history prefix loaded from earlier pages while
/// the bounded live suffix changes during streaming.
final class CodexPromptHistory._withLive(
  final List<String> _history,
  List<String> live,
) extends ListBase<String> {
  this : _live = List<String>.unmodifiableOf(live);

  final List<String> _live;

  List<String> get history => _history;

  @override
  int get length => _history.length + _live.length;

  @override
  set length(int value) =>
      throw UnsupportedError('Prompt history is immutable.');

  @override
  String operator [](int index) {
    RangeError.checkValidIndex(index, this);
    return index < _history.length
        ? _history[index]
        : _live[index - _history.length];
  }

  @override
  void operator []=(int index, String value) =>
      throw UnsupportedError('Prompt history is immutable.');
}

@immutable
class const CodexChatSnapshot({
  final List<CodexTimelineEvent> events = const <CodexTimelineEvent>[],
  final List<CodexTimelineCell> timelineCells = const <CodexTimelineCell>[],
  final List<CodexPendingRequest> pendingRequests =
      const <CodexPendingRequest>[],
  final List<String> promptHistory = const <String>[],
  final bool mcpInitializing = false,
  final String? activeTurnId,
  final bool? hasCompletedTurns,
  final int? contextUsed,
  final int? contextLimit,
  final String? title,
  final CodexThreadGoal? goal,
}) {
  factory CodexChatSnapshot.fromJson(Object? value) {
    final json = _map(value);
    final events = _codexTimelineEvents(json['events']);
    var cells = <CodexTimelineCell>[
      for (final item
          in json['timelineCells'] is List
              ? json['timelineCells'] as List
              : const <Object?>[])
        if (item is Map) CodexTimelineCell.fromJson(_map(item)),
    ];
    if (cells.isEmpty && events.isNotEmpty) {
      for (final event in events) {
        cells = CodexTimelineReducer.reduce(cells, event.raw);
      }
    }
    return CodexChatSnapshot(
      events: events,
      timelineCells: cells,
      promptHistory: _codexPromptHistory(cells),
      mcpInitializing: _codexHasInitializingMcp(cells),
      pendingRequests: _codexPendingRequests(json['pendingRequests']),
      activeTurnId: _string(json['activeTurnId']),
      hasCompletedTurns: json['hasCompletedTurns'] as bool?,
      contextUsed: _int(json['contextUsed']),
      contextLimit: _int(json['contextLimit']),
      title: _string(json['title']),
      goal: json['goal'] is Map ? CodexThreadGoal.fromJson(json['goal']) : null,
    );
  }

  CodexChatSnapshot applyDelta(Object? value) {
    final json = _map(value);
    if (json.isEmpty) return this;
    final timeline = _CodexTimelineDelta.fromJson(json).apply(timelineCells);
    return CodexChatSnapshot(
      events: _applyCodexEventDelta(events, json),
      timelineCells: timeline.cells,
      promptHistory: timeline.updatesPromptHistory
          ? _codexPromptHistory(timeline.cells)
          : promptHistory,
      mcpInitializing: timeline.updatesMcpState
          ? _codexHasInitializingMcp(timeline.cells)
          : mcpInitializing,
      pendingRequests: _codexDeltaValue(
        json,
        'pendingRequests',
        pendingRequests,
        _codexPendingRequests,
      ),
      activeTurnId: _codexDeltaValue(
        json,
        'activeTurnId',
        activeTurnId,
        _string,
      ),
      hasCompletedTurns:
          json['hasCompletedTurns'] as bool? ?? hasCompletedTurns,
      contextUsed: _codexDeltaValue(json, 'contextUsed', contextUsed, _int),
      contextLimit: _codexDeltaValue(json, 'contextLimit', contextLimit, _int),
      title: _codexDeltaValue(json, 'title', title, _string),
      goal: _codexDeltaValue(json, 'goal', goal, _codexThreadGoal),
    );
  }

  bool get isBusy => activeTurnId != null;

  /// The plan prompt is a turn-local affordance. Older snapshots can retain
  /// plans from many turns, so rendering a button for any plan makes a stale
  /// plan actionable after the user has started a new request.
  CodexTimelineCell? get latestActionablePlan {
    final latestUserIndex = _latestUserIndex;
    if (latestUserIndex < 0) return null;
    for (
      var index = timelineCells.length - 1;
      index > latestUserIndex;
      index--
    ) {
      final cell = timelineCells[index];
      if (cell.kind == CodexTimelineKind.systemNotice &&
          const <String>{
            'threadBoundary',
            'contextReset',
          }.contains(cell.metadata['noticeType'])) {
        return null;
      }
      if (cell.kind != CodexTimelineKind.plan ||
          cell.metadata['plan'] is List ||
          cell.status == CodexTimelineStatus.failed ||
          cell.status == CodexTimelineStatus.declined ||
          cell.isStreaming ||
          (cell.markdownText ?? cell.detailsText ?? '').trim().isEmpty) {
        continue;
      }
      return cell;
    }
    return null;
  }

  /// A server question asking whether to implement a plan owns the prompt.
  /// Showing the local fallback at the same time creates two competing
  /// actions and can send an answer for an already resolved request.
  bool get hasEquivalentPlanRequest =>
      pendingRequests.any((request) => request.isImplementPlanQuestion);

  bool get shouldShowImplementPlan =>
      latestActionablePlan != null && !hasEquivalentPlanRequest;

  bool get hasPlan => shouldShowImplementPlan;

  int get _latestUserIndex {
    for (var index = timelineCells.length - 1; index >= 0; index--) {
      if (timelineCells[index].kind == CodexTimelineKind.userMessage) {
        return index;
      }
    }
    return -1;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 2,
    'events': <Map<String, Object?>>[for (final event in events) event.raw],
    'timelineCells': <Map<String, Object?>>[
      for (final cell in timelineCells) cell.toJson(),
    ],
    'pendingRequests': <Map<String, Object?>>[
      for (final request in pendingRequests)
        <String, Object?>{
          'id': request.id,
          'method': request.method,
          'params': request.params,
        },
    ],
    if (activeTurnId != null) 'activeTurnId': activeTurnId,
    if (contextUsed != null) 'contextUsed': contextUsed,
    if (contextLimit != null) 'contextLimit': contextLimit,
    if (title != null) 'title': title,
    if (goal != null) 'goal': goal!.toJson(),
  };
}

List<CodexTimelineEvent> _codexTimelineEvents(Object? value) =>
    <CodexTimelineEvent>[
      for (final item in value is List ? value : const <Object?>[])
        CodexTimelineEvent.fromJson(item),
    ];

List<CodexPendingRequest> _codexPendingRequests(Object? value) =>
    <CodexPendingRequest>[
      for (final item in value is List ? value : const <Object?>[])
        CodexPendingRequest.fromJson(item),
    ];

List<String> _codexPromptHistory(List<CodexTimelineCell> cells) =>
    List<String>.unmodifiableOf(<String>[
      for (final cell in cells)
        if (cell.kind == CodexTimelineKind.userMessage &&
            cell.metadata[CodexTimelineMetadata.isSteering] != true &&
            cell.metadata[CodexTimelineMetadata.isGoal] != true &&
            (cell.markdownText ?? '').trim().isNotEmpty)
          cell.markdownText!.trim(),
    ]);

bool _codexHasInitializingMcp(List<CodexTimelineCell> cells) => cells.any(
  (cell) =>
      _codexIsMcpStartup(cell) &&
      (cell.isStreaming || cell.status == CodexTimelineStatus.inProgress),
);

bool _codexIsMcpStartup(CodexTimelineCell? cell) =>
    cell?.metadata['itemType'] == 'mcpServerStartup';
