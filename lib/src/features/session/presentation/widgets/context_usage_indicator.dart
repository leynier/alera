import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/session/domain/context_usage.dart';
import 'package:flutter/material.dart';

/// A circular progress indicator that shows how much of the context window
/// has been consumed. On hover, a tooltip-like popover appears showing
/// detailed token info and a manual compact button.
class ContextUsageIndicator extends StatefulWidget {
  const ContextUsageIndicator({
    super.key,
    required this.contextUsage,
    required this.onCompact,
  });

  final ContextUsage contextUsage;
  final VoidCallback onCompact;

  @override
  State<ContextUsageIndicator> createState() => _ContextUsageIndicatorState();
}

class _ContextUsageIndicatorState extends State<ContextUsageIndicator> {
  final _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _isHovering = false;

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ContextUsageIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_overlayEntry != null) {
      _overlayEntry!.markNeedsBuild();
    }
  }

  void _showOverlay() {
    if (_overlayEntry != null) return;
    _overlayEntry = OverlayEntry(builder: (_) => _buildOverlay());
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _onEnter(PointerEvent _) {
    _isHovering = true;
    _showOverlay();
  }

  void _onExit(PointerEvent _) {
    _isHovering = false;
    Future<void>.delayed(const Duration(milliseconds: 200), () {
      if (!_isHovering && mounted) {
        _removeOverlay();
      }
    });
  }

  Color _progressColor(double percentUsed) {
    if (percentUsed >= 0.9) return AleraTokens.error;
    if (percentUsed >= 0.75) return AleraTokens.warning;
    return AleraTokens.foregroundFaint;
  }

  @override
  Widget build(BuildContext context) {
    final usage = widget.contextUsage;
    final window = usage.contextWindowSize;
    if (window == null || window <= 0) {
      return const SizedBox.shrink();
    }

    final total = usage.tokensInContext;
    if (total <= 0) {
      return const SizedBox.shrink();
    }

    final percentUsed = (total / window).clamp(0.0, 1.0);
    final color = _progressColor(percentUsed);

    return CompositedTransformTarget(
      link: _layerLink,
      child: MouseRegion(
        onEnter: _onEnter,
        onExit: _onExit,
        cursor: SystemMouseCursors.click,
        child: SizedBox(
          width: 16,
          height: 16,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              RepaintBoundary(
                child: SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    value: percentUsed,
                    strokeWidth: 1.5,
                    color: color,
                    backgroundColor: AleraTokens.border,
                  ),
                ),
              ),
              if (usage.isCompacting)
                const RepaintBoundary(
                  child: SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: AleraTokens.accent,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOverlay() {
    final usage = widget.contextUsage;
    final total = usage.tokensInContext;
    final window = usage.contextWindowSize ?? 0;
    final percentUsed = window > 0 ? (total / window).clamp(0.0, 1.0) : 0.0;
    final percentLeft = ((1 - percentUsed) * 100).toInt();

    return Positioned(
      width: 240,
      child: CompositedTransformFollower(
        link: _layerLink,
        targetAnchor: Alignment.topCenter,
        followerAnchor: Alignment.bottomCenter,
        offset: const Offset(0, -8),
        child: MouseRegion(
          onEnter: (_) => _isHovering = true,
          onExit: (_) {
            _isHovering = false;
            Future<void>.delayed(const Duration(milliseconds: 150), () {
              if (!_isHovering && mounted) {
                _removeOverlay();
              }
            });
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
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'Context window:',
                    style: TextStyle(
                      color: AleraTokens.foreground,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AleraTokens.space6),
                  Text(
                    '${(percentUsed * 100).toInt()}% used ($percentLeft% left)',
                    style: const TextStyle(
                      color: AleraTokens.foregroundMuted,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: AleraTokens.space4),
                  Text(
                    '${_formatTokens(total)} / ${_formatTokens(window)} tokens used',
                    style: const TextStyle(
                      color: AleraTokens.foregroundMuted,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: AleraTokens.space8),
                  // Credits info (if available).
                  if (usage.rateLimits?.credits != null &&
                      usage.rateLimits!.credits!.balance != null) ...<Widget>[
                    Text(
                      'Credits: ${usage.rateLimits!.credits!.balance}',
                      style: const TextStyle(
                        color: AleraTokens.foregroundMuted,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: AleraTokens.space8),
                  ],
                  const Divider(height: 1, color: AleraTokens.border),
                  const SizedBox(height: AleraTokens.space8),
                  if (usage.isCompacting)
                    const Text(
                      'Compacting context...',
                      style: TextStyle(
                        color: AleraTokens.foregroundMuted,
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                    )
                  else
                    SizedBox(
                      width: double.infinity,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () {
                            _removeOverlay();
                            widget.onCompact();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: AleraTokens.space6,
                            ),
                            decoration: BoxDecoration(
                              color: AleraTokens.surfaceVariant,
                              borderRadius: BorderRadius.circular(
                                AleraTokens.radiusMd,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: const Text(
                              'Compact context',
                              style: TextStyle(
                                color: AleraTokens.foreground,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatTokens(int count) {
    if (count >= 1000000) {
      final m = count / 1000000;
      return '${m.toStringAsFixed(m.truncateToDouble() == m ? 0 : 1)}M';
    }
    if (count >= 1000) {
      final k = count / 1000;
      return '${k.toStringAsFixed(k.truncateToDouble() == k ? 0 : 1)}k';
    }
    return count.toString();
  }
}
