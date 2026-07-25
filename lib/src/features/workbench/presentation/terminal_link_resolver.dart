import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart' as xterm;

final class TerminalLinkRange {
  const TerminalLinkRange({
    required this.uri,
    required this.start,
    required this.end,
  });

  final Uri uri;
  final xterm.CellOffset start;
  final xterm.CellOffset end;

  bool get isEmpty => start == end;

  bool contains(xterm.CellOffset offset) {
    if (start.y == end.y) {
      return offset.y == start.y && offset.x >= start.x && offset.x < end.x;
    }
    if (offset.y < start.y || offset.y > end.y) {
      return false;
    }
    if (offset.y == start.y) {
      return offset.x >= start.x;
    }
    if (offset.y == end.y) {
      return offset.x < end.x;
    }
    return true;
  }

  @override
  bool operator ==(Object other) {
    return other is TerminalLinkRange &&
        other.uri == uri &&
        other.start == start &&
        other.end == end;
  }

  @override
  int get hashCode => Object.hash(uri, start, end);
}

TerminalLinkRange? resolveTerminalLinkAt({
  required xterm.Terminal terminal,
  required xterm.CellOffset offset,
  Osc8TerminalLinkTracker? osc8Tracker,
}) {
  final osc8Link = osc8Tracker?.linkAt(offset);
  if (osc8Link != null) {
    return osc8Link;
  }
  return resolveVisibleHttpLinkAt(terminal: terminal, offset: offset);
}

TerminalLinkRange? resolveVisibleHttpLinkAt({
  required xterm.Terminal terminal,
  required xterm.CellOffset offset,
}) {
  final logicalLine = _LogicalTerminalLine.fromBuffer(
    terminal.buffer,
    offset.y,
  );
  if (logicalLine == null) {
    return null;
  }
  final characterIndex = logicalLine.characterIndexAt(offset);
  if (characterIndex == null) {
    return null;
  }

  for (final match in _visibleHttpUrlPattern.allMatches(logicalLine.text)) {
    final matchEnd = _trimVisibleUrlMatchEnd(
      logicalLine.text,
      match.start,
      match.end,
    );
    if (matchEnd <= match.start) {
      continue;
    }
    if (characterIndex < match.start || characterIndex >= matchEnd) {
      continue;
    }
    final rawUri = logicalLine.text.substring(match.start, matchEnd);
    final uri = Uri.tryParse(rawUri);
    if (!_supportsWebUri(uri)) {
      continue;
    }
    final startSpan = logicalLine.spans[match.start];
    final endSpan = logicalLine.spans[matchEnd - 1];
    return TerminalLinkRange(
      uri: uri!,
      start: xterm.CellOffset(startSpan.startX, startSpan.row),
      end: xterm.CellOffset(endSpan.endXExclusive, endSpan.row),
    );
  }

  return null;
}

bool isTerminalLinkActivation({
  HardwareKeyboard? keyboard,
  TargetPlatform? platform,
}) {
  final resolvedKeyboard = keyboard ?? HardwareKeyboard.instance;
  final resolvedPlatform = platform ?? defaultTargetPlatform;
  return switch (resolvedPlatform) {
    TargetPlatform.macOS => resolvedKeyboard.isMetaPressed,
    TargetPlatform.android ||
    TargetPlatform.fuchsia ||
    TargetPlatform.iOS ||
    TargetPlatform.linux ||
    TargetPlatform.windows => resolvedKeyboard.isControlPressed,
  };
}

class Osc8TerminalLinkTracker {
  Osc8TerminalLinkTracker({required this._terminal});

  final xterm.Terminal _terminal;
  final List<_TrackedOsc8Link> _links = <_TrackedOsc8Link>[];
  _PendingOsc8Link? _activeLink;

  /// Links are only detached when their anchors scroll out of the buffer, so
  /// pruning on every close was O(n) per link and quadratic over a session
  /// with many hyperlinks. Prune on growth instead, which amortizes to O(1).
  int _nextPruneThreshold = _osc8LinkPruneFloor;

  void handlePrivateOsc(String code, List<String> args) {
    if (code != '8') {
      return;
    }
    final rawTarget = args.length >= 2 ? args[1].trim() : '';
    if (rawTarget.isEmpty) {
      _closeActiveLink();
      return;
    }
    final uri = Uri.tryParse(rawTarget);
    if (!_supportsWebUri(uri)) {
      _closeActiveLink();
      return;
    }
    _startLink(uri!);
  }

  TerminalLinkRange? linkAt(xterm.CellOffset offset) {
    _pruneDetachedLinks();
    for (final link in _links.reversed) {
      final materialized = link.materialize();
      if (materialized != null && materialized.contains(offset)) {
        return materialized;
      }
    }
    final activeLink = _activeLink;
    if (activeLink == null || !activeLink.attached) {
      return null;
    }
    final materialized = activeLink.materialize(_currentCursorOffset());
    if (materialized != null && materialized.contains(offset)) {
      return materialized;
    }
    return null;
  }

  void dispose() {
    _activeLink?.dispose();
    _activeLink = null;
    for (final link in _links) {
      link.dispose();
    }
    _links.clear();
  }

  void _startLink(Uri uri) {
    _closeActiveLink();
    _activeLink = _PendingOsc8Link(
      uri: uri,
      start: _terminal.buffer.createAnchorFromOffset(_currentCursorOffset()),
    );
  }

  void _closeActiveLink() {
    final activeLink = _activeLink;
    if (activeLink == null) {
      return;
    }
    final materialized = activeLink.materialize(_currentCursorOffset());
    final end = _terminal.buffer.createAnchorFromOffset(_currentCursorOffset());
    if (materialized != null && !materialized.isEmpty) {
      _links.add(
        _TrackedOsc8Link(
          uri: activeLink.uri,
          start: activeLink.start,
          end: end,
        ),
      );
    } else {
      end.dispose();
      activeLink.start.dispose();
    }
    _activeLink = null;
    _pruneDetachedLinks();
  }

  void _pruneDetachedLinks({bool force = false}) {
    if (!force && _links.length < _nextPruneThreshold) {
      return;
    }
    _links.removeWhere((link) {
      final keep = link.attached;
      if (!keep) {
        link.dispose();
      }
      return !keep;
    });
    final doubled = _links.length * 2;
    _nextPruneThreshold = doubled > _osc8LinkPruneFloor
        ? doubled
        : _osc8LinkPruneFloor;
  }

  xterm.CellOffset _currentCursorOffset() {
    final buffer = _terminal.buffer;
    final row = buffer.absoluteCursorY;
    final line = buffer.lines[row];
    // Why: xterm's public cursorX clamps to the last visible cell, which loses
    // the exclusive line-end position immediately after writing the last glyph.
    // Using the current line's trimmed length preserves OSC 8 boundaries at the
    // true end of the rendered link label.
    final x = line
        .getTrimmedLength(buffer.viewWidth)
        .clamp(0, buffer.viewWidth);
    return xterm.CellOffset(x, row);
  }
}

final class _LogicalTerminalLine {
  _LogicalTerminalLine({required this.text, required this.spans});

  final String text;
  final List<_CharacterCellSpan> spans;

  static _LogicalTerminalLine? fromBuffer(xterm.Buffer buffer, int row) {
    if (row < 0 || row >= buffer.lines.length) {
      return null;
    }

    var startRow = row;
    while (startRow > 0 && buffer.lines[startRow].isWrapped) {
      startRow -= 1;
    }

    var endRow = row;
    while (endRow < buffer.lines.length - 1 &&
        buffer.lines[endRow + 1].isWrapped) {
      endRow += 1;
    }

    final text = StringBuffer();
    final spans = <_CharacterCellSpan>[];
    for (var currentRow = startRow; currentRow <= endRow; currentRow += 1) {
      final line = buffer.lines[currentRow];
      final segmentEnd = currentRow < endRow
          ? buffer.viewWidth
          : line.getTrimmedLength(buffer.viewWidth);
      for (var column = 0; column < segmentEnd; column += 1) {
        final codePoint = line.getCodePoint(column);
        final width = line.getWidth(column);
        if (codePoint == 0) {
          if (column > 0 && line.getWidth(column - 1) == 2) {
            continue;
          }
          text.writeCharCode(0x20);
          spans.add(
            _CharacterCellSpan(
              row: currentRow,
              startX: column,
              endXExclusive: column + 1,
            ),
          );
          continue;
        }
        if (width < 1 || column + width > segmentEnd) {
          continue;
        }
        text.writeCharCode(codePoint);
        spans.add(
          _CharacterCellSpan(
            row: currentRow,
            startX: column,
            endXExclusive: column + width,
          ),
        );
      }
    }
    return _LogicalTerminalLine(text: text.toString(), spans: spans);
  }

  int? characterIndexAt(xterm.CellOffset offset) {
    for (var index = 0; index < spans.length; index += 1) {
      if (spans[index].contains(offset)) {
        return index;
      }
    }
    return null;
  }
}

final class _CharacterCellSpan {
  const _CharacterCellSpan({
    required this.row,
    required this.startX,
    required this.endXExclusive,
  });

  final int row;
  final int startX;
  final int endXExclusive;

  bool contains(xterm.CellOffset offset) {
    return offset.y == row && offset.x >= startX && offset.x < endXExclusive;
  }
}

final class _PendingOsc8Link {
  const _PendingOsc8Link({required this.uri, required this.start});

  final Uri uri;
  final xterm.CellAnchor start;

  bool get attached => start.attached;

  TerminalLinkRange? materialize(xterm.CellOffset end) {
    if (!attached) {
      return null;
    }
    final range = TerminalLinkRange(uri: uri, start: start.offset, end: end);
    return range.isEmpty ? null : range;
  }

  void dispose() {
    start.dispose();
  }
}

final class _TrackedOsc8Link {
  const _TrackedOsc8Link({
    required this.uri,
    required this.start,
    required this.end,
  });

  final Uri uri;
  final xterm.CellAnchor start;
  final xterm.CellAnchor end;

  bool get attached => start.attached && end.attached;

  TerminalLinkRange? materialize() {
    if (!attached) {
      return null;
    }
    final range = TerminalLinkRange(
      uri: uri,
      start: start.offset,
      end: end.offset,
    );
    return range.isEmpty ? null : range;
  }

  void dispose() {
    start.dispose();
    end.dispose();
  }
}

bool _supportsWebUri(Uri? uri) {
  if (uri == null || uri.host.trim().isEmpty) {
    return false;
  }
  return switch (uri.scheme.toLowerCase()) {
    'http' || 'https' => true,
    _ => false,
  };
}

int _trimVisibleUrlMatchEnd(String text, int start, int end) {
  var trimmedEnd = end;
  while (trimmedEnd > start) {
    final character = text[trimmedEnd - 1];
    if (_alwaysTrimmedTrailingUrlCharacters.contains(character)) {
      trimmedEnd -= 1;
      continue;
    }
    if (_isUnbalancedClosingCharacter(text, start, trimmedEnd, character)) {
      trimmedEnd -= 1;
      continue;
    }
    break;
  }
  return trimmedEnd;
}

bool _isUnbalancedClosingCharacter(
  String text,
  int start,
  int end,
  String trailingCharacter,
) {
  return switch (trailingCharacter) {
    ')' =>
      _countCharacter(text, start, end, '(') <
          _countCharacter(text, start, end, ')'),
    ']' =>
      _countCharacter(text, start, end, '[') <
          _countCharacter(text, start, end, ']'),
    '}' =>
      _countCharacter(text, start, end, '{') <
          _countCharacter(text, start, end, '}'),
    _ => false,
  };
}

int _countCharacter(String text, int start, int end, String character) {
  var count = 0;
  for (var index = start; index < end; index += 1) {
    if (text[index] == character) {
      count += 1;
    }
  }
  return count;
}

final RegExp _visibleHttpUrlPattern = RegExp(
  r'https?:\/\/[^\s]+',
  caseSensitive: false,
);

/// Below this many tracked links the O(n) sweep is cheap enough to skip the
/// growth heuristic entirely.
const int _osc8LinkPruneFloor = 64;

const Set<String> _alwaysTrimmedTrailingUrlCharacters = <String>{
  '.',
  ',',
  ';',
  ':',
  '!',
  '?',
  '"',
  "'",
};
