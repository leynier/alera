part of 'mobile_codex_chat_screen.dart';

class _MobilePlanPreview extends StatefulWidget {
  const _MobilePlanPreview({
    super.key,
    required this.initiallyOverflowing,
    required this.preserveOverflow,
    required this.onOverflowChanged,
    required this.child,
  });

  final bool initiallyOverflowing;
  final bool preserveOverflow;
  final ValueChanged<bool> onOverflowChanged;
  final Widget child;

  @override
  State<_MobilePlanPreview> createState() => _MobilePlanPreviewState();
}

class _MobilePlanPreviewState extends State<_MobilePlanPreview> {
  final ScrollController _controller = ScrollController();
  late bool _overflowing = widget.initiallyOverflowing;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _scheduleOverflowCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      final overflowing = _controller.position.maxScrollExtent > 0;
      if (!overflowing && widget.preserveOverflow && _overflowing) return;
      if (overflowing != _overflowing) {
        setState(() => _overflowing = overflowing);
        widget.onOverflowChanged(overflowing);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    _scheduleOverflowCheck();
    return ConstrainedBox(
      key: const ValueKey<String>('mobile-codex-plan-preview'),
      constraints: const BoxConstraints(
        maxHeight: AleraTokens.codexPlanPreviewHeight,
      ),
      child: Stack(
        children: <Widget>[
          ClipRect(
            child: SingleChildScrollView(
              controller: _controller,
              physics: const NeverScrollableScrollPhysics(),
              child: widget.child,
            ),
          ),
          if (_overflowing)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: AleraTokens.codexPlanPreviewFadeHeight,
              child: IgnorePointer(
                child: DecoratedBox(
                  key: const ValueKey<String>('mobile-codex-plan-preview-fade'),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        AleraTokens.surface.withValues(alpha: 0),
                        AleraTokens.surface.withValues(alpha: 0.08),
                        AleraTokens.surface.withValues(alpha: 0.3),
                        AleraTokens.surface.withValues(alpha: 0.68),
                        AleraTokens.surface,
                      ],
                      stops: const <double>[0, 0.25, 0.5, 0.75, 1],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
