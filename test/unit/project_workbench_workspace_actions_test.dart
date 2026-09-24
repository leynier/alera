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

AleraDropdownSubmenuEntry<String>? _submenu(
  List<PopupMenuEntry<String>> entries,
  String label,
) {
  for (final entry in entries) {
    if (entry is AleraDropdownSubmenuEntry<String> && entry.label == label) {
      return entry;
    }
  }
  return null;
}

WorkspaceSection _section(String id) {
  final now = DateTime.utc(2026, 8, 30);
  return WorkspaceSection(id: id, name: id, createdAt: now, updatedAt: now);
}

void main() {
  test('organize families nest variants and keep tags after section', () {
    final entries = workspaceContextMenuEntries(
      fileManagerLabel: 'Files',
      hasClearParent: true,
      canRemove: true,
      isPinned: true,
      supportsSections: true,
      hasSection: true,
      hasDescendants: true,
      hasTreeSection: true,
      sections: <WorkspaceSection>[_section('Work'), _section('Review')],
      currentSectionId: 'Work',
    );
    expect(_labels(entries).sublist(1, 6), <String>[
      'Pin',
      'Parent',
      'Section',
      'Manage Tags',
      'Open',
    ]);
    expect(_labels(_submenu(entries, 'Pin')!.items), <String>[
      'Unpin Workspace',
      'Pin Workspace Tree',
      'Unpin Workspace Tree',
    ]);
    expect(_labels(_submenu(entries, 'Parent')!.items), <String>[
      'Set Parent Workspace',
      'Clear Parent Workspace',
    ]);
    final section = _submenu(entries, 'Section')!;
    expect(_labels(section.items), <String>[
      'Work',
      'Review',
      'New Section',
      'Clear Section',
      'Apply to Tree',
    ]);
    expect(_labels(_submenu(section.items, 'Apply to Tree')!.items), <String>[
      'Work',
      'Review',
      'New Section',
      'Clear Section Tree',
    ]);
    expect(_labels(_submenu(entries, 'Open')!.items), <String>[
      'In Browser',
      'In Files',
      'In Project Settings',
    ]);
    expect(_leadingIcon(entries, 'Section'), AleraIcons.section);
    expect(_leadingIcon(section.items, 'Clear Section'), AleraIcons.sectionOff);
  });

  test('leaves omit tree and clear actions', () {
    final unassigned = _labels(
      workspaceContextMenuEntries(
        fileManagerLabel: 'Files',
        hasClearParent: false,
        canRemove: true,
        isPinned: false,
        supportsSections: true,
      ),
    );
    expect(unassigned, contains('Section'));
    expect(unassigned, contains('Pin Workspace'));
    expect(unassigned, contains('Set Parent Workspace'));
    expect(unassigned, isNot(contains('Pin')));
    expect(unassigned, isNot(contains('Parent')));
    expect(unassigned, isNot(contains('Apply to Tree')));
    expect(unassigned, isNot(contains('Clear Section')));
    expect(unassigned, isNot(contains('Pin Workspace Tree')));
  });

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
    final section = _submenu(entries, 'Section')!;
    expect(_labels(section.items).take(3), <String>[
      'Work',
      'Review',
      'New Section',
    ]);
    expect(_submenu(section.items, 'Apply to Tree'), isNotNull);
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
    expect(_submenu(entries, 'Section'), isNull);
    expect(
      entries.whereType<AleraDropdownEntry<String>>().map(
        (entry) => entry.label,
      ),
      contains('Set Section'),
    );
    expect(_leadingIcon(entries, 'Set Section'), AleraIcons.section);
  });

  test('hand off and hand on are first-class workspace actions', () {
    final handOff = workspaceContextMenuEntries(
      fileManagerLabel: 'Files',
      hasClearParent: false,
      canRemove: false,
      isPinned: false,
      canHandOff: true,
    );
    expect(_labels(handOff), containsAll(['Hand Off', 'Recovery']));
    expect(_leadingIcon(handOff, 'Recovery'), AleraIcons.restore);
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
      containsAll(['Hand On', 'Recovery']),
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
      'Set Parent Workspace',
      'Manage Tags',
      'Open',
      'Copy Path',
      'Sleep',
      'Archive',
      'Remove',
    ]);
    expect(_labels(_submenu(entries, 'Open')!.items), <String>[
      'In Browser',
      'In Files',
      'In Project Settings',
    ]);
  });

  test('workspace context menu omits archive when unsupported', () {
    final entries = workspaceContextMenuEntries(
      fileManagerLabel: 'Files',
      hasClearParent: false,
      canRemove: true,
      isPinned: false,
      supportsArchive: false,
    );

    expect(_labels(entries), contains('Sleep'));
    expect(_labels(entries), isNot(contains('Archive')));
    expect(_labels(entries), contains('Remove'));
  });

  test('workspace context menu offers unarchive for archived workspaces', () {
    final entries = workspaceContextMenuEntries(
      fileManagerLabel: 'Files',
      hasClearParent: false,
      canRemove: true,
      isPinned: false,
      isArchived: true,
    );

    expect(_labels(entries), contains('Unarchive'));
    expect(_labels(entries), isNot(contains('Archive')));
    expect(_leadingIcon(entries, 'Unarchive'), AleraIcons.unarchive);
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
