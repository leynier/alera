enum AleraBrowserPermissionDecision { deny, allow }

final class AleraBrowserPermissionRequest {
  const AleraBrowserPermissionRequest({
    required this.pageId,
    required this.resources,
    this.origin,
  });

  final String pageId;
  final Uri? origin;
  final Set<String> resources;
}

enum AleraBrowserTlsDecision { cancel, proceed }

final class AleraBrowserTlsError {
  const AleraBrowserTlsError({
    required this.pageId,
    this.url,
    this.description,
  });

  final String pageId;
  final Uri? url;
  final String? description;
}

enum AleraBrowserPopupDisposition { deny, newPage }

final class AleraBrowserPopupRequest {
  const AleraBrowserPopupRequest({
    required this.requestId,
    required this.pageId,
    required this.transientPageId,
    required this.userInitiated,
    required this.trusted,
    required this.requiresOpener,
    this.url,
    this.windowName,
  });

  final String requestId;
  final String pageId;
  final String transientPageId;
  final Uri? url;
  final String? windowName;
  final bool userInitiated;
  final bool trusted;
  final bool requiresOpener;
}

final class AleraBrowserPopupDecision {
  const AleraBrowserPopupDecision.deny()
    : disposition = AleraBrowserPopupDisposition.deny,
      targetPageId = null;

  const AleraBrowserPopupDecision.openInPage(this.targetPageId)
    : disposition = AleraBrowserPopupDisposition.newPage;

  final AleraBrowserPopupDisposition disposition;
  final String? targetPageId;
}

enum AleraBrowserDownloadDisposition { deny, accept }

final class AleraBrowserDownloadRequest {
  const AleraBrowserDownloadRequest({
    required this.pageId,
    required this.url,
    this.suggestedFileName,
    this.mimeType,
    this.totalBytes,
  });

  final String pageId;
  final Uri url;
  final String? suggestedFileName;
  final String? mimeType;
  final int? totalBytes;
}

final class AleraBrowserDownloadDecision {
  const AleraBrowserDownloadDecision.deny()
    : disposition = AleraBrowserDownloadDisposition.deny,
      destinationPath = null;

  const AleraBrowserDownloadDecision.accept({required this.destinationPath})
    : disposition = AleraBrowserDownloadDisposition.accept;

  final AleraBrowserDownloadDisposition disposition;
  final String? destinationPath;
}

typedef AleraBrowserPermissionCallback =
    Future<AleraBrowserPermissionDecision> Function(
      AleraBrowserPermissionRequest request,
    );
typedef AleraBrowserTlsCallback =
    Future<AleraBrowserTlsDecision> Function(AleraBrowserTlsError error);
typedef AleraBrowserPopupCallback =
    Future<AleraBrowserPopupDecision> Function(
      AleraBrowserPopupRequest request,
    );
typedef AleraBrowserDownloadCallback =
    Future<AleraBrowserDownloadDecision> Function(
      AleraBrowserDownloadRequest request,
    );

/// Security-sensitive decisions. Missing callbacks always deny or cancel.
final class AleraBrowserCallbacks {
  const AleraBrowserCallbacks({
    this.onPermissionRequest,
    this.onTlsError,
    this.onPopupRequest,
    this.onDownloadRequest,
  });

  final AleraBrowserPermissionCallback? onPermissionRequest;
  final AleraBrowserTlsCallback? onTlsError;
  final AleraBrowserPopupCallback? onPopupRequest;
  final AleraBrowserDownloadCallback? onDownloadRequest;
}
