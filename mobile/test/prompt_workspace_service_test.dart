import 'dart:async';

import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_providers.dart';
import 'package:alera_mobile/src/features/workbench/application/background_setup_jobs.dart';
import 'package:alera_mobile/src/features/workbench/application/prompt_workspace_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/prompt_workspace_pipeline.dart';
import 'package:alera_mobile/src/features/workbench/application/prompt_workspace_service.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workbench/domain/background_setup_job.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_terminal_client.dart';

/// A paired runtime that may run New Workspace from Prompt itself.
class _ServiceClient extends FakeTerminalClient
    implements MobilePromptWorkspaceServiceClient {
  _ServiceClient({bool service = true})
    : runtimeCapabilities = <String>{
        if (service) promptWorkspaceServiceCapability,
      };

  @override
  final Set<String> runtimeCapabilities;
  final List<(String, Map<String, Object?>)> requests =
      <(String, Map<String, Object?>)>[];
  final List<Map<String, Object?>> reads = <Map<String, Object?>>[];
  Map<String, Object?> started = _operation('running', 'resolvingProject');

  /// Holds the start answer back until completed, when set.
  Completer<void>? startGate;
  final StreamController<MobileRuntimeEvent> serviceEvents =
      StreamController<MobileRuntimeEvent>.broadcast();

  @override
  Stream<MobileRuntimeEvent> get events => serviceEvents.stream;

  @override
  Future<Map<String, Object?>> requestMap(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    requests.add((type, payload));
    if (type == 'workspace.promptStart.start') {
      await startGate?.future;
    }
    return switch (type) {
      'workspace.promptStart.start' ||
      'workspace.promptStart.retryLaunch' => started,
      'workspace.promptStart.get' => reads.removeAt(0),
      'workspace.promptStart.cancel' => <String, Object?>{
        'id': payload['id'],
        'cancelling': true,
      },
      _ => throw StateError('unexpected $type'),
    };
  }

  void changed() => serviceEvents.add(
    const MobileRuntimeEvent(promptWorkspaceOperationsChangedEvent, {
      'id': 'op-1',
    }),
  );

  List<String> get types => <String>[
    for (final request in requests) request.$1,
  ];

  /// The payloads of every [type] request, in order.
  List<Map<String, Object?>> payloadsOf(String type) => <Map<String, Object?>>[
    for (final request in requests)
      if (request.$1 == type) request.$2,
  ];
}

Map<String, Object?> _operation(
  String status,
  String phase, {
  bool workspace = false,
  String? agentTabId,
  String? errorMessage,
}) => <String, Object?>{
  'id': 'op-1',
  'status': status,
  'phase': phase,
  if (workspace)
    'workspace': const <String, Object?>{
      'id': 'ws-1',
      'projectId': 'project',
      'name': 'Prompt Workspace',
      'path': '/repo/ws-1',
      'branch': 'feat/prompt-workspace',
    },
  if (agentTabId != null) 'agent': <String, Object?>{'tabId': agentTabId},
  if (workspace) 'setup': const <String, Object?>{'tabId': 'setup-tab'},
  if (errorMessage != null)
    'error': <String, Object?>{
      'code': 'failed',
      'message': errorMessage,
      'retryable': workspace,
    },
};

const _request = PromptWorkspaceCreateRequest(
  hostId: 'host',
  checkoutHostId: 'local',
  projectId: 'project',
  prompt: ' Build the feature ',
  sourceBranch: 'main',
  profileId: 'profile-1',
  workspaceBranches: {},
  parentWorkspaceId: 'parent-1',
  autoAssignSection: true,
);

Future<PromptWorkspaceCreateOutcome> _create(
  _ServiceClient client, {
  PromptWorkspaceCreateRequest request = _request,
  List<String>? phases,
}) => runPromptWorkspaceCreate(
  client: client,
  loadTerminalClient: () async => client,
  request: request,
  clientMutationId: 'mutation-1',
  serviceRequestId: 'req-1',
  onPhase: phases?.add,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('runs the client pipeline when the runtime has no service', () async {
    final client = _ServiceClient(service: false)
      ..projectBranches = const <String>['main'];
    addTearDown(client.dispose);

    final outcome = await _create(client);

    expect(client.requests, isEmpty);
    expect(
      client.calls,
      contains('createWorkspace project feat/generated-workspace'),
    );
    expect(outcome.agentTabId, 'agent-tab');
  });

  test('delegates to the runtime and follows its change events', () async {
    final client = _ServiceClient()
      ..deferredSetupCommand = '/bin/sh "/runtime/setup.sh"'
      ..reads.addAll(<Map<String, Object?>>[
        _operation('running', 'creatingWorkspace', workspace: true),
        _operation(
          'completed',
          'done',
          workspace: true,
          agentTabId: 'agent-tab',
        ),
      ]);
    addTearDown(client.dispose);
    final phases = <String>[];

    final future = _create(client, phases: phases);
    await pumpEventQueue();
    client.changed();
    await pumpEventQueue();
    client.changed();
    final outcome = await future;

    expect(client.requests.first.$2, <String, Object?>{
      'prompt': 'Build the feature',
      'projectId': 'project',
      'profile': 'profile-1',
      'mode': 'worktree',
      'sourceBranch': 'main',
      'parentWorkspaceId': 'parent-1',
      'section': 'auto',
      'requestId': 'req-1',
    });
    expect(client.types, <String>[
      'workspace.promptStart.start',
      'workspace.promptStart.get',
      'workspace.promptStart.get',
    ]);
    expect(phases, <String>[
      'Generating workspace identity',
      'Creating workspace',
    ]);
    expect(outcome.agentTabId, 'agent-tab');
    expect(outcome.creation.workspace.id, 'ws-1');
    expect(outcome.creation.hasDeferredSetup, isFalse);
    // The host created the Setup tab; the phone starts neither a workspace,
    // an agent, nor a second Setup terminal.
    expect(client.calls, isEmpty);
  });

  test('polls the operation when no change event arrives', () async {
    final client = _ServiceClient()
      ..started = _operation('running', 'generatingIdentity')
      ..reads.addAll(<Map<String, Object?>>[
        _operation('running', 'launchingAgent', workspace: true),
        _operation('completed', 'done', workspace: true, agentTabId: 'a'),
      ]);
    addTearDown(client.dispose);

    final operation = await runPromptWorkspaceOperation(
      client,
      request: _request,
      requestId: 'req-1',
      pollInterval: Duration.zero,
    );

    expect(operation.status, PromptWorkspaceOperationStatus.completed);
    expect(operation.agentTabId, 'a');
  });

  test(
    'a launch failure keeps the workspace and retries on the host',
    () async {
      final client = _ServiceClient()
        ..started = _operation(
          'failed',
          'launchingAgent',
          workspace: true,
          errorMessage: 'The agent did not start.',
        );
      addTearDown(client.dispose);

      final failure = await _create(client)
          .then<PromptWorkspaceLaunchException?>(
            (_) => null,
            onError: (Object error) => error as PromptWorkspaceLaunchException,
          );
      expect(failure!.toString(), 'The agent did not start.');
      expect(failure.serviceOperationId, 'op-1');
      expect(failure.setupStarted, isTrue);
      expect(failure.creation.workspace.id, 'ws-1');

      client.started = _operation(
        'completed',
        'done',
        workspace: true,
        agentTabId: 'agent-tab',
      );
      final retried = await _create(
        client,
        request: _request.withCreated(
          failure.creation,
          serviceOperationId: failure.serviceOperationId,
        ),
      );
      expect(client.requests.last.$1, 'workspace.promptStart.retryLaunch');
      expect(client.requests.last.$2, <String, Object?>{'id': 'op-1'});
      expect(retried.agentTabId, 'agent-tab');
      expect(client.calls, isEmpty);
    },
  );

  test('a prompt the runtime cannot place fails with its message', () async {
    final client = _ServiceClient()
      ..started = _operation(
        'needsInput',
        'resolvingProject',
        errorMessage: 'The prompt does not clearly name a project.',
      );
    addTearDown(client.dispose);

    await expectLater(
      _create(client),
      throwsA(
        isA<PromptWorkspaceServiceFailure>().having(
          (failure) => failure.toString(),
          'message',
          'The prompt does not clearly name a project.',
        ),
      ),
    );
  });

  test('a background job retries the launch through its operation', () async {
    final client = _ServiceClient()
      ..started = _operation(
        'failed',
        'launchingAgent',
        workspace: true,
        errorMessage: 'The agent did not start.',
      );
    addTearDown(client.dispose);
    final container = ProviderContainer(
      overrides: [
        workspaceClientProvider('host').overrideWith((ref) async => client),
        terminalClientProvider('host').overrideWith((ref) async => client),
      ],
    );
    addTearDown(container.dispose);
    final jobs = container.read(backgroundSetupJobsProvider.notifier);

    await expectLater(
      jobs.enqueuePromptWorkspace(_request, jobId: 'job-1'),
      throwsA(isA<PromptWorkspaceLaunchException>()),
    );
    final requestId = client.requests.single.$2['requestId'] as String?;
    expect(requestId, startsWith('mobile-prompt-workspace:job-1:0:'));
    final job = container.read(backgroundSetupJobsProvider).jobById('job-1');
    expect(job?.isFailed, isTrue);
    final snapshot = job!.snapshot as PromptWorkspaceCreateRequest;
    expect(snapshot.serviceOperationId, 'op-1');
    expect(snapshot.created?.workspace.id, 'ws-1');

    client.started = _operation(
      'completed',
      'done',
      workspace: true,
      agentTabId: 'agent-tab',
    );
    final outcome = await jobs.enqueuePromptWorkspace(_request, jobId: 'job-1');

    expect(client.types.last, 'workspace.promptStart.retryLaunch');
    expect(outcome.agentTabId, 'agent-tab');
    expect(
      container.read(backgroundSetupJobsProvider).jobById('job-1'),
      isNull,
    );
  });

  test('reports the running operation so a caller can cancel it', () async {
    final client = _ServiceClient()
      ..started = _operation('running', 'generatingIdentity')
      ..reads.add(_operation('cancelled', 'generatingIdentity'));
    addTearDown(client.dispose);
    final ids = <String?>[];

    final future = runPromptWorkspaceCreate(
      client: client,
      loadTerminalClient: () async => client,
      request: _request,
      clientMutationId: 'mutation-1',
      serviceRequestId: 'req-1',
      onServiceOperationId: ids.add,
    );
    await pumpEventQueue();
    expect(ids, <String?>['op-1']);
    await cancelPromptWorkspaceOperation(client, ids.single!);
    client.changed();

    await expectLater(
      future,
      throwsA(
        isA<PromptWorkspaceServiceFailure>().having(
          (failure) => failure.toString(),
          'message',
          'Workspace creation was cancelled.',
        ),
      ),
    );
    expect(ids, <String?>['op-1', null]);
    expect(client.types[1], 'workspace.promptStart.cancel');
    expect(client.payloadsOf('workspace.promptStart.cancel'), [
      {'id': 'op-1'},
    ]);
  });

  group('prompt workspace controller on the runtime service', () {
    Future<PromptWorkspaceController> controllerFor(
      _ServiceClient client,
    ) async {
      final container = ProviderContainer(
        overrides: [
          workspaceClientProvider('host').overrideWith((ref) async => client),
          terminalClientProvider('host').overrideWith((ref) async => client),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        promptWorkspaceControllerProvider('host'),
        (_, _) {},
      );
      addTearDown(subscription.close);
      final controller = container.read(
        promptWorkspaceControllerProvider('host').notifier,
      );
      await controller.selectProject('project');
      return controller;
    }

    test('cancel stops the operation and Retry Agent relaunches it', () async {
      final client = _ServiceClient()
        ..projectBranches = const <String>['main']
        ..started = _operation('running', 'generatingIdentity')
        ..reads.add(_operation('cancelled', 'launchingAgent', workspace: true));
      addTearDown(client.dispose);
      final controller = await controllerFor(client);

      final created = controller.create(
        prompt: 'Build the feature',
        workspaceBranches: const <String>{},
      );
      final failure = expectLater(
        created,
        throwsA(isA<PromptWorkspaceLaunchException>()),
      );
      await pumpEventQueue();
      expect(controller.state.phase, 'Generating workspace identity');
      await controller.cancelGeneration();
      client.changed();
      await failure;

      expect(client.payloadsOf('workspace.promptStart.cancel'), [
        {'id': 'op-1'},
      ]);
      expect(
        client.calls.where((call) => call.startsWith('cancelWorkspace')),
        isEmpty,
      );
      expect(controller.state.creation?.workspace.id, 'ws-1');

      // The host kept the workspace; Retry Agent relaunches the operation
      // there rather than launching a second agent from the phone.
      client.started = _operation(
        'completed',
        'done',
        workspace: true,
        agentTabId: 'agent-tab',
      );
      await controller.retryAgent('Build the feature');

      expect(client.requests.last.$1, 'workspace.promptStart.retryLaunch');
      expect(client.requests.last.$2, <String, Object?>{'id': 'op-1'});
      expect(controller.state.agentTabId, 'agent-tab');
      expect(controller.state.error, isNull);
      expect(
        client.calls.where((call) => call.startsWith('launchAgentProfile')),
        isEmpty,
      );
    });

    test('cancel before the runtime answers reaches the operation', () async {
      final gate = Completer<void>();
      final client = _ServiceClient()
        ..projectBranches = const <String>['main']
        ..startGate = gate
        ..started = _operation('running', 'generatingIdentity')
        ..reads.add(_operation('cancelled', 'generatingIdentity'));
      addTearDown(client.dispose);
      final controller = await controllerFor(client);

      final failure = expectLater(
        controller.create(
          prompt: 'Build the feature',
          workspaceBranches: const <String>{},
        ),
        throwsA(isA<PromptWorkspaceServiceFailure>()),
      );
      await pumpEventQueue();
      await controller.cancelGeneration();
      expect(client.types, <String>['workspace.promptStart.start']);

      gate.complete();
      await pumpEventQueue();
      expect(client.types[1], 'workspace.promptStart.cancel');
      expect(client.payloadsOf('workspace.promptStart.cancel'), [
        {'id': 'op-1'},
      ]);
      client.changed();
      await failure;
      expect(controller.state.error, 'Workspace creation was cancelled.');
    });
  });
}
