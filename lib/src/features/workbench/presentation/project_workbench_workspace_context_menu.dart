part of 'project_workbench_sidebar.dart';

extension _WorkspaceContextMenu on _WorkspaceRowState {
  Future<void> _showContextMenu(
    BuildContext context,
    Offset globalPosition,
  ) async {
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final container = ProviderScope.containerOf(context, listen: false);
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(globalPosition, globalPosition),
        Offset.zero & overlay.size,
      ),
      items: workspaceContextMenuEntries(
        fileManagerLabel: widget.fileManagerLabel,
        supportsSections: widget.onSetSection != null,
        hasSection: widget.workspace.sectionId != null,
        hasClearParent: widget.onClearParent != null,
        canRemove: widget.onDelete != null,
        isPinned: widget.workspace.isPinned,
        isArchived: widget.workspace.isArchived,
        supportsArchive: widget.onToggleArchived != null,
        hasDescendants: widget.onPinWorkspaceTree != null,
        hasTreeSection: widget.hasTreeSection,
        sections: widget.sections,
        currentSectionId: widget.workspace.sectionId,
        canHandOff: widget.onHandOff != null,
        canHandOn: widget.onHandOn != null,
        linkedIssueEntries: linkedIssueMenuEntries(
          supported: container.read(linkedIssuesSupportedProvider),
          linkedIssue: container.read(
            workspaceLinkedIssueProvider(widget.workspace.id),
          ),
        ),
      ),
    );

    if (selected == _recoveryAction && context.mounted) {
      await showWorkspaceRecoveryFlow(context, widget.workspace);
    } else if (isLinkedIssueMenuAction(selected) && context.mounted) {
      launchLinkedIssueMenuAction(
        context,
        workspace: widget.workspace,
        action: selected!,
      );
    } else if (selected == _handOffAction) {
      widget.onHandOff?.call();
    } else if (selected == _handOnAction) {
      widget.onHandOn?.call();
    } else if (selected == _openProjectSettingsAction) {
      widget.onOpenProjectSettings();
    } else if (selected == _renameAction) {
      widget.onRename();
    } else if (selected == _togglePinAction) {
      widget.onSetPinned();
    } else if (selected == _pinWorkspaceTreeAction) {
      widget.onPinWorkspaceTree?.call();
    } else if (selected == _unpinWorkspaceTreeAction) {
      widget.onUnpinWorkspaceTree?.call();
    } else if (selected == _manageTagsAction) {
      widget.onManageTags();
    } else if (selected == _setSectionAction) {
      widget.onSetSection?.call(_SectionTarget.workspace, false);
    } else if (selected == _setSectionTreeAction) {
      widget.onSetSection?.call(_SectionTarget.tree, false);
    } else if (selected == _newSectionAction) {
      widget.onSetSection?.call(_SectionTarget.workspace, true);
    } else if (selected == _newSectionTreeAction) {
      widget.onSetSection?.call(_SectionTarget.tree, true);
    } else if (selected == _clearSectionAction) {
      widget.onClearSection?.call(_SectionTarget.workspace);
    } else if (selected == _clearSectionTreeAction) {
      widget.onClearSection?.call(_SectionTarget.tree);
    } else if (selected != null &&
        selected.startsWith(_assignSectionTreePrefix)) {
      widget.onAssignSection?.call(
        _SectionTarget.tree,
        selected.substring(_assignSectionTreePrefix.length),
      );
    } else if (selected != null && selected.startsWith(_assignSectionPrefix)) {
      widget.onAssignSection?.call(
        _SectionTarget.workspace,
        selected.substring(_assignSectionPrefix.length),
      );
    } else if (selected == _setParentAction) {
      widget.onSetParent();
    } else if (selected == _clearParentAction) {
      widget.onClearParent?.call();
    } else if (selected == _openFolderAction) {
      widget.onOpenFolder();
    } else if (selected == _copyPathAction) {
      widget.onCopyPath();
    } else if (selected == _openInBrowserAction) {
      widget.onOpenInBrowser();
    } else if (selected == _sleepAction) {
      widget.onSleep();
    } else if (selected == _archiveAction || selected == _unarchiveAction) {
      widget.onToggleArchived?.call();
    } else if (selected == _removeAction) {
      widget.onDelete?.call();
    }
  }
}
