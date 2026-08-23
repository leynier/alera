part of 'codex_chat_models.dart';

final class _CodexTimelineDelta {
  const _CodexTimelineDelta({required this.removedIds, required this.upserts});

  factory _CodexTimelineDelta.fromJson(Map<String, Object?> json) {
    final removedIds = <String>{};
    final rawRemovedIds = json['timelineRemovedIds'];
    if (rawRemovedIds is List) {
      for (final id in rawRemovedIds) {
        final value = id?.toString();
        if (value != null && value.isNotEmpty) removedIds.add(value);
      }
    }
    final upserts = <String, CodexTimelineCell>{};
    final rawUpserts = json['timelineUpserts'];
    if (rawUpserts is List) {
      for (final item in rawUpserts) {
        if (item is! Map) continue;
        final cell = CodexTimelineCell.fromJson(_map(item));
        upserts[cell.id] = cell;
      }
    }
    return _CodexTimelineDelta(removedIds: removedIds, upserts: upserts);
  }

  final Set<String> removedIds;
  final Map<String, CodexTimelineCell> upserts;

  _CodexTimelineUpdate apply(List<CodexTimelineCell> current) {
    if (removedIds.isEmpty && upserts.isEmpty) {
      return _CodexTimelineUpdate.unchanged(current);
    }
    final timeline = _MutableCodexTimeline(current);
    final updatesPromptHistory = _affects(
      timeline.cellFor,
      (cell) => cell?.kind == CodexTimelineKind.userMessage,
    );
    final updatesMcpState = _affects(timeline.cellFor, _codexIsMcpStartup);
    timeline.removeAll(removedIds);
    timeline.upsertAll(upserts, removedIds: removedIds);
    return _CodexTimelineUpdate(
      cells: timeline.build(),
      updatesPromptHistory: updatesPromptHistory,
      updatesMcpState: updatesMcpState,
    );
  }

  bool _affects(
    CodexTimelineCell? Function(String id) currentCell,
    bool Function(CodexTimelineCell? cell) matches,
  ) {
    if (removedIds.any((id) => matches(currentCell(id)))) return true;
    return upserts.entries.any(
      (entry) => matches(currentCell(entry.key)) || matches(entry.value),
    );
  }
}

final class _CodexTimelineUpdate {
  const _CodexTimelineUpdate({
    required this.cells,
    required this.updatesPromptHistory,
    required this.updatesMcpState,
  });

  const _CodexTimelineUpdate.unchanged(this.cells)
    : updatesPromptHistory = false,
      updatesMcpState = false;

  final List<CodexTimelineCell> cells;
  final bool updatesPromptHistory;
  final bool updatesMcpState;
}

final class _MutableCodexTimeline {
  _MutableCodexTimeline(List<CodexTimelineCell> cells)
    : _segmented = cells is CodexTimelineCells ? cells : null,
      _history = cells is CodexTimelineCells
          ? cells.history
          : const <CodexTimelineCell>[],
      _live = List<CodexTimelineCell>.of(
        cells is CodexTimelineCells ? cells.live : cells,
      ) {
    _indexCells();
  }

  final CodexTimelineCells? _segmented;
  List<CodexTimelineCell> _history;
  final List<CodexTimelineCell> _live;
  late Map<String, int> _historyIndexes;
  late Map<String, int> _liveIndexes;
  var _historyChanged = false;

  CodexTimelineCell? cellFor(String id) {
    final liveIndex = _liveIndexes[id];
    if (liveIndex != null) return _live[liveIndex];
    final historyIndex = _historyIndexes[id];
    return historyIndex == null ? null : _history[historyIndex];
  }

  void removeAll(Set<String> ids) {
    if (ids.isEmpty) return;
    if (ids.any(_historyIndexes.containsKey)) {
      _history = <CodexTimelineCell>[
        for (final cell in _history)
          if (!ids.contains(cell.id)) cell,
      ];
      _historyChanged = true;
    }
    _live.removeWhere((cell) => ids.contains(cell.id));
    _indexCells();
  }

  void upsertAll(
    Map<String, CodexTimelineCell> upserts, {
    required Set<String> removedIds,
  }) {
    for (final entry in upserts.entries) {
      final liveIndex = _liveIndexes[entry.key];
      if (liveIndex != null) {
        _live[liveIndex] = entry.value;
        continue;
      }
      final historyIndex = _historyIndexes[entry.key];
      if (historyIndex != null && !removedIds.contains(entry.key)) {
        if (!_historyChanged) {
          _history = List<CodexTimelineCell>.of(_history);
          _historyChanged = true;
        }
        _history[historyIndex] = entry.value;
        continue;
      }
      _liveIndexes[entry.key] = _live.length;
      _live.add(entry.value);
    }
  }

  List<CodexTimelineCell> build() {
    if (_history.isEmpty) {
      return List<CodexTimelineCell>.unmodifiable(_live);
    }
    if (_historyChanged || _segmented == null) {
      return CodexTimelineCells.segmented(history: _history, live: _live);
    }
    return _segmented.withLive(_live);
  }

  void _indexCells() {
    _historyIndexes = <String, int>{
      for (var index = 0; index < _history.length; index++)
        _history[index].id: index,
    };
    _liveIndexes = <String, int>{
      for (var index = 0; index < _live.length; index++) _live[index].id: index,
    };
  }
}

List<CodexTimelineEvent> _applyCodexEventDelta(
  List<CodexTimelineEvent> current,
  Map<String, Object?> json,
) {
  final replacement = json['eventsReplace'] is List
      ? _codexTimelineEvents(json['eventsReplace'])
      : null;
  final appended = _codexTimelineEvents(json['eventsAppend']);
  final eventLimit = _int(json['eventLimit']) ?? 160;
  final combined =
      replacement ??
      (appended.isEmpty
          ? current
          : <CodexTimelineEvent>[...current, ...appended]);
  return combined.length <= eventLimit
      ? combined
      : combined.sublist(combined.length - eventLimit);
}

T _codexDeltaValue<T>(
  Map<String, Object?> json,
  String key,
  T current,
  T Function(Object? value) parse,
) => json.containsKey(key) ? parse(json[key]) : current;

CodexThreadGoal? _codexThreadGoal(Object? value) =>
    value is Map ? CodexThreadGoal.fromJson(value) : null;
