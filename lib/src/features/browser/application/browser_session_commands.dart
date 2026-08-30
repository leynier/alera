part of 'browser_session_registry.dart';

final class BrowserOperationGuard({
  required final DateTime deadline,
  required final Future<void> cancellation,
  required final bool Function() isCancelled,
  required final DateTime Function() now,
}) {
  void ensureActive() {
    if (isCancelled()) {
      throw const BrowserFailure(
        code: .staleAutomationReference,
        message: 'The browser operation was cancelled.',
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
            code: .staleAutomationReference,
            message: 'The browser operation was cancelled.',
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
        code: .operationInProgress,
        message: 'A previous native browser operation is still draining.',
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
    final target = BrowserNavigationPolicy(searchEngine: searchEngine)
        .resolve(input);
    await _runCommand<void>(
      entry,
      .command,
      () => _engine.loadUrl(entry.pageId, target.url),
      guard: guard,
    );
    return target;
  }

  Future<T> _withFlutterOverlay<T>(
    _BrowserSessionEntry entry,
    Future<T> Function() operation,
  ) async {
    final obscuration = _acquireObscuration(entry, .overlay);
    try {
      await obscuration.ready;
      return await operation();
    } finally {
      await obscuration.dispose();
    }
  }
}
