/// A line of terminal text that can be searched without retaining the whole
/// terminal buffer as a second string.
final class TerminalSearchLine {
  const TerminalSearchLine({
    required this.id,
    required this.index,
    required this.text,
  });

  final Object id;
  final int index;
  final String text;
}

/// A literal occurrence in one terminal buffer line.
final class TerminalSearchMatch {
  const TerminalSearchMatch({
    required this.lineId,
    required this.lineIndex,
    required this.start,
    required this.end,
  });

  final Object lineId;
  final int lineIndex;
  final int start;
  final int end;
}

/// Finds non-overlapping literal matches in [lines].
///
/// Terminal search is case-insensitive by default. Regex syntax is never
/// interpreted, so a query such as `[` is searched literally.
List<TerminalSearchMatch> findTerminalSearchMatches(
  Iterable<TerminalSearchLine> lines,
  String query, {
  bool caseSensitive = false,
}) {
  if (query.isEmpty) {
    return const <TerminalSearchMatch>[];
  }

  final needle = caseSensitive ? query : query.toLowerCase();
  final matches = <TerminalSearchMatch>[];
  for (final line in lines) {
    final haystack = caseSensitive ? line.text : line.text.toLowerCase();
    var start = 0;
    while (start < haystack.length) {
      final matchStart = haystack.indexOf(needle, start);
      if (matchStart < 0) {
        break;
      }
      matches.add(
        TerminalSearchMatch(
          lineId: line.id,
          lineIndex: line.index,
          start: matchStart,
          end: matchStart + needle.length,
        ),
      );
      start = matchStart + needle.length;
    }
  }
  return matches;
}
