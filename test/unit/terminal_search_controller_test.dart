import 'package:alera/src/features/workbench/domain/terminal_search.dart';
import 'package:alera/src/features/workbench/presentation/terminal_search_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart' as xterm;

void main() {
  test('finds literal matches case-insensitively by default', () {
    final matches = findTerminalSearchMatches(const <TerminalSearchLine>[
      TerminalSearchLine(id: 'first', index: 3, text: 'A [literal] match'),
      TerminalSearchLine(id: 'second', index: 4, text: 'MATCH again'),
    ], '[literal]');

    expect(matches, hasLength(1));
    expect(matches.single.lineId, 'first');
    expect(matches.single.lineIndex, 3);
    expect(matches.single.start, 2);
    expect(matches.single.end, 11);
  });

  test('returns no results for an empty or missing query', () {
    const lines = <TerminalSearchLine>[
      TerminalSearchLine(id: 'line', index: 0, text: 'terminal output'),
    ];

    expect(findTerminalSearchMatches(lines, ''), isEmpty);
    expect(findTerminalSearchMatches(lines, 'missing'), isEmpty);
  });

  test('supports explicit case-sensitive matching', () {
    final matches = findTerminalSearchMatches(
      const <TerminalSearchLine>[
        TerminalSearchLine(id: 'line', index: 0, text: 'Match match'),
      ],
      'match',
      caseSensitive: true,
    );

    expect(matches, hasLength(1));
    expect(matches.single.start, 6);
  });

  test('navigates matches and wraps in both directions', () {
    final terminal = _terminal()..write('needle\r\nother\r\nNEEDLE\r\nthird');
    final visitedLines = <int>[];
    final controller = TerminalSearchController(
      terminal: terminal,
      scrollToLine: visitedLines.add,
    );
    addTearDown(controller.dispose);

    controller.open();
    controller.setQuery('needle');

    expect(controller.matchCount, 2);
    expect(controller.selectedMatchNumber, 1);
    expect(controller.selectedMatch?.lineIndex, 0);
    expect(visitedLines, <int>[0]);

    controller.next();
    expect(controller.selectedMatchNumber, 2);
    expect(controller.selectedMatch?.lineIndex, 2);

    controller.next();
    expect(controller.selectedMatchNumber, 1);
    expect(controller.selectedMatch?.lineIndex, 0);

    controller.previous();
    expect(controller.selectedMatchNumber, 2);
    expect(controller.selectedMatch?.lineIndex, 2);
  });

  test('updates matches after new output without rebuilding the query', () {
    final terminal = _terminal()..write('ready\r\n');
    final controller = TerminalSearchController(
      terminal: terminal,
      scrollToLine: (_) {},
    );
    addTearDown(controller.dispose);

    controller.open();
    controller.setQuery('result');
    expect(controller.matchCount, 0);

    terminal.write('new RESULT');

    expect(controller.matchCount, 1);
    expect(controller.selectedMatch?.lineIndex, 1);
    expect(controller.needsFullRefreshForTesting, isFalse);
  });

  test('releases the match index when the overlay closes', () {
    final terminal = _terminal()..write('needle\r\nother needle');
    final controller = TerminalSearchController(
      terminal: terminal,
      scrollToLine: (_) {},
    );
    addTearDown(controller.dispose);

    controller.open();
    controller.setQuery('needle');
    expect(controller.matchCount, 2);

    // Matches are one entry per scrollback hit; keeping them while the
    // overlay is hidden retains memory nobody can see.
    controller.close();
    expect(controller.matchCount, 0);
    expect(controller.selectedMatch, isNull);

    // Reopening rescans with the kept query, so nothing is lost.
    controller.open();
    expect(controller.matchCount, 2);
  });

  test('rechecks output that arrived while the overlay was closed', () {
    final terminal = _terminal()..write('first');
    final controller = TerminalSearchController(
      terminal: terminal,
      scrollToLine: (_) {},
    );
    addTearDown(controller.dispose);

    controller.open();
    controller.setQuery('later');
    expect(controller.matchCount, 0);

    controller.close();
    terminal.write('\r\nlater');
    controller.open();

    expect(controller.matchCount, 1);
    expect(controller.selectedMatch?.lineIndex, 1);
  });
}

xterm.Terminal _terminal() {
  return xterm.Terminal(maxLines: 64)..resize(80, 8);
}
