import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/pull_requests/domain/review_check.dart';
import 'package:flutter/material.dart';

/// Presentational icon for a single check's status/conclusion. Pure: derives an
/// icon and token color from [status] and [conclusion] with no Riverpod reads.
/// The running/pending loader rotates continuously.
class PullRequestCheckIcon extends StatefulWidget {
  const PullRequestCheckIcon({
    super.key,
    required this.status,
    required this.conclusion,
    this.size = 16,
  });

  final ReviewCheckStatus status;
  final ReviewCheckConclusion conclusion;
  final double size;

  @override
  State<PullRequestCheckIcon> createState() => _PullRequestCheckIconState();
}

class _PullRequestCheckIconState extends State<PullRequestCheckIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  bool get _spinning =>
      widget.status != ReviewCheckStatus.completed ||
      widget.conclusion == ReviewCheckConclusion.pending;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AleraTokens.durationSpin,
    );
    if (_spinning) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(PullRequestCheckIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_spinning && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!_spinning && _controller.isAnimating) {
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
    final (icon, color) = _iconAndColor();
    final child = Icon(icon, size: widget.size, color: color);
    if (!_spinning) {
      return child;
    }
    return RotationTransition(turns: _controller, child: child);
  }

  (IconData, Color) _iconAndColor() {
    if (_spinning) {
      return (AleraIcons.loading, AleraTokens.warning);
    }
    return switch (widget.conclusion) {
      ReviewCheckConclusion.success => (
        AleraIcons.success,
        AleraTokens.success,
      ),
      ReviewCheckConclusion.failure ||
      ReviewCheckConclusion.cancelled ||
      ReviewCheckConclusion.timedOut ||
      ReviewCheckConclusion.actionRequired => (
        AleraIcons.cancel,
        AleraTokens.error,
      ),
      ReviewCheckConclusion.neutral || ReviewCheckConclusion.skipped => (
        AleraIcons.circle,
        AleraTokens.foregroundMuted,
      ),
      ReviewCheckConclusion.pending => (
        AleraIcons.loading,
        AleraTokens.warning,
      ),
    };
  }
}
