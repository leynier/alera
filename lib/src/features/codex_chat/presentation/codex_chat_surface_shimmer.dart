part of 'codex_chat_surface.dart';

class _CodexShimmerScope extends StatefulWidget {
  const _CodexShimmerScope({required this.child});

  final Widget child;

  static _CodexShimmerScopeState? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_CodexShimmerPhase>()?.owner;

  @override
  State<_CodexShimmerScope> createState() => _CodexShimmerScopeState();
}

class _CodexShimmerScopeState extends State<_CodexShimmerScope>
    with WidgetsBindingObserver {
  final ValueNotifier<double> _phase = ValueNotifier<double>(0);
  final Stopwatch _elapsed = Stopwatch();
  Timer? _timer;
  bool _animationsEnabled = false;
  bool _applicationActive = true;
  int _consumers = 0;

  ValueListenable<double> get phase => _phase;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animationsEnabled =
        !(MediaQuery.maybeOf(context)?.disableAnimations ?? false) &&
        TickerMode.valuesOf(context).enabled;
    _syncTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _applicationActive = state == AppLifecycleState.resumed;
    _syncTimer();
  }

  void _syncTimer() {
    final shouldRun =
        _consumers > 0 && _animationsEnabled && _applicationActive;
    if (!shouldRun) {
      _timer?.cancel();
      _timer = null;
      _elapsed.stop();
      return;
    }
    if (_timer != null) return;
    _elapsed.start();
    // A shared fixed cadence avoids one vsync-driven controller per label and
    // caps Linux compositor work while streamed output remains active.
    _timer = Timer.periodic(AleraTokens.codexShimmerFrameInterval, (_) {
      final durationMicros = AleraTokens.codexShimmerDuration.inMicroseconds;
      _phase.value =
          (_elapsed.elapsedMicroseconds % durationMicros) / durationMicros;
    });
  }

  void acquire() {
    _consumers += 1;
    _syncTimer();
  }

  void release() {
    assert(_consumers > 0);
    _consumers -= 1;
    _syncTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _elapsed.stop();
    _phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _CodexShimmerPhase(owner: this, child: widget.child);
}

class _CodexShimmerPhase extends InheritedWidget {
  const _CodexShimmerPhase({required this.owner, required super.child});

  final _CodexShimmerScopeState owner;

  @override
  bool updateShouldNotify(_CodexShimmerPhase oldWidget) =>
      !identical(owner, oldWidget.owner);
}

class _CodexShimmerText extends StatefulWidget {
  const _CodexShimmerText({required this.text, this.style});

  final String text;
  final TextStyle? style;

  @override
  State<_CodexShimmerText> createState() => _CodexShimmerTextState();
}

class _CodexShimmerTextState extends State<_CodexShimmerText> {
  _CodexShimmerScopeState? _scope;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = _CodexShimmerScope.maybeOf(context);
    if (identical(next, _scope)) return;
    _scope?.release();
    _scope = next;
    _scope?.acquire();
  }

  @override
  void dispose() {
    _scope?.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Text(widget.text, style: widget.style);
    final phase = _scope?.phase;
    if (phase == null ||
        (MediaQuery.maybeOf(context)?.disableAnimations ?? false)) {
      return text;
    }
    return RepaintBoundary(
      child: ValueListenableBuilder<double>(
        valueListenable: phase,
        child: text,
        builder: (context, value, child) => ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) {
            final width = bounds.width;
            final left = bounds.left - width + (width * 2 * value);
            return const LinearGradient(
              colors: <Color>[
                AleraTokens.foregroundFaint,
                AleraTokens.foreground,
                AleraTokens.foregroundFaint,
              ],
            ).createShader(
              Rect.fromLTWH(left, bounds.top, width, bounds.height),
            );
          },
          child: child,
        ),
      ),
    );
  }
}
