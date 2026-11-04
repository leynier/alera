import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

/// Drives one shared shimmer phase for every working label in a chat.
///
/// A coarse timer rather than an animation controller: a turn can run for
/// many minutes, and a per-vsync animation on a phone costs battery for a hint
/// that reads the same at a few steps per second.
class const AgentChatShimmerScope({
  super.key,
  required final bool enabled,
  required final Widget child,
}) extends StatefulWidget {
  @override
  State<AgentChatShimmerScope> createState() => _AgentChatShimmerScopeState();
}

class _AgentChatShimmerScopeState extends State<AgentChatShimmerScope> {
  final ValueNotifier<double> _phase = ValueNotifier<double>(0);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant AgentChatShimmerScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) _sync();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _phase.dispose();
    super.dispose();
  }

  void _sync() {
    _timer?.cancel();
    _timer = null;
    if (!widget.enabled) return;
    final step =
        AleraTokens.durationFast.inMilliseconds /
        AleraTokens.durationSpin.inMilliseconds;
    _timer = Timer.periodic(AleraTokens.durationFast, (_) {
      _phase.value = (_phase.value + step) % 1;
    });
  }

  @override
  Widget build(BuildContext context) => widget.enabled
      ? _AgentChatShimmerPhase(phase: _phase, child: widget.child)
      : widget.child;
}

class const _AgentChatShimmerPhase({
  required ValueNotifier<double> phase,
  required super.child,
}) extends InheritedNotifier<ValueNotifier<double>> {
  this : super(notifier: phase);

  static ValueNotifier<double>? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_AgentChatShimmerPhase>()
      ?.notifier;
}

/// A label that shimmers while its scope is enabled and reads as plain text
/// otherwise, including in tests and with animations disabled.
class const AgentChatShimmerText({
  super.key,
  required final String text,
  final TextStyle? style,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final phase = _AgentChatShimmerPhase.maybeOf(context);
    final label = Text(text, style: style, maxLines: 1, overflow: .ellipsis);
    if (phase == null) return label;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: phase,
        builder: (context, child) => ShaderMask(
          blendMode: .srcIn,
          shaderCallback: (bounds) {
            final center = phase.value * 2.4 - 0.7;
            return LinearGradient(
              colors: const <Color>[
                AleraTokens.foregroundFaint,
                AleraTokens.foreground,
                AleraTokens.foregroundFaint,
              ],
              stops: <double>[
                (center - 0.25).clamp(0.0, 1.0),
                center.clamp(0.0, 1.0),
                (center + 0.25).clamp(0.0, 1.0),
              ],
            ).createShader(bounds);
          },
          child: child,
        ),
        child: label,
      ),
    );
  }
}
