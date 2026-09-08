import 'package:alera/src/design_system/menus/alera_dropdown_entry.dart';
import 'package:alera/src/features/workbench/presentation/project_workbench_sidebar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'section actions follow Parent and Clear Section requires membership',
    () {
      final labels =
          workspaceContextMenuEntries(
                fileManagerLabel: 'Files',
                hasClearParent: true,
                canRemove: true,
                isPinned: true,
                supportsSections: true,
                hasSection: true,
                hasDescendants: true,
              )
              .whereType<AleraDropdownEntry<String>>()
              .map((entry) => entry.label)
              .toList();
      expect(
        labels.sublist(
          labels.indexOf('Pin Workspace Tree'),
          labels.indexOf('Clear Section') + 1,
        ),
        [
          'Pin Workspace Tree',
          'Unpin Workspace Tree',
          'Manage Tags',
          'Set Parent Workspace',
          'Clear Parent Workspace',
          'Set Section',
          'Clear Section',
        ],
      );
      final unassigned = workspaceContextMenuEntries(
        fileManagerLabel: 'Files',
        hasClearParent: false,
        canRemove: true,
        isPinned: false,
        supportsSections: true,
      ).whereType<AleraDropdownEntry<String>>().map((entry) => entry.label);
      expect(unassigned, contains('Set Section'));
      expect(unassigned, isNot(contains('Clear Section')));
      expect(unassigned, isNot(contains('Pin Workspace Tree')));
      expect(unassigned, isNot(contains('Unpin Workspace Tree')));
    },
  );

  test('hand off and hand on are first-class workspace actions', () {
    expect(
      workspaceContextMenuEntries(
        fileManagerLabel: 'Files',
        hasClearParent: false,
        canRemove: false,
        isPinned: false,
        canHandOff: true,
      ).whereType<AleraDropdownEntry<String>>().map((entry) => entry.label),
      contains('Hand Off'),
    );
    expect(
      workspaceContextMenuEntries(
        fileManagerLabel: 'Files',
        hasClearParent: false,
        canRemove: true,
        isPinned: false,
        canHandOn: true,
      ).whereType<AleraDropdownEntry<String>>().map((entry) => entry.label),
      contains('Hand On'),
    );
  });

  test('workspace context menu places project settings with open actions', () {
    final entries = workspaceContextMenuEntries(
      fileManagerLabel: 'Files',
      hasClearParent: false,
      canRemove: true,
      isPinned: false,
    );

    expect(
      entries.whereType<AleraDropdownEntry<String>>().map(
        (entry) => entry.label,
      ),
      <String>[
        'Rename',
        'Pin Workspace',
        'Manage Tags',
        'Set Parent Workspace',
        'Open in Browser',
        'Open in Files',
        'Open in Project Settings',
        'Copy Path',
        'Sleep',
        'Remove',
      ],
    );
  });
}
