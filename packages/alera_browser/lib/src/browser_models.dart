enum AleraBrowserProfileStorage { persistent, ephemeral }

final class AleraBrowserProfileOptions {
  const AleraBrowserProfileOptions({
    required this.id,
    this.storage = AleraBrowserProfileStorage.persistent,
  });

  final String id;
  final AleraBrowserProfileStorage storage;
}

final class AleraBrowserProfile {
  const AleraBrowserProfile({
    required this.id,
    required this.storage,
    required this.isDefault,
  });

  final String id;
  final AleraBrowserProfileStorage storage;
  final bool isDefault;
}

final class AleraBrowserPageOptions {
  const AleraBrowserPageOptions({
    this.id,
    this.profileId = 'default',
    this.initialUrl,
    this.userAgent,
    this.openerPageId,
    this.transient = false,
  });

  final String? id;
  final String profileId;
  final Uri? initialUrl;
  final String? userAgent;
  final String? openerPageId;
  final bool transient;
}

final class AleraBrowserPage {
  const AleraBrowserPage({
    required this.id,
    required this.profileId,
    required this.isAttached,
    required this.transient,
    this.url,
    this.title,
    this.openerPageId,
  });

  final String id;
  final String profileId;
  final Uri? url;
  final String? title;
  final bool isAttached;
  final String? openerPageId;
  final bool transient;
}

enum AleraBrowserCookieSameSite { none, lax, strict }

final class AleraBrowserCookie {
  const AleraBrowserCookie({
    required this.name,
    required this.value,
    required this.domain,
    this.path = '/',
    this.expiresUtc,
    this.secure = false,
    this.httpOnly = false,
    this.sameSite,
    this.session,
  });

  final String name;
  final String value;
  final String domain;
  final String path;
  final DateTime? expiresUtc;
  final bool secure;
  final bool httpOnly;
  final AleraBrowserCookieSameSite? sameSite;
  final bool? session;
}

final class AleraBrowserCookieFilter {
  const AleraBrowserCookieFilter({this.url, this.name, this.domain, this.path});

  final Uri? url;
  final String? name;
  final String? domain;
  final String? path;

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

final class AleraBrowserAction {
  const AleraBrowserAction({
    required this.kind,
    required this.elementRef,
    this.value,
    this.values = const <String>[],
    this.targetElementRef,
    this.offsetX = 0,
    this.offsetY = 0,
    this.filePaths = const <String>[],
  });

  final AleraBrowserActionKind kind;
  final String elementRef;
  final String? value;
  final List<String> values;
  final String? targetElementRef;
  final double offsetX;
  final double offsetY;
  final List<String> filePaths;
}

final class AleraBrowserSnapshotNode {
  const AleraBrowserSnapshotNode({
    required this.ref,
    required this.role,
    required this.name,
    required this.depth,
    this.value,
    this.disabled = false,
    this.checked,
  });

  final String ref;
  final String role;
  final String name;
  final String? value;
  final int depth;
  final bool disabled;
  final bool? checked;
}

final class AleraBrowserSnapshot {
  const AleraBrowserSnapshot({
    required this.pageId,
    required this.namespace,
    required this.pageGeneration,
    required this.snapshotId,
    required this.url,
    required this.title,
    required this.nodes,
    required this.blockedCrossOriginFrameCount,
    this.truncated = false,
  });

  final String pageId;
  final String namespace;
  final int pageGeneration;
  final String snapshotId;
  final Uri? url;
  final String title;
  final List<AleraBrowserSnapshotNode> nodes;
  final int blockedCrossOriginFrameCount;
  final bool truncated;
}

final class AleraBrowserSnapshotOptions {
  const AleraBrowserSnapshotOptions({
    this.includeSameOriginFrames = true,
    this.failOnCrossOriginFrames = true,
    this.interactiveOnly = false,
    this.maxNodes = 500,
  }) : assert(maxNodes > 0 && maxNodes <= 5000);

  final bool includeSameOriginFrames;
  final bool failOnCrossOriginFrames;
  final bool interactiveOnly;
  final int maxNodes;
}

enum AleraBrowserWaitKind { url, text, selector }

final class AleraBrowserWaitCondition {
  const AleraBrowserWaitCondition.url(this.value, {this.exact = false})
    : kind = AleraBrowserWaitKind.url;

  const AleraBrowserWaitCondition.text(this.value, {this.exact = false})
    : kind = AleraBrowserWaitKind.text;

  const AleraBrowserWaitCondition.selector(this.value)
    : kind = AleraBrowserWaitKind.selector,
      exact = true;

  final AleraBrowserWaitKind kind;
  final String value;
  final bool exact;
}

final class AleraBrowserArtifact {
  const AleraBrowserArtifact({
    required this.path,
    required this.mimeType,
    required this.sizeBytes,
    this.width,
    this.height,
    this.suggestedFileName,
  });

  final String path;
  final String mimeType;
  final int sizeBytes;
  final int? width;
  final int? height;
  final String? suggestedFileName;
}

final class AleraBrowserScreenshotOptions {
  const AleraBrowserScreenshotOptions({this.fullPage = false, this.scale = 1});

  final bool fullPage;
  final double scale;
}

final class AleraBrowserPdfOptions {
  const AleraBrowserPdfOptions({
    this.landscape = false,
    this.printBackground = true,
  });

  final bool landscape;
  final bool printBackground;
}
