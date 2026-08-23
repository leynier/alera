part of 'browser_session_registry.dart';

extension _BrowserSessionRegistryLeases on BrowserSessionRegistry {
  BrowserVisibilityLease? _tryAcquireVisibility(
    _BrowserSessionEntry entry,
    BrowserVisibilityReason reason,
  ) {
    _checkNotDisposed();
    if (entry.closing || entry.closed) {
      return null;
    }
    return _acquireVisibility(entry, reason);
  }

  BrowserVisibilityLease _acquireVisibility(
    _BrowserSessionEntry entry,
    BrowserVisibilityReason reason,
  ) {
    _ensureOpen(entry);
    final first = entry.visibilityCount++ == 0;
    final ready = first
        ? _queueVisibility(entry, () async {
            await entry.ready.future;
            await _ensureOperational(entry);
            await _engine.attachPage(entry.pageId);
          })
        : entry.visibilityTail;
    return BrowserVisibilityLease._(
      reason: reason,
      ready: ready,
      release: () async {
        if (--entry.visibilityCount == 0) {
          await _queueVisibility(entry, () async {
            if (entry.created && !entry.closed) {
              await _engine.detachPage(entry.pageId);
            }
          });
        }
      },
    );
  }

  BrowserObscurationLease _acquireObscuration(
    _BrowserSessionEntry entry,
    BrowserObscurationReason reason,
  ) {
    _ensureOpen(entry);
    final lifecycle = _acquireLifecycle(entry, BrowserLifecycleReason.overlay);
    final first = entry.obscurationCount++ == 0;
    final ready = first
        ? _queueObscuration(entry, () async {
            await entry.ready.future;
            await _ensureOperational(entry);
            await _engine.setPageObscured(entry.pageId, obscured: true);
          })
        : entry.obscurationTail;
    return BrowserObscurationLease._(
      reason: reason,
      ready: ready,
      release: () async {
        try {
          if (entry.obscurationCount > 0) {
            entry.obscurationCount -= 1;
          }
          if (entry.obscurationCount == 0) {
            await _queueObscuration(entry, () async {
              if (entry.created && !entry.closed) {
                await _engine.setPageObscured(entry.pageId, obscured: false);
              }
            });
          }
        } finally {
          await lifecycle.dispose();
        }
      },
    );
  }

  BrowserLifecycleLease _acquireLifecycleForHandle(
    _BrowserSessionEntry entry,
    BrowserLifecycleReason reason,
  ) => _acquireLifecycle(entry, reason);

  BrowserLifecycleLease _acquireLifecycle(
    _BrowserSessionEntry entry,
    BrowserLifecycleReason reason,
  ) {
    _ensureOpen(entry);
    entry.lifecycleCount += 1;
    return BrowserLifecycleLease._(
      reason: reason,
      release: () => _releaseLifecycle(entry),
    );
  }

  Future<void> _releaseLifecycle(_BrowserSessionEntry entry) async {
    if (entry.lifecycleCount > 0) {
      entry.lifecycleCount -= 1;
    }
    if (entry.closing && entry.lifecycleCount == 0) {
      await _finishClose(entry);
    }
  }

  Future<void> _queueVisibility(
    _BrowserSessionEntry entry,
    Future<void> Function() operation,
  ) {
    final next = entry.visibilityTail
        .catchError((Object _) {})
        .then((_) => operation());
    entry.visibilityTail = next;
    return next;
  }

  Future<void> _queueObscuration(
    _BrowserSessionEntry entry,
    Future<void> Function() operation,
  ) {
    final next = entry.obscurationTail
        .catchError((Object _) {})
        .then((_) => operation());
    entry.obscurationTail = next;
    return next;
  }
}
