part of 'workspace_workbench_view.dart';

@visibleForTesting
int resolveWorkbenchTabStripGapIndex({
  required int chipIndex,
  required double localDx,
  required double chipWidth,
}) {
  return drop_zones.resolveWorkbenchTabStripGapIndex(
    chipIndex: chipIndex,
    localDx: localDx,
    chipWidth: chipWidth,
  );
}

@visibleForTesting
int? resolveWorkbenchTabStripDropIndex({
  required List<String> tabIds,
  required String sourceGroupId,
  required String targetGroupId,
  required String draggedTabId,
  required int gapIndex,
}) {
  return drop_zones.resolveWorkbenchTabStripDropIndex(
    tabIds: tabIds,
    sourceGroupId: sourceGroupId,
    targetGroupId: targetGroupId,
    draggedTabId: draggedTabId,
    gapIndex: gapIndex,
  );
}

typedef _TabStripGapDragCallback = void Function(
  _WorkspaceTabDragData data,
  int gapIndex,
);

class const _TabStripChipDropTarget({
  required final int chipIndex,
  required final String workspaceId,
  required final bool showLeadingIndicator,
  required final bool showTrailingIndicator,
  required final _TabStripGapDragCallback onHoverGap,
  required final VoidCallback onLeave,
  required final _TabStripGapDragCallback onDropGap,
  required final Widget child,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DragTarget<_WorkspaceTabDragData>(
      onWillAcceptWithDetails: (details) =>
          details.data.workspaceId == workspaceId,
      onMove: (details) =>
          _reportGap(context, details.data, details.offset, onHoverGap),
      onLeave: (_) => onLeave(),
      onAcceptWithDetails: (details) =>
          _reportGap(context, details.data, details.offset, onDropGap),
      builder: (context, _, _) {
        return Stack(
          clipBehavior: .none,
          children: <Widget>[
            child,
            if (showLeadingIndicator)
              const Positioned(
                left: -(AleraTokens.space8 + AleraTokens.space2) / 2,
                top: 0,
                bottom: 0,
                width: AleraTokens.space2,
                child: _TabStripInsertionIndicator(),
              ),
            if (showTrailingIndicator)
              const Positioned(
                right: (AleraTokens.space8 - AleraTokens.space2) / 2,
                top: 0,
                bottom: 0,
                width: AleraTokens.space2,
                child: _TabStripInsertionIndicator(),
              ),
          ],
        );
      },
    );
  }

  void _reportGap(
    BuildContext context,
    _WorkspaceTabDragData data,
    Offset globalOffset,
    _TabStripGapDragCallback callback,
  ) {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return;
    }
    final local = renderObject.globalToLocal(globalOffset);
    callback(
      data,
      resolveWorkbenchTabStripGapIndex(
        chipIndex: chipIndex,
        localDx: local.dx,
        chipWidth: renderObject.size.width,
      ),
    );
  }
}

class const _TabStripAppendDropTarget({
  required final String workspaceId,
  required final int tabCount,
  required final _TabStripGapDragCallback onHoverGap,
  required final VoidCallback onLeave,
  required final _TabStripGapDragCallback onDropGap,
  required final Widget child,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DragTarget<_WorkspaceTabDragData>(
      onWillAcceptWithDetails: (details) =>
          details.data.workspaceId == workspaceId,
      onMove: (details) => onHoverGap(details.data, tabCount),
      onLeave: (_) => onLeave(),
      onAcceptWithDetails: (details) => onDropGap(details.data, tabCount),
      builder: (context, _, _) => child,
    );
  }
}

class const _TabStripInsertionIndicator() extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      key: ValueKey<String>('tab-strip-insertion-indicator'),
      decoration: BoxDecoration(
        color: AleraTokens.accent,
        borderRadius: BorderRadius.all(.circular(AleraTokens.radiusSm)),
      ),
    );
  }
}
