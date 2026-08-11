part of 'codex_chat_models.dart';

/// Keeps explicitly loaded history separate from the bounded live window.
/// Streaming deltas can replace the live segment without copying or indexing
/// the full conversation on the Flutter isolate.
final class CodexTimelineCells extends ListBase<CodexTimelineCell> {
  CodexTimelineCells.segmented({
    required List<CodexTimelineCell> history,
    required List<CodexTimelineCell> live,
  }) : _history = List<CodexTimelineCell>.unmodifiable(history),
       _live = List<CodexTimelineCell>.unmodifiable(live),
       _historyPromptHistory = List<String>.unmodifiable(
         _codexPromptHistory(history),
       ),
       _historyIndexById = Map<String, int>.unmodifiable(<String, int>{
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

  CodexTimelineCells._withLive(
    this._history,
    List<CodexTimelineCell> live,
    this._historyPromptHistory,
    this._historyIndexById,
    this._historyItemIds,
  ) : _live = List<CodexTimelineCell>.unmodifiable(live);

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
final class CodexPromptHistory extends ListBase<String> {
  CodexPromptHistory._withLive(this._history, List<String> live)
    : _live = List<String>.unmodifiable(live);

  final List<String> _history;
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
class CodexChatSnapshot {
  const CodexChatSnapshot({
    this.events = const <CodexTimelineEvent>[],
    this.timelineCells = const <CodexTimelineCell>[],
    this.pendingRequests = const <CodexPendingRequest>[],
    this.promptHistory = const <String>[],
    this.mcpInitializing = false,
    this.activeTurnId,
    this.contextUsed,
    this.contextLimit,
    this.title,
  });

  factory CodexChatSnapshot.fromJson(Object? value) {
    final json = _map(value);
    final events = <CodexTimelineEvent>[
      for (final item
          in json['events'] is List
              ? json['events'] as List
              : const <Object?>[])
        CodexTimelineEvent.fromJson(item),
    ];
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
      pendingRequests: <CodexPendingRequest>[
        for (final item
            in json['pendingRequests'] is List
                ? json['pendingRequests'] as List
                : const <Object?>[])
          CodexPendingRequest.fromJson(item),
      ],
      activeTurnId: _string(json['activeTurnId']),
      contextUsed: _int(json['contextUsed']),
      contextLimit: _int(json['contextLimit']),
      title: _string(json['title']),
    );
  }

  CodexChatSnapshot applyDelta(Object? value) {
    final json = _map(value);
    if (json.isEmpty) return this;
    final removedIds = <String>{
      for (final id
          in json['timelineRemovedIds'] is List
              ? json['timelineRemovedIds'] as List
              : const <Object?>[])
        if (id?.toString() case final String value when value.isNotEmpty) value,
    };
    final upserts = <String, CodexTimelineCell>{};
    for (final item
        in json['timelineUpserts'] is List
            ? json['timelineUpserts'] as List
            : const <Object?>[]) {
      if (item is! Map) continue;
      final cell = CodexTimelineCell.fromJson(_map(item));
      upserts[cell.id] = cell;
    }
    final segmented = timelineCells is CodexTimelineCells
        ? timelineCells as CodexTimelineCells
        : null;
    var historyCells = segmented?.history ?? const <CodexTimelineCell>[];
    var liveCells = List<CodexTimelineCell>.of(
      segmented?.live ?? timelineCells,
      growable: true,
    );
    var liveIndexes = <String, int>{
      for (var index = 0; index < liveCells.length; index++)
        liveCells[index].id: index,
    };
    var historyIndexes = segmented?.historyIndexes ?? const <String, int>{};
    CodexTimelineCell? currentCell(String id) {
      final liveIndex = liveIndexes[id];
      if (liveIndex != null) return liveCells[liveIndex];
      final historyIndex = historyIndexes[id];
      return historyIndex == null ? null : historyCells[historyIndex];
    }

    final historyChanged =
        removedIds.any(
          (id) => currentCell(id)?.kind == CodexTimelineKind.userMessage,
        ) ||
        upserts.entries.any(
          (entry) =>
              currentCell(entry.key)?.kind == CodexTimelineKind.userMessage ||
              entry.value.kind == CodexTimelineKind.userMessage,
        );
    final mcpChanged =
        removedIds.any((id) => _codexIsMcpStartup(currentCell(id))) ||
        upserts.entries.any(
          (entry) =>
              _codexIsMcpStartup(currentCell(entry.key)) ||
              _codexIsMcpStartup(entry.value),
        );
    final cellsChanged = removedIds.isNotEmpty || upserts.isNotEmpty;
    var historySegmentChanged = false;
    if (removedIds.isNotEmpty) {
      final removesHistory =
          segmented != null &&
          removedIds.any((id) => segmented.historyIndexFor(id) != null);
      if (removesHistory) {
        historyCells = <CodexTimelineCell>[
          for (final cell in historyCells)
            if (!removedIds.contains(cell.id)) cell,
        ];
        historyIndexes = <String, int>{
          for (var index = 0; index < historyCells.length; index++)
            historyCells[index].id: index,
        };
        historySegmentChanged = true;
      }
      liveCells.removeWhere((cell) => removedIds.contains(cell.id));
      liveIndexes = <String, int>{
        for (var index = 0; index < liveCells.length; index++)
          liveCells[index].id: index,
      };
    }
    for (final entry in upserts.entries) {
      final liveIndex = liveIndexes[entry.key];
      if (liveIndex != null) {
        liveCells[liveIndex] = entry.value;
        continue;
      }
      final historyIndex = historyIndexes[entry.key];
      if (historyIndex != null && !removedIds.contains(entry.key)) {
        if (!historySegmentChanged) {
          historyCells = List<CodexTimelineCell>.of(historyCells);
          historySegmentChanged = true;
        }
        historyCells[historyIndex] = entry.value;
        continue;
      }
      liveIndexes[entry.key] = liveCells.length;
      liveCells.add(entry.value);
    }
    final nextCells = !cellsChanged
        ? timelineCells
        : historyCells.isEmpty
        ? List<CodexTimelineCell>.unmodifiable(liveCells)
        : historySegmentChanged || segmented == null
        ? CodexTimelineCells.segmented(history: historyCells, live: liveCells)
        : segmented.withLive(liveCells);
    final replacementEvents = json['eventsReplace'] is List
        ? <CodexTimelineEvent>[
            for (final item in json['eventsReplace'] as List)
              CodexTimelineEvent.fromJson(item),
          ]
        : null;
    final appendedEvents = <CodexTimelineEvent>[
      for (final item
          in json['eventsAppend'] is List
              ? json['eventsAppend'] as List
              : const <Object?>[])
        CodexTimelineEvent.fromJson(item),
    ];
    final eventLimit = _int(json['eventLimit']) ?? 160;
    final combinedEvents =
        replacementEvents ??
        (appendedEvents.isEmpty
            ? events
            : <CodexTimelineEvent>[...events, ...appendedEvents]);
    final nextEvents = combinedEvents.length <= eventLimit
        ? combinedEvents
        : combinedEvents.sublist(combinedEvents.length - eventLimit);
    return CodexChatSnapshot(
      events: nextEvents,
      timelineCells: nextCells,
      promptHistory: historyChanged
          ? _codexPromptHistory(nextCells)
          : promptHistory,
      mcpInitializing: mcpChanged
          ? _codexHasInitializingMcp(nextCells)
          : mcpInitializing,
      pendingRequests: json.containsKey('pendingRequests')
          ? <CodexPendingRequest>[
              for (final item
                  in json['pendingRequests'] is List
                      ? json['pendingRequests'] as List
                      : const <Object?>[])
                CodexPendingRequest.fromJson(item),
            ]
          : pendingRequests,
      activeTurnId: json.containsKey('activeTurnId')
          ? _string(json['activeTurnId'])
          : activeTurnId,
      contextUsed: json.containsKey('contextUsed')
          ? _int(json['contextUsed'])
          : contextUsed,
      contextLimit: json.containsKey('contextLimit')
          ? _int(json['contextLimit'])
          : contextLimit,
      title: json.containsKey('title') ? _string(json['title']) : title,
    );
  }

  final List<CodexTimelineEvent> events;
  final List<CodexTimelineCell> timelineCells;
  final List<CodexPendingRequest> pendingRequests;
  final List<String> promptHistory;
  final bool mcpInitializing;
  final String? activeTurnId;
  final int? contextUsed;
  final int? contextLimit;
  final String? title;

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
  };
}

List<String> _codexPromptHistory(List<CodexTimelineCell> cells) =>
    List<String>.unmodifiable(<String>[
      for (final cell in cells)
        if (cell.kind == CodexTimelineKind.userMessage &&
            cell.metadata[CodexTimelineMetadata.isSteering] != true &&
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
