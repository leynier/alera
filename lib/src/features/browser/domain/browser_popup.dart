final class const BrowserPopupRequest({
  required final String requestId,
  required final String openerPageId,
  required final String transientPageId,
  required final bool userInitiated,
  required final bool trusted,
  required final bool requiresOpener,
  required final DateTime requestedAt,
  final Uri? url,
  final String? windowName,
});

final class BrowserPopupDecision {
  const new deny() : targetPageId = null;

  const new openInPage(this.targetPageId);

  final String? targetPageId;

  bool get accepted => targetPageId != null && targetPageId!.trim().isNotEmpty;
}
