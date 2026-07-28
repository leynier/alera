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
final class AleraBrowserUserGestureToken {
  @internal
  const AleraBrowserUserGestureToken.internal(this.id, this.issuedAt);

  final String id;
  final DateTime issuedAt;
}

final class AleraBrowserCookieImportSourceStatus {
  const AleraBrowserCookieImportSourceStatus({
    required this.source,
    required this.supported,
    required this.available,
    this.profileNames = const <String>[],
    this.detailCode,
  });

  final AleraBrowserCookieImportSource source;
  final bool supported;
  final bool available;
  final List<String> profileNames;
  final String? detailCode;
}

sealed class AleraBrowserCookieImportRequest {
  const AleraBrowserCookieImportRequest({
    required this.profileId,
    required this.gestureToken,
  });

  final String profileId;
  final AleraBrowserUserGestureToken gestureToken;
}

final class AleraBrowserNativeCookieImportRequest
    extends AleraBrowserCookieImportRequest {
  const AleraBrowserNativeCookieImportRequest({
    required super.profileId,
    required super.gestureToken,
    required this.source,
    required this.sourceProfileName,
  }) : assert(source != AleraBrowserCookieImportSource.manualJson);

  final AleraBrowserCookieImportSource source;
  final String sourceProfileName;
}

final class AleraBrowserManualCookieImportRequest
    extends AleraBrowserCookieImportRequest {
  const AleraBrowserManualCookieImportRequest({
    required super.profileId,
    required super.gestureToken,
    required this.json,
  });

  /// JSON remains in memory and is never staged as plaintext by the plugin.
  final String json;
}

enum AleraBrowserCookieImportOutcome {
  imported,
  partiallyImported,
  unavailable,
  unsupported,
  denied,
  failed,
}

/// Redacted import summary. Cookie names and values are intentionally absent.
final class AleraBrowserCookieImportResult {
  const AleraBrowserCookieImportResult({
    required this.source,
    required this.profileId,
    required this.outcome,
    required this.importedCount,
    required this.skippedCount,
    this.detailCode,
  });

  final AleraBrowserCookieImportSource source;
  final String profileId;
  final AleraBrowserCookieImportOutcome outcome;
  final int importedCount;
  final int skippedCount;
  final String? detailCode;
}
