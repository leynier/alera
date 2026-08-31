part of 'workspace_workbench_view.dart';

@visibleForTesting
int resolveWorkbenchTabStripGapIndex({
  required int chipIndex,
  required double localDx,
  required double chipWidth,
}) {
  return localDx < chipWidth / 2 ? chipIndex : chipIndex + 1;
}

@visibleForTesting
int? resolveWorkbenchTabStripDropIndex({
  required List<String> tabIds,
  required String sourceGroupId,
  required String targetGroupId,
  required String draggedTabId,
  required int gapIndex,
}) {
  final clamped = gapIndex.clamp(0, tabIds.length);
  if (sourceGroupId != targetGroupId) {
    return clamped;
  }
  final sourceIndex = tabIds.indexOf(draggedTabId);
  if (sourceIndex < 0) {
    return clamped;
  }
  // The domain removes the dragged tab before inserting, so gaps to the
  // right of the source position shift left by one.
  final adjusted = clamped > sourceIndex ? clamped - 1 : clamped;
  return adjusted == sourceIndex ? null : adjusted;
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
