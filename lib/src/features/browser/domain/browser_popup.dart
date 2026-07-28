final class BrowserPopupRequest {
  const BrowserPopupRequest({
    required this.requestId,
    required this.openerPageId,
    required this.transientPageId,
    required this.userInitiated,
    required this.trusted,
    required this.requiresOpener,
    required this.requestedAt,
    this.url,
    this.windowName,
  });

  final String requestId;
  final String openerPageId;
  final String transientPageId;
  final Uri? url;
  final String? windowName;
  final bool userInitiated;
  final bool trusted;
  final bool requiresOpener;
  final DateTime requestedAt;
}

final class BrowserPopupDecision {
  const BrowserPopupDecision.deny() : targetPageId = null;

  const BrowserPopupDecision.openInPage(this.targetPageId);

  final String? targetPageId;

  bool get accepted => targetPageId != null && targetPageId!.trim().isNotEmpty;
}
