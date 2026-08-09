part of 'codex_chat_surface.dart';

class _CodexViewportAnchor {
  const _CodexViewportAnchor({required this.entryKey, required this.top});

  final String entryKey;
  final double top;
}

extension _CodexTimelineViewport on _CodexTimelineState {
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
