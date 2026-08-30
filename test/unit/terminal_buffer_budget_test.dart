import 'package:alera/src/features/workbench/presentation/terminal_buffer_budget.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm2/xterm.dart' as xterm;

const int _mb = 1024 * 1024;

TerminalBufferUsage _usage(
  String tabId, {
  required int megabytes,
  DateTime? lastVisibleAt,
}) {
  return TerminalBufferUsage(
    tabId: tabId,
    bytes: megabytes * _mb,
    lastVisibleAt: lastVisibleAt,
  );
}

void main() {
  group('estimateTerminalBufferBytes', () {
    test('scales with lines and columns at 16 bytes per cell', () {
      expect(estimateTerminalBufferBytes(lines: 10, columns: 4), 640);
      expect(estimateTerminalBufferBytes(lines: 20, columns: 4), 1280);
      expect(estimateTerminalBufferBytes(lines: 10, columns: 8), 1280);
    });

    test('a default terminal lands in the tens of megabytes', () {
      // The number that motivates the whole budget: 10000 lines at 120
      // columns is ~19 MB for a single terminal.
      final bytes = estimateTerminalBufferBytes(lines: 10000, columns: 120);
      expect(bytes ~/ _mb, inInclusiveRange(15, 25));
    });

    test('degenerate sizes cost nothing', () {
      expect(estimateTerminalBufferBytes(lines: 0, columns: 120), 0);
      expect(estimateTerminalBufferBytes(lines: 100, columns: 0), 0);
      expect(estimateTerminalBufferBytes(lines: -1, columns: -1), 0);
    });

    test('measures compacted history rows and full viewport rows', () {
      final terminal = xterm.Terminal(maxLines: 100);
      terminal.resize(120, 24);
      terminal.write(List<String>.filled(150, 'line\r\n').join());

      final lineCount = terminal.buffer.lines.length;
      final scrollBack = terminal.buffer.scrollBack;
      final bytes = measureTerminalCellBufferBytes(terminal);
      // History rows compact to their content ('line' is 4 cells); the
      // viewport keeps its rounded 128-cell allocation for in-place edits.
      expect(
        bytes,
        lessThan(lineCount * 128 * 16),
        reason: 'history rows release the slack blank capacity',
      );
      expect(
        bytes,
        greaterThanOrEqualTo((lineCount - scrollBack) * 128 * 16),
        reason: 'viewport rows keep their full allocation',
      );

      terminal.resize(80, 24);
      expect(
        measureTerminalCellBufferBytes(terminal),
        lessThanOrEqualTo(bytes),
        reason: 'a width resize re-compacts the rebuilt history rows',
      );
    });
  });

  group('TerminalBufferBudget', () {
    final now = DateTime.utc(2026, 7, 25, 12);

    test('evicts nothing while the total fits', () {
      const budget = TerminalBufferBudget(budgetBytes: 100 * _mb);

      expect(
        budget.selectEvictions(
          live: <TerminalBufferUsage>[
            _usage('a', megabytes: 20, lastVisibleAt: now),
            _usage('b', megabytes: 20, lastVisibleAt: now),
          ],
          pinnedTabIds: const <String>{},
        ),
        isEmpty,
      );
    });

    test('evicts least recently visible first, and only enough to fit', () {
      const budget = TerminalBufferBudget(budgetBytes: 50 * _mb);

      final evicted = budget.selectEvictions(
        live: <TerminalBufferUsage>[
          _usage('newest', megabytes: 20, lastVisibleAt: now),
          _usage(
            'oldest',
            megabytes: 20,
            lastVisibleAt: now.subtract(const Duration(hours: 2)),
          ),
          _usage(
            'middle',
            megabytes: 20,
            lastVisibleAt: now.subtract(const Duration(hours: 1)),
          ),
        ],
        pinnedTabIds: const <String>{},
      );

      // 60 MB over a 50 MB budget: dropping the oldest alone gets under it.
      expect(evicted, <String>['oldest']);
    });

    test('a handle that was never visible is the first candidate', () {
      const budget = TerminalBufferBudget(budgetBytes: 30 * _mb);

      final evicted = budget.selectEvictions(
        live: <TerminalBufferUsage>[
          _usage(
            'seen-long-ago',
            megabytes: 20,
            lastVisibleAt: now.subtract(const Duration(days: 1)),
          ),
          _usage('never-seen', megabytes: 20),
        ],
        pinnedTabIds: const <String>{},
      );

      expect(evicted, <String>['never-seen']);
    });

    test('never evicts a pinned tab, even when that leaves it over', () {
      // The active workspace is pinned, so the real ceiling is the budget plus
      // whatever it holds. This test states that tradeoff explicitly.
      const budget = TerminalBufferBudget(budgetBytes: 10 * _mb);

      final evicted = budget.selectEvictions(
        live: <TerminalBufferUsage>[
          _usage(
            'pinned',
            megabytes: 40,
            lastVisibleAt: now.subtract(const Duration(days: 1)),
          ),
          _usage('cold', megabytes: 5, lastVisibleAt: now),
        ],
        pinnedTabIds: const <String>{'pinned'},
      );

      expect(evicted, <String>['cold']);
    });

    test('evicts several when one is not enough', () {
      const budget = TerminalBufferBudget(budgetBytes: 25 * _mb);

      final evicted = budget.selectEvictions(
        live: <TerminalBufferUsage>[
          _usage(
            'a',
            megabytes: 20,
            lastVisibleAt: now.subtract(const Duration(hours: 3)),
          ),
          _usage(
            'b',
            megabytes: 20,
            lastVisibleAt: now.subtract(const Duration(hours: 2)),
          ),
          _usage('c', megabytes: 20, lastVisibleAt: now),
        ],
        pinnedTabIds: const <String>{},
      );

      expect(evicted, <String>['a', 'b']);
    });

    test('a zero budget means unbounded, not evict everything', () {
      const budget = TerminalBufferBudget(budgetBytes: 0);

      expect(budget.isUnbounded, isTrue);
      expect(
        budget.selectEvictions(
          live: <TerminalBufferUsage>[_usage('a', megabytes: 500)],
          pinnedTabIds: const <String>{},
        ),
        isEmpty,
      );
    });

    test('everything pinned means nothing to evict', () {
      const budget = TerminalBufferBudget(budgetBytes: 1);

      expect(
        budget.selectEvictions(
          live: <TerminalBufferUsage>[_usage('a', megabytes: 40)],
          pinnedTabIds: const <String>{'a'},
        ),
        isEmpty,
      );
    });
  });
}
