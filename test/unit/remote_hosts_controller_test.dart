import 'dart:async';

import 'package:alera/src/features/remote_hosts/application/remote_hosts_controller.dart';
import 'package:alera/src/features/remote_hosts/application/remote_hosts_state.dart';
import 'package:alera/src/features/remote_hosts/application/ssh_target_providers.dart';
import 'package:alera/src/features/remote_hosts/domain/remote_host_form_values.dart';
import 'package:alera/src/features/remote_hosts/domain/remote_host_install_steps.dart';
import 'package:alera/src/features/remote_hosts/domain/remote_host_status.dart';
import 'package:alera/src/features/remote_hosts/infra/runtime_ssh_target_repository.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/runtime/runtime_change_coalescer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('merges targets, links and the runtime status', () async {
    final client = _FakeRuntimeClient()
      ..responses['sshTarget.list'] = <Object?>[
        _targetJson('mac', 'Build Mac', bootstrapStatus: 'installed'),
        _targetJson('box', 'Linux Box', bootstrapStatus: 'notInstalled'),
        _targetJson(
          'pi',
          'Pi',
          bootstrapStatus: 'installed',
          port: 2222,
          hostStatus: <String, Object?>{'state': 'offline'},
        ),
      ]
      ..responses['hostLink.status'] = <String, Object?>{
        'links': <Object?>[
          <String, Object?>{
            'hostId': 'mac',
            'state': 'attached',
            'attachment': <String, Object?>{
              'runtimeDir': '/Users/leynier/.alera/data',
              'platform': 'macos',
              'arch': 'arm64',
              'hostVersion': '1.4.0',
            },
          },
          // The runtime's own status for pi wins over its link.
          <String, Object?>{'hostId': 'pi', 'state': 'attached'},
        ],
      };
    final container = _container(client);

    final state = await _settle(container);

    expect(state.loading, isFalse);
    expect(state.hosts.map((host) => host.alias), <String>[
      'Build Mac',
      'Linux Box',
      'Pi',
    ]);
    expect(state.hostById('mac')!.status, isA<RemoteHostConnected>());
    expect(state.hostById('box')!.status, isA<RemoteHostNeedsSetup>());
    expect(state.hostById('pi')!.status, isA<RemoteHostOffline>());
    expect(state.hostById('pi')!.address, 'leynier@pi.local:2222');
    expect(state.readyHosts.map((host) => host.id), <String>['mac', 'pi']);
    expect(state.worstHost?.id, 'box');
    expect(state.capabilities.hostLinks, isTrue);
    expect(state.capabilities.runtimeUpdate, isFalse);
  });

  test('recovers running installs from the job list', () async {
    final client = _FakeRuntimeClient()
      ..responses['sshTarget.list'] = <Object?>[
        _targetJson('mac', 'Build Mac', bootstrapStatus: 'installing'),
        _targetJson('box', 'Linux Box', bootstrapStatus: 'installing'),
      ]
      ..responses['sshTarget.bootstrap.jobs'] = <Object?>[
        <String, Object?>{
          'jobId': 'job-7',
          'targetId': 'mac',
          'status': 'installing',
          'stage': 'upload',
        },
      ];
    final container = _container(client);

    final state = await _settle(container);

    final mac = state.hostById('mac')!;
    expect(mac.status, isA<RemoteHostInstalling>());
    expect(mac.installProgress?.jobId, 'job-7');
    expect(mac.installProgress?.phaseLabel, 'Upload runtime');
    // An install the store still marks as running but no job owns was
    // interrupted, so the host needs setup again.
    expect(state.hostById('box')!.status, isA<RemoteHostNeedsSetup>());
  });

  test('accumulates progress and keeps a failure until dismissed', () async {
    final client = _FakeRuntimeClient()
      ..responses['sshTarget.list'] = <Object?>[
        _targetJson('mac', 'Build Mac', bootstrapStatus: 'notInstalled'),
      ]
      ..responses['sshTarget.bootstrap.start'] = <String, Object?>{
        'jobId': 'job-1',
        'targetId': 'mac',
        'status': 'installing',
      };
    final container = _container(client);
    await _settle(container);
    final controller = container.read(remoteHostsControllerProvider.notifier);

    final started = await controller.install('mac');
    expect(started.succeeded, isTrue);
    expect(
      container.read(remoteHostsControllerProvider).hostById('mac')!.status,
      isA<RemoteHostInstalling>(),
    );

    client
      ..emitProgress('mac', 'detect')
      ..emitProgress('mac', 'artifact');
    var state = await _settle(container);
    expect(
      state.hostById('mac')!.installProgress!.steps[2].state,
      RemoteHostInstallStepState.active,
    );

    client.emitProgress(
      'mac',
      'failed',
      status: 'failed',
      error: 'no matching runtime artifact',
    );
    state = await _settle(container);
    final failed = state.hostById('mac')!.status;
    expect(failed, isA<RemoteHostError>());
    expect((failed as RemoteHostError).origin, RemoteHostErrorOrigin.install);
    expect(failed.detail, 'no matching runtime artifact');

    controller.dismissInstallFailure('mac');
    expect(
      container.read(remoteHostsControllerProvider).hostById('mac')!.status,
      isA<RemoteHostNeedsSetup>(),
    );
  });

  test('maps a host in use to a typed failure', () async {
    final client = _FakeRuntimeClient()
      ..responses['sshTarget.list'] = <Object?>[
        _targetJson('mac', 'Build Mac', bootstrapStatus: 'installed'),
      ]
      ..errors['sshTarget.remove'] = const TerminalHostConflictException(
        code: 'sshTargetInUse',
        message: 'host in use',
        details: <String, Object?>{
          'hostId': 'mac',
          'alias': 'Build Mac',
          'workspaceCount': 3,
          'checkoutCount': 2,
          'projectIds': <Object?>['p1', 'p2'],
        },
      );
    final container = _container(client);
    await _settle(container);
    final controller = container.read(remoteHostsControllerProvider.notifier);

    final result = await controller.removeHost('mac');

    expect(result.succeeded, isFalse);
    expect(result.inUse?.workspaceCount, 3);
    expect(
      result.errorMessage,
      'Build Mac still has 2 projects and 3 workspaces. Remove them first.',
    );
    final host = container.read(remoteHostsControllerProvider).hostById('mac')!;
    expect(host.actionError, result.errorMessage);
    expect(host.busy, isFalse);
  });

  test('a busy host asks to force the runtime update', () async {
    final client = _FakeRuntimeClient()
      ..capabilities.add(aleraRuntimeHostRemoteRuntimeUpdateCapability)
      ..responses['sshTarget.list'] = <Object?>[
        _targetJson('mac', 'Build Mac', bootstrapStatus: 'installed'),
      ]
      ..errorSequences['sshTarget.bootstrap.start'] = <Object?>[
        const TerminalHostConflictException(
          code: 'hostBusy',
          message: 'busy',
          details: <String, Object?>{
            'hostId': 'mac',
            'alias': 'Build Mac',
            'activeSessions': 2,
            'sessionIds': <Object?>['s1', 's2'],
          },
        ),
      ]
      ..responses['sshTarget.bootstrap.start'] = <String, Object?>{
        'jobId': 'job-2',
        'targetId': 'mac',
        'status': 'installing',
      };
    final container = _container(client);
    await _settle(container);
    final controller = container.read(remoteHostsControllerProvider.notifier);

    final busy = await controller.updateRuntime('mac');
    expect(busy.hostBusy?.activeSessions, 2);
    expect(busy.errorMessage, '2 terminals on Build Mac would close.');

    final forced = await controller.updateRuntime('mac', force: true);
    expect(forced.succeeded, isTrue);
    final payloads = client.payloads['sshTarget.bootstrap.start']!;
    expect(payloads.last['targetId'], 'mac');
    expect(payloads.last['restartRuntime'], isTrue);
    expect(payloads.last['force'], isTrue);
    final host = container.read(remoteHostsControllerProvider).hostById('mac')!;
    expect(host.installProgress?.includesRestart, isTrue);
    expect(host.installProgress?.steps, hasLength(8));
  });

  test('refuses the update on a runtime that cannot restart hosts', () async {
    final client = _FakeRuntimeClient()
      ..responses['sshTarget.list'] = <Object?>[
        _targetJson('mac', 'Build Mac', bootstrapStatus: 'installed'),
      ];
    final container = _container(client);
    await _settle(container);

    final result = await container
        .read(remoteHostsControllerProvider.notifier)
        .updateRuntime('mac');

    expect(result.succeeded, isFalse);
    expect(client.payloads['sshTarget.bootstrap.start'], isNull);
  });

  test('rejects a duplicate alias before and after the runtime', () async {
    final client = _FakeRuntimeClient()
      ..responses['sshTarget.list'] = <Object?>[
        _targetJson('mac', 'Build Mac', bootstrapStatus: 'installed'),
      ]
      ..errors['sshTarget.upsert'] = StateError(
        'ssh target alias already exists: Linux Box',
      );
    final container = _container(client);
    await _settle(container);
    final controller = container.read(remoteHostsControllerProvider.notifier);

    final local = await controller.addHost(
      const RemoteHostConnectionValues(
        alias: 'build mac',
        address: 'leynier@other',
      ),
    );
    expect(local.errorMessage, 'A host named build mac already exists.');
    expect(client.payloads['sshTarget.upsert'], isNull);

    final remote = await controller.addHost(
      const RemoteHostConnectionValues(
        alias: 'Linux Box',
        address: 'deploy@box',
        authKind: .key,
        identityFile: '~/.ssh/box',
      ),
    );
    expect(remote.errorMessage, 'A host named Linux Box already exists.');
    expect(
      client.payloads['sshTarget.upsert']!.single['identityFile'],
      '~/.ssh/box',
    );
  });

  test('checks a host through sshTarget.check', () async {
    final client = _FakeRuntimeClient()
      ..responses['sshTarget.list'] = <Object?>[
        _targetJson('mac', 'Build Mac', bootstrapStatus: 'installed'),
      ]
      ..responses['sshTarget.check'] = <String, Object?>{
        'targets': <Object?>[
          _targetJson(
            'mac',
            'Build Mac',
            bootstrapStatus: 'installed',
            lastStatus: 'runtimeReady',
          ),
        ],
      };
    final container = _container(client);
    await _settle(container);

    final result = await container
        .read(remoteHostsControllerProvider.notifier)
        .checkConnection('mac');

    expect(result.check?.runtimeInstalled, isTrue);
    expect(client.payloads['sshTarget.check']!.single, <String, Object?>{
      'id': 'mac',
    });
  });
}

ProviderContainer _container(_FakeRuntimeClient client) {
  final container = ProviderContainer(
    overrides: [
      sshTargetRepositoryProvider.overrideWithValue(
        RuntimeSshTargetRepository(
          client,
          bootstrapDefaults: const RuntimeSshBootstrapDefaults(
            channel: '',
            archiveUrl: '',
            version: '',
          ),
          coalescer: RuntimeChangeCoalescer(debounce: .zero, maxDelay: .zero),
        ),
      ),
    ],
  );
  addTearDown(() {
    container.dispose();
    unawaited(client.dispose());
  });
  container.listen(remoteHostsControllerProvider, (_, _) {});
  return container;
}

Future<RemoteHostsState> _settle(ProviderContainer container) async {
  for (var i = 0; i < 5; i++) {
    await pumpEventQueue();
  }
  return container.read(remoteHostsControllerProvider);
}

Map<String, Object?> _targetJson(
  String id,
  String alias, {
  required String bootstrapStatus,
  int port = 22,
  String? lastStatus,
  Map<String, Object?>? hostStatus,
}) {
  return <String, Object?>{
    'id': id,
    'alias': alias,
    'host': '$id.local',
    'port': port,
    'username': 'leynier',
    'authKind': 'agent',
    'createdAt': '2026-10-01T00:00:00Z',
    'updatedAt': '2026-10-01T00:00:00Z',
    'bootstrapStatus': bootstrapStatus,
    'lastStatus': ?lastStatus,
    'hostStatus': ?hostStatus,
  };
}

final class _FakeRuntimeClient
    implements RuntimeHostClient, RuntimeHostCapabilityClient {
  final responses = <String, Object?>{};
  final errors = <String, Object>{};
  final errorSequences = <String, List<Object?>>{};
  final payloads = <String, List<Map<String, Object?>>>{};
  final capabilities = <String>{aleraRuntimeHostRemoteHostLinkCapability};
  final _events = StreamController<RuntimeHostEvent>.broadcast();

  @override
  Stream<RuntimeHostEvent> get runtimeEvents => _events.stream;

  @override
  Future<bool> supportsRuntimeCapability(String capability) async =>
      capabilities.contains(capability);

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    payloads.putIfAbsent(type, () => <Map<String, Object?>>[]).add(payload);
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
    return responses[type];
  }

  void emitProgress(
    String targetId,
    String stage, {
    String status = 'installing',
    String? error,
  }) {
    _events.add(
      RuntimeHostEvent('sshTargetBootstrapProgress', <String, Object?>{
        'jobId': 'job-1',
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
