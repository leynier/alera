enum AleraBrowserPermissionDecision { deny, allow }

final class const AleraBrowserPermissionRequest({
  required final String pageId,
  required final Set<String> resources,
  final Uri? origin,
});

enum AleraBrowserTlsDecision { cancel, proceed }

enum AleraBrowserTlsErrorType {
  untrustedIssuer,
  nameMismatch,
  expired,
  notYetValid,
  revoked,
  insecure,
  other,
}

final class const AleraBrowserTlsError({
  required final String pageId,
  required final String host,
  required final String fingerprintSha256,
  final Uri? url,
  final String? description,
  final String? subject,
  final String? issuer,
  final DateTime? validFrom,
  final DateTime? validTo,
  final Set<AleraBrowserTlsErrorType> errors =
      const <AleraBrowserTlsErrorType>{},
});

enum AleraBrowserPopupDisposition { deny, newPage }

final class const AleraBrowserPopupRequest({
  required final String requestId,
  required final String pageId,
  required final String transientPageId,
  required final bool userInitiated,
  required final bool trusted,
  required final bool requiresOpener,
  final Uri? url,
  final String? windowName,
});

final class AleraBrowserPopupDecision {
  const new deny()
    : disposition = AleraBrowserPopupDisposition.deny,
      targetPageId = null;

  const new openInPage(this.targetPageId)
    : disposition = AleraBrowserPopupDisposition.newPage;

  final AleraBrowserPopupDisposition disposition;
  final String? targetPageId;
}

enum AleraBrowserDownloadDisposition { deny, accept }

final class const AleraBrowserDownloadRequest({
  required final String pageId,
  required final Uri url,
  final String? suggestedFileName,
  final String? mimeType,
  final int? totalBytes,
});

final class AleraBrowserDownloadDecision {
  const new deny()
    : disposition = AleraBrowserDownloadDisposition.deny,
      destinationPath = null;

  const new accept({required this.destinationPath})
    : disposition = AleraBrowserDownloadDisposition.accept;

  final AleraBrowserDownloadDisposition disposition;
  final String? destinationPath;
}

typedef AleraBrowserPermissionCallback =
    Future<AleraBrowserPermissionDecision> Function(
      AleraBrowserPermissionRequest request,
    );
typedef AleraBrowserTlsCallback = Future<AleraBrowserTlsDecision> Function(
  AleraBrowserTlsError error,
);
typedef AleraBrowserPopupCallback = Future<AleraBrowserPopupDecision> Function(
  AleraBrowserPopupRequest request,
);
typedef AleraBrowserDownloadCallback =
    Future<AleraBrowserDownloadDecision> Function(
      AleraBrowserDownloadRequest request,
    );

/// Security-sensitive decisions. Missing callbacks always deny or cancel.
final class const AleraBrowserCallbacks({
  final AleraBrowserPermissionCallback? onPermissionRequest,
  final AleraBrowserTlsCallback? onTlsError,
  final AleraBrowserPopupCallback? onPopupRequest,
  final AleraBrowserDownloadCallback? onDownloadRequest,
});
