part of 'browser_session_registry.dart';

extension BrowserSessionRegistryReconciliation on BrowserSessionRegistry {
  Future<void> closeWorkspace(String workspaceId) async {
    final pageIds = <String>[
      for (final entry in _entries.values)
        if (entry.state.value.workspaceId == workspaceId) entry.pageId,
    ];
    await Future.wait(<Future<void>>[
      for (final pageId in pageIds) closePage(pageId),
    ]);
  }

  Future<void> reconcilePersistentTabs(
    Iterable<WorkspaceTabRecord> tabs, {
    bool Function()? isCurrent,
  }) async {
    final remainsCurrent = isCurrent ?? _alwaysCurrent;
    final browserTabs = <WorkspaceTabRecord>[
      for (final tab in tabs)
        if (tab.kind == WorkspaceTabKind.browser) tab,
    ];
    for (final tab in browserTabs) {
      if (!remainsCurrent()) {
        return;
      }
      final handle = await _reconcilePersistentSession(tab, remainsCurrent);
      if (handle == null) {
        return;
      }
    }
    if (!remainsCurrent()) {
      return;
    }
    await reconcilePersistentPages(<String>{
      for (final tab in browserTabs) tab.id,
    }, isCurrent: remainsCurrent);
  }

  Future<void> reconcilePersistentPages(
    Set<String> pageIds, {
    bool Function()? isCurrent,
  }) async {
    final remainsCurrent = isCurrent ?? _alwaysCurrent;
    final stalePageIds = <String>[
      for (final entry in _entries.values)
        if (!entry.transient && !pageIds.contains(entry.pageId)) entry.pageId,
    ];
    for (final pageId in stalePageIds) {
      if (!remainsCurrent()) {
        return;
      }
      await _closePageIf(pageId, remainsCurrent);
    }
  }

  Future<BrowserSessionHandle> reconcilePersistentSession(
    WorkspaceTabRecord tab,
  ) async => (await _reconcilePersistentSession(tab, _alwaysCurrent))!;

  Future<BrowserSessionHandle?> _reconcilePersistentSession(
    WorkspaceTabRecord tab,
    bool Function() remainsCurrent,
  ) async {
    final payload = _codec.decode(tab);
    final existing = _entries[payload.page.pageId];
    if (existing != null) {
      await existing.ready.future;
      if (!remainsCurrent()) {
        return null;
      }
      final currentPage = existing.state.value.page;
      if (currentPage.workspaceId != payload.page.workspaceId ||
          currentPage.profileId != payload.page.profileId) {
        await _closePageIf(payload.page.pageId, remainsCurrent);
      }
    }
    if (!remainsCurrent()) {
      return null;
    }
    return _sessionForPayload(payload);
  }
}

final class BrowserPersistentSessionReconciler {
  BrowserPersistentSessionReconciler(this._registry);

  final BrowserSessionRegistry _registry;
  Future<void> _tail = Future<void>.value();
  var _generation = 0;
  var _disposed = false;

  void schedule(Iterable<WorkspaceTabRecord> tabs) {
    if (_disposed) {
      return;
    }
    final snapshot = List<WorkspaceTabRecord>.unmodifiable(tabs);
    final generation = ++_generation;
    _tail = _tail.catchError((Object _) {}).then((_) async {
      if (!_isCurrent(generation)) {
        return;
      }
      for (var attempt = 0; attempt < 2; attempt += 1) {
        try {
          await _registry.reconcilePersistentTabs(
            snapshot,
            isCurrent: () => _isCurrent(generation),
          );
          return;
        } on Object {
          if (attempt == 1 || !_isCurrent(generation)) {
            rethrow;
          }
        }
      }
    });
    unawaited(_tail.catchError((Object _) {}));
  }

  @visibleForTesting
  Future<void> get settled => _tail;

  void dispose() {
    _disposed = true;
    _generation += 1;
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;
}

bool _alwaysCurrent() => true;
