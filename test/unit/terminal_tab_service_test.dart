import 'package:alera/src/features/workbench/application/terminal_tab_service.dart';
import 'package:alera/src/features/workbench/application/workbench_repository.dart';
import 'package:alera/src/features/workbench/domain/terminal_tab_record.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TerminalTabService', () {
    test('ensureInitialTab creates the first terminal tab when none exist', () async {
      final repository = _FakeWorkbenchRepository();
      final service = TerminalTabService(
        repository: repository,
        now: () => DateTime.utc(2026, 5, 21),
      );

      final tab = await service.ensureInitialTab('workspace-1');

      expect(tab.title, 'Terminal 1');
      expect(repository.tabs.single.title, 'Terminal 1');
    });

    test('createTab picks the next available terminal ordinal', () async {
      final repository = _FakeWorkbenchRepository()
        ..tabs.addAll(<TerminalTabRecord>[
          TerminalTabRecord(
            id: 'tab-1',
            workspaceId: 'workspace-1',
            title: 'Terminal 1',
            createdAt: DateTime.utc(2026, 5, 21),
            updatedAt: DateTime.utc(2026, 5, 21),
          ),
          TerminalTabRecord(
            id: 'tab-3',
            workspaceId: 'workspace-1',
            title: 'Terminal 3',
            createdAt: DateTime.utc(2026, 5, 21),
            updatedAt: DateTime.utc(2026, 5, 21),
          ),
        ]);
      final service = TerminalTabService(
        repository: repository,
        now: () => DateTime.utc(2026, 5, 21, 1),
      );

      final tab = await service.createTab('workspace-1');

      expect(tab.title, 'Terminal 2');
      expect(repository.tabs.map((record) => record.title), contains('Terminal 2'));
    });
  });
}

class _FakeWorkbenchRepository implements WorkbenchRepository {
  final List<TerminalTabRecord> tabs = <TerminalTabRecord>[];

  @override
  Future<Workspace?> findWorkspaceById(String workspaceId) async => null;

  @override
  Future<TerminalTabRecord?> findTerminalTabById(String tabId) async => null;

  @override
  Future<List<TerminalTabRecord>> listTerminalTabs(String workspaceId) async {
    return tabs
        .where((tab) => tab.workspaceId == workspaceId)
        .toList(growable: false);
  }

  @override
  Future<List<Workspace>> listWorkspaces(String projectId) async =>
      const <Workspace>[];

  @override
  Future<void> removeTerminalTab(String tabId) async {
    tabs.removeWhere((tab) => tab.id == tabId);
  }

  @override
  Future<void> removeTerminalTabsForWorkspace(String workspaceId) async {}

  @override
  Future<void> removeWorkspace(String workspaceId, {bool cascadeTabs = true}) async {}

  @override
  Future<void> removeWorkspacesForProject(String projectId) async {}

  @override
  Future<TerminalTabRecord> upsertTerminalTab(TerminalTabRecord tab) async {
    final index = tabs.indexWhere((record) => record.id == tab.id);
    if (index == -1) {
      tabs.add(tab);
    } else {
      tabs[index] = tab;
    }
    return tab;
  }

  @override
  Future<Workspace> upsertWorkspace(Workspace workspace) async => workspace;

  @override
  Stream<List<TerminalTabRecord>> watchTerminalTabs(String workspaceId) =>
      const Stream<List<TerminalTabRecord>>.empty();

  @override
  Stream<List<Workspace>> watchWorkspaces(String projectId) =>
      const Stream<List<Workspace>>.empty();
}
