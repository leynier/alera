import 'package:alera/src/features/workbench/domain/terminal_search.dart';
import 'package:alera/src/features/workbench/presentation/terminal_search_controller.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm2/xterm.dart' as xterm;

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

  test('folds output inside the refresh window into one refresh', () {
    fakeAsync((async) {
      final terminal = _terminal()..write('ready\r\n');
      final controller = TerminalSearchController(
        terminal: terminal,
        scrollToLine: (_) {},
      );
      var notifications = 0;
      controller
        ..open()
        ..setQuery('hit')
        ..addListener(() => notifications += 1);

      terminal.write('hit 1\r\n');
      expect(controller.matchCount, 1, reason: 'the first change is live');
      for (var index = 2; index <= 20; index += 1) {
        terminal.write('hit $index\r\n');
      }
      expect(controller.matchCount, 1);

      async.elapse(terminalSearchOutputRefreshInterval);

      expect(controller.matchCount, 20);
      expect(notifications, 2);
      controller.dispose();
    });
  });

  test('finds every new line once the scrollback stops growing', () {
    fakeAsync((async) {
      final terminal = xterm.Terminal(maxLines: 30)..resize(40, 5);
      for (var index = 0; index < 40; index += 1) {
        terminal.write('filler $index\r\n');
      }
      final controller = TerminalSearchController(
        terminal: terminal,
        scrollToLine: (_) {},
      );
      controller
        ..open()
        ..setQuery('needle');
      terminal.write('warm up\r\n');

      // More than a screen of matches lands inside one refresh window while
      // the line count is pinned at the scrollback cap.
      for (var index = 0; index < 12; index += 1) {
        terminal.write('needle $index\r\n');
      }
      async.elapse(terminalSearchOutputRefreshInterval);

      expect(controller.matchCount, 12);
      controller.dispose();
    });
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
