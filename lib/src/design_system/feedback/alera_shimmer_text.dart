import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

// Pacing, not motion tokens: about 20 repaints per second over one sweep.
const Duration _shimmerRepaintInterval = Duration(milliseconds: 50);
const Duration _shimmerSweepPeriod = Duration(milliseconds: 1400);

/// One paced animation for every [AleraShimmerText] under this scope.
///
/// A vsync-driven ticker requests a frame per refresh, and on Linux every
/// frame is composited in software whether or not it changed anything. The
/// scope instead advances a shared phase from a periodic timer, so a streaming
/// timeline repaints its labels about 20 times per second and builds nothing.
///
/// The timer is reference counted by the shimmers that are mounted and
/// animating, and it parks while the window is hidden, so an idle scope
/// schedules no timers or frames at all.
class const AleraShimmerScope({super.key, required final Widget child})
    extends StatefulWidget {
  static _AleraShimmerScopeState? _maybeStateOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_AleraShimmerPhase>()
        ?.scope;
  }

  /// Whether the scope above [context] is pacing repaints right now.
  @visibleForTesting
  static bool isAnimating(BuildContext context) {
    final scope = context
        .getInheritedWidgetOfExactType<_AleraShimmerPhase>()
        ?.scope;
    return scope?._timer != null;
  }

  @override
  State<AleraShimmerScope> createState() => _AleraShimmerScopeState();
}

class _AleraShimmerScopeState extends State<AleraShimmerScope>
    with WidgetsBindingObserver {
  final ValueNotifier<double> _phase = ValueNotifier<double>(0);
  Timer? _timer;
  int _lastTick = 0;
  int _shimmers = 0;
  bool _windowVisible = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _windowVisible = _isVisible(WidgetsBinding.instance.lifecycleState);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _windowVisible = _isVisible(state);
    _sync();
  }

  static bool _isVisible(AppLifecycleState? state) => switch (state) {
    null || AppLifecycleState.resumed || AppLifecycleState.inactive => true,
    _ => false,
  };

  void _acquire() {
    _shimmers += 1;
    _sync();
  }

  void _release() {
    assert(_shimmers > 0);
    _shimmers -= 1;
    _sync();
  }

  void _sync() {
    if (_shimmers == 0 || !_windowVisible) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    if (_timer != null) {
      return;
    }
    _lastTick = 0;
    _timer = Timer.periodic(_shimmerRepaintInterval, _advance);
  }

  // `Timer.tick` also counts intervals missed while the isolate was busy, so
  // the sweep keeps wall-clock speed and resumes where it paused.
  void _advance(Timer timer) {
    final steps = timer.tick - _lastTick;
    _lastTick = timer.tick;
    final step =
        _shimmerRepaintInterval.inMicroseconds /
        _shimmerSweepPeriod.inMicroseconds;
    _phase.value = (_phase.value + steps * step) % 1;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _timer = null;
    _phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _AleraShimmerPhase(scope: this, child: widget.child);
  }
}

/// A plain [InheritedWidget], deliberately not an `InheritedNotifier`: the
/// latter rebuilds every dependent on each tick. The scope identity is stable,
/// so dependents never rebuild and repaint off the shared phase instead.
class const _AleraShimmerPhase({
  required final _AleraShimmerScopeState scope,
  required super.child,
}) extends InheritedWidget {
  @override
  bool updateShouldNotify(_AleraShimmerPhase oldWidget) {
    return !identical(scope, oldWidget.scope);
  }
}

/// Muted [text] with a highlight sweeping across it, for transient states
/// such as Thinking, Working or Streaming.
///
/// The base color is [style]'s color, or `foregroundMuted` without one, and
/// the highlight is `foreground`, so a base as bright as `foreground` hides
/// the sweep: pass a muted or faint color. The sweep needs an
/// [AleraShimmerScope] ancestor; without one, with animations disabled, or
/// under a disabled [TickerMode] the text renders statically in the base
/// color.
class const AleraShimmerText({
  super.key,
  required final String text,
  final TextStyle? style,
  final int? maxLines,
  final TextOverflow? overflow,
}) extends StatefulWidget {
  @override
  State<AleraShimmerText> createState() => _AleraShimmerTextState();
}

class _AleraShimmerTextState extends State<AleraShimmerText> {
  _AleraShimmerScopeState? _scope;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animate =
        TickerMode.valuesOf(context).enabled &&
        !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    final scope = animate ? AleraShimmerScope._maybeStateOf(context) : null;
    if (identical(scope, _scope)) {
      return;
    }
    _scope?._release();
    _scope = scope?.._acquire();
  }

  @override
  void dispose() {
    _scope?._release();
    _scope = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseColor = widget.style?.color ?? AleraTokens.foregroundMuted;
    final text = Text(
      widget.text,
      style: (widget.style ?? const TextStyle()).copyWith(color: baseColor),
      maxLines: widget.maxLines,
      overflow: widget.overflow,
    );
    final scope = _scope;
    if (scope == null) {
      return text;
    }
    return RepaintBoundary(
      child: _AleraShimmerMask(
        phase: scope._phase,
        baseColor: baseColor,
        highlightColor: AleraTokens.foreground,
        child: text,
      ),
    );
  }
}

class const _AleraShimmerMask({
  required final ValueListenable<double> phase,
  required final Color baseColor,
  required final Color highlightColor,
  required super.child,
}) extends SingleChildRenderObjectWidget {
  @override
  _RenderAleraShimmerMask createRenderObject(BuildContext context) {
    return _RenderAleraShimmerMask(
      phase: phase,
      baseColor: baseColor,
      highlightColor: highlightColor,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderAleraShimmerMask renderObject,
  ) {
    renderObject
      ..phase = phase
      ..baseColor = baseColor
      ..highlightColor = highlightColor;
  }
}

/// Paints its child through a moving gradient mask, repainting (never
/// rebuilding or relaying out) whenever the shared phase advances.
class _RenderAleraShimmerMask({
  required this._phase,
  required this._baseColor,
  required this._highlightColor,
}) extends RenderProxyBox {
  ValueListenable<double> _phase;
  Color _baseColor;
  Color _highlightColor;

  set phase(ValueListenable<double> value) {
    if (identical(value, _phase)) {
      return;
    }
    if (attached) {
      _phase.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _phase = value;
    markNeedsPaint();
  }

  set baseColor(Color value) {
    if (value == _baseColor) {
      return;
    }
    _baseColor = value;
    markNeedsPaint();
  }

  set highlightColor(Color value) {
    if (value == _highlightColor) {
      return;
    }
    _highlightColor = value;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _phase.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _phase.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  ShaderMaskLayer? get layer => super.layer as ShaderMaskLayer?;

  @override
  bool get alwaysNeedsCompositing => child != null;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) {
      layer = null;
      return;
    }
    // The band starts fully left of the text and leaves fully right of it,
    // so each sweep enters and exits smoothly.
    final width = size.width;
    final band = Rect.fromLTWH(
      width * (2 * _phase.value - 1),
      0,
      width,
      size.height,
    );
    final mask = layer ?? ShaderMaskLayer();
    mask
      ..shader = LinearGradient(
        colors: <Color>[_baseColor, _highlightColor, _baseColor],
      ).createShader(band)
      ..maskRect = offset & size
      ..blendMode = BlendMode.srcIn;
    layer = mask;
    context.pushLayer(mask, super.paint, offset);
  }
}
