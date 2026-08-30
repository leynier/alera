import 'dart:math' as math;

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

/// Resource-management scaffold: a resizable master column (header with
/// title and optional action, then a scrollable list) beside an expanded
/// detail area with its own scroll context.
///
/// Used by settings resource panes (Projects, Remote Hosts, Agent Profiles)
/// so entity CRUD screens share one layout.
class const AleraMasterDetail({
  super.key,
  required final String masterTitle,
  final Widget? masterAction,
  required final Widget master,
  required final Widget detail,
  final double masterWidth = AleraTokens.masterDetailDefaultWidth,
  final double masterMinWidth = AleraTokens.masterDetailMinWidth,
  final double masterMaxWidth = AleraTokens.masterDetailMaxWidth,
}) extends StatefulWidget {
  @override
  State<AleraMasterDetail> createState() => _AleraMasterDetailState();
}

class _AleraMasterDetailState extends State<AleraMasterDetail> {
  late double _masterWidth;

  @override
  void initState() {
    super.initState();
    _masterWidth = widget.masterWidth;
  }

  @override
  void didUpdateWidget(AleraMasterDetail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.masterWidth != oldWidget.masterWidth) {
      _masterWidth = widget.masterWidth;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final maximumMasterWidth = _maximumMasterWidth(constraints);
        final masterWidth = _masterWidth
            .clamp(widget.masterMinWidth, maximumMasterWidth)
            .toDouble();
        return Row(
          crossAxisAlignment: .stretch,
          children: <Widget>[
            SizedBox(
              width: masterWidth,
              child: Column(
                crossAxisAlignment: .stretch,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(
                      left: AleraTokens.space4,
                      bottom: AleraTokens.space8,
                    ),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            widget.masterTitle,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: AleraTokens.foreground,
                              fontWeight: .w600,
                            ),
                          ),
                        ),
                        ?widget.masterAction,
                      ],
                    ),
                  ),
                  Expanded(child: widget.master),
                ],
              ),
            ),
            _MasterDetailResizeHandle(
              currentWidth: masterWidth,
              minWidth: widget.masterMinWidth,
              maxWidth: maximumMasterWidth,
              label: 'Resize ${widget.masterTitle} List',
              onResize: (width) => setState(() {
                _masterWidth = width;
              }),
            ),
            Expanded(child: widget.detail),
          ],
        );
      },
    );
  }

  double _maximumMasterWidth(BoxConstraints constraints) {
    if (!constraints.hasBoundedWidth) {
      return widget.masterMaxWidth;
    }
    final availableWidth =
        constraints.maxWidth -
        _masterDetailHandleWidth -
        AleraTokens.masterDetailMinDetailWidth;
    return math.max(
      widget.masterMinWidth,
      math.min(widget.masterMaxWidth, availableWidth),
    );
  }
}

const double _masterDetailHandleWidth =
    AleraTokens.space16 * 2 + AleraTokens.dividerExtent;

class const _MasterDetailResizeHandle({
  required final double currentWidth,
  required final double minWidth,
  required final double maxWidth,
  required final String label,
  required final ValueChanged<double> onResize,
}) extends StatefulWidget {
  @override
  State<_MasterDetailResizeHandle> createState() =>
      _MasterDetailResizeHandleState();
}

class _MasterDetailResizeHandleState extends State<_MasterDetailResizeHandle> {
  bool _hovered = false;
  bool _dragging = false;
  double? _dragWidth;

  @override
  Widget build(BuildContext context) {
    final emphasised = _hovered || _dragging;
    return Semantics(
      container: true,
      label: widget.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          key: const ValueKey<String>('alera-master-detail-resize-handle'),
          behavior: .translucent,
          onHorizontalDragStart: (_) {
            _dragWidth = widget.currentWidth;
            setState(() => _dragging = true);
          },
          onHorizontalDragEnd: (_) => _stopDragging(),
          onHorizontalDragCancel: _stopDragging,
          onHorizontalDragUpdate: (details) {
            final next = (_dragWidth ?? widget.currentWidth) + details.delta.dx;
            final constrained = next.clamp(widget.minWidth, widget.maxWidth);
            _dragWidth = constrained.toDouble();
            widget.onResize(_dragWidth!);
          },
          child: SizedBox(
            width: _masterDetailHandleWidth,
            child: Center(
              child: AnimatedContainer(
                duration: AleraTokens.durationFast,
                width: emphasised
                    ? AleraTokens.space2
                    : AleraTokens.dividerExtent,
                decoration: BoxDecoration(
                  color: emphasised
                      ? AleraTokens.border
                      : AleraTokens.borderSubtle,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _stopDragging() {
    _dragWidth = null;
    setState(() => _dragging = false);
  }
}
