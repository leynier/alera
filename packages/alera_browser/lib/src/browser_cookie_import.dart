import 'package:meta/meta.dart';

enum AleraBrowserCookieImportSource {
  chrome,
  edge,
  arc,
  brave,
  comet,
  helium,
  firefox,
  safari,
  manualJson,
}

extension AleraBrowserCookieImportSourceId on AleraBrowserCookieImportSource {
  String get id => switch (this) {
    AleraBrowserCookieImportSource.chrome => 'chrome',
    AleraBrowserCookieImportSource.edge => 'edge',
    AleraBrowserCookieImportSource.arc => 'arc',
    AleraBrowserCookieImportSource.brave => 'brave',
    AleraBrowserCookieImportSource.comet => 'comet',
    AleraBrowserCookieImportSource.helium => 'helium',
    AleraBrowserCookieImportSource.firefox => 'firefox',
    AleraBrowserCookieImportSource.safari => 'safari',
    AleraBrowserCookieImportSource.manualJson => 'manualJson',
  };
}

/// Opaque, short-lived proof that cookie discovery started from explicit UI.
final class const AleraBrowserUserGestureToken.internal(
  final String id,
  final DateTime issuedAt,
) {
  @internal
  this;
}

final class const AleraBrowserCookieImportSourceStatus({
  required final AleraBrowserCookieImportSource source,
  required final bool supported,
  required final bool available,
  final List<String> profileNames = const <String>[],
  final String? detailCode,
});

sealed class const AleraBrowserCookieImportRequest({
  required final String profileId,
  required final AleraBrowserUserGestureToken gestureToken,
});

final class const AleraBrowserNativeCookieImportRequest({
  required super.profileId,
  required super.gestureToken,
  required final AleraBrowserCookieImportSource source,
  required final String sourceProfileName,
}) extends AleraBrowserCookieImportRequest {
  this : assert(source != AleraBrowserCookieImportSource.manualJson);
}

final class const AleraBrowserManualCookieImportRequest({
  required super.profileId,
  required super.gestureToken,

  /// JSON remains in memory and is never staged as plaintext by the plugin.
  required final String json,
}) extends AleraBrowserCookieImportRequest;

enum AleraBrowserCookieImportOutcome {
  imported,
  partiallyImported,
  unavailable,
  unsupported,
  denied,
  failed,
}

/// Redacted import summary. Cookie names and values are intentionally absent.
final class const AleraBrowserCookieImportResult({
  required final AleraBrowserCookieImportSource source,
  required final String profileId,
  required final AleraBrowserCookieImportOutcome outcome,
  required final int importedCount,
  required final int skippedCount,
  final String? detailCode,
});
