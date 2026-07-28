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

final class BrowserCookieImportGesture {
  const BrowserCookieImportGesture({required this.id, required this.issuedAt});

  final String id;
  final DateTime issuedAt;
}

final class BrowserCookieImportSourceStatus {
  const BrowserCookieImportSourceStatus({
    required this.source,
    required this.supported,
    required this.available,
    this.profileNames = const <String>[],
    this.detailCode,
  });

  final BrowserImportSourceFamily source;
  final bool supported;
  final bool available;
  final List<String> profileNames;
  final String? detailCode;
}

final class BrowserCookieImportResult {
  const BrowserCookieImportResult({
    required this.source,
    required this.profileId,
    required this.outcome,
    required this.importedCount,
    required this.skippedCount,
    this.detailCode,
  });

  final BrowserImportSourceFamily source;
  final String profileId;
  final BrowserCookieImportOutcome outcome;
  final int importedCount;
  final int skippedCount;
  final String? detailCode;

  bool get completedAtomically =>
      outcome == BrowserCookieImportOutcome.imported;
}
