import 'dart:async';

import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/prompt_workspace_service_run.dart';
import 'package:alera/src/features/workbench/domain/background_setup_job.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_creation_result.dart';
import 'package:alera/src/features/workbench/infra/prompt_workspace_service_client.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client_models.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRuntime implements RuntimeHostClient, RuntimeHostCapabilityClient {
  _FakeRuntime({this.capabilities = const <String>{}});

  final Set<String> capabilities;
  final List<(String, Map<String, Object?>)> requests =
      <(String, Map<String, Object?>)>[];
  final List<Map<String, Object?>> reads = <Map<String, Object?>>[];
  Map<String, Object?> started = _operation('running', 'resolvingProject');
  final StreamController<RuntimeHostEvent> events =
      StreamController<RuntimeHostEvent>.broadcast();

  @override
  Stream<RuntimeHostEvent> get runtimeEvents => events.stream;

  @override
  Future<bool> supportsRuntimeCapability(String capability) async =>
      capabilities.contains(capability);

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    requests.add((type, payload));
    return switch (type) {
      'workspace.promptStart.start' ||
      'workspace.promptStart.retryLaunch' => started,
      'workspace.promptStart.get' => reads.removeAt(0),
      _ => throw StateError('Unknown terminal host request: $type'),
    };
  }

  void changed() => events.add(
    const RuntimeHostEvent(aleraPromptWorkspaceOperationsChangedEvent, {
      'id': 'op-1',
    }),
  );

  List<String> get types => <String>[
    for (final request in requests) request.$1,
  ];
}

class _PlainRuntime implements RuntimeHostClient {
  @override
  Stream<RuntimeHostEvent> get runtimeEvents => const Stream.empty();

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async => throw StateError('unexpected $type');
}

Map<String, Object?> _workspace() => <String, Object?>{
  'id': 'ws-1',
  'projectId': 'project-1',
  'name': 'Prompt Workspace',
  'branch': 'feat/prompt-workspace',
  'path': '/repo/alera-ws',
  'createdAt': '2026-10-10T00:00:00Z',
  'updatedAt': '2026-10-10T00:00:00Z',
  'kind': 'linked',
  'status': 'active',
};

Map<String, Object?> _operation(
  String status,
  String phase, {
  bool workspace = false,
  Map<String, Object?>? agent,
  Map<String, Object?>? error,
  List<String> warnings = const <String>[],
}) => <String, Object?>{
  'id': 'op-1',
  'status': status,
  'phase': phase,
  'workspace': ?(workspace ? _workspace() : null),
  'agent': ?agent,
  'setup': ?(workspace ? const <String, Object?>{'tabId': 'setup-tab'} : null),
  'warnings': warnings,
  'error': ?error,
};

void main() {
  final now = DateTime.utc(2026, 10, 10);
  final project = Project(
    id: 'project-1',
    name: 'Alera',
    repoPath: '/repo/alera',
    createdAt: now,
    updatedAt: now,
  );

  PromptWorkspaceCreateRequest request({
    bool useProjectCheckout = false,
    bool autoAssignSection = true,
    String prompt = '  Build the feature  ',
  }) => PromptWorkspaceCreateRequest(
    useProjectCheckout: useProjectCheckout,
    project: project,
    prompt: prompt,
    profileId: 'profile-1',
    sourceBranch: useProjectCheckout ? '' : 'main',
    parentWorkspaceId: 'parent-1',
    issueUrl: 'https://github.com/o/r/issues/1',
    autoAssignSection: autoAssignSection,
  );

  PromptWorkspaceServiceClient service(
    RuntimeHostClient runtime, {
    Duration pollInterval = const Duration(hours: 1),
  }) => PromptWorkspaceServiceClient(
    runtime,
    pollInterval: pollInterval,
    eventSafetyInterval: const Duration(hours: 1),
  );

  test('the service is used only when the runtime advertises it', () async {
    expect(
      runtimeHostEventNames,
      contains(aleraPromptWorkspaceOperationsChangedEvent),
    );
    expect(await service(_FakeRuntime()).isSupported(), isFalse);
    expect(await service(_PlainRuntime()).isSupported(), isFalse);
    expect(
      await service(
        _FakeRuntime(
          capabilities: {aleraRuntimeHostPromptWorkspaceServiceCapability},
        ),
      ).isSupported(),
      isTrue,
    );
    final created = WorkspaceCreationResult(
      workspace: Workspace.fromJson(_workspace()),
      setupReport: WorktreeSetupReport.empty,
    );
    expect(canRunPromptWorkspaceOnService(request()), isTrue);
    expect(
      canRunPromptWorkspaceOnService(request().withCreated(created)),
      isFalse,
      reason: 'a client-created workspace keeps its client-side retry',
    );
    expect(
      canRunPromptWorkspaceOnService(
        request().withCreated(created, serviceOperationId: 'op-1'),
      ),
      isTrue,
    );
  });

  test('the start payload states the form choices explicitly', () {
    final worktree = promptWorkspaceStartPayload(request(), requestId: 'req-1');
    expect(worktree, <String, Object?>{
      'prompt': 'Build the feature',
      'projectId': 'project-1',
      'profile': 'profile-1',
      'mode': 'worktree',
      'sourceBranch': 'main',
      'parentWorkspaceId': 'parent-1',
      'issueUrl': 'https://github.com/o/r/issues/1',
      'section': 'auto',
      'requestId': 'req-1',
      'origin': <String, Object?>{'surface': 'desktop'},
    });
    final checkout = promptWorkspaceStartPayload(
      request(useProjectCheckout: true, autoAssignSection: false),
      requestId: 'req-2',
    );
    expect(checkout['mode'], 'projectCheckout');
    expect(checkout.containsKey('sourceBranch'), isFalse);
    expect(checkout['section'], 'none');
  });

  test('request ids repeat for one submission and change per attempt', () {
    String id({int attempt = 0, String prompt = 'Build the feature'}) =>
        promptWorkspaceServiceRequestId(
          jobId: 'job-1',
          attempt: attempt,
          request: request(prompt: prompt),
        );
    expect(id(), id());
    expect(id(attempt: 1), isNot(id()));
    expect(id(prompt: 'Something else'), isNot(id()));
  });

  test('follows the operation through its change events', () async {
    final runtime = _FakeRuntime()
      ..reads.addAll(<Map<String, Object?>>[
        _operation('running', 'creatingWorkspace', workspace: true),
        _operation(
          'completed',
          'done',
          workspace: true,
          agent: const <String, Object?>{'tabId': 'agent-tab'},
        ),
      ]);
    final phases = <String>[];
    final outcome = runPromptWorkspaceService(
      service: service(runtime),
      request: request(),
      requestId: 'req-1',
      onPhase: phases.add,
    );
    await pumpEventQueue();
    expect(runtime.types, <String>['workspace.promptStart.start']);
    runtime.changed();
    await pumpEventQueue();
    runtime.changed();
    final result = await outcome;

    expect(runtime.requests.first.$2['requestId'], 'req-1');
    expect(runtime.types, <String>[
      'workspace.promptStart.start',
      'workspace.promptStart.get',
      'workspace.promptStart.get',
    ]);
    expect(phases, <String>[
      'Generating workspace identity',
      'Creating workspace',
    ]);
    expect(result.creation.workspace.id, 'ws-1');
    expect(result.agentTabId, 'agent-tab');
    expect(runtime.events.hasListener, isFalse);
  });

  test('polls when no change event arrives', () async {
    final runtime = _FakeRuntime()
      ..reads.addAll(<Map<String, Object?>>[
        _operation('running', 'generatingIdentity'),
        _operation(
          'completed',
          'done',
          workspace: true,
          agent: const <String, Object?>{'tabId': 'agent-tab'},
        ),
      ]);
    final result = await runPromptWorkspaceService(
      service: service(runtime, pollInterval: Duration.zero),
      request: request(),
      requestId: 'req-1',
    );
    expect(result.agentTabId, 'agent-tab');
    expect(
      runtime.types.where((type) => type == 'workspace.promptStart.get'),
      hasLength(2),
    );
  });

  test('a failed launch keeps the workspace and retries on the host', () async {
    final runtime = _FakeRuntime()
      ..started = _operation(
        'failed',
        'launchingAgent',
        workspace: true,
        error: const <String, Object?>{
          'code': 'failed',
          'message': 'Agent profile not found: profile-1',
          'retryable': true,
        },
      );
    final failure =
        await runPromptWorkspaceService(
          service: service(runtime),
          request: request(),
          requestId: 'req-1',
        ).then<PromptWorkspaceServiceFailure?>(
          (_) => null,
          onError: (Object e) {
            return e as PromptWorkspaceServiceFailure;
          },
        );
    expect(failure, isNotNull);
    expect(failure!.toString(), 'Agent profile not found: profile-1');
    expect(failure.operation.retryable, isTrue);
    expect(failure.operation.setupTabId, 'setup-tab');
    final creation = failure.creation!;
    expect(creation.workspace.id, 'ws-1');
    expect(creation.deferredSetupCommand, isNull);

    runtime.started = _operation(
      'completed',
      'done',
      workspace: true,
      agent: const <String, Object?>{'tabId': 'agent-tab'},
    );
    final retried = await runPromptWorkspaceService(
      service: service(runtime),
      request: request().withCreated(creation, serviceOperationId: 'op-1'),
      requestId: 'req-1',
    );
    expect(runtime.requests.last.$1, 'workspace.promptStart.retryLaunch');
    expect(runtime.requests.last.$2, <String, Object?>{'id': 'op-1'});
    expect(retried.agentTabId, 'agent-tab');
  });

  test('needs input and cancellation fail with their message', () async {
    final runtime = _FakeRuntime()
      ..started = _operation(
        'needsInput',
        'resolvingProject',
        error: const <String, Object?>{
          'code': 'needs_input',
          'message': 'The prompt does not clearly name a project.',
          'retryable': false,
        },
      );
    await expectLater(
      runPromptWorkspaceService(
        service: service(runtime),
        request: request(),
        requestId: 'req-1',
      ),
      throwsA(
        isA<PromptWorkspaceServiceFailure>()
            .having((f) => f.creation, 'creation', isNull)
            .having(
              (f) => f.toString(),
              'message',
              'The prompt does not clearly name a project.',
            ),
      ),
    );
    runtime.started = _operation('cancelled', 'creatingWorkspace');
    await expectLater(
      runPromptWorkspaceService(
        service: service(runtime),
        request: request(),
        requestId: 'req-2',
      ),
      throwsA(
        isA<PromptWorkspaceServiceFailure>().having(
          (f) => f.toString(),
          'message',
          'Workspace creation was cancelled.',
        ),
      ),
    );
  });

  test('a job falls back to the client pipeline without the service', () async {
    final shown = <String?>[];
    final absent = _FakeRuntime();
    expect(
      await runPromptWorkspaceJobOnService(
        service: service(absent),
        request: request(),
        requestId: 'req-1',
        showWorkspace: (_, tabId) async => shown.add(tabId),
      ),
      isNull,
    );
    final created = WorkspaceCreationResult(
      workspace: Workspace.fromJson(_workspace()),
      setupReport: WorktreeSetupReport.empty,
    );
    final present = _FakeRuntime(
      capabilities: {aleraRuntimeHostPromptWorkspaceServiceCapability},
    );
    expect(
      await runPromptWorkspaceJobOnService(
        service: service(present),
        request: request().withCreated(created),
        requestId: 'req-1',
        showWorkspace: (_, tabId) async => shown.add(tabId),
      ),
      isNull,
    );
    expect(absent.requests, isEmpty);
    expect(present.requests, isEmpty);
    expect(shown, isEmpty);
  });

  test('a job shows the workspace on the agent tab', () async {
    final runtime =
        _FakeRuntime(
            capabilities: {aleraRuntimeHostPromptWorkspaceServiceCapability},
          )
          ..started = _operation(
            'completed',
            'done',
            workspace: true,
            agent: const <String, Object?>{'tabId': 'agent-tab'},
          );
    final shown = <(String, String?)>[];
    final phases = <String>[];
    final outcome = await runPromptWorkspaceJobOnService(
      service: service(runtime),
      request: request(),
      requestId: 'req-1',
      onPhase: phases.add,
      showWorkspace: (creation, tabId) async =>
          shown.add((creation.workspace.id, tabId)),
    );
    expect(outcome, isNotNull);
    expect(shown, <(String, String?)>[('ws-1', 'agent-tab')]);
    expect(phases, <String>['Starting agent']);
  });

  test('a failed job keeps a snapshot that retries on the host', () async {
    final runtime =
        _FakeRuntime(
            capabilities: {aleraRuntimeHostPromptWorkspaceServiceCapability},
          )
          ..started = _operation(
            'failed',
            'launchingAgent',
            workspace: true,
            error: const <String, Object?>{
              'code': 'runtime_unavailable',
              'message': 'The agent did not start.',
              'retryable': true,
            },
          );
    final shown = <String?>[];
    final kept = <PromptWorkspaceCreateRequest>[];
    await expectLater(
      runPromptWorkspaceJobOnService(
        service: service(runtime),
        request: request(),
        requestId: 'req-1',
        showWorkspace: (_, tabId) async => shown.add(tabId),
        onWorkspaceKept: kept.add,
      ),
      throwsA(isA<PromptWorkspaceServiceFailure>()),
    );
    expect(shown, <String?>['setup-tab']);
    expect(kept.single.created?.workspace.id, 'ws-1');
    expect(kept.single.serviceOperationId, 'op-1');
    expect(canRunPromptWorkspaceOnService(kept.single), isTrue);
  });
}
