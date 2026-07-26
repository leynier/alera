import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_focus_history.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:flutter_test/flutter_test.dart';

WorkspaceTabRecord _tab(String id) => WorkspaceTabRecord(
  id: id,
  workspaceId: 'workspace-1',
  title: id,
  createdAt: DateTime.utc(2026, 7, 26),
  updatedAt: DateTime.utc(2026, 7, 26),
);

void main() {
  group('WorkspaceTabFocusHistory', () {
    test('returns the most recent focus, most recent first', () {
      final history = WorkspaceTabFocusHistory();

      history.record('workspace-1', 'a');
      history.record('workspace-1', 'b');

      expect(history.mostRecentOpen('workspace-1', <String>{'a', 'b'}), 'b');
    });

    test('refocusing a tab moves it back to the front', () {
      final history = WorkspaceTabFocusHistory();

      history.record('workspace-1', 'a');
      history.record('workspace-1', 'b');
      history.record('workspace-1', 'a');

      expect(history.mostRecentOpen('workspace-1', <String>{'a', 'b'}), 'a');
    });

    test('skips remembered tabs that are no longer open', () {
      final history = WorkspaceTabFocusHistory();

      history.record('workspace-1', 'a');
      history.record('workspace-1', 'b');

      expect(history.mostRecentOpen('workspace-1', <String>{'a'}), 'a');
    });

    test('a workspace with no history at all reports none', () {
      expect(
        WorkspaceTabFocusHistory().mostRecentOpen('unknown', <String>{'a'}),
        isNull,
      );
    });

    test('a history whose tabs all closed reports none', () {
      final history = WorkspaceTabFocusHistory();
      history.record('workspace-1', 'a');

      expect(history.mostRecentOpen('workspace-1', <String>{'b'}), isNull);
      // The emptied workspace is dropped rather than left as an empty list.
      expect(history.mostRecentOpen('workspace-1', <String>{'a'}), isNull);
    });

    test('keeps only the most recent entries up to the limit', () {
      // The bound is what stops a long-lived session from growing the list
      // without end; the entries it drops are the oldest.
      final history = WorkspaceTabFocusHistory(limit: 2);

      history.record('workspace-1', 'a');
      history.record('workspace-1', 'b');
      history.record('workspace-1', 'c');

      expect(history.mostRecentOpen('workspace-1', <String>{'a', 'b'}), 'b');
    });

    test('forgetting a workspace drops its history', () {
      final history = WorkspaceTabFocusHistory();
      history.record('workspace-1', 'a');

      history.forget('workspace-1');

      expect(history.mostRecentOpen('workspace-1', <String>{'a'}), isNull);
    });
  });

  group('refocusMostRecentlyUsedTab', () {
    WorkbenchLayout layoutFor(List<String> tabIds) =>
        WorkbenchLayout.single(workspaceId: 'workspace-1', tabIds: tabIds);

    test('moves focus to the most recently used tab that survived', () {
      final history = WorkspaceTabFocusHistory();
      history.record('workspace-1', 'a');
      history.record('workspace-1', 'b');
      history.record('workspace-1', 'c');

      final layout = refocusMostRecentlyUsedTab(
        layout: layoutFor(<String>['a', 'b']),
        history: history,
        workspaceId: 'workspace-1',
        remaining: <WorkspaceTabRecord>[_tab('a'), _tab('b')],
      );

      expect(layout.activeTabId, 'b');
    });

    test('leaves the layout alone when nothing remembered is still open', () {
      final layout = layoutFor(<String>['a']);

      expect(
        refocusMostRecentlyUsedTab(
          layout: layout,
          history: WorkspaceTabFocusHistory(),
          workspaceId: 'workspace-1',
          remaining: <WorkspaceTabRecord>[_tab('a')],
        ),
        same(layout),
      );
    });

    test('leaves the layout alone when the tab is not in any group', () {
      // The history can name a tab the layout has already dropped; sanitize
      // has picked something by then and second-guessing it would be worse.
      final history = WorkspaceTabFocusHistory();
      history.record('workspace-1', 'ghost');
      final layout = layoutFor(<String>['a']);

      expect(
        refocusMostRecentlyUsedTab(
          layout: layout,
          history: history,
          workspaceId: 'workspace-1',
          remaining: <WorkspaceTabRecord>[_tab('a'), _tab('ghost')],
        ),
        same(layout),
      );
    });
  });
}
