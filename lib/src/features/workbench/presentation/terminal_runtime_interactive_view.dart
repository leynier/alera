part of 'terminal_runtime.dart';

class _InteractiveTerminalView extends StatefulWidget {
  const _InteractiveTerminalView({
    super.key,
    required this.session,
    required this.autofocus,
    this.onKeyEvent,
  });

  final _XtermTerminalSessionHandle session;
  final bool autofocus;
  final FocusOnKeyEventCallback? onKeyEvent;

  @override
  State<_InteractiveTerminalView> createState() =>
      _InteractiveTerminalViewState();
}

class _InteractiveTerminalViewState extends State<_InteractiveTerminalView> {
  TerminalLinkRange? _hoveredLink;

  @override
  void didUpdateWidget(covariant _InteractiveTerminalView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      _hoveredLink = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onExit: (_) => _setHoveredLink(null),
      onHover: _handleHover,
      child: widget.session._buildTerminalView(
        autofocus: widget.autofocus,
        onKeyEvent: widget.onKeyEvent,
        mouseCursor: _hoveredLink == null
            ? SystemMouseCursors.text
            : SystemMouseCursors.click,
        onTapUp: _handleTapUp,
      ),
    );
  }

  void _handleHover(PointerHoverEvent event) {
    final viewState = widget.session._terminalViewKey.currentState;
    if (viewState == null) {
      return;
    }
    final localPosition = viewState.renderTerminal.globalToLocal(
      event.position,
    );
    final offset = viewState.renderTerminal.getCellOffset(localPosition);
    _setHoveredLink(widget.session._linkAt(offset));
  }

  void _handleTapUp(TapUpDetails _, xterm.CellOffset offset) {
    if (!isTerminalLinkActivation()) {
      return;
    }
    final link = widget.session._linkAt(offset);
    if (link == null) {
      return;
    }
    unawaited(_openLink(link.uri));
  }

  Future<void> _openLink(Uri uri) async {
    try {
      await widget.session._openLink(uri);
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not open link: $uri')));
    }
  }

  void _setHoveredLink(TerminalLinkRange? link) {
    if (_hoveredLink == link) {
      return;
    }
    setState(() {
      _hoveredLink = link;
    });
  }
}

class _TerminalPtySize {
  const _TerminalPtySize({
    required this.cols,
    required this.rows,
    required this.cellWidthPx,
    required this.cellHeightPx,
  });

  final int cols;
  final int rows;
  final int cellWidthPx;
  final int cellHeightPx;
}

const Duration _ptyResizeDebounceDuration = Duration(milliseconds: 150);

final class _TerminalVisibilityLease implements TerminalVisibilityLease {
  _TerminalVisibilityLease(this._onDispose);

  final VoidCallback _onDispose;
  bool _disposed = false;

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _onDispose();
  }
}
