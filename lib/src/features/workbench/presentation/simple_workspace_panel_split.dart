part of 'simple_workspace_panel_view.dart';

class const _SimplePanelSplitLayout({
  required final WorkbenchSplitAxis axis,
  required final double persistedRatio,
  required final Widget first,
  required final Widget second,
  required final ValueChanged<double> onPersistRatio,
}) extends StatefulWidget {
  @override
  State<_SimplePanelSplitLayout> createState() =>
      _SimplePanelSplitLayoutState();
}

class _SimplePanelSplitLayoutState extends State<_SimplePanelSplitLayout> {
  double? _transientRatio;

  double get _ratio => _transientRatio ?? widget.persistedRatio;

  @override
  void didUpdateWidget(covariant _SimplePanelSplitLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_transientRatio != null &&
        (widget.persistedRatio - _transientRatio!).abs() < 0.0001) {
      _transientRatio = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = widget.axis == WorkbenchSplitAxis.horizontal;
        final available = horizontal
            ? constraints.maxWidth
            : constraints.maxHeight;
        final handleExtent = AleraTokens.space8;
        final contentExtent = available.isFinite
            ? math.max(0.0, available - handleExtent)
            : 0.0;
        final firstExtent = contentExtent * _ratio;
        final secondExtent = contentExtent - firstExtent;
        return Flex(
          direction: horizontal ? Axis.horizontal : Axis.vertical,
          children: <Widget>[
            SizedBox(
              width: horizontal ? firstExtent : null,
              height: horizontal ? null : firstExtent,
              child: ClipRect(child: widget.first),
            ),
            _SimplePanelResizeHandle(
              axis: widget.axis,
              onRatioDelta: (delta) {
                if (contentExtent <= 0) {
                  return;
                }
                setState(() {
                  _transientRatio = (_ratio + delta / contentExtent).clamp(
                    workbenchMinSplitRatio,
                    workbenchMaxSplitRatio,
                  );
                });
              },
              onDragEnd: _persistRatio,
            ),
            SizedBox(
              width: horizontal ? secondExtent : null,
              height: horizontal ? null : secondExtent,
              child: ClipRect(child: widget.second),
            ),
          ],
        );
      },
    );
  }

  void _persistRatio() {
    final ratio = _transientRatio;
    if (ratio == null) {
      return;
    }
    widget.onPersistRatio(ratio);
  }
}

class const _SimplePanelResizeHandle({
  required final WorkbenchSplitAxis axis,
  required final ValueChanged<double> onRatioDelta,
  final VoidCallback? onDragEnd,
}) extends StatefulWidget {
  @override
  State<_SimplePanelResizeHandle> createState() =>
      _SimplePanelResizeHandleState();
}

class _SimplePanelResizeHandleState extends State<_SimplePanelResizeHandle> {
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
      onExit: (_) {
        if (!_dragging) {
          setState(() => _hovered = false);
        }
      },
      child: GestureDetector(
        behavior: .opaque,
        onHorizontalDragStart: horizontal
            ? (_) => setState(() => _dragging = true)
            : null,
        onHorizontalDragUpdate: horizontal
            ? (details) => widget.onRatioDelta(details.delta.dx)
            : null,
        onHorizontalDragEnd: horizontal ? (_) => _stopDragging() : null,
        onHorizontalDragCancel: horizontal ? _stopDragging : null,
        onVerticalDragStart: horizontal
            ? null
            : (_) => setState(() => _dragging = true),
        onVerticalDragUpdate: horizontal
            ? null
            : (details) => widget.onRatioDelta(details.delta.dy),
        onVerticalDragEnd: horizontal ? null : (_) => _stopDragging(),
        onVerticalDragCancel: horizontal ? null : _stopDragging,
        child: SizedBox(
          width: horizontal ? AleraTokens.space8 : null,
          height: horizontal ? null : AleraTokens.space8,
          child: Stack(
            fit: .expand,
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
    widget.onDragEnd?.call();
  }
}
