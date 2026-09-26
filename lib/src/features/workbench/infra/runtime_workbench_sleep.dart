part of 'runtime_workbench_repository.dart';

mixin _RuntimeWorkbenchSleep implements WorkspaceSleepRepository {
  RuntimeHostClient get _client;
  RuntimeChangeCoalescer get _coalescer;
  Future<void> _ensureReady();

  @override
  Stream<Map<String, List<String>>> watchSleptWorkspaceTabs() =>
      runtimeSnapshotStream(
        client: _client,
        eventNames: const {'workspaceSleepChanged', 'workspaceTabsChanged'},
        readSnapshot: _listSleptWorkspaceTabs,
        coalesceKey: 'slept-workspace-tabs',
        coalescer: _coalescer,
      );

  Future<Map<String, List<String>>> _listSleptWorkspaceTabs() async {
    await _ensureReady();
    final client = _client;
    // Keep watching an older host: an in-app update can add the capability.
    if (client is! RuntimeHostCapabilityClient ||
        !await (client as RuntimeHostCapabilityClient)
            .supportsRuntimeCapability(
              aleraRuntimeHostWorkspaceSleepStateCapability,
            )) {
      return const <String, List<String>>{};
    }
    return <String, List<String>>{
      for (final entry in _asMap(
        await _client.runtimeRequest('workspace.sleptTabs'),
      ).entries)
        entry.key: <String>[
          if (entry.value case final List<Object?> tabIds)
            for (final tabId in tabIds)
              if (tabId is String) tabId,
        ],
    };
  }
}
