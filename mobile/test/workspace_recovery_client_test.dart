import 'package:alera_mobile/src/core/mobile_protocol.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_recovery_client.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> task({
  String host = 'local',
  String instance = 'instance',
  String path = '/project',
  String kind = 'main',
}) => {
  'id': 'task',
  'instanceId': instance,
  'projectId': 'project',
  'hostId': host,
  'name': 'Task',
  'path': path,
  'kind': kind,
  'branch': 'topic',
};

Map<String, Object?> journal() => {
  'id': 'operation',
  'source': task(),
  'destination': task(path: '/linked', kind: 'linked'),
  'phase': 'prepared',
  'moveChanges': false,
};

class Host(
  final Object? response, {
  final bool compatible = true,
  final Map<String, Object?> replies = const {},
}) with MobileRuntimeRecoveryClient {
  final calls = <String>[];
  final payloads = <String, Map<String, Object?>>{};
  @override
  Set<String> get runtimeCapabilities => compatible
      ? {sharedCheckoutWorkspacesCapability, 'safeWorkspaceHandoffV1'}
      : {};
  @override
  Future<Object?> request(
    String type, [
    Map<String, Object?> payload = const {},
    Duration? timeout,
  ]) async {
    calls.add(type);
    payloads[type] = payload;
    return replies.containsKey(type) ? replies[type] : response;
  }
}

void main() {
  test('workspace parser preserves owner and instance without changing legacy defaults', () {
    final remote = WorkspaceSummary.fromJson(task(host: 'ssh'));
    expect(remote.hostId, 'ssh');
    expect(remote.instanceId, 'instance');
    expect(remote.isRemote, isTrue);
    final legacy = task()
      ..remove('hostId')
      ..remove('instanceId');
    final local = WorkspaceSummary.fromJson(legacy);
    expect(local.isRemote, isFalse);
    expect(local.instanceId, isNull);
  });

  test(
    'local resume keeps the operation and requires a fresh buffer guard',
    () async {
      final source = WorkspaceSummary.fromJson(task());
      final host = Host(
        [
          {'relocation': journal()},
        ],
        replies: {
          'workspace.bufferGuard.acquire': {'guardId': 'fresh', 'ready': true},
          'workspace.handOff': {
            'workspace': task(path: '/linked', kind: 'linked'),
            'setupReport': {'steps': []},
          },
          'workspace.bufferGuard.release': null,
        },
      );
      final entry = (await host.inspectWorkspaceRecovery(source))
          .entries
          .single;
      host.calls.clear();
      await expectLater(
        host.resumeWorkspaceRecovery(
          source,
          entry,
          sharedImpactConfirmed: false,
        ),
        throwsStateError,
      );
      expect(host.calls, isEmpty);
      final result = await host.resumeWorkspaceRecovery(
        source,
        entry,
        sharedImpactConfirmed: true,
      );
      expect(result.workspace.instanceId, 'instance');
      expect(result.workspace.path, '/linked');
      expect(host.calls, [
        'workspace.relocationRecovery',
        'workspace.bufferGuard.acquire',
        'workspace.handOff',
        'workspace.bufferGuard.release',
      ]);
      expect(host.payloads['workspace.handOff']!['relocationId'], 'operation');
      expect(host.payloads['workspace.handOff']!['path'], '/linked');
      expect(host.payloads['workspace.handOff']!['bufferGuardId'], 'fresh');
    },
  );

  test(
    'SSH inspection preserves Home choices when the owner is disconnected',
    () async {
      final source = WorkspaceSummary.fromJson(task(host: 'ssh'));
      final host = Host({
        'kind': 'remoteWorkspaceRelocationRecovery',
        'workspace': task(host: 'ssh'),
        'owner': null,
        'ownerError': 'SSH disconnected',
        'homeIntents': [
          {
            'homeCommitted': false,
            'intent': {
              'id': 'operation',
              'source': task(host: 'ssh'),
              'workspaceRoot': '/original-root',
              'destinationPath': '/resolved-owner-path',
              'intent': {
                'workspaceId': 'task',
                'toProjectCheckout': false,
                'branch': 'saved',
                'moveChanges': false,
                'destinationPath': null,
              },
            },
          },
        ],
      });
      final snapshot = await host.inspectWorkspaceRecovery(source);
      expect(host.calls, ['workspace.sshRelocationRecovery']);
      expect(snapshot.ownerError, 'SSH disconnected');
      final entry = snapshot.entries.single;
      expect(entry.completed, isFalse);
      expect(entry.setupFinished, isFalse);
      expect(
        entry.resumePayload(sharedImpactConfirmed: true)['workspaceRoot'],
        '/original-root',
      );
      expect(
        entry.resumePayload(sharedImpactConfirmed: true).containsKey('path'),
        isFalse,
      );
    },
  );

  test(
    'foreign identities and old capabilities fail before recovery actions',
    () async {
      final source = WorkspaceSummary.fromJson(task());
      final old = Host([], compatible: false);
      await expectLater(
        old.inspectWorkspaceRecovery(source),
        throwsUnsupportedError,
      );
      expect(old.calls, isEmpty);
      final foreign = Host([
        {
          'relocation': {...journal(), 'source': task(instance: 'replacement')},
        },
      ]);
      await expectLater(
        foreign.inspectWorkspaceRecovery(source),
        throwsFormatException,
      );
    },
  );

  test(
    'setup cancellation retains the exact attempt and cannot silently rerun it',
    () async {
      final source = WorkspaceSummary.fromJson(task());
      final host = Host(
        [
          {
            'relocation': {...journal(), 'phase': 'completed'},
            'setup': {'attemptId': 'attempt', 'report': null},
          },
        ],
        replies: {
          'workspace.cancelRelocationSetup': {
            'cancellationRequested': true,
            'processesClosed': false,
          },
        },
      );
      final entry = (await host.inspectWorkspaceRecovery(source))
          .entries
          .single;
      await host.cancelWorkspaceRecoverySetup(source, entry);
      expect(host.payloads['workspace.cancelRelocationSetup'], {
        'id': 'task',
        'relocationId': 'operation',
        'attemptId': 'attempt',
      });
      await expectLater(
        host.runWorkspaceRecoverySetup(source, entry),
        throwsStateError,
      );
      expect(host.calls, isNot(contains('workspace.runSetup')));
    },
  );
}
