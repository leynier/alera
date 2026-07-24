import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Shows structured, presentational content near [child].
///
/// The card appears on hover after [hoverDelay] and, when [pinOnTap] is set,
/// also on tap. A tapped card stays pinned until the next tap on the trigger or
/// outside of it, so its contents stay reachable without holding the pointer.
class AleraHoverCard extends StatefulWidget {
  const AleraHoverCard({
    super.key,
    required this.semanticsLabel,
    required this.card,
    required this.child,
    this.hoverDelay = AleraTokens.durationSlow,
    this.pinOnTap = true,
  });

  final String semanticsLabel;
  final Widget card;
  final Widget child;
  final Duration hoverDelay;
  final bool pinOnTap;

  @override
  State<AleraHoverCard> createState() => _AleraHoverCardState();
}

class _AleraHoverCardState extends State<AleraHoverCard>
    with SingleTickerProviderStateMixin {
  /// Only one card may be open at a time, so a pinned card cannot overlap the
  /// card of a neighbouring trigger.
  static final Set<_AleraHoverCardState> _openCards = <_AleraHoverCardState>{};

  final OverlayPortalController _portal = OverlayPortalController();
  late final AnimationController _animation;
  late final CurvedAnimation _fade;

  Timer? _timer;
  bool _hoveringTrigger = false;
  bool _hoveringCard = false;
  bool _pinned = false;

  /// A tap that closes the card must not let the resting pointer reopen it.
  bool _hoverSuppressed = false;

  bool get _shouldShow =>
      _pinned || (_hoveringTrigger && !_hoverSuppressed) || _hoveringCard;

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
      vsync: this,
      duration: AleraTokens.durationFast,
      reverseDuration: AleraTokens.durationFast,
    )..addStatusListener(_handleAnimationStatus);
    _fade = CurvedAnimation(
      parent: _animation,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );
  }

  @override
  void dispose() {
    _openCards.remove(this);
    _timer?.cancel();
    _fade.dispose();
    _animation.dispose();
    super.dispose();
  }

  void _handleAnimationStatus(AnimationStatus status) {
    if (status.isDismissed) {
      _openCards.remove(this);
      _portal.hide();
    }
  }

  void _schedule({Duration delay = Duration.zero}) {
    _timer?.cancel();
    _timer = null;
    if (delay == Duration.zero) {
      _apply();
      return;
    }
    _timer = Timer(delay, _apply);
  }

  void _apply() {
    if (!mounted) {
      return;
    }
    if (!_shouldShow) {
      _animation.reverse();
      return;
    }
    for (final card in _openCards.toList()) {
      if (card != this) {
        card._dismissForOther();
      }
    }
    _openCards.add(this);
    _portal.show();
    _animation.forward();
  }

  void _dismissForOther() {
    _pinned = false;
    _hoveringTrigger = false;
    _hoveringCard = false;
    _hoverSuppressed = false;
    _schedule();
  }

  void _handleTriggerEnter(PointerEnterEvent event) {
    _hoveringTrigger = true;
    _schedule(
      delay: _animation.isForwardOrCompleted
          ? Duration.zero
          : widget.hoverDelay,
    );
  }

  void _handleTriggerExit(PointerExitEvent event) {
    _hoveringTrigger = false;
    _hoverSuppressed = false;
    _schedule(delay: AleraTokens.durationMid);
  }

  void _handleCardEnter(PointerEnterEvent event) {
    _hoveringCard = true;
    _schedule();
  }

  void _handleCardExit(PointerExitEvent event) {
    _hoveringCard = false;
    _schedule(delay: AleraTokens.durationMid);
  }

  void _handleTap() {
    if (_pinned) {
      _pinned = false;
      _hoverSuppressed = _hoveringTrigger;
    } else {
      _pinned = true;
      _hoverSuppressed = false;
    }
    _schedule();
  }

  void _handleTapOutside(PointerDownEvent event) {
    if (!_pinned) {
      return;
    }
    _pinned = false;
    _hoverSuppressed = _hoveringTrigger;
    _schedule();
  }

  Widget _buildCardOverlay(BuildContext context, OverlayChildLayoutInfo info) {
    if (info.childPaintTransform.determinant() == 0.0) {
      return const SizedBox.shrink();
    }
    final target = MatrixUtils.transformPoint(
      info.childPaintTransform,
      info.childSize.center(Offset.zero),
    );
    return Positioned.fill(
      bottom: MediaQuery.maybeViewInsetsOf(context)?.bottom ?? 0.0,
      child: CustomSingleChildLayout(
        delegate: _AleraHoverCardLayout(
          target: target,
          targetSize: info.childSize,
        ),
        child: TapRegion(
          groupId: this,
          child: MouseRegion(
            onEnter: _handleCardEnter,
            onExit: _handleCardExit,
            child: FadeTransition(opacity: _fade, child: widget.card),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final onTap = widget.pinOnTap ? _handleTap : null;
    Widget trigger = Semantics(
      tooltip: widget.semanticsLabel,
      button: widget.pinOnTap,
      onTap: onTap,
      child: widget.child,
    );
    trigger = MouseRegion(
      onEnter: _handleTriggerEnter,
      onExit: _handleTriggerExit,
      hitTestBehavior: HitTestBehavior.opaque,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: trigger,
      ),
    );
    return TapRegion(
      groupId: this,
      onTapOutside: _handleTapOutside,
      child: OverlayPortal.overlayChildLayoutBuilder(
        controller: _portal,
        overlayChildBuilder: _buildCardOverlay,
        child: trigger,
      ),
    );
  }
}

class _AleraHoverCardLayout extends SingleChildLayoutDelegate {
  const _AleraHoverCardLayout({required this.target, required this.targetSize});

  final Offset target;
  final Size targetSize;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return constraints.loosen();
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    return positionDependentBox(
      size: size,
      childSize: childSize,
      target: target,
      preferBelow: false,
      verticalOffset: targetSize.height / 2 + AleraTokens.space8,
      margin: AleraTokens.space8,
    );
  }

  @override
  bool shouldRelayout(_AleraHoverCardLayout oldDelegate) {
    return target != oldDelegate.target || targetSize != oldDelegate.targetSize;
  }
}
