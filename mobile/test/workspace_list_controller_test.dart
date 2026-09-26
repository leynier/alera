import 'dart:async';

import 'package:alera_mobile/src/features/runtime/domain/agent_profile_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/project_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/prompt_image_upload.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_creation_result.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_section_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_sidebar_snapshot.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_list_controller.dart';
import 'package:alera_mobile/src/features/workbench/domain/mobile_view_prefs.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

part 'workspace_list_controller_test_harness.dart';

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

  test(
    'exposes main-panel tab ids and refreshes when view prefs change',
    () async {
      final client = _FakeWorkspaceClient()
        ..workspaceMainTabIds = <String, List<String>>{
          'a': <String>['tab-1'],
        };
      final container = _container(client);

      final data = await container.read(
        workspaceListControllerProvider('host-1').future,
      );
      expect(data.workspaceMainTabIds, <String, List<String>>{
        'a': <String>['tab-1'],
      });

      client.workspaceMainTabIds = <String, List<String>>{
        'a': <String>['tab-2'],
      };
      client.emit('workbenchViewPrefsChanged');
      await Future.pause(.zero);

      final refreshed = await container.read(
        workspaceListControllerProvider('host-1').future,
      );
      expect(refreshed.workspaceMainTabIds, <String, List<String>>{
        'a': <String>['tab-2'],
      });
    },
  );

  test('refreshes the terminal counts when a workspace sleeps', () async {
    final client = _FakeWorkspaceClient()
      ..terminalTabCountByWorkspaceId = <String, int>{'a': 1};
    final container = _container(client);
    await container.read(workspaceListControllerProvider('host-1').future);

    client.terminalTabCountByWorkspaceId = const <String, int>{};
    client.emit('workspaceSleepChanged');
    await Future.pause(.zero);

    final refreshed = await container.read(
      workspaceListControllerProvider('host-1').future,
    );
    expect(refreshed.terminalTabCountByWorkspaceId, isEmpty);
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
    final client = _FakeWorkspaceClient()
      ..workspaces = <WorkspaceSummary>[
        _workspace('a'),
        _workspace('child', parent: 'a'),
        _workspace('grandchild', parent: 'child'),
        _workspace('b'),
      ];
    final container = _container(client);
    final notifier = container.read(
      workspaceListControllerProvider('host-1').notifier,
    );
    await container.read(workspaceListControllerProvider('host-1').future);

    await notifier.setTreePinned('a', true);
    expect(client.calls, contains('setPinned a true'));
    expect(client.calls, contains('setPinned child true'));
    expect(client.calls, contains('setPinned grandchild true'));

    await notifier.saveTreeSection('a', sectionId: 'work');
    expect(client.calls, contains('setSection a work'));
    expect(client.calls, contains('setSection child work'));
    expect(client.calls, contains('setSection grandchild work'));

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
