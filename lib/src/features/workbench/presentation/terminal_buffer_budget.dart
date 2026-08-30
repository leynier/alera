import 'package:xterm2/xterm.dart' as xterm;

/// Bytes an xterm buffer holds for a given size.
///
/// xterm stores 4 `Uint32` per cell (16 bytes), so a fully scrolled 10000-line
/// terminal at 120 columns is around 19 MB. This is an estimate, not a
/// measurement: it ignores the capacity rounding in `BufferLine` and any
/// extended text. That is fine for ordering eviction candidates and holding a
/// ceiling, and it errs low, which the budget accounts for by evicting until
/// the estimate is under the limit rather than at it.
int estimateTerminalBufferBytes({required int lines, required int columns}) {
  if (lines <= 0 || columns <= 0) {
    return 0;
  }
  return lines * columns * _bytesPerCell;
}

const int _bytesPerCell = 16;

/// Actual typed-data storage retained by the terminal's cell buffers.
///
/// `BufferLine` rounds its capacity above the visible width and keeps that
/// allocation after a shrink. Reading the allocated lists makes the budget
/// account for both behaviors instead of systematically undercounting them.
int measureTerminalCellBufferBytes(xterm.Terminal terminal) {
  var bytes = 0;
  final lines = terminal.buffer.lines;
  for (var index = 0; index < lines.length; index += 1) {
    bytes += lines[index].data.lengthInBytes;
  }
  return bytes;
}

/// What one live terminal costs and when it was last on screen.
class TerminalBufferUsage {
  const TerminalBufferUsage({
    required this.tabId,
    required this.bytes,
    required this.lastVisibleAt,
  });

  final String tabId;
  final int bytes;

  /// Null for a handle that has never been visible, which makes it the first
  /// candidate: nobody is looking at it and nobody was.
  final DateTime? lastVisibleAt;
}

/// Picks which terminal buffers to drop so total memory stays under a ceiling.
///
/// Eviction detaches a session but never terminates its PTY, so the agent in
/// that terminal keeps running on the host and its scrollback is restored from
/// the host snapshot on return. That is what makes a memory ceiling affordable
/// at all.
class TerminalBufferBudget {
  const TerminalBufferBudget({required this.budgetBytes});

  /// Zero or negative means unbounded, matching the "no limit" setting.
  final int budgetBytes;

  bool get isUnbounded => budgetBytes <= 0;

  /// Least-recently-visible first, stopping as soon as the remaining total
  /// fits. Pinned tabs are never returned, so the real ceiling is this budget
  /// plus whatever the active workspace holds.
  List<String> selectEvictions({
    required Iterable<TerminalBufferUsage> live,
    required Set<String> pinnedTabIds,
  }) {
    if (isUnbounded) {
      return const <String>[];
    }
    var total = 0;
    final candidates = <TerminalBufferUsage>[];
    for (final usage in live) {
      total += usage.bytes;
      if (!pinnedTabIds.contains(usage.tabId)) {
        candidates.add(usage);
      }
    }
    if (total <= budgetBytes || candidates.isEmpty) {
      return const <String>[];
    }
    candidates.sort(_byLeastRecentlyVisible);
    final evicted = <String>[];
    for (final usage in candidates) {
      if (total <= budgetBytes) {
        break;
      }
      evicted.add(usage.tabId);
      total -= usage.bytes;
    }
    return evicted;
  }
}

int _byLeastRecentlyVisible(TerminalBufferUsage a, TerminalBufferUsage b) {
  final left = a.lastVisibleAt;
  final right = b.lastVisibleAt;
  if (left == null && right == null) {
    return a.tabId.compareTo(b.tabId);
  }
  // Never visible sorts first: nobody is looking at it and nobody was.
  if (left == null) {
    return -1;
  }
  if (right == null) {
    return 1;
  }
  final byTime = left.compareTo(right);
  return byTime != 0 ? byTime : a.tabId.compareTo(b.tabId);
}
