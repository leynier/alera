part of 'project_workbench_sidebar.dart';

const String _renameAction = 'rename';
const String _openProjectSettingsAction = 'open-project-settings';
const String _openFolderAction = 'open-folder';
const String _copyPathAction = 'copy-path';
const String _openInBrowserAction = 'open-in-browser';
const String _sleepAction = 'sleep';
const String _archiveAction = 'archive';
const String _unarchiveAction = 'unarchive';
const String _manageTagsAction = 'manage-tags';
const String _togglePinAction = 'toggle-pin';
const String _pinWorkspaceTreeAction = 'pin-workspace-tree';
const String _unpinWorkspaceTreeAction = 'unpin-workspace-tree';
const String _setParentAction = 'set-parent';
const String _clearParentAction = 'clear-parent';
const String _setSectionAction = 'set-section';
const String _setSectionTreeAction = 'set-section-tree';
const String _clearSectionAction = 'clear-section';
const String _clearSectionTreeAction = 'clear-section-tree';
const String _newSectionAction = 'new-section';
const String _newSectionTreeAction = 'new-section-tree';
const String _assignSectionPrefix = 'assign-section:';
const String _assignSectionTreePrefix = 'assign-section-tree:';
const String _removeAction = 'remove';
const String _handOffAction = 'hand-off';
const String _handOnAction = 'hand-on';
const String _recoveryAction = 'workspace-recovery';

/// Inline section lists stay in the context menu below this count.
const int workspaceSectionSubmenuLimit = 10;

const PopupMenuDivider _workspaceMenuDivider = PopupMenuDivider(
  height: AleraTokens.space8,
);

/// Builds the right-click menu entries for a workspace row. [hasClearParent]
/// gates the "Clear Parent Workspace" item and [canRemove] disables the remove
/// action for the main (non-deletable) workspace.
List<PopupMenuEntry<String>> workspaceContextMenuEntries({
  required String fileManagerLabel,
  bool supportsSections = false,
  bool hasSection = false,
  required bool hasClearParent,
  required bool canRemove,
  required bool isPinned,
  bool hasDescendants = false,
  bool isArchived = false,
  bool supportsArchive = true,
  bool hasTreeSection = false,
  List<WorkspaceSection> sections = const <WorkspaceSection>[],
  String? currentSectionId,
  bool canHandOff = false,
  bool canHandOn = false,
  List<PopupMenuEntry<String>> linkedIssueEntries =
      const <PopupMenuEntry<String>>[],
}) {
  final pairing = <PopupMenuEntry<String>>[
    if (canHandOff)
      const AleraDropdownEntry<String>(
        value: _handOffAction,
        leading: Icon(AleraIcons.gitFork, size: 16),
        label: 'Hand Off',
      ),
    if (canHandOn)
      const AleraDropdownEntry<String>(
        value: _handOnAction,
        leading: Icon(AleraIcons.workspaceMain, size: 16),
        label: 'Hand On',
      ),
    if (canHandOff || canHandOn)
      const AleraDropdownEntry<String>(
        value: _recoveryAction,
        label: 'Workspace Recovery',
      ),
  ];
  return <PopupMenuEntry<String>>[
    const AleraDropdownEntry<String>(
      value: _renameAction,
      leading: Icon(AleraIcons.edit, size: 16),
      label: 'Rename',
    ),
    _workspaceMenuDivider,
    ...pairing,
    if (pairing.isNotEmpty) _workspaceMenuDivider,
    _pinMenuEntry(isPinned: isPinned, hasDescendants: hasDescendants),
    _parentMenuEntry(hasClearParent: hasClearParent),
    if (supportsSections)
      _sectionMenuEntry(
        hasSection: hasSection,
        hasDescendants: hasDescendants,
        hasTreeSection: hasTreeSection,
        sections: sections,
        currentSectionId: currentSectionId,
      ),
    const AleraDropdownEntry<String>(
      value: _manageTagsAction,
      leading: Icon(AleraIcons.tag, size: 16),
      label: 'Manage Tags',
    ),
    _workspaceMenuDivider,
    ...linkedIssueEntries,
    if (linkedIssueEntries.isNotEmpty) _workspaceMenuDivider,
    _openMenuEntry(fileManagerLabel: fileManagerLabel),
    const AleraDropdownEntry<String>(
      value: _copyPathAction,
      leading: Icon(AleraIcons.copy, size: 16, color: AleraTokens.foreground),
      label: 'Copy Path',
    ),
    _workspaceMenuDivider,
    const AleraDropdownEntry<String>(
      value: _sleepAction,
      leading: Icon(AleraIcons.theme, size: 16, color: AleraTokens.foreground),
      label: 'Sleep',
    ),
    if (supportsArchive)
      AleraDropdownEntry<String>(
        value: isArchived ? _unarchiveAction : _archiveAction,
        leading: Icon(
          isArchived ? AleraIcons.unarchive : AleraIcons.archive,
          size: 16,
          color: AleraTokens.foreground,
        ),
        label: isArchived ? 'Unarchive' : 'Archive',
      ),
    AleraDropdownEntry<String>(
      value: _removeAction,
      leading: Icon(
        AleraIcons.delete,
        size: 16,
        color: canRemove ? AleraTokens.foreground : AleraTokens.foregroundFaint,
      ),
      label: 'Remove',
      enabled: canRemove,
    ),
  ];
}

PopupMenuEntry<String> _pinMenuEntry({
  required bool isPinned,
  required bool hasDescendants,
}) {
  final toggle = AleraDropdownEntry<String>(
    value: _togglePinAction,
    leading: Icon(isPinned ? AleraIcons.pinOff : AleraIcons.pin, size: 16),
    label: isPinned ? 'Unpin Workspace' : 'Pin Workspace',
  );
  if (!hasDescendants) {
    return toggle;
  }
  return AleraDropdownSubmenuEntry<String>(
    leading: Icon(isPinned ? AleraIcons.pinOff : AleraIcons.pin, size: 16),
    label: 'Pin',
    items: <PopupMenuEntry<String>>[
      toggle,
      const AleraDropdownEntry<String>(
        value: _pinWorkspaceTreeAction,
        leading: Icon(AleraIcons.pin, size: 16),
        label: 'Pin Workspace Tree',
      ),
      const AleraDropdownEntry<String>(
        value: _unpinWorkspaceTreeAction,
        leading: Icon(AleraIcons.pinOff, size: 16),
        label: 'Unpin Workspace Tree',
      ),
    ],
  );
}

PopupMenuEntry<String> _parentMenuEntry({required bool hasClearParent}) {
  const setParent = AleraDropdownEntry<String>(
    value: _setParentAction,
    leading: Icon(AleraIcons.link, size: 16),
    label: 'Set Parent Workspace',
  );
  if (!hasClearParent) {
    return setParent;
  }
  return const AleraDropdownSubmenuEntry<String>(
    leading: Icon(AleraIcons.link, size: 16),
    label: 'Parent',
    items: <PopupMenuEntry<String>>[
      setParent,
      AleraDropdownEntry<String>(
        value: _clearParentAction,
        leading: Icon(AleraIcons.close, size: 16),
        label: 'Clear Parent Workspace',
      ),
    ],
  );
}

PopupMenuEntry<String> _sectionMenuEntry({
  required bool hasSection,
  required bool hasDescendants,
  required bool hasTreeSection,
  required List<WorkspaceSection> sections,
  required String? currentSectionId,
}) {
  const leading = Icon(AleraIcons.section, size: 16);
  final items = <PopupMenuEntry<String>>[
    ..._sectionAssignmentItems(
      tree: false,
      sections: sections,
      currentSectionId: currentSectionId,
    ),
    if (hasSection)
      const AleraDropdownEntry<String>(
        value: _clearSectionAction,
        leading: Icon(AleraIcons.sectionOff, size: 16),
        label: 'Clear Section',
      ),
  ];
  if (hasDescendants) {
    items.addAll(<PopupMenuEntry<String>>[
      _workspaceMenuDivider,
      AleraDropdownSubmenuEntry<String>(
        leading: leading,
        label: 'Apply to Tree',
        items: <PopupMenuEntry<String>>[
          ..._sectionAssignmentItems(
            tree: true,
            sections: sections,
            currentSectionId: currentSectionId,
          ),
          if (hasTreeSection)
            const AleraDropdownEntry<String>(
              value: _clearSectionTreeAction,
              leading: Icon(AleraIcons.sectionOff, size: 16),
              label: 'Clear Section Tree',
            ),
        ],
      ),
    ]);
  }
  if (items case [final AleraDropdownEntry<String> only]
      when only.value == _setSectionAction) {
    return only;
  }
  return AleraDropdownSubmenuEntry<String>(
    leading: leading,
    label: 'Section',
    items: items,
  );
}

List<PopupMenuEntry<String>> _sectionAssignmentItems({
  required bool tree,
  required List<WorkspaceSection> sections,
  required String? currentSectionId,
}) {
  if (sections.length >= workspaceSectionSubmenuLimit) {
    return <PopupMenuEntry<String>>[
      AleraDropdownEntry<String>(
        value: tree ? _setSectionTreeAction : _setSectionAction,
        leading: const Icon(AleraIcons.section, size: 16),
        label: tree ? 'Set Section Tree' : 'Set Section',
      ),
    ];
  }
  return _sectionChoiceEntries(
    sections: sections,
    currentSectionId: currentSectionId,
    tree: tree,
  );
}

List<PopupMenuEntry<String>> _sectionChoiceEntries({
  required List<WorkspaceSection> sections,
  required String? currentSectionId,
  required bool tree,
}) {
  return <PopupMenuEntry<String>>[
    for (final section in sections)
      AleraDropdownEntry<String>(
        value:
            '${tree ? _assignSectionTreePrefix : _assignSectionPrefix}${section.id}',
        label: section.name,
        selected: section.id == currentSectionId,
      ),
    if (sections.isNotEmpty) _workspaceMenuDivider,
    AleraDropdownEntry<String>(
      value: tree ? _newSectionTreeAction : _newSectionAction,
      leading: const Icon(AleraIcons.add, size: 16),
      label: 'New Section',
    ),
  ];
}

PopupMenuEntry<String> _openMenuEntry({required String fileManagerLabel}) {
  return AleraDropdownSubmenuEntry<String>(
    leading: const Icon(
      AleraIcons.external,
      size: 16,
      color: AleraTokens.foreground,
    ),
    label: 'Open',
    items: <PopupMenuEntry<String>>[
      const AleraDropdownEntry<String>(
        value: _openInBrowserAction,
        leading: Icon(
          AleraIcons.external,
          size: 16,
          color: AleraTokens.foreground,
        ),
        label: 'In Browser',
      ),
      AleraDropdownEntry<String>(
        value: _openFolderAction,
        leading: const Icon(
          AleraIcons.folderOpen,
          size: 16,
          color: AleraTokens.foreground,
        ),
        label: 'In $fileManagerLabel',
      ),
      const AleraDropdownEntry<String>(
        value: _openProjectSettingsAction,
        leading: Icon(AleraIcons.settings, size: 16),
        label: 'In Project Settings',
      ),
    ],
  );
}
