import 'dart:math' as math;

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Opens and closes an [AleraPopover] from outside its anchor, and lets the
/// owner rebuild (for example an anchor chip's active state) while it is open.
class AleraPopoverController extends ChangeNotifier {
  bool _isOpen = false;

  bool get isOpen => _isOpen;

  void open() {
    if (_isOpen) {
      return;
    }
    _isOpen = true;
    notifyListeners();
  }

  void close() {
    if (!_isOpen) {
      return;
    }
    _isOpen = false;
    notifyListeners();
  }

  void toggle() => _isOpen ? close() : open();
}

/// Builds the content of an [AleraPopover]; [close] dismisses it.
typedef AleraPopoverContentBuilder = Widget Function(
  BuildContext context,
  VoidCallback close,
);

/// Anchored popover surface: [builder] renders below [child] (or above it when
/// there is more room there), clamped inside the overlay, on the `surface`
/// token with a border, `radiusMd` corners and a `shadowSoft` shadow.
///
/// A tap outside the popover or Escape closes it, and closing hands focus back
/// to whatever held it when the popover opened. A passive anchor toggles the
/// popover on tap; an anchor that handles taps itself (such as
/// `AleraPropertyChip`) should call [AleraPopoverController.toggle] from its
/// own callback so Enter and Space open it too.
class const AleraPopover({
  super.key,
  required final Widget child,
  required final AleraPopoverContentBuilder builder,
  final AleraPopoverController? controller,
  final double? width,
  final bool matchAnchorWidth = false,
  final double? maxHeight,
  final bool toggleOnAnchorTap = true,
}) extends StatefulWidget {
  @override
  State<AleraPopover> createState() => _AleraPopoverState();
}

class _AleraPopoverState extends State<AleraPopover> {
  final OverlayPortalController _portal = OverlayPortalController();
  final FocusScopeNode _scopeNode = FocusScopeNode(debugLabel: 'AleraPopover');
  AleraPopoverController? _ownedController;
  FocusNode? _returnFocus;

  AleraPopoverController get _controller =>
      widget.controller ?? (_ownedController ??= AleraPopoverController());

  @override
  void initState() {
    super.initState();
    _controller.addListener(_sync);
    if (_controller.isOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
    }
  }

  @override
  void didUpdateWidget(AleraPopover oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = oldWidget.controller ?? _ownedController;
    if (previous != _controller) {
      previous?.removeListener(_sync);
      _controller.addListener(_sync);
      _sync();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_sync);
    _ownedController?.dispose();
    _scopeNode.dispose();
    super.dispose();
  }

  void _sync() {
    if (!mounted) {
      return;
    }
    final open = _controller.isOpen;
    if (open == _portal.isShowing) {
      return;
    }
    if (open) {
      _returnFocus = FocusManager.instance.primaryFocus;
      _portal.show();
      // Content such as a search field may claim focus on its own first;
      // only fall back to the scope so Escape still reaches it.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _portal.isShowing && !_scopeNode.hasFocus) {
          _scopeNode.requestFocus();
        }
      });
    } else {
      final hadFocus = _scopeNode.hasFocus;
      _portal.hide();
      final target = _returnFocus;
      _returnFocus = null;
      if (hadFocus && target != null && target.context != null) {
        target.requestFocus();
      }
    }
  }

  void _close() => _controller.close();

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _close();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _buildOverlay(BuildContext context, OverlayChildLayoutInfo info) {
    if (info.childPaintTransform.determinant() == 0.0) {
      return const SizedBox.shrink();
    }
    final anchor = MatrixUtils.transformRect(
      info.childPaintTransform,
      Offset.zero & info.childSize,
    );
    final width = widget.matchAnchorWidth ? info.childSize.width : widget.width;
    return Positioned.fill(
      bottom: MediaQuery.maybeViewInsetsOf(context)?.bottom ?? 0.0,
      child: Stack(
        children: <Widget>[
          // A full-overlay barrier rather than a TapRegion: menus and pickers
          // opened from inside the popover live on their own routes, and a
          // TapRegion would treat taps on them as outside taps.
          Positioned.fill(
            child: Listener(behavior: .opaque, onPointerDown: (_) => _close()),
          ),
          CustomSingleChildLayout(
            delegate: _AleraPopoverLayout(
              anchor: anchor,
              width: width,
              maxHeight: widget.maxHeight,
            ),
            child: FocusScope(
              node: _scopeNode,
              onKeyEvent: _handleKey,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: AleraTokens.shadowSoft,
                      blurRadius: AleraTokens.space16,
                      offset: Offset(0, AleraTokens.space8),
                    ),
                  ],
                ),
                child: Material(
                  color: AleraTokens.surface,
                  clipBehavior: .antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
                    side: const BorderSide(color: AleraTokens.border),
                  ),
                  child: Builder(
                    builder: (context) => widget.builder(context, _close),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    var anchor = widget.child;
    if (widget.toggleOnAnchorTap) {
      anchor = GestureDetector(
        behavior: .opaque,
        onTap: _controller.toggle,
        child: anchor,
      );
    }
    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _portal,
      overlayChildBuilder: _buildOverlay,
      child: anchor,
    );
  }
}

/// Places the popover under the anchor, flips it above when it fits better
/// there, and clamps it inside the overlay with a `space8` margin.
class const _AleraPopoverLayout({
  required final Rect anchor,
  required final double? width,
  required final double? maxHeight,
}) extends SingleChildLayoutDelegate {
  static const double _gap = AleraTokens.space4;
  static const double _margin = AleraTokens.space8;

  double _spaceBelow(Size overlay) =>
      overlay.height - _margin - anchor.bottom - _gap;

  double _spaceAbove() => anchor.top - _gap - _margin;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final overlay = constraints.biggest;
    final maxWidth = math.max(0.0, overlay.width - _margin * 2);
    final available = math.max(
      0.0,
      math.max(_spaceBelow(overlay), _spaceAbove()),
    );
    final height = maxHeight == null
        ? available
        : math.min(maxHeight!, available);
    final requestedWidth = width;
    if (requestedWidth == null) {
      return BoxConstraints(maxWidth: maxWidth, maxHeight: height);
    }
    return BoxConstraints.tightFor(width: math.min(requestedWidth, maxWidth))
        .copyWith(maxHeight: height);
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final below = _spaceBelow(size);
    final opensDown = childSize.height <= below || below >= _spaceAbove();
    final y = opensDown
        ? anchor.bottom + _gap
        : anchor.top - _gap - childSize.height;
    final maxX = math.max(_margin, size.width - _margin - childSize.width);
    final x = anchor.left.clamp(_margin, maxX);
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_AleraPopoverLayout oldDelegate) =>
      anchor != oldDelegate.anchor ||
      width != oldDelegate.width ||
      maxHeight != oldDelegate.maxHeight;
}
