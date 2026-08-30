part of 'mobile_codex_chat_screen.dart';

class const _MobileCodexShimmerScope({
  required final bool enabled,
  required final Widget child,
}) extends StatefulWidget {
  @override
  State<_MobileCodexShimmerScope> createState() =>
      _MobileCodexShimmerScopeState();
}

class _MobileCodexShimmerScopeState extends State<_MobileCodexShimmerScope> {
  final ValueNotifier<double> _phase = ValueNotifier<double>(0);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant _MobileCodexShimmerScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) _syncTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _phase.dispose();
    super.dispose();
  }

  void _syncTimer() {
    _timer?.cancel();
    _timer = null;
    if (!widget.enabled) return;
    final steps =
        AleraTokens.codexShimmerCycle.inMilliseconds /
        AleraTokens.codexShimmerCadence.inMilliseconds;
    _timer = Timer.periodic(AleraTokens.codexShimmerCadence, (_) {
      _phase.value = (_phase.value + 1 / steps) % 1;
    });
  }

  @override
  Widget build(BuildContext context) => widget.enabled
      ? _MobileCodexShimmerPhase(phase: _phase, child: widget.child)
      : widget.child;
}

class const _MobileCodexShimmerPhase({
  required ValueNotifier<double> phase,
  required super.child,
}) extends InheritedNotifier<ValueNotifier<double>> {
  this : super(notifier: phase);

  static ValueNotifier<double>? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_MobileCodexShimmerPhase>()
      ?.notifier;
}

class const _MobileCodexShimmerText({
  required final String text,
  final TextStyle? style,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final phase = _MobileCodexShimmerPhase.maybeOf(context);
    if (phase == null) return Text(text, style: style);
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: phase,
        builder: (context, child) => ShaderMask(
          blendMode: .srcIn,
          shaderCallback: (bounds) {
            final center = phase.value * 2.4 - 0.7;
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
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
        child: Text(text, style: style),
      ),
    );
  }
}
