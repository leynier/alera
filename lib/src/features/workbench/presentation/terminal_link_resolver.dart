import 'dart:math' show min;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:xterm2/xterm.dart' as xterm;

final class const TerminalLinkRange({
  required final Uri uri,
  required final xterm.CellOffset start,
  required final xterm.CellOffset end,
}) {
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
}) {
  final osc8Link = _resolveNativeHyperlink(terminal, offset);
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

TerminalLinkRange? _resolveNativeHyperlink(
  xterm.Terminal terminal,
  xterm.CellOffset offset,
) {
  final buffer = terminal.buffer;
  if (offset.y < 0 ||
      offset.y >= buffer.lines.length ||
      offset.x < 0 ||
      offset.x >= buffer.viewWidth) {
    return null;
  }
  final target = terminal.hyperlinkAt(offset);
  final uri = target == null ? null : Uri.tryParse(target);
  if (!_supportsWebUri(uri)) return null;
  final id = terminal.hyperlinkIdAt(offset);
  var start = offset;
  var end = offset;
  while (true) {
    final previous = start.x > 0
        ? xterm.CellOffset(start.x - 1, start.y)
        : start.y > 0 && buffer.lines[start.y].isWrapped
        ? xterm.CellOffset(buffer.viewWidth - 1, start.y - 1)
        : null;
    if (previous == null || terminal.hyperlinkIdAt(previous) != id) break;
    start = previous;
  }
  while (true) {
    final next = end.x + 1 < buffer.viewWidth
        ? xterm.CellOffset(end.x + 1, end.y)
        : end.y + 1 < buffer.lines.length && buffer.lines[end.y + 1].isWrapped
        ? xterm.CellOffset(0, end.y + 1)
        : null;
    if (next == null || terminal.hyperlinkIdAt(next) != id) break;
    end = next;
  }
  return TerminalLinkRange(
    uri: uri!,
    start: start,
    end: xterm.CellOffset(end.x + 1, end.y),
  );
}

final class _LogicalTerminalLine({
  required final String text,
  required final List<_CharacterCellSpan> spans,
}) {
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
      // A resize can leave a wrapped row shorter than the current viewport.
      final segmentEnd = min(
        line.length,
        currentRow < endRow
            ? buffer.viewWidth
            : line.getTrimmedLength(buffer.viewWidth),
      );
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
        final span = _CharacterCellSpan(
          row: currentRow,
          startX: column,
          endXExclusive: column + width,
        );
        text.writeCharCode(codePoint);
        spans.add(span);
        // RegExp match offsets use UTF-16 code units, so both halves of an
        // astral code point must map back to the same terminal cell.
        if (codePoint > 0xffff) {
          spans.add(span);
        }
        final combining = line.getCombiningCharacters(column);
        if (combining != null) {
          text.write(combining);
          spans.addAll(List.filled(combining.length, span));
        }
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

final class const _CharacterCellSpan({
  required final int row,
  required final int startX,
  required final int endXExclusive,
}) {
  bool contains(xterm.CellOffset offset) {
    return offset.y == row && offset.x >= startX && offset.x < endXExclusive;
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
