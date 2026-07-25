import 'dart:math' as math;

import 'package:flutter/material.dart';

/// One ticker for every agent spinner under this scope.
///
/// A `CircularProgressIndicator` owns a private `AnimationController` and
/// rebuilds itself every frame, so a sidebar with twenty working agents ran
/// twenty tickers and twenty per-frame rebuilds. Sharing one animation and
/// painting it keeps the cost to one ticker and N paints, with no build or
/// layout work in the list.
///
/// The ticker is reference counted by the mounted spinners, so an idle sidebar
/// schedules no frames at all.
class AgentRunSpinnerScope extends StatefulWidget {
  const AgentRunSpinnerScope({super.key, required this.child});

  final Widget child;

  static _AgentRunSpinnerScopeState? _maybeStateOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_AgentRunSpinnerAnimation>()
        ?.scope;
  }

  @override
  State<AgentRunSpinnerScope> createState() => _AgentRunSpinnerScopeState();
}

class _AgentRunSpinnerScopeState extends State<AgentRunSpinnerScope>
    with SingleTickerProviderStateMixin {
  // Built eagerly, never lazily: a `late final` would construct a ticker
  // inside dispose() when no spinner ever mounted, which is unsafe.
  late final AnimationController _controller;
  int _spinners = 0;

  Animation<double> get animation => _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1400),
      vsync: this,
    );
  }

  void _acquire() {
    _spinners += 1;
    if (_spinners == 1 && !_controller.isAnimating) {
      _controller.repeat();
    }
  }

  void _release() {
    _spinners -= 1;
    if (_spinners <= 0) {
      _spinners = 0;
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _AgentRunSpinnerAnimation(scope: this, child: widget.child);
  }
}

/// A plain [InheritedWidget], deliberately not an `InheritedNotifier`: the
/// latter rebuilds every dependent on each tick, which is the cost this scope
/// exists to remove. The scope identity is stable, so dependents never rebuild
/// and repaint off the shared ticker instead.
class _AgentRunSpinnerAnimation extends InheritedWidget {
  const _AgentRunSpinnerAnimation({required this.scope, required super.child});

  final _AgentRunSpinnerScopeState scope;

  @override
  bool updateShouldNotify(_AgentRunSpinnerAnimation oldWidget) {
    return !identical(scope, oldWidget.scope);
  }
}

/// Indeterminate spinner painted off the nearest [AgentRunSpinnerScope].
class AgentRunSharedSpinner extends StatefulWidget {
  const AgentRunSharedSpinner({
    super.key,
    required this.size,
    required this.color,
    required this.strokeWidth,
  });

  final double size;
  final Color color;
  final double strokeWidth;

  /// Whether a scope is available, so callers outside the sidebar can fall
  /// back to their own indicator.
  static bool isAvailable(BuildContext context) {
    return AgentRunSpinnerScope._maybeStateOf(context) != null;
  }

  @override
  State<AgentRunSharedSpinner> createState() => _AgentRunSharedSpinnerState();
}

class _AgentRunSharedSpinnerState extends State<AgentRunSharedSpinner> {
  _AgentRunSpinnerScopeState? _scope;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = AgentRunSpinnerScope._maybeStateOf(context);
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
    final scope = _scope;
    if (scope == null) {
      return SizedBox.square(dimension: widget.size);
    }
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: AgentRunSpinnerPainter(
          progress: scope.animation,
          color: widget.color,
          strokeWidth: widget.strokeWidth,
        ),
      ),
    );
  }
}

/// Draws the indeterminate arc for one agent run off a shared ticker.
class AgentRunSpinnerPainter extends CustomPainter {
  AgentRunSpinnerPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final Color color;
  final double strokeWidth;

  static const double _sweep = 4.7;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth
      ..color = color;
    final inset = strokeWidth / 2;
    final rect = Rect.fromLTWH(
      inset,
      inset,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );
    canvas.drawArc(rect, progress.value * 2 * math.pi, _sweep, false, paint);
  }

  @override
  bool shouldRepaint(AgentRunSpinnerPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        !identical(oldDelegate.progress, progress);
  }
}
