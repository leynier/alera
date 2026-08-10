part of 'codex_chat_surface.dart';

class _CodexViewportAnchor {
  const _CodexViewportAnchor({required this.entryKey, required this.top});

  final String entryKey;
  final double top;
}

extension _CodexTimelineViewport on _CodexTimelineState {
  void _scheduleScrollToBottom({bool animate = false}) {
    if (!mounted) return;
    _scrollToBottomRequested = true;
    _animateScrollToBottom = _animateScrollToBottom || animate;
    if (_scrollToBottomScheduled) return;
    _scrollToBottomScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_settleScrollToBottom());
    });
  }

  Future<void> _settleScrollToBottom() async {
    try {
      for (var attempt = 0; attempt < 6; attempt += 1) {
        if (!mounted || !widget.timeline.hasClients) return;
        final animate = _animateScrollToBottom;
        _animateScrollToBottom = false;
        _scrollToBottomRequested = false;
        if (_showScrollToBottom && !animate) return;
        final position = widget.timeline.position;
        final target = position.maxScrollExtent;
        if ((target - position.pixels).abs() >= AleraTokens.dividerExtent) {
          if (animate) {
            await widget.timeline.animateTo(
              target,
              duration: AleraTokens.durationMid,
              curve: Curves.easeOut,
            );
          } else {
            widget.timeline.jumpTo(target);
          }
        }
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted || !widget.timeline.hasClients) return;
        if (_showScrollToBottom) return;
        if (!_scrollToBottomRequested &&
            widget.timeline.position.extentAfter < AleraTokens.space2) {
          return;
        }
      }
    } finally {
      _scrollToBottomScheduled = false;
      if (mounted && _scrollToBottomRequested) {
        _scheduleScrollToBottom(animate: _animateScrollToBottom);
      }
    }
  }

  _CodexViewportAnchor? captureViewportAnchor() {
    final viewport =
        _timelineViewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (viewport == null || !viewport.hasSize) return null;
    final viewportTop = viewport.localToGlobal(Offset.zero).dy;
    final viewportBottom = viewportTop + viewport.size.height;
    _CodexViewportAnchor? result;
    for (final entry in _entryWidgets.entries) {
      final context = entry.value.anchorKey.currentContext;
      final box = context?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached || !box.hasSize) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      if (top >= viewportBottom || top + box.size.height <= viewportTop) {
        continue;
      }
      if (result == null || top < result.top) {
        result = _CodexViewportAnchor(entryKey: entry.key, top: top);
      }
    }
    _pinnedEntryKey = result?.entryKey;
    return result;
  }

  void restoreViewportAnchor(_CodexViewportAnchor? anchor) {
    if (anchor == null || !widget.timeline.hasClients) {
      _pinnedEntryKey = null;
      return;
    }
    final record = _entryWidgets[anchor.entryKey];
    final box =
        record?.anchorKey.currentContext?.findRenderObject() as RenderBox?;
    _pinnedEntryKey = null;
    if (box == null || !box.attached || !box.hasSize) return;
    final correction = box.localToGlobal(Offset.zero).dy - anchor.top;
    if (correction.abs() < 0.5) return;
    final position = widget.timeline.position;
    widget.timeline.jumpTo(
      (position.pixels + correction).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
  }

  void releaseViewportAnchor() => _pinnedEntryKey = null;
}
