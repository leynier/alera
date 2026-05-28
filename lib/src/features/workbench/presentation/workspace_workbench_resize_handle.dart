part of 'workspace_workbench_view.dart';

class _SplitResizeHandle extends StatefulWidget {
  const _SplitResizeHandle({required this.axis, required this.onRatioDelta});

  final WorkbenchSplitAxis axis;
  final ValueChanged<double> onRatioDelta;

  @override
  State<_SplitResizeHandle> createState() => _SplitResizeHandleState();
}

class _SplitResizeHandleState extends State<_SplitResizeHandle> {
  bool _hovered = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final horizontal = widget.axis == WorkbenchSplitAxis.horizontal;
    final lineColor = _dragging
        ? AleraTokens.accent
        : (_hovered ? AleraTokens.foregroundFaint : AleraTokens.border);
    return MouseRegion(
      cursor: horizontal
          ? SystemMouseCursors.resizeColumn
          : SystemMouseCursors.resizeRow,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => setState(() => _dragging = true),
        onPanUpdate: (details) {
          widget.onRatioDelta(horizontal ? details.delta.dx : details.delta.dy);
        },
        onPanEnd: (_) => _stopDragging(),
        onPanCancel: _stopDragging,
        child: SizedBox(
          width: horizontal ? AleraTokens.space6 : null,
          height: horizontal ? null : AleraTokens.space6,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              const ColoredBox(color: AleraTokens.surface),
              Positioned(
                left: horizontal ? AleraTokens.space2 : 0,
                right: horizontal ? AleraTokens.space2 : 0,
                top: horizontal ? 0 : AleraTokens.space2,
                bottom: horizontal ? 0 : AleraTokens.space2,
                child: AnimatedContainer(
                  duration: AleraTokens.durationFast,
                  color: lineColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _stopDragging() {
    setState(() => _dragging = false);
  }
}

class _WorkspaceTabDragData {
  const _WorkspaceTabDragData({
    required this.workspaceId,
    required this.sourceGroupId,
    required this.tabId,
  });

  final String workspaceId;
  final String sourceGroupId;
  final String tabId;
}

enum _PaneMenuAction { splitRight, splitDown, splitLeft, splitUp, closeSplit }

WorkspaceTabRecord? _activeTab(
  WorkbenchPaneGroup? group,
  List<WorkspaceTabRecord> tabs,
) {
  if (group == null || tabs.isEmpty) {
    return null;
  }
  for (final tab in tabs) {
    if (tab.id == group.activeTabId) {
      return tab;
    }
  }
  return tabs.first;
}
