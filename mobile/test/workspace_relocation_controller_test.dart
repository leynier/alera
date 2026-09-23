import 'dart:async';

import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_creation_result.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_relocation_client.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_providers.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_relocation_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const projectTask = WorkspaceSummary(
  id: 'task',
  projectId: 'project',
  name: 'Task',
  path: '/repo',
  kind: 'main',
  branch: 'current',
);

class RelocationTestClient
    implements MobileWorkspaceClient, WorkspaceRelocationClient {
  @override
  bool get supportsWorkspaceRelocation => true;
  final requests = <Map<String, Object?>>[];
  bool failNext = false;
  Completer<void>? pending;
  bool deferredSetup = false;

  @override
  Future<WorkspaceCreationResult> handOffWorkspace({
    required String workspaceId,
    required String relocationId,
    required String branch,
    required bool moveChanges,
    required bool sharedImpactConfirmed,
    String? replacementBranch,
  }) async {
    requests.add({
      'id': relocationId,
      'workspaceId': workspaceId,
      'branch': branch,
      'moveChanges': moveChanges,
      'replacement': replacementBranch,
      'confirmed': sharedImpactConfirmed,
    });
    await pending?.future;
    if (failNext) {
      failNext = false;
      throw StateError('Response lost');
    }
    return WorkspaceCreationResult(
      workspace: projectTask,
      steps: const [],
      deferredSetupCommand: deferredSetup ? 'setup-command' : null,
    );
  }

  @override
  Future<WorkspaceSummary> handOnWorkspace({
    required String workspaceId,
    required String relocationId,
    required bool sharedImpactConfirmed,
  }) async {
    requests.add({
      'id': relocationId,
      'workspaceId': workspaceId,
      'confirmed': sharedImpactConfirmed,
    });
    return projectTask;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late RelocationTestClient client;
  late ProviderContainer container;
  final provider = workspaceRelocationControllerProvider('host', 'task');
  setUp(() {
    client = RelocationTestClient();
    container = ProviderContainer(
      overrides: [
        workspaceClientProvider('host').overrideWith((ref) async => client),
        terminalClientProvider('host').overrideWith(
          (ref) async => throw StateError('Terminal connection unavailable'),
        ),
      ],
    );
    container.listen(provider, (_, _) {});
  });
  tearDown(() => container.dispose());

  test(
    'setup launch failure reports a warning after a successful transfer',
    () async {
      client.deferredSetup = true;
      final controller = container.read(provider.notifier);
      controller.edit(branch: 'topic');
      controller.confirm(true);
      expect(await controller.submit(projectTask), isTrue);
      expect(client.requests, hasLength(1));
      expect(container.read(provider).error, isNull);
      expect(
        container.read(provider).warning,
        contains('The transfer completed'),
      );
    },
  );

  test(
    'decisions revoke consent and retry retains the original relocation ID',
    () async {
      final controller = container.read(provider.notifier);
      expect(container.read(provider).moveChanges, isFalse);
      controller.edit(branch: 'topic');
      expect(await controller.submit(projectTask), isFalse);
      expect(client.requests, isEmpty);
      controller.confirm(true);
      client.failNext = true;
      expect(await controller.submit(projectTask), isFalse);
      final id = client.requests.single['id'];
      controller.edit(moveChanges: true);
      expect(container.read(provider).confirmed, isFalse);
      controller.edit(moveChanges: false);
      controller.confirm(true);
      expect(await controller.submit(projectTask), isTrue);
      expect(client.requests.last['id'], id);
      expect(client.requests.last['confirmed'], isTrue);
      expect(client.requests.last['moveChanges'], isFalse);
    },
  );

  test(
    'moving the current branch requires its replacement and all changes',
    () async {
      final controller = container.read(provider.notifier);
      controller.edit(useCurrentBranch: true);
      expect(container.read(provider).moveChanges, isTrue);
      controller.confirm(true);
      expect(await controller.submit(projectTask), isFalse);
      expect(client.requests, isEmpty);
      controller.edit(replacementBranch: 'main');
      expect(container.read(provider).confirmed, isFalse);
      controller.confirm(true);
      expect(await controller.submit(projectTask), isTrue);
      expect(client.requests.single['branch'], 'current');
      expect(client.requests.single['replacement'], 'main');
      expect(client.requests.single['moveChanges'], isTrue);
    },
  );

  test(
    'Hand On preserves the task identity and requires explicit consent',
    () async {
      const linked = WorkspaceSummary(
        id: 'task',
        projectId: 'project',
        name: 'Task',
        path: '/linked/task',
      );
      final controller = container.read(provider.notifier);
      expect(await controller.submit(linked), isFalse);
      expect(client.requests, isEmpty);
      controller.confirm(true);
      expect(await controller.submit(linked), isTrue);
      expect(client.requests.single['workspaceId'], 'task');
      expect(client.requests.single['confirmed'], isTrue);
    },
  );
}
