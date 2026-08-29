import 'dart:math' show max;

import 'package:alera/src/features/workbench/domain/terminal_search.dart';
import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart' as xterm;

typedef TerminalSearchLineScroller = void Function(int lineIndex);

final class TerminalSearchController extends ChangeNotifier {
  factory TerminalSearchController({
    required xterm.Terminal terminal,
    required TerminalSearchLineScroller scrollToLine,
  }) {
    return TerminalSearchController._(terminal, scrollToLine);
  }

  TerminalSearchController._(this._terminal, this._scrollToLine) {
    _terminal.addListener(_handleTerminalChanged);
  }

  xterm.Terminal _terminal;
  final TerminalSearchLineScroller _scrollToLine;
  xterm.Buffer? _indexedBuffer;
  int _indexedHeight = -1;
  int _indexedWidth = -1;
  bool _needsFullRefresh = true;
  bool _isOpen = false;
  String _query = '';
  int _selectedIndex = -1;
  final Map<xterm.BufferLine, List<_LineMatch>> _matchesByLine =
      <xterm.BufferLine, List<_LineMatch>>{};
  List<TerminalSearchMatch> _matches = const <TerminalSearchMatch>[];

  bool get isOpen => _isOpen;

  String get query => _query;

  List<TerminalSearchMatch> get matches => _matches;

  int get matchCount => _matches.length;

  int? get selectedMatchNumber {
    if (_selectedIndex < 0 || _selectedIndex >= _matches.length) {
      return null;
    }
    return _selectedIndex + 1;
  }

  TerminalSearchMatch? get selectedMatch {
    if (_selectedIndex < 0 || _selectedIndex >= _matches.length) {
      return null;
    }
    return _matches[_selectedIndex];
  }

  void open() {
    if (_isOpen) {
      return;
    }
    _isOpen = true;
    if (_query.isNotEmpty) {
      _refresh(forceFull: _needsFullRefresh);
    }
    notifyListeners();
  }

  void close() {
    if (!_isOpen) {
      return;
    }
    _isOpen = false;
    // Keep the query for the next invocation, but make reopening authoritative
    // after output that arrived while the overlay was hidden. The match index
    // is released because reopening rescans anyway; keeping it would retain
    // one entry per scrollback hit while nobody can see them.
    _needsFullRefresh = true;
    _matchesByLine.clear();
    _matches = const <TerminalSearchMatch>[];
    _selectedIndex = -1;
    notifyListeners();
  }

  void setQuery(String query) {
    if (_query == query) {
      return;
    }
    _query = query;
    _selectedIndex = -1;
    _matchesByLine.clear();
    _matches = const <TerminalSearchMatch>[];
    _needsFullRefresh = true;
    if (_query.isNotEmpty) {
      _refresh(forceFull: true);
      if (_matches.isNotEmpty) {
        _selectedIndex = 0;
        _scrollSelectedMatch();
      }
    }
    notifyListeners();
  }

  void next() {
    if (_matches.isEmpty) {
      return;
    }
    _selectedIndex = (_selectedIndex + 1) % _matches.length;
    _scrollSelectedMatch();
    notifyListeners();
  }

  void previous() {
    if (_matches.isEmpty) {
      return;
    }
    _selectedIndex = (_selectedIndex - 1) % _matches.length;
    if (_selectedIndex < 0) {
      _selectedIndex = _matches.length - 1;
    }
    _scrollSelectedMatch();
    notifyListeners();
  }

  /// Reattaches the search index when a snapshot replaces the emulator.
  void attachTerminal(xterm.Terminal terminal) {
    if (identical(_terminal, terminal)) {
      return;
    }
    _terminal.removeListener(_handleTerminalChanged);
    _terminal = terminal;
    _terminal.addListener(_handleTerminalChanged);
    _indexedBuffer = null;
    _indexedHeight = -1;
    _indexedWidth = -1;
    _needsFullRefresh = true;
    if (_isOpen && _query.isNotEmpty) {
      _refresh(forceFull: true);
      notifyListeners();
    }
  }

  @visibleForTesting
  bool get needsFullRefreshForTesting => _needsFullRefresh;

  void _handleTerminalChanged() {
    if (!_isOpen || _query.isEmpty) {
      _needsFullRefresh = true;
      return;
    }
    if (_refresh()) {
      notifyListeners();
    }
  }

  bool _refresh({bool forceFull = false}) {
    if (_query.isEmpty) {
      final hadMatches = _matches.isNotEmpty || _matchesByLine.isNotEmpty;
      _matchesByLine.clear();
      _matches = const <TerminalSearchMatch>[];
      _selectedIndex = -1;
      return hadMatches;
    }

    final buffer = _terminal.buffer;
    final height = buffer.height;
    final shouldScanAll =
        forceFull ||
        _needsFullRefresh ||
        !identical(_indexedBuffer, buffer) ||
        _indexedWidth != _terminal.viewWidth ||
        _indexedHeight < 0 ||
        height < _indexedHeight;
    final selected = selectedMatch;

    if (shouldScanAll) {
      _matchesByLine.clear();
      _scanLines(buffer, 0, height);
    } else {
      // A normal output batch appends from the previous tail. When the line
      // count is stable, rescan only the visible tail because TUIs rewrite
      // their viewport instead of the whole scrollback.
      final start = height > _indexedHeight
          ? max(0, _indexedHeight - 1)
          : max(0, height - _terminal.viewHeight);
      _removeMatchesInRange(buffer, start, height);
      _scanLines(buffer, start, height);
    }

    _indexedBuffer = buffer;
    _indexedHeight = height;
    _indexedWidth = _terminal.viewWidth;
    _needsFullRefresh = false;
    _rebuildMatches(selected);
    return true;
  }

  void _scanLines(xterm.Buffer buffer, int start, int end) {
    final safeStart = start.clamp(0, buffer.height);
    final safeEnd = end.clamp(safeStart, buffer.height);
    for (var index = safeStart; index < safeEnd; index++) {
      final line = buffer.lines[index];
      final lineMatches = findTerminalSearchMatches(<TerminalSearchLine>[
        TerminalSearchLine(id: line, index: index, text: line.getText()),
      ], _query);
      if (lineMatches.isEmpty) {
        _matchesByLine.remove(line);
      } else {
        _matchesByLine[line] = <_LineMatch>[
          for (final match in lineMatches)
            _LineMatch(start: match.start, end: match.end),
        ];
      }
    }
  }

  void _removeMatchesInRange(xterm.Buffer buffer, int start, int end) {
    final staleLines = <xterm.BufferLine>[];
    for (final line in _matchesByLine.keys) {
      if (!_lineIndex(buffer, line).caseInRange(start, end)) {
        continue;
      }
      staleLines.add(line);
    }
    for (final line in staleLines) {
      _matchesByLine.remove(line);
    }
  }

  void _rebuildMatches(TerminalSearchMatch? selected) {
    final next = <TerminalSearchMatch>[];
    final staleLines = <xterm.BufferLine>[];
    for (final entry in _matchesByLine.entries) {
      final lineIndex = _lineIndex(_terminal.buffer, entry.key);
      if (lineIndex == null) {
        staleLines.add(entry.key);
        continue;
      }
      for (final match in entry.value) {
        next.add(
          TerminalSearchMatch(
            lineId: entry.key,
            lineIndex: lineIndex,
            start: match.start,
            end: match.end,
          ),
        );
      }
    }
    for (final line in staleLines) {
      _matchesByLine.remove(line);
    }
    next.sort((a, b) {
      final lineOrder = a.lineIndex.compareTo(b.lineIndex);
      return lineOrder == 0 ? a.start.compareTo(b.start) : lineOrder;
    });
    _matches = List<TerminalSearchMatch>.unmodifiable(next);

    if (_matches.isEmpty) {
      _selectedIndex = -1;
      return;
    }
    if (selected != null) {
      final retainedIndex = _matches.indexWhere(
        (match) =>
            identical(match.lineId, selected.lineId) &&
            match.start == selected.start,
      );
      if (retainedIndex >= 0) {
        _selectedIndex = retainedIndex;
        return;
      }
    }
    _selectedIndex = _selectedIndex.clamp(0, _matches.length - 1);
  }

  int? _lineIndex(xterm.Buffer buffer, xterm.BufferLine line) {
    if (!line.attached) {
      return null;
    }
    final index = line.index;
    if (index < 0 || index >= buffer.height) {
      return null;
    }
    return identical(buffer.lines[index], line) ? index : null;
  }

  void _scrollSelectedMatch() {
    final match = selectedMatch;
    if (match != null) {
      _scrollToLine(match.lineIndex);
    }
  }

  @override
  void dispose() {
    _terminal.removeListener(_handleTerminalChanged);
    super.dispose();
  }
}

final class _LineMatch {
  const _LineMatch({required this.start, required this.end});

  final int start;
  final int end;
}

extension on int? {
  bool caseInRange(int start, int end) {
    final value = this;
    return value != null && value >= start && value < end;
  }
}
