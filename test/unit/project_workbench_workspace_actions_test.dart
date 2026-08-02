import 'package:alera/src/design_system/menus/alera_dropdown_entry.dart';
import 'package:alera/src/features/workbench/presentation/project_workbench_sidebar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
