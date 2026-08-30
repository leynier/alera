import 'dart:async';

import 'package:alera_mobile/src/features/runtime/domain/agent_profile_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/project_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/prompt_image_upload.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_creation_result.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_sidebar_snapshot.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_list_controller.dart';
import 'package:alera_mobile/src/features/workbench/domain/mobile_view_prefs.dart';
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
    await Future.pause(.zero);

    final refreshed = await container.read(
      workspaceListControllerProvider('host-1').future,
    );
    expect(refreshed.workspaces, hasLength(2));
  });

  test('ignores a runtime event delivered after controller disposal', () async {
    final client = _FakeWorkspaceClient();
    final container = _container(client);

    await container.read(workspaceListControllerProvider('host-1').future);
    container.dispose();
    client.emitAfterDispose('workspacesChanged');
  });

  test(
    'does not subscribe when the client resolves after controller disposal',
    () async {
      final client = _FakeWorkspaceClient();
      final clientReady = Completer<MobileWorkspaceClient>();
      final container = ProviderContainer(
        overrides: [
          workspaceClientProvider('host-disposed-build')
              .overrideWith((ref) => clientReady.future),
        ],
      );
      final provider = workspaceListControllerProvider('host-disposed-build');
      final subscription = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      final result = container.read(provider.future);
      subscription.close();
      container.dispose();

      clientReady.complete(client);
      await result;
      expect(client.eventSubscriptionCount, 0);
      await client.dispose();
    },
  );

  test(
    'does not invalidate after a mutation completes after disposal',
    () async {
      final client = _FakeWorkspaceClient();
      final container = _container(client);
      final notifier = container.read(
        workspaceListControllerProvider('host-1').notifier,
      );
      await container.read(workspaceListControllerProvider('host-1').future);

      final completion = Completer<void>();
      client.pinCompletion = completion;
      final operation = notifier.setPinned('a', true);
      await Future.pause(.zero);
      container.dispose();

      completion.complete();
      await operation;
    },
  );

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

    await notifier.sleepWorkspace('a');
    expect(client.calls, contains('sleep a'));

    await notifier.deleteWorkspace('a', deleteBranch: true);
    expect(client.calls, contains('remove a true'));

    final result = await notifier.createWorkspace(
      projectId: 'p1',
      branch: 'feature/x',
      sourceBranch: 'main',
      parentWorkspaceId: 'b',
    );
    expect(result.workspace.id, 'created');
    expect(client.calls, contains('create p1 feature/x main null'));
    expect(client.calls, contains('link b created'));
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

class _FakeWorkspaceClient() implements MobileWorkspaceClient {
  this {
    _events = StreamController<MobileRuntimeEvent>.broadcast(
      onListen: () => eventSubscriptionCount += 1,
      onCancel: () => eventSubscriptionCount -= 1,
    );
  }

  late final StreamController<MobileRuntimeEvent> _events;
  final List<String> calls = <String>[];
  final List<void Function(MobileRuntimeEvent)> _eventListeners =
      <void Function(MobileRuntimeEvent)>[];
  Object? linkError;
  Completer<void>? pinCompletion;
  int eventSubscriptionCount = 0;
  List<WorkspaceSummary> workspaces = <WorkspaceSummary>[_workspace('a')];
  List<String> cascadeIds = <String>['a'];

  void emit(String name) {
    _events.add(MobileRuntimeEvent(name, const <String, Object?>{}));
  }

  void emitAfterDispose(String name) {
    final event = MobileRuntimeEvent(name, const <String, Object?>{});
    for (final listener in List<void Function(MobileRuntimeEvent)>.of(
      _eventListeners,
    )) {
      listener(event);
    }
  }

  Future<void> dispose() => _events.close();

  @override
  Stream<MobileRuntimeEvent> get events =>
      _CapturingEventStream(_events.stream, _eventListeners.add);

  @override
  bool get supportsWorkspaceMutations => true;

  @override
  bool get supportsWorkspaceSidebarParity => true;

  @override
  bool get supportsTabRename => true;

  @override
  bool get supportsPromptWorkspaceCreation => true;

  @override
  bool get supportsIdempotentAgentProfileLaunch => true;

  @override
  bool get supportsPromptImageUpload => true;

  @override
  Future<WorkspaceSidebarSnapshot> workspaceSidebarSnapshot() async {
    return WorkspaceSidebarSnapshot(
      projects: await listProjects(),
      workspaces: workspaces,
      tags: const <WorkspaceTagSummary>[],
      activity: const <String, DateTime>{},
      viewPrefs: const MobileViewPrefs(),
      confirmWorkspaceRemoval: true,
    );
  }

  @override
  Future<MobileViewPrefs> loadWorkbenchViewPrefs() async =>
      const MobileViewPrefs();

  @override
  Future<MobileViewPrefs> updateWorkbenchViewPrefs(
    MobileViewPrefs prefs,
  ) async => prefs.copyWith(revision: prefs.revision + 1);

  @override
  Future<List<AgentPresenceSummary>> listAgentPresence() async =>
      const <AgentPresenceSummary>[];

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
  Future<List<AgentProfileSummary>> listAgentProfiles() async {
    return const <AgentProfileSummary>[
      AgentProfileSummary(id: 'profile-1', name: 'Codex', agentType: 'codex'),
    ];
  }

  @override
  Future<GeneratedWorkspaceIdentity> generateWorkspaceIdentity({
    required String operationId,
    required String projectId,
    required String prompt,
  }) async {
    return const GeneratedWorkspaceIdentity(
      workspaceName: 'Generated Workspace',
      branchName: 'feat/generated-workspace',
    );
  }

  @override
  Future<void> cancelWorkspaceIdentity(String operationId) async {}

  @override
  Future<PromptImageUploadResult> uploadPromptImage({
    required String format,
    required int sizeBytes,
    required Stream<List<int>> Function() openRead,
  }) async {
    return PromptImageUploadResult(
      hostPath: '/runtime/prompt-images/test.$format',
    );
  }

  @override
  Future<AgentProfileLaunchResult> launchAgentProfile({
    required String workspaceId,
    required String profileId,
    required String prompt,
    required String clientMutationId,
  }) async {
    return const AgentProfileLaunchResult(
      tabId: 'agent-tab',
      agentType: 'codex',
    );
  }

  @override
  Future<List<WorkspaceSummary>> listWorkspaces() async {
    return workspaces;
  }

  @override
  Future<void> setWorkspacePinned(String workspaceId, bool isPinned) async {
    calls.add('setPinned $workspaceId $isPinned');
    await pinCompletion?.future;
  }

  @override
  Future<void> linkWorkspaces({
    required String parentWorkspaceId,
    required String childWorkspaceId,
  }) async {
    calls.add('link $parentWorkspaceId $childWorkspaceId');
    final error = linkError;
    if (error != null) {
      throw error;
    }
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
    calls.add('create $projectId $branch $sourceBranch $parentWorkspaceId');
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

  @override
  Future<WorkspaceTabSummary> renameTab(String tabId, String title) async {
    calls.add('renameTab $tabId $title');
    return WorkspaceTabSummary(
      id: tabId,
      workspaceId: 'a',
      kind: 'terminal',
      title: title,
      payload: const <String, Object?>{},
    );
  }

  @override
  Future<WorkspaceSummary> renameWorkspace(String id, String name) async {
    calls.add('rename $id $name');
    return WorkspaceSummary(
      id: id,
      projectId: 'p1',
      name: name,
      path: '/tmp/$id',
    );
  }

  @override
  Future<void> sleepWorkspace(String workspaceId) async {
    calls.add('sleep $workspaceId');
  }

  @override
  Future<String?> workspaceRepositoryRemoteUrl(String workspaceId) async =>
      null;

  @override
  Future<WorkspaceTagSummary> createWorkspaceTag(
    String name, {
    String? color,
  }) async => WorkspaceTagSummary(id: name, name: name, color: color);

  @override
  Future<void> removeWorkspaceTag(String tagId) async {}

  @override
  Future<WorkspaceSummary> setWorkspaceTags(
    String workspaceId,
    List<String> tagIds,
  ) async => _workspace(workspaceId);
}

final class _CapturingEventStream(
  final Stream<MobileRuntimeEvent> _source,
  final void Function(void Function(MobileRuntimeEvent)) _capture,
) extends Stream<MobileRuntimeEvent> {
  @override
  bool get isBroadcast => _source.isBroadcast;

  @override
  StreamSubscription<MobileRuntimeEvent> listen(
    void Function(MobileRuntimeEvent)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    if (onData != null) {
      _capture(onData);
    }
    return _source.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}
