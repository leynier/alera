import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_entry.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/workbench/domain/terminal_toolbar_placement.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client_models.dart';
import 'package:alera/src/features/workbench/presentation/terminal_pulse_dialog.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:flutter/material.dart';

class TerminalSurfaceToolbar extends StatefulWidget {
  const TerminalSurfaceToolbar({
    super.key,
    required this.session,
    required this.viewportSize,
    required this.corner,
    required this.hasCanvas,
    required this.refreshing,
    required this.onRefresh,
    required this.onShowAgentCanvas,
    this.onCornerChanged,
  });

  final TerminalSessionHandle session;
  final Size viewportSize;
  final TerminalToolbarCorner corner;
  final bool hasCanvas;
  final bool refreshing;
  final VoidCallback onRefresh;
  final VoidCallback onShowAgentCanvas;
  final ValueChanged<TerminalToolbarCorner>? onCornerChanged;

  @override
  State<TerminalSurfaceToolbar> createState() => _TerminalSurfaceToolbarState();
}

class _TerminalSurfaceToolbarState extends State<TerminalSurfaceToolbar> {
  final GlobalKey _toolbarKey = GlobalKey();
  TerminalToolbarCorner? _localCorner;
  Offset? _dragOrigin;

  TerminalToolbarCorner get _corner => _localCorner ?? widget.corner;

  @override
  void didUpdateWidget(TerminalSurfaceToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.corner != widget.corner && _dragOrigin == null) {
      _localCorner = null;
    }
  }

  void _setCorner(TerminalToolbarCorner corner) {
    if (corner == _corner) {
      return;
    }
    setState(() {
      _localCorner = corner;
      _dragOrigin = null;
    });
    widget.onCornerChanged?.call(corner);
  }

  Future<void> _showCornerMenu(Offset globalPosition) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final selected = await showMenu<TerminalToolbarCorner>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(globalPosition, globalPosition),
        Offset.zero & overlay.size,
      ),
      items: <PopupMenuEntry<TerminalToolbarCorner>>[
        for (final corner in TerminalToolbarCorner.values)
          AleraDropdownEntry<TerminalToolbarCorner>(
            value: corner,
            label: corner.label,
            selected: corner == _corner,
          ),
      ],
    );
    if (!mounted || selected == null) {
      return;
    }
    _setCorner(selected);
  }

  void _onPanStart(DragStartDetails details) {
    final toolbarSize = _toolbarKey.currentContext?.size;
    if (toolbarSize == null) {
      return;
    }
    final origin = terminalToolbarOffset(
      corner: _corner,
      viewportWidth: widget.viewportSize.width,
      viewportHeight: widget.viewportSize.height,
      toolbarWidth: toolbarSize.width,
      toolbarHeight: toolbarSize.height,
    );
    setState(() => _dragOrigin = Offset(origin.left, origin.top));
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final origin = _dragOrigin;
    final toolbarSize = _toolbarKey.currentContext?.size;
    if (origin == null || toolbarSize == null) {
      return;
    }
    setState(() {
      _dragOrigin = Offset(
        clampTerminalToolbarLeft(
          left: origin.dx + details.delta.dx,
          viewportWidth: widget.viewportSize.width,
          toolbarWidth: toolbarSize.width,
        ),
        clampTerminalToolbarTop(
          top: origin.dy + details.delta.dy,
          viewportHeight: widget.viewportSize.height,
          toolbarHeight: toolbarSize.height,
        ),
      );
    });
  }

  void _onPanEnd(DragEndDetails details) {
    final origin = _dragOrigin;
    final toolbarSize = _toolbarKey.currentContext?.size;
    if (origin == null || toolbarSize == null) {
      return;
    }
    final next = nearestTerminalToolbarCorner(
      centerX: origin.dx + toolbarSize.width / 2,
      centerY: origin.dy + toolbarSize.height / 2,
      viewportWidth: widget.viewportSize.width,
      viewportHeight: widget.viewportSize.height,
    );
    _setCorner(next);
  }

  @override
  Widget build(BuildContext context) {
    final dragOrigin = _dragOrigin;
    if (dragOrigin != null) {
      return Positioned(
        left: dragOrigin.dx,
        top: dragOrigin.dy,
        child: _buildCluster(),
      );
    }
    final anchor = TerminalToolbarAnchor.forCorner(_corner);
    return Positioned(
      top: anchor.top,
      left: anchor.left,
      right: anchor.right,
      bottom: anchor.bottom,
      child: _buildCluster(),
    );
  }

  Widget _buildCluster() {
    final handle = _MoveToolbarHandle(
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
    );
    final actions = <Widget>[
      if (widget.session.supportsTerminalPulse) _buildTerminalPulseControl(),
      AleraIconButton(
        tooltip: widget.session.composerController.visible
            ? 'Hide Terminal Composer'
            : 'Show Terminal Composer',
        icon: AleraIcons.composer,
        iconColor: widget.session.composerController.visible
            ? AleraTokens.foreground
            : AleraTokens.foregroundMuted,
        backgroundColor: widget.session.composerController.visible
            ? AleraTokens.accentSubtle
            : AleraTokens.surfaceElevated,
        borderColor: AleraTokens.borderSubtle,
        onPressed: widget.session.composerController.toggle,
      ),
      AleraIconButton(
        tooltip: widget.refreshing ? 'Refreshing Terminal' : 'Refresh Terminal',
        icon: widget.refreshing ? AleraIcons.loading : AleraIcons.refresh,
        backgroundColor: AleraTokens.surfaceElevated,
        borderColor: AleraTokens.borderSubtle,
        onPressed: widget.refreshing ? null : widget.onRefresh,
      ),
      if (widget.hasCanvas)
        AleraIconButton(
          tooltip: 'Agent Canvas',
          icon: AleraIcons.agent,
          backgroundColor: AleraTokens.surfaceElevated,
          borderColor: AleraTokens.borderSubtle,
          onPressed: widget.onShowAgentCanvas,
        ),
    ];
    return GestureDetector(
      onSecondaryTapDown: (details) {
        unawaited(_showCornerMenu(details.globalPosition));
      },
      child: Row(
        key: _toolbarKey,
        mainAxisSize: MainAxisSize.min,
        spacing: AleraTokens.space2,
        children: <Widget>[
          if (_corner.isRight) handle,
          ...actions,
          if (_corner.isLeft) handle,
        ],
      ),
    );
  }

  Widget _buildTerminalPulseControl() {
    return ValueListenableBuilder<TerminalPulseState>(
      valueListenable: widget.session.terminalPulseState,
      builder: (context, state, _) {
        return AleraIconButton(
          tooltip: !state.statusKnown
              ? 'Configure Terminal Pulse - Status Unavailable'
              : state.armed
              ? 'Configure Terminal Pulse - Armed'
              : 'Configure Terminal Pulse',
          icon: AleraIcons.pulse,
          iconColor: state.statusKnown && state.armed
              ? AleraTokens.foreground
              : AleraTokens.foregroundMuted,
          backgroundColor: state.statusKnown && state.armed
              ? AleraTokens.accentSubtle
              : AleraTokens.surfaceElevated,
          borderColor: AleraTokens.borderSubtle,
          onPressed: () =>
              unawaited(showTerminalPulseDialog(context, widget.session)),
        );
      },
    );
  }
}

class _MoveToolbarHandle extends StatelessWidget {
  const _MoveToolbarHandle({
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
  });

  final GestureDragStartCallback onPanStart;
  final GestureDragUpdateCallback onPanUpdate;
  final GestureDragEndCallback onPanEnd;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.move,
      child: GestureDetector(
        onPanStart: onPanStart,
        onPanUpdate: onPanUpdate,
        onPanEnd: onPanEnd,
        child: AleraIconButton(
          tooltip: 'Move Toolbar',
          icon: AleraIcons.dragHandle,
          backgroundColor: AleraTokens.surfaceElevated,
          borderColor: AleraTokens.borderSubtle,
          onPressed: () {},
        ),
      ),
    );
  }
}
