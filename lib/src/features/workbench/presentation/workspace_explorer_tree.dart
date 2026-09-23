part of 'workspace_explorer.dart';

extension _WorkspaceExplorerTree on _WorkspaceExplorerState {
  Widget _buildExpander(
    BuildContext context,
    tree.VisibleNode node,
    bool expanded,
    VoidCallback _,
  ) {
    return InkWell(
      onTap: () => unawaited(_toggleDirectory(node)),
      // InkWell defaults to adaptiveClickable, which is the basic arrow off the
      // web, so the hand cursor has to be requested explicitly here.
      mouseCursor: SystemMouseCursors.click,
      child: Icon(
        expanded ? AleraIcons.chevronDown : AleraIcons.chevronRight,
        size: 16,
        color: AleraTokens.foregroundMuted,
      ),
    );
  }

  Widget _buildNode(
    BuildContext context,
    tree.VisibleNode node,
    tree.NodeVisualState state,
  ) {
    final entry = _entryByNodeId[node.id];
    final selected = _controller.selection.isSelected(node.id);
    final child = _ExplorerRow(
      name: node.name,
      entry: entry,
      expanded: state.isExpanded,
      selected: selected,
      sourceControlRoot:
          entry != null &&
          entry.relativePath == widget.focusedSourceControlRoot,
      onTap: () => unawaited(_handlePrimaryTap(node)),
    );
    if (entry == null) {
      return child;
    }
    return DragTarget<_ExplorerDragData>(
      onWillAcceptWithDetails: (details) =>
          _canDrop(details.data, entry.relativePath),
      onAcceptWithDetails: (details) =>
          unawaited(_moveEntry(details.data.relativePath, entry.relativePath)),
      builder: (context, _, _) => TerminalPathDraggable<_ExplorerDragData>(
        data: _ExplorerDragData(
          relativePath: entry.relativePath,
          absolutePath: _absolutePath(entry.relativePath),
        ),
        feedback: Material(
          color: Colors.transparent,
          child: SizedBox(width: AleraTokens.sidebarDefaultWidth, child: child),
        ),
        child: child,
      ),
    );
  }
}
