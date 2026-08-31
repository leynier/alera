part of 'project_workbench_sidebar.dart';

extension _WorkspaceContextMenu on _WorkspaceRowState {
  Future<void> _showContextMenu(
    BuildContext context,
    Offset globalPosition,
  ) async {
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(globalPosition, globalPosition),
        Offset.zero & overlay.size,
      ),
      items: workspaceContextMenuEntries(
        fileManagerLabel: widget.fileManagerLabel,
        supportsSections: widget.onSetSection != null,
        hasSection: widget.onClearSection != null,
        hasClearParent: widget.onClearParent != null,
        canRemove: widget.onDelete != null,
        isPinned: widget.workspace.isPinned,
      ),
    );

    if (selected == _openProjectSettingsAction) {
      widget.onOpenProjectSettings();
    } else if (selected == _renameAction) {
      widget.onRename();
    } else if (selected == _togglePinAction) {
      widget.onSetPinned();
    } else if (selected == _pinWorkspaceTreeAction) {
      widget.onPinWorkspaceTree();
    } else if (selected == _unpinWorkspaceTreeAction) {
      widget.onUnpinWorkspaceTree();
    } else if (selected == _manageTagsAction) {
      widget.onManageTags();
    } else if (selected == _setSectionAction) {
      widget.onSetSection?.call();
    } else if (selected == _clearSectionAction) {
      widget.onClearSection?.call();
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
    } else if (selected == _removeAction) {
      widget.onDelete?.call();
    }
  }
}
