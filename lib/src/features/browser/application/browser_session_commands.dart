part of 'browser_session_registry.dart';

final class BrowserOperationGuard {
  BrowserOperationGuard({
    required this.deadline,
    required this.cancellation,
    required this.isCancelled,
    required this.now,
  });

  final DateTime deadline;
  final Future<void> cancellation;
  final bool Function() isCancelled;
  final DateTime Function() now;

  void ensureActive() {
    if (isCancelled()) {
      throw const BrowserFailure(
        code: BrowserErrorCode.staleAutomationReference,
        message: 'The Browser Operation Was Cancelled.',
        recoverable: true,
      );
    }
    if (!now().isBefore(deadline)) {
      throw TimeoutException('The browser operation deadline has passed.');
    }
  }

  Future<T> run<T>(Future<T> operation) async {
    try {
      ensureActive();
      final remaining = deadline.difference(now());
      final result = await Future.any<T>(<Future<T>>[
        operation.timeout(remaining),
        cancellation.then<T>(
          (_) => throw const BrowserFailure(
            code: BrowserErrorCode.staleAutomationReference,
            message: 'The Browser Operation Was Cancelled.',
            recoverable: true,
          ),
        ),
      ]);
      ensureActive();
      return result;
    } catch (error, stackTrace) {
      try {
        await operation;
      } on Object {
        // The first error remains the caller-visible outcome.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}

extension _BrowserSessionRegistryCommands on BrowserSessionRegistry {
  Future<T> _runCommand<T>(
    _BrowserSessionEntry entry,
    BrowserLifecycleReason reason,
    Future<T> Function() operation, {
    BrowserOperationGuard? guard,
    bool serialized = true,
  }) async {
    guard?.ensureActive();
    if (serialized && entry.commandInFlight) {
      throw const BrowserFailure(
        code: BrowserErrorCode.operationInProgress,
        message: 'A Previous Native Browser Operation Is Still Draining.',
        recoverable: true,
      );
    }
    final lease = _acquireLifecycle(entry, reason);
    if (serialized) {
      entry.commandInFlight = true;
    }
    try {
      final work = () async {
        await entry.ready.future;
        guard?.ensureActive();
        _ensureOpen(entry);
        await _ensureOperational(entry);
        return operation();
      }();
      return await (guard?.run(work) ?? work);
    } finally {
      if (serialized) {
        entry.commandInFlight = false;
      }
      await lease.dispose();
    }
  }

  Future<BrowserNavigationTarget> _loadUrl(
    _BrowserSessionEntry entry,
    String input, {
    BrowserOperationGuard? guard,
  }) async {
    final searchEngine = await _readSearchEngine();
    final target = BrowserNavigationPolicy(
      searchEngine: searchEngine,
    ).resolve(input);
    await _runCommand<void>(
      entry,
      BrowserLifecycleReason.command,
      () => _engine.loadUrl(entry.pageId, target.url),
      guard: guard,
    );
    return target;
  }

  Future<T> _withFlutterOverlay<T>(
    _BrowserSessionEntry entry,
    Future<T> Function() operation,
  ) {
    return _runCommand<T>(entry, BrowserLifecycleReason.overlay, () async {
      final firstOverlay = entry.overlayCount++ == 0;
      try {
        if (firstOverlay) {
          await _queueOverlay(
            entry,
            () => _engine.setPageObscured(entry.pageId, obscured: true),
          );
        } else {
          await entry.overlayTail;
        }
        return await operation();
      } finally {
        if (entry.overlayCount > 0) {
          entry.overlayCount -= 1;
        }
        if (entry.overlayCount == 0) {
          await _queueOverlay(
            entry,
            () => _engine.setPageObscured(entry.pageId, obscured: false),
          );
        }
      }
    }, serialized: false);
  }

  Future<void> _queueOverlay(
    _BrowserSessionEntry entry,
    Future<void> Function() operation,
  ) {
    final next = entry.overlayTail
        .catchError((Object _) {})
        .then((_) => operation());
    entry.overlayTail = next;
    return next;
  }
}
