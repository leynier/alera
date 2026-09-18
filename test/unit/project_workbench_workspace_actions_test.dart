import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_entry.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_submenu_entry.dart';
import 'package:alera/src/features/workbench/domain/workspace_section.dart';
import 'package:alera/src/features/workbench/presentation/project_workbench_sidebar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> _labels(List<PopupMenuEntry<String>> entries) {
  return <String>[
    for (final entry in entries)
      if (entry is AleraDropdownEntry<String>)
        entry.label
      else if (entry is AleraDropdownSubmenuEntry<String>)
        entry.label,
  ];
}

WorkspaceSection _section(String id) {
  final now = DateTime.utc(2026, 8, 30);
  return WorkspaceSection(id: id, name: id, createdAt: now, updatedAt: now);
}

void main() {
  test(
    'section actions follow Parent and Clear Section requires membership',
    () {
      final labels = _labels(
        workspaceContextMenuEntries(
          fileManagerLabel: 'Files',
          hasClearParent: true,
          canRemove: true,
          isPinned: true,
          supportsSections: true,
          hasSection: true,
          hasDescendants: true,
          hasTreeSection: true,
        ),
      );
      expect(
        labels.sublist(
          labels.indexOf('Pin Workspace Tree'),
          labels.indexOf('Clear Section Tree') + 1,
        ),
        [
          'Pin Workspace Tree',
          'Unpin Workspace Tree',
          'Manage Tags',
          'Set Parent Workspace',
          'Clear Parent Workspace',
          'Set Section',
          'Set Section Tree',
          'Clear Section',
          'Clear Section Tree',
        ],
      );
      final unassigned = _labels(
        workspaceContextMenuEntries(
          fileManagerLabel: 'Files',
          hasClearParent: false,
          canRemove: true,
          isPinned: false,
          supportsSections: true,
        ),
      );
      expect(unassigned, contains('Set Section'));
      expect(unassigned, isNot(contains('Set Section Tree')));
      expect(unassigned, isNot(contains('Clear Section')));
      expect(unassigned, isNot(contains('Clear Section Tree')));
      expect(unassigned, isNot(contains('Pin Workspace Tree')));
      expect(unassigned, isNot(contains('Unpin Workspace Tree')));
      final withTree = workspaceContextMenuEntries(
        fileManagerLabel: 'Files',
        hasClearParent: false,
        canRemove: true,
        isPinned: false,
        supportsSections: true,
        hasSection: true,
        hasDescendants: true,
        hasTreeSection: true,
      );
      expect(_leadingIcon(withTree, 'Set Section'), AleraIcons.section);
      expect(_leadingIcon(withTree, 'Set Section Tree'), AleraIcons.section);
      expect(_leadingIcon(withTree, 'Clear Section'), AleraIcons.sectionOff);
      expect(
        _leadingIcon(withTree, 'Clear Section Tree'),
        AleraIcons.sectionOff,
      );
    },
  );

  test('fewer than 10 sections use a submenu with New Section', () {
    final entries = workspaceContextMenuEntries(
      fileManagerLabel: 'Files',
      hasClearParent: false,
      canRemove: true,
      isPinned: false,
      supportsSections: true,
      hasDescendants: true,
      sections: <WorkspaceSection>[_section('Work'), _section('Review')],
      currentSectionId: 'Work',
    );
    final submenu = entries.whereType<AleraDropdownSubmenuEntry<String>>();
    expect(submenu.map((entry) => entry.label), <String>[
      'Set Section',
      'Set Section Tree',
    ]);
    expect(
      submenu.first.items.whereType<AleraDropdownEntry<String>>().map(
        (entry) => entry.label,
      ),
      <String>['Work', 'Review', 'New Section'],
    );
    expect(
      entries.whereType<AleraDropdownEntry<String>>().map(
        (entry) => entry.label,
      ),
      isNot(contains('Set Section')),
    );
  });

  test('10 or more sections keep the picker action', () {
    final entries = workspaceContextMenuEntries(
      fileManagerLabel: 'Files',
      hasClearParent: false,
      canRemove: true,
      isPinned: false,
      supportsSections: true,
      sections: <WorkspaceSection>[
        for (var i = 0; i < workspaceSectionSubmenuLimit; i++) _section('s$i'),
      ],
    );
    expect(entries.whereType<AleraDropdownSubmenuEntry<String>>(), isEmpty);
    expect(
      entries.whereType<AleraDropdownEntry<String>>().map(
        (entry) => entry.label,
      ),
      contains('Set Section'),
    );
    expect(_leadingIcon(entries, 'Set Section'), AleraIcons.section);
  });

  test('hand off and hand on are first-class workspace actions', () {
    expect(
      _labels(
        workspaceContextMenuEntries(
          fileManagerLabel: 'Files',
          hasClearParent: false,
          canRemove: false,
          isPinned: false,
          canHandOff: true,
        ),
      ),
      containsAll(['Hand Off', 'Workspace Recovery']),
    );
    expect(
      _labels(
        workspaceContextMenuEntries(
          fileManagerLabel: 'Files',
          hasClearParent: false,
          canRemove: true,
          isPinned: false,
          canHandOn: true,
        ),
      ),
      containsAll(['Hand On', 'Workspace Recovery']),
    );
  });

  test('workspace context menu places project settings with open actions', () {
    final entries = workspaceContextMenuEntries(
      fileManagerLabel: 'Files',
      hasClearParent: false,
      canRemove: true,
      isPinned: false,
    );

    expect(_labels(entries), <String>[
      'Rename',
      'Pin Workspace',
      'Manage Tags',
      'Set Parent Workspace',
      'Open in Browser',
      'Open in Files',
      'Open in Project Settings',
      'Copy Path',
      'Sleep',
      'Archive Workspace',
      'Remove',
    ]);
  });

  test('workspace context menu offers unarchive for archived workspaces', () {
    final entries = workspaceContextMenuEntries(
      fileManagerLabel: 'Files',
      hasClearParent: false,
      canRemove: true,
      isPinned: false,
      isArchived: true,
    );

    expect(_labels(entries), contains('Unarchive Workspace'));
    expect(_labels(entries), isNot(contains('Archive Workspace')));
    expect(_leadingIcon(entries, 'Unarchive Workspace'), AleraIcons.unarchive);
  });
}

IconData? _leadingIcon(List<PopupMenuEntry<String>> entries, String label) {
  for (final entry in entries) {
    final leading = switch (entry) {
      final AleraDropdownEntry<String> item when item.label == label =>
        item.leading,
      final AleraDropdownSubmenuEntry<String> item when item.label == label =>
        item.leading,
      _ => null,
    };
    if (leading is Icon) {
      return leading.icon;
    }
  }
  return null;
}
