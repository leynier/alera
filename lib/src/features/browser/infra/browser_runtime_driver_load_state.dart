part of 'browser_runtime_driver.dart';

BrowserLoadPhase? _browserExpectedLoadPhase(Object? value) {
  if (value == null || value == '') {
    return null;
  }
  if (value is String) {
    for (final phase in BrowserLoadPhase.values) {
      if (phase != BrowserLoadPhase.failed && phase.name == value) {
        return phase;
      }
    }
  }
  throw const BrowserFailure(
    code: BrowserErrorCode.invalidPayload,
    message: 'Browser Load State Must Be Started, Committed, Or Finished.',
    recoverable: true,
  );
}

bool _browserLoadPhaseReached(
  BrowserLoadPhase actual,
  BrowserLoadPhase? expected,
) {
  if (expected == null) {
    return true;
  }
  return switch (expected) {
    BrowserLoadPhase.started => actual != BrowserLoadPhase.failed,
    BrowserLoadPhase.committed =>
      actual == BrowserLoadPhase.committed ||
          actual == BrowserLoadPhase.finished,
    BrowserLoadPhase.finished => actual == BrowserLoadPhase.finished,
    BrowserLoadPhase.failed => false,
  };
}
