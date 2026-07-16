import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

/// Shows structured, presentational content near [child] with tooltip-like
/// hover and long-press behavior.
class AleraHoverCard extends StatelessWidget {
  const AleraHoverCard({
    super.key,
    required this.semanticsLabel,
    required this.card,
    required this.child,
    this.hoverDelay = AleraTokens.durationSlow,
  });

  final String semanticsLabel;
  final Widget card;
  final Widget child;
  final Duration hoverDelay;

  @override
  Widget build(BuildContext context) {
    return RawTooltip(
      semanticsTooltip: semanticsLabel,
      hoverDelay: hoverDelay,
      dismissDelay: AleraTokens.durationMid,
      animationStyle: const AnimationStyle(
        duration: AleraTokens.durationFast,
        reverseDuration: AleraTokens.durationFast,
        curve: Curves.easeOut,
        reverseCurve: Curves.easeIn,
      ),
      positionDelegate: (position) => positionDependentBox(
        size: position.overlaySize,
        childSize: position.tooltipSize,
        target: position.target,
        preferBelow: false,
        verticalOffset: position.targetSize.height / 2 + AleraTokens.space8,
        margin: AleraTokens.space8,
      ),
      tooltipBuilder: (context, animation) =>
          FadeTransition(opacity: animation, child: card),
      child: child,
    );
  }
}
