import 'package:alera/src/features/workbench/presentation/workspace_workbench_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveWorkbenchTabStripGapIndex', () {
    test('left half of the chip resolves to the chip index', () {
      expect(
        resolveWorkbenchTabStripGapIndex(
          chipIndex: 2,
          localDx: 10,
          chipWidth: 80,
        ),
        2,
      );
    });

    test('right half of the chip resolves to the next gap', () {
      expect(
        resolveWorkbenchTabStripGapIndex(
          chipIndex: 2,
          localDx: 70,
          chipWidth: 80,
        ),
        3,
      );
    });

    test('exact midpoint resolves to the next gap', () {
      expect(
        resolveWorkbenchTabStripGapIndex(
          chipIndex: 0,
          localDx: 40,
          chipWidth: 80,
        ),
        1,
      );
    });
  });

  group('resolveWorkbenchTabStripDropIndex', () {
    const tabIds = <String>['tab-1', 'tab-2', 'tab-3'];

    test('cross-group drops keep the gap index', () {
      for (final (gap, expected) in <(int, int)>[(0, 0), (2, 2), (3, 3)]) {
        expect(
          resolveWorkbenchTabStripDropIndex(
            tabIds: tabIds,
            sourceGroupId: 'group-b',
            targetGroupId: 'group-a',
            draggedTabId: 'tab-x',
            gapIndex: gap,
          ),
          expected,
        );
      }
    });

    test('cross-group drops clamp out-of-range gaps', () {
      expect(
        resolveWorkbenchTabStripDropIndex(
          tabIds: tabIds,
          sourceGroupId: 'group-b',
          targetGroupId: 'group-a',
          draggedTabId: 'tab-x',
          gapIndex: 9,
        ),
        3,
      );
    });

    test('same-group drag rightward adjusts for the removed tab', () {
      expect(
        resolveWorkbenchTabStripDropIndex(
          tabIds: tabIds,
          sourceGroupId: 'group-a',
          targetGroupId: 'group-a',
          draggedTabId: 'tab-1',
          gapIndex: 3,
        ),
        2,
      );
    });

    test('same-group drag leftward keeps the gap index', () {
      expect(
        resolveWorkbenchTabStripDropIndex(
          tabIds: tabIds,
          sourceGroupId: 'group-a',
          targetGroupId: 'group-a',
          draggedTabId: 'tab-3',
          gapIndex: 0,
        ),
        0,
      );
    });

    test('gaps around the source position are no-ops', () {
      for (final gap in <int>[1, 2]) {
        expect(
          resolveWorkbenchTabStripDropIndex(
            tabIds: tabIds,
            sourceGroupId: 'group-a',
            targetGroupId: 'group-a',
            draggedTabId: 'tab-2',
            gapIndex: gap,
          ),
          isNull,
        );
      }
    });

    test('single-tab group drops onto itself are no-ops', () {
      for (final gap in <int>[0, 1]) {
        expect(
          resolveWorkbenchTabStripDropIndex(
            tabIds: const <String>['tab-1'],
            sourceGroupId: 'group-a',
            targetGroupId: 'group-a',
            draggedTabId: 'tab-1',
            gapIndex: gap,
          ),
          isNull,
        );
      }
    });

    test('same-group drag with a stale tab id keeps the clamped gap', () {
      expect(
        resolveWorkbenchTabStripDropIndex(
          tabIds: tabIds,
          sourceGroupId: 'group-a',
          targetGroupId: 'group-a',
          draggedTabId: 'tab-gone',
          gapIndex: 5,
        ),
        3,
      );
    });
  });
}
