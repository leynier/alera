import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_relocation_recovery.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alera/src/features/workbench/infra/workspace_relocation_recovery_client.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';

Workspace task({String host = 'local'}) => Workspace(
  id: 'task',
  instanceId: 'instance',
  projectId: 'project',
  name: 'Task',
  path: '/project',
  branch: 'original',
  hostId: host,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  kind: .main,
  status: .active,
);

Map<String, Object?> journal(Workspace source) => {
  'id': 'operation',
  'source': source.toMap(),
  'destination': source
      .copyWith(kind: .linked, path: '/linked', branch: 'topic')
      .toMap(),
  'phase': 'prepared',
  'moveChanges': false,
  'replacementBranch': null,
};

Map<String, Object?> remoteReport(
  Workspace source, {
  bool ownerAvailable = true,
}) => {
  'kind': 'remoteWorkspaceRelocationRecovery',
  'workspace': source.toMap(),
  'homeIntents': [
    {
      'homeCommitted': false,
      'intent': {
        'id': 'operation',
        'source': source.toMap(),
        'workspaceRoot': '/original-root',
        'destinationPath': '/resolved-owner-path',
        'intent': {
          'workspaceId': source.id,
          'toProjectCheckout': false,
          'branch': 'original-choice',
          'replacementBranch': null,
          'moveChanges': false,
          'destinationPath': null,
        },
      },
    },
  ],
  'owner': ownerAvailable
      ? {
          'version': 1,
          'workspace': source.copyWith(hostId: 'local').toMap(),
          'items': [
            {'relocation': journal(source.copyWith(hostId: 'local'))},
          ],
        }
      : null,
  'ownerError': ownerAvailable ? null : 'Owner is unreachable',
};

class RecoveryHost(
  final Object? response, {
  final bool compatible = true,
  final Map<String, Object?> replies = const {},
}) implements RuntimeHostClient {
  final calls = <String>[];
  final payloads = <String, Map<String, Object?>>{};
  @override
  Stream<RuntimeHostEvent> get runtimeEvents => const Stream.empty();
  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const {},
    Duration? timeout,
  ]) async {
    calls.add(type);
    payloads[type] = payload;
    if (type == 'status.get') {
      return {
        'runtimeCapabilities': compatible
            ? [
                aleraRuntimeHostSharedCheckoutCapability,
                aleraRuntimeHostSafeHandoffCapability,
              ]
            : [],
      };
    }
    if (replies.containsKey(type)) return replies[type];
    expect(payload, {'id': 'task', 'limit': 20});
    expect(timeout, const Duration(seconds: 45));
    return response;
  }
}

void main() {
  test(
    'resume refreshes original intent and acquires a fresh buffer guard',
    () async {
      final source = task();
      final response = [
        {'relocation': journal(source)},
      ];
      final entry = WorkspaceRelocationRecoverySnapshot.fromResponse(
        source,
        response,
      ).entries.single;
      final host = RecoveryHost(
        response,
        replies: {
          'workspace.bufferGuard.acquire': {
            'guardId': 'fresh-guard',
            'ready': true,
          },
          'workspace.handOff': {
            'workspace': source
                .copyWith(kind: .linked, path: '/linked', branch: 'topic')
                .toMap(),
            'setupReport': {'steps': []},
          },
          'workspace.bufferGuard.release': null,
        },
      );
      final client = WorkspaceRelocationRecoveryClient(host);
      await expectLater(
        client.resume(source, entry, sharedImpactConfirmed: false),
        throwsStateError,
      );
      expect(host.calls, isEmpty);
      final result = await client.resume(
        source,
        entry,
        sharedImpactConfirmed: true,
      );
      expect(result.workspace.id, source.id);
      expect(result.workspace.path, '/linked');
      expect(host.calls, [
        'status.get',
        'workspace.relocationRecovery',
        'workspace.bufferGuard.acquire',
        'workspace.handOff',
        'workspace.bufferGuard.release',
      ]);
      expect(host.payloads['workspace.handOff'], {
        ...entry.resumePayload(sharedImpactConfirmed: true),
        'bufferGuardId': 'fresh-guard',
      });
    },
  );

  test(
    'superseded history and dirty buffers prevent resume dispatch',
    () async {
      final source = task();
      final response = [
        {'relocation': journal(source)},
      ];
      final entry = WorkspaceRelocationRecoverySnapshot.fromResponse(
        source,
        response,
      ).entries.single;
      final superseded = RecoveryHost([
        {
          'relocation': {...journal(source), 'id': 'newer-operation'},
        },
      ]);
      await expectLater(
        WorkspaceRelocationRecoveryClient(superseded)
            .resume(source, entry, sharedImpactConfirmed: true),
        throwsStateError,
      );
      expect(superseded.calls, ['status.get', 'workspace.relocationRecovery']);
      final dirty = RecoveryHost(
        response,
        replies: {
          'workspace.bufferGuard.acquire': {
            'guardId': 'guard',
            'ready': false,
            'blockers': [
              {'path': '/project/file', 'reason': 'Unsaved buffer'},
            ],
          },
          'workspace.bufferGuard.release': null,
        },
      );
      await expectLater(
        WorkspaceRelocationRecoveryClient(dirty)
            .resume(source, entry, sharedImpactConfirmed: true),
        throwsStateError,
      );
      expect(dirty.calls, isNot(contains('workspace.handOff')));
      expect(dirty.calls.last, 'workspace.bufferGuard.release');
    },
  );

  test('setup controls reject a replaced attempt and preserve exact cancellation scope', () async {
    final source = task();
    Map<String, Object?> record(String attempt) => {
      'relocation': {...journal(source), 'phase': 'completed'},
      'setup': {'attemptId': attempt, 'report': null},
    };
    final entry = WorkspaceRelocationRecoverySnapshot.fromResponse(source, [
      record('original'),
    ]).entries.single;
    final changed = RecoveryHost([record('replacement')]);
    await expectLater(
      WorkspaceRelocationRecoveryClient(changed).cancelSetup(source, entry),
      throwsStateError,
    );
    expect(changed.calls, isNot(contains('workspace.cancelRelocationSetup')));
    final owner = RecoveryHost(
      [record('original')],
      replies: {
        'workspace.cancelRelocationSetup': {
          'cancellationRequested': true,
          'processesClosed': false,
        },
      },
    );
    await WorkspaceRelocationRecoveryClient(owner).cancelSetup(source, entry);
    expect(owner.payloads['workspace.cancelRelocationSetup'], {
      'id': 'task',
      'relocationId': 'operation',
      'attemptId': 'original',
    });
    await expectLater(
      WorkspaceRelocationRecoveryClient(owner).runSetup(source, entry),
      throwsStateError,
    );
    expect(owner.calls, isNot(contains('workspace.runSetup')));
  });

  test(
    'inspection negotiates support and uses only the matching read endpoint',
    () async {
      for (final hostId in ['local', 'ssh']) {
        final source = task(host: hostId);
        final host = RecoveryHost(
          hostId == 'local' ? [] : remoteReport(source),
        );
        var initialized = false;
        final client = WorkspaceRelocationRecoveryClient(
          host,
          beforeAccess: () async {
            initialized = true;
          },
        );
        await client.inspect(source);
        expect(initialized, isTrue);
        expect(host.calls, [
          'status.get',
          hostId == 'local'
              ? 'workspace.relocationRecovery'
              : 'workspace.sshRelocationRecovery',
        ]);
      }
      final oldHost = RecoveryHost([], compatible: false);
      await expectLater(
        WorkspaceRelocationRecoveryClient(oldHost).inspect(task()),
        throwsUnsupportedError,
      );
      expect(oldHost.calls, ['status.get']);
    },
  );
  test(
    'local resume retains original path and requires fresh impact consent',
    () {
      final source = task();
      final snapshot = WorkspaceRelocationRecoverySnapshot.fromResponse(
        source,
        [
          {'relocation': journal(source)},
        ],
      );
      final entry = snapshot.entries.single;
      expect(
        () => entry.resumePayload(sharedImpactConfirmed: false),
        throwsStateError,
      );
      expect(entry.resumePayload(sharedImpactConfirmed: true), {
        'id': 'task',
        'expectedInstanceId': 'instance',
        'relocationId': 'operation',
        'sharedImpactConfirmed': true,
        'branch': 'topic',
        'replacementBranch': null,
        'reuseExistingBranch': false,
        'moveChanges': false,
        'path': '/linked',
        'deferSetup': true,
      });
      expect(entry.completed, isFalse);
    },
  );

  test('SSH retry uses original choices rather than resolved owner path', () {
    final source = task(host: 'ssh');
    final snapshot = WorkspaceRelocationRecoverySnapshot.fromResponse(
      source,
      remoteReport(source),
    );
    final payload = snapshot.entries.single.resumePayload(
      sharedImpactConfirmed: true,
    );
    expect(payload['workspaceRoot'], '/original-root');
    expect(payload['branch'], 'original-choice');
    expect(payload.containsKey('path'), isFalse);
    expect(snapshot.ownerError, isNull);
  });

  test(
    'offline owner retains Home intent without claiming process closure',
    () {
      final source = task(host: 'ssh');
      final snapshot = WorkspaceRelocationRecoverySnapshot.fromResponse(
        source,
        remoteReport(source, ownerAvailable: false),
      );
      expect(snapshot.ownerError, 'Owner is unreachable');
      expect(snapshot.entries.single.phase, 'awaitingOwner');
      expect(snapshot.entries.single.completed, isFalse);
      expect(snapshot.entries.single.setupFinished, isFalse);
      expect(snapshot.entries.single.processObservations, isEmpty);
    },
  );

  test('history from another instance or host cannot supply retry choices', () {
    final source = task();
    for (final different in [
      source.copyWith(instanceId: 'replacement'),
      source.copyWith(hostId: 'ssh'),
    ]) {
      expect(
        () => WorkspaceRelocationRecoverySnapshot.fromResponse(source, [
          {'relocation': journal(different)},
        ]),
        throwsFormatException,
      );
    }
    final remote = task(host: 'ssh');
    final response = remoteReport(remote);
    (response['owner'] as Map)['workspace'] = remote
        .copyWith(hostId: 'other-owner')
        .toMap();
    expect(
      () => WorkspaceRelocationRecoverySnapshot.fromResponse(remote, response),
      throwsFormatException,
    );
  });

  test('setup observations preserve unknown state and recorded failures', () {
    final source = task();
    final record = {
      'relocation': journal(source),
      'setup': {
        'attemptId': 'attempt',
        'report': {
          'steps': [
            {'succeeded': false},
          ],
        },
      },
      'setupCancellationRequested': true,
      'setupRootObservations': [
        {'state': 'unknown', 'reason': 'Process closure cannot be verified'},
      ],
    };
    final snapshot = WorkspaceRelocationRecoverySnapshot.fromResponse(source, [
      record,
    ]);
    final entry = snapshot.entries.single;
    expect(entry.setupFailed, isTrue);
    expect(entry.setupCancellationRequested, isTrue);
    expect(
      entry.processObservations.single,
      'unknown: Process closure cannot be verified',
    );
    expect(() => snapshot.entries.clear(), throwsUnsupportedError);
    expect(
      () => WorkspaceRelocationRecoverySnapshot.fromResponse(source, [
        record,
        record,
      ]),
      throwsFormatException,
    );
  });
}
