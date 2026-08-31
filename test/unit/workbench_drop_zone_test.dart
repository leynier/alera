import 'dart:ui';

import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:alera/src/features/workbench/presentation/workspace_workbench_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('workbench pane drop zones', () {
    test('resolve center and directional regions', () {
      const size = Size(300, 240);

      expect(
        resolveWorkbenchPaneDropZone(
          paneSize: size,
          localPosition: const Offset(150, 120),
        ),
        WorkbenchDropZone.center,
      );
      expect(
        resolveWorkbenchPaneDropZone(
          paneSize: size,
          localPosition: const Offset(80, 120),
        ),
        WorkbenchDropZone.left,
      );
      expect(
        resolveWorkbenchPaneDropZone(
          paneSize: size,
          localPosition: const Offset(220, 120),
        ),
        WorkbenchDropZone.right,
      );
      expect(
        resolveWorkbenchPaneDropZone(
          paneSize: size,
          localPosition: const Offset(150, 64),
        ),
        WorkbenchDropZone.up,
      );
      expect(
        resolveWorkbenchPaneDropZone(
          paneSize: size,
          localPosition: const Offset(150, 176),
        ),
        WorkbenchDropZone.down,
      );
    });

    test('resolve visible overlay geometry for each zone', () {
      const size = Size(300, 240);

      expect(
        resolveWorkbenchDropOverlayRect(zone: .left, paneSize: size),
        const Rect.fromLTWH(0, 0, 150, 240),
      );
      expect(
        resolveWorkbenchDropOverlayRect(zone: .right, paneSize: size),
        const Rect.fromLTWH(150, 0, 150, 240),
      );
      expect(
        resolveWorkbenchDropOverlayRect(zone: .up, paneSize: size),
        const Rect.fromLTWH(0, 0, 300, 120),
      );
      expect(
        resolveWorkbenchDropOverlayRect(zone: .down, paneSize: size),
        const Rect.fromLTWH(0, 120, 300, 120),
      );
      expect(
        resolveWorkbenchDropOverlayRect(zone: .center, paneSize: size),
        const Rect.fromLTWH(96, 72, 108, 96),
      );
    });

    test('suppress same-group no-op drops', () {
      expect(
        isWorkbenchPaneDropActionEnabled(
          sourceGroupId: 'group-a',
          targetGroupId: 'group-a',
          targetTabCount: 1,
          zone: .left,
        ),
        isFalse,
      );
      expect(
        isWorkbenchPaneDropActionEnabled(
          sourceGroupId: 'group-a',
          targetGroupId: 'group-a',
          targetTabCount: 3,
          zone: .center,
        ),
        isFalse,
      );
      expect(
        isWorkbenchPaneDropActionEnabled(
          sourceGroupId: 'group-a',
          targetGroupId: 'group-a',
          targetTabCount: 3,
          zone: .right,
        ),
        isTrue,
      );
      expect(
        isWorkbenchPaneDropActionEnabled(
          sourceGroupId: 'group-a',
          targetGroupId: 'group-b',
          targetTabCount: 1,
          zone: .center,
        ),
        isTrue,
      );
    });
  });
}
