import 'dart:async';

import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/design_system/icons/alera_host_os_icon.dart';
import 'package:alera/src/features/projects/application/project_hosts_providers.dart';
import 'package:alera/src/features/projects/application/project_providers.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/remote_hosts/application/remote_hosts_state.dart';
import 'package:alera/src/features/remote_hosts/application/ssh_target_providers.dart';
import 'package:alera/src/features/remote_hosts/domain/remote_host_status.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:alera/src/features/remote_hosts/infra/runtime_ssh_target_repository.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/runtime/runtime_change_coalescer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A runtime that stores SSH targets in memory and answers every other
/// request from [responses], so remote host widgets run without a sidecar.
final class FakeRemoteHostsRuntime
    implements RuntimeHostClient, RuntimeHostCapabilityClient {
  FakeRemoteHostsRuntime({List<Map<String, Object?>>? targets})
    : targets = targets ?? <Map<String, Object?>>[];

  final List<Map<String, Object?>> targets;
  final Map<String, Object?> responses = <String, Object?>{
    'hostLink.status': <String, Object?>{'links': <Object?>[]},
    'sshTarget.bootstrap.jobs': <Object?>[],
  };
  final Map<String, Object> errors = <String, Object>{};
  final Map<String, List<Object?>> errorSequences = <String, List<Object?>>{};
  final Map<String, Completer<void>> gates = <String, Completer<void>>{};
  final List<(String, Map<String, Object?>)> requests =
      <(String, Map<String, Object?>)>[];

  /// Fields `sshTarget.check` writes onto the probed target, such as
  /// `lastStatus` and `lastError`. Null leaves the request to [responses].
  Map<String, Object?>? checkPatch;
  final Set<String> capabilities = <String>{
    aleraRuntimeHostRemoteHostLinkCapability,
  };
  final StreamController<RuntimeHostEvent> _events =
      StreamController<RuntimeHostEvent>.broadcast();

  @override
  Stream<RuntimeHostEvent> get runtimeEvents => _events.stream;

  @override
  Future<bool> supportsRuntimeCapability(String capability) async =>
      capabilities.contains(capability);

  List<Map<String, Object?>> payloadsOf(String type) => <Map<String, Object?>>[
    for (final (name, payload) in requests)
      if (name == type) payload,
  ];

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    requests.add((type, Map<String, Object?>.from(payload)));
    await gates[type]?.future;
    final sequence = errorSequences[type];
    if (sequence != null && sequence.isNotEmpty) {
      final error = sequence.removeAt(0);
      if (error != null) {
        throw error;
      }
    }
    if (errors[type] case final error?) {
      throw error;
    }
    switch (type) {
      case 'sshTarget.list':
        return <Object?>[...targets];
      case 'sshTarget.upsert':
        final index = targets.indexWhere((item) => item['id'] == payload['id']);
        final stored = <String, Object?>{
          if (index >= 0) ...targets[index],
          ...payload,
        };
        if (index >= 0) {
          targets[index] = stored;
        } else {
          targets.add(stored);
        }
        emitTargetsChanged();
        return stored;
      case 'sshTarget.check' when checkPatch != null:
        for (var i = 0; i < targets.length; i++) {
          if (targets[i]['id'] == payload['id']) {
            targets[i] = <String, Object?>{...targets[i], ...?checkPatch};
          }
        }
        emitTargetsChanged();
        return <String, Object?>{
          'targets': <Object?>[...targets],
        };
      case 'sshTarget.remove':
        targets.removeWhere((item) => item['id'] == payload['id']);
        emitTargetsChanged();
        return null;
    }
    return responses[type];
  }

  void emitTargetsChanged() {
    _events.add(
      const RuntimeHostEvent('sshTargetsChanged', <String, Object?>{}),
    );
  }

  void emitProgress(
    String targetId,
    String stage, {
    String status = 'installing',
    String? error,
    String jobId = 'job-1',
  }) {
    _events.add(
      RuntimeHostEvent('sshTargetBootstrapProgress', <String, Object?>{
        'jobId': jobId,
        'targetId': targetId,
        'status': status,
        'stage': stage,
        'message': 'Working',
        'error': ?error,
      }),
    );
  }

  Future<void> dispose() => _events.close();
}

Map<String, Object?> remoteHostTargetJson(
  String id,
  String alias, {
  String bootstrapStatus = 'installed',
  String host = '',
  int port = 22,
  String? runtimeVersion,
  String? runtimePlatform,
  String? lastError,
  String? lastStatus,
  Map<String, Object?>? hostStatus,
}) {
  return <String, Object?>{
    'id': id,
    'alias': alias,
    'host': host.isEmpty ? '$id.local' : host,
    'port': port,
    'username': 'leynier',
    'authKind': 'agent',
    'createdAt': '2026-10-01T00:00:00Z',
    'updatedAt': '2026-10-01T00:00:00Z',
    'bootstrapStatus': bootstrapStatus,
    'runtimeVersion': ?runtimeVersion,
    'runtimePlatform': ?runtimePlatform,
    'lastError': ?lastError,
    'lastStatus': ?lastStatus,
    'hostStatus': ?hostStatus,
  };
}

/// A host as the remote host surfaces receive it, for presentational widgets
/// that take [RemoteHostView]s instead of reading the controller.
RemoteHostView remoteHostTestView(
  String id,
  String alias, {
  RemoteHostStatus status = const RemoteHostConnected(),
  HostOs os = HostOs.macos,
}) {
  final now = DateTime.utc(2026, 10);
  return RemoteHostView(
    target: SshTarget(
      id: id,
      alias: alias,
      host: '$id.local',
      port: 22,
      username: 'leynier',
      authKind: SshAuthKind.agent,
      createdAt: now,
      updatedAt: now,
      bootstrapStatus: status is RemoteHostNeedsSetup
          ? SshBootstrapStatus.notInstalled
          : SshBootstrapStatus.installed,
    ),
    status: status,
    os: os,
    address: 'leynier@$id.local',
  );
}

Project remoteHostTestProject(
  String id,
  String name, {
  String primaryHostId = 'local',
  List<ProjectCheckout> checkouts = const <ProjectCheckout>[],
}) {
  final now = DateTime.utc(2026, 10);
  return Project(
    id: id,
    name: name,
    repoPath: '/repos/$id',
    createdAt: now,
    updatedAt: now,
    primaryHostId: primaryHostId,
    checkouts: checkouts,
  );
}

Workspace remoteHostTestWorkspace(String id, String projectId, String hostId) {
  final now = DateTime.utc(2026, 10);
  return Workspace(
    id: id,
    projectId: projectId,
    name: id,
    path: '/work/$id',
    createdAt: now,
    updatedAt: now,
    kind: WorkspaceKind.linked,
    status: WorkspaceStatus.active,
    hostId: hostId,
  );
}

/// Pumps [child] with the remote host providers backed by [runtime].
Future<ProviderContainer> pumpRemoteHostsHarness(
  WidgetTester tester,
  FakeRemoteHostsRuntime runtime,
  Widget child, {
  List<Project> projects = const <Project>[],
  Map<String, List<Workspace>> workspacesByProject =
      const <String, List<Workspace>>{},
  bool projectHosts = true,
  Size surfaceSize = const Size(1280, 1000),
}) async {
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final container = ProviderContainer(
    overrides: [
      sshTargetRepositoryProvider.overrideWithValue(
        RuntimeSshTargetRepository(
          runtime,
          bootstrapDefaults: const RuntimeSshBootstrapDefaults(
            channel: '',
            archiveUrl: '',
            version: '',
          ),
          coalescer: RuntimeChangeCoalescer(debounce: .zero, maxDelay: .zero),
        ),
      ),
      projectListProvider.overrideWithValue(AsyncData<List<Project>>(projects)),
      projectHostsSupportedProvider.overrideWithValue(
        AsyncData<bool>(projectHosts),
      ),
      workbenchControllerProvider.overrideWithValue(
        WorkbenchState(workspacesByProject: workspacesByProject),
      ),
    ],
  );
  addTearDown(() {
    container.dispose();
    unawaited(runtime.dispose());
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildAleraDarkTheme(),
        home: Scaffold(body: child),
      ),
    ),
  );
  await settleRemoteHosts(tester);
  return container;
}

/// Lets the runtime fakes answer without waiting on endless spinners, which
/// `pumpAndSettle` would.
Future<void> settleRemoteHosts(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
