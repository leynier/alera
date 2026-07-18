import 'dart:async';

import 'package:alera_mobile/src/features/runtime/domain/project_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_creation_result.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_list_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Loads workspaces and refreshes on runtime events', () async {
    final client = _FakeWorkspaceClient();
    final container = _container(client);

    final data = await container.read(
      workspaceListControllerProvider('host-1').future,
    );
    expect(data.workspaces.map((workspace) => workspace.id), <String>['a']);
    expect(data.supportsMutations, isTrue);

    client.workspaces = <WorkspaceSummary>[_workspace('a'), _workspace('b')];
    client.emit('workspacesChanged');
    await Future<void>.delayed(Duration.zero);

    final refreshed = await container.read(
      workspaceListControllerProvider('host-1').future,
    );
    expect(refreshed.workspaces, hasLength(2));
  });

  test('Mutations call the runtime and refresh the list', () async {
    final client = _FakeWorkspaceClient();
    final container = _container(client);
    final notifier = container.read(
      workspaceListControllerProvider('host-1').notifier,
    );
    await container.read(workspaceListControllerProvider('host-1').future);

    await notifier.setPinned('a', true);
    expect(client.calls, contains('setPinned a true'));

    await notifier.linkParent(childWorkspaceId: 'a', parentWorkspaceId: 'b');
    expect(client.calls, contains('link b a'));

    await notifier.unlinkParent(_workspace('a', parent: 'b'));
    expect(client.calls, contains('unlink b a'));

    await notifier.deleteWorkspace('a', deleteBranch: true);
    expect(client.calls, contains('remove a true'));

    final result = await notifier.createWorkspace(
      projectId: 'p1',
      branch: 'feature/x',
      sourceBranch: 'main',
    );
    expect(result.workspace.id, 'created');
    expect(client.calls, contains('create p1 feature/x main'));
  });

  test('Cascade preview returns the subtree ids', () async {
    final client = _FakeWorkspaceClient()..cascadeIds = <String>['a', 'child'];
    final container = _container(client);
    final notifier = container.read(
      workspaceListControllerProvider('host-1').notifier,
    );
    await container.read(workspaceListControllerProvider('host-1').future);

    expect(await notifier.cascadePreview('a'), <String>['a', 'child']);
  });
}

ProviderContainer _container(_FakeWorkspaceClient client) {
  final container = ProviderContainer(
    overrides: [
      workspaceClientProvider('host-1').overrideWith((ref) async => client),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(client.dispose);
  final subscription = container.listen(
    workspaceListControllerProvider('host-1'),
    (_, _) {},
  );
  addTearDown(subscription.close);
  return container;
}

WorkspaceSummary _workspace(String id, {String? parent}) {
  return WorkspaceSummary(
    id: id,
    projectId: 'p1',
    name: id,
    path: '/tmp/$id',
    parentWorkspaceId: parent,
  );
}

class _FakeWorkspaceClient implements MobileWorkspaceClient {
  final StreamController<MobileRuntimeEvent> _events =
      StreamController<MobileRuntimeEvent>.broadcast();
  final List<String> calls = <String>[];
  List<WorkspaceSummary> workspaces = <WorkspaceSummary>[_workspace('a')];
  List<String> cascadeIds = <String>['a'];

  void emit(String name) {
    _events.add(MobileRuntimeEvent(name, const <String, Object?>{}));
  }

  Future<void> dispose() => _events.close();

  @override
  Stream<MobileRuntimeEvent> get events => _events.stream;

  @override
  bool get supportsWorkspaceMutations => true;

  @override
  Future<List<ProjectSummary>> listProjects() async {
    return <ProjectSummary>[
      const ProjectSummary(id: 'p1', name: 'Project', repoPath: '/repo'),
    ];
  }

  @override
  Future<ProjectBranches> listBranches(String projectId) async {
    return ProjectBranches(
      projectId: projectId,
      branches: const <String>['main'],
      localBranches: const <String>['main'],
    );
  }

  @override
  Future<List<WorkspaceSummary>> listWorkspaces() async {
    return workspaces;
  }

  @override
  Future<void> setWorkspacePinned(String workspaceId, bool isPinned) async {
    calls.add('setPinned $workspaceId $isPinned');
  }

  @override
  Future<void> linkWorkspaces({
    required String parentWorkspaceId,
    required String childWorkspaceId,
  }) async {
    calls.add('link $parentWorkspaceId $childWorkspaceId');
  }

  @override
  Future<void> unlinkWorkspaces({
    required String parentWorkspaceId,
    required String childWorkspaceId,
  }) async {
    calls.add('unlink $parentWorkspaceId $childWorkspaceId');
  }

  @override
  Future<WorkspaceCreationResult> createManagedWorkspace({
    required String projectId,
    required String branch,
    String? sourceBranch,
    bool reuseExistingBranch = false,
    String? name,
    String? parentWorkspaceId,
  }) async {
    calls.add('create $projectId $branch $sourceBranch');
    return WorkspaceCreationResult(
      workspace: _workspace('created'),
      steps: const <WorkspaceSetupStep>[],
    );
  }

  @override
  Future<void> removeManagedWorkspace(
    String workspaceId, {
    bool? deleteBranch,
  }) async {
    calls.add('remove $workspaceId $deleteBranch');
  }

  @override
  Future<List<String>> cascadePreview(String workspaceId) async {
    return cascadeIds;
  }

  @override
  Future<void> removeTab(String tabId) async {
    calls.add('removeTab $tabId');
  }
}
