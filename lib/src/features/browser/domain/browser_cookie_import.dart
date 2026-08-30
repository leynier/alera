import 'package:alera/src/features/browser/domain/browser_profile.dart';

const browserManualCookieImportMaximumBytes = 16 * 1024 * 1024;

enum BrowserCookieImportOutcome {
  imported,
  partiallyImported,
  unavailable,
  unsupported,
  denied,
  failed,
}

final class const BrowserCookieImportGesture({
  required final String id,
  required final DateTime issuedAt,
});

final class const BrowserCookieImportSourceStatus({
  required final BrowserImportSourceFamily source,
  required final bool supported,
  required final bool available,
  final List<String> profileNames = const <String>[],
  final String? detailCode,
});

final class const BrowserCookieImportResult({
  required final BrowserImportSourceFamily source,
  required final String profileId,
  required final BrowserCookieImportOutcome outcome,
  required final int importedCount,
  required final int skippedCount,
  final String? detailCode,
}) {
  bool get completedAtomically =>
      outcome == BrowserCookieImportOutcome.imported;
}
