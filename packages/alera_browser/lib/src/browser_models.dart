enum AleraBrowserProfileStorage { persistent, ephemeral }

final class const AleraBrowserProfileOptions({
  required final String id,
  final AleraBrowserProfileStorage storage =
      AleraBrowserProfileStorage.persistent,
});

final class const AleraBrowserProfile({
  required final String id,
  required final AleraBrowserProfileStorage storage,
  required final bool isDefault,
});

final class const AleraBrowserPageOptions({
  final String? id,
  final String profileId = 'default',
  final Uri? initialUrl,
  final String? userAgent,
  final String? openerPageId,
  final bool transient = false,
});

final class const AleraBrowserPage({
  required final String id,
  required final String profileId,
  required final bool isAttached,
  required final bool transient,
  final Uri? url,
  final String? title,
  final String? openerPageId,
});

enum AleraBrowserCookieSameSite { none, lax, strict }

final class const AleraBrowserCookie({
  required final String name,
  required final String value,
  required final String domain,
  final String path = '/',
  final DateTime? expiresUtc,
  final bool secure = false,
  final bool httpOnly = false,
  final AleraBrowserCookieSameSite? sameSite,
  final bool? session,
});

final class const AleraBrowserCookieFilter({
  final Uri? url,
  final String? name,
  final String? domain,
  final String? path,
}) {
  bool get selectsAll =>
      url == null && name == null && domain == null && path == null;
}

enum AleraBrowserActionKind {
  click,
  focus,
  fill,
  clear,
  type,
  select,
  check,
  uncheck,
  hover,
  scrollIntoView,
  scroll,
  drag,
  keyPress,
  upload,
}

final class const AleraBrowserAction({
  required final AleraBrowserActionKind kind,
  required final String elementRef,
  final String? value,
  final List<String> values = const <String>[],
  final String? targetElementRef,
  final double offsetX = 0,
  final double offsetY = 0,
  final List<String> filePaths = const <String>[],
});

final class const AleraBrowserSnapshotNode({
  required final String ref,
  required final String role,
  required final String name,
  required final int depth,
  final String? value,
  final bool disabled = false,
  final bool? checked,
});

final class const AleraBrowserSnapshot({
  required final String pageId,
  required final String namespace,
  required final int pageGeneration,
  required final String snapshotId,
  required final Uri? url,
  required final String title,
  required final List<AleraBrowserSnapshotNode> nodes,
  required final int blockedCrossOriginFrameCount,
  final bool truncated = false,
});

final class const AleraBrowserSnapshotOptions({
  final bool includeSameOriginFrames = true,
  final bool failOnCrossOriginFrames = true,
  final bool interactiveOnly = false,
  final int maxNodes = 500,
}) {
  this : assert(maxNodes > 0 && maxNodes <= 5000);
}

enum AleraBrowserWaitKind { url, text, selector }

final class AleraBrowserWaitCondition {
  const new url(this.value, {this.exact = false})
    : kind = AleraBrowserWaitKind.url;

  const new text(this.value, {this.exact = false})
    : kind = AleraBrowserWaitKind.text;

  const new selector(this.value)
    : kind = AleraBrowserWaitKind.selector,
      exact = true;

  final AleraBrowserWaitKind kind;
  final String value;
  final bool exact;
}

final class const AleraBrowserArtifact({
  required final String path,
  required final String mimeType,
  required final int sizeBytes,
  final int? width,
  final int? height,
  final String? suggestedFileName,
});

final class const AleraBrowserScreenshotOptions({
  final bool fullPage = false,
  final double scale = 1,
});

final class const AleraBrowserPdfOptions({
  final bool landscape = false,
  final bool printBackground = true,
});
