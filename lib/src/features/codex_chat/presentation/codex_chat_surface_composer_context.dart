part of 'codex_chat_surface.dart';

class _CodexContextUsageIndicator extends StatefulWidget {
  const _CodexContextUsageIndicator({
    required this.used,
    required this.limit,
    required this.onCompact,
  });

  final int used;
  final int limit;
  final VoidCallback onCompact;

  @override
  State<_CodexContextUsageIndicator> createState() =>
      _CodexContextUsageIndicatorState();
}

class _CodexContextUsageIndicatorState
    extends State<_CodexContextUsageIndicator> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlay;
  bool _hovered = false;

  double get _fraction => (widget.used / widget.limit).clamp(0.0, 1.0);

  @override
  void didUpdateWidget(covariant _CodexContextUsageIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    _overlay?.markNeedsBuild();
  }

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  void _showOverlay() {
    if (_overlay != null) return;
    _overlay = OverlayEntry(builder: (_) => _buildOverlay());
    Overlay.of(context).insert(_overlay!);
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  void _scheduleHide() {
    Future<void>.delayed(AleraTokens.durationMid, () {
      if (mounted && !_hovered) _removeOverlay();
    });
  }

  @override
  Widget build(BuildContext context) {
    final color = _fraction >= 0.9
        ? AleraTokens.error
        : _fraction >= 0.75
        ? AleraTokens.warning
        : AleraTokens.foregroundFaint;
    return CompositedTransformTarget(
      link: _layerLink,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) {
          _hovered = true;
          _showOverlay();
        },
        onExit: (_) {
          _hovered = false;
          _scheduleHide();
        },
        child: SizedBox.square(
          dimension: AleraTokens.space16,
          child: CircularProgressIndicator(
            value: _fraction,
            strokeWidth: AleraTokens.strokeThin,
            color: color,
            backgroundColor: AleraTokens.border,
          ),
        ),
      ),
    );
  }

  Widget _buildOverlay() => Positioned(
    width: AleraTokens.contextMenuWidth,
    child: CompositedTransformFollower(
      link: _layerLink,
      targetAnchor: Alignment.topRight,
      followerAnchor: Alignment.bottomRight,
      offset: const Offset(0, -AleraTokens.space8),
      child: MouseRegion(
        onEnter: (_) => _hovered = true,
        onExit: (_) {
          _hovered = false;
          _scheduleHide();
        },
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(AleraTokens.space12),
            decoration: BoxDecoration(
              color: AleraTokens.surfaceElevated,
              borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
              border: Border.all(color: AleraTokens.border),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: AleraTokens.shadowSoft,
                  blurRadius: AleraTokens.space12,
                  offset: Offset(0, AleraTokens.space4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Text('Context Window'),
                const SizedBox(height: AleraTokens.space4),
                Text(
                  '${(_fraction * 100).round()}% used - ${_formatCodexTokens(widget.used)} / ${_formatCodexTokens(widget.limit)} tokens',
                  style: const TextStyle(color: AleraTokens.foregroundMuted),
                ),
                const SizedBox(height: AleraTokens.space8),
                TextButton(
                  onPressed: () {
                    _removeOverlay();
                    widget.onCompact();
                  },
                  child: const Text('Compact Context'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

String _formatCodexTokens(int value) {
  if (value >= 1000000) {
    return '${(value / 1000000).toStringAsFixed(1)}M';
  }
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
  return value.toString();
}
