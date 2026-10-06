part of 'workbench_controller_test.dart';

class _FakeSleepingWorkbenchRepository extends _FakeWorkbenchRepository
    implements WorkspaceSleepRepository {
  Stream<Map<String, List<String>>>? sleepSnapshots;

  Map<String, List<String>> sleptTabs = const <String, List<String>>{};

  @override
  Stream<Map<String, List<String>>> watchSleptWorkspaceTabs() =>
      sleepSnapshots ?? Stream<Map<String, List<String>>>.value(const {});

  Future<void> Function()? onSleep;

  @override
  Future<void> sleepWorkspace(String workspaceId) async {
    await onSleep?.call();
  }

  Completer<void>? sleptTabsGate;
  Object? sleptTabsError;

  @override
  Future<Map<String, List<String>>> listSleptWorkspaceTabs() async {
    final snapshot = sleptTabs;
    await sleptTabsGate?.future;
    if (sleptTabsError case final error?) throw error;
    return snapshot;
  }
}

void _registerWorkbenchControllerSleepBootstrapTests() {
  test(
    'bootstrap keeps terminals grey until the sleep snapshot arrives',
    () async {
      final snapshots = StreamController<Map<String, List<String>>>();
      _harness.workbenchRepository.sleepSnapshots = snapshots.stream;
      const tabId = 'persisted-terminal';
      await _harness.workbenchRepository.upsertWorkspaceTab(
        WorkspaceTabRecord(
          id: tabId,
          workspaceId: 'initial-task',
          title: 'Terminal',
          createdAt: _harness.project.createdAt,
          updatedAt: _harness.project.updatedAt,
        ),
      );

      await _controller.bootstrap();
      expect(_controller.state.bootstrapped, isTrue);
      expect(_controller.state.sleepSnapshotReady, isFalse);
      await _flushUntil(
        () => _harness.workbenchRepository.hasTabWatcher('initial-task'),
      );
      _harness.workbenchRepository.emitTabs('initial-task');
      await _flushUntil(
        () => _controller.state.tabsFor('initial-task').isNotEmpty,
      );

      WorkbenchWorkspaceRow row() =>
          buildSidebarRows(_controller.state)
              .whereType<WorkbenchWorkspaceRow>()
              .single;
      expect(row().hasTerminalTabs, isFalse);

      snapshots.add(<String, List<String>>{
        'initial-task': <String>[tabId],
      });
      await _flushUntil(() => _controller.state.sleepSnapshotReady);
      expect(row().hasTerminalTabs, isFalse);

      snapshots.add(const <String, List<String>>{});
      await _flushUntil(() => row().hasTerminalTabs);
      await snapshots.close();
    },
  );
}
