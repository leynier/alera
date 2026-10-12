import 'package:alera/src/features/remote_hosts/application/remote_host_selection.dart';
import 'package:alera/src/features/remote_hosts/domain/remote_host_status.dart';
import 'package:alera/src/features/workbench/domain/remote_workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/remote_host_view_fixtures.dart';

void main() {
  test('Workspace.isRemote is false for local and blank host ids', () {
    expect(_workspace(hostId: 'local').isRemote, isFalse);
    expect(_workspace(hostId: '  ').isRemote, isFalse);
    expect(_workspace(hostId: 'ssh-box').isRemote, isTrue);
  });

  test('normalizedRemoteHostId drops local ids', () {
    expect(normalizedRemoteHostId(null), isNull);
    expect(normalizedRemoteHostId('local'), isNull);
    expect(normalizedRemoteHostId(' ssh-box '), 'ssh-box');
  });

  test('host selection errors name the reason a host cannot be used', () {
    final connected = remoteHostView(
      'ssh-1',
      'Build Mac',
      status: const RemoteHostConnected(),
    );
    final offline = remoteHostView(
      'ssh-2',
      'Office Linux',
      status: const RemoteHostOffline(),
    );
    final needsSetup = remoteHostView(
      'ssh-3',
      'Windows Box',
      status: const RemoteHostNeedsSetup(),
    );
    final installing = remoteHostView(
      'ssh-4',
      'GPU Rig',
      status: const RemoteHostInstalling(),
    );
    final failing = remoteHostView(
      'ssh-5',
      'Old Mac',
      status: const RemoteHostError(detail: 'Permission denied'),
    );
    final hosts = [connected, offline, needsSetup, installing, failing];
    String? error(String? hostId, {bool supported = true}) =>
        remoteHostSelectionError(
          hostId: hostId,
          hosts: hosts,
          supportsRemoteSshWorkspaces: supported,
        );

    expect(error(null), isNull);
    expect(error('ssh-1'), isNull);
    expect(error('ssh-2'), isNull, reason: 'the runtime connects on demand');
    expect(
      error('ssh-1', supported: false),
      remoteHostMissingCapabilityMessage(),
    );
    expect(error('missing'), sshTargetNotFoundMessage('missing'));
    expect(
      error('ssh-3'),
      'The Alera runtime is not installed on Windows Box yet.',
    );
    expect(error('ssh-4'), 'The Alera runtime is still installing on GPU Rig.');
    expect(error('ssh-5'), 'Old Mac: Permission denied');
  });

  test('host messages never send the user to plain-text settings paths', () {
    for (final message in <String>[
      remoteHostMissingCapabilityMessage(),
      remoteWorkspaceFilesMissingCapabilityMessage(),
      sshTargetNotFoundMessage('ssh-1'),
    ]) {
      expect(message, isNot(contains('→')));
      expect(message.toLowerCase(), isNot(contains('sidecar')));
    }
  });

  test('user-facing mapper keeps runtime host errors and strips prefixes', () {
    expect(
      userFacingExceptionMessage(
        StateError(
          "host 'Office Linux' is not bootstrapped. Open Settings → Remote Hosts and install the Alera runtime.",
        ),
      ),
      contains('not bootstrapped'),
    );
    expect(
      remoteWorkspaceErrorMessage(
        Exception('retry from Settings → Remote Hosts.'),
      ),
      'retry from Settings → Remote Hosts.',
    );
    expect(
      userFacingExceptionMessage(Exception('source branch is required')),
      'source branch is required',
    );
  });

  test('picker labels mark hosts that are not ready', () {
    expect(remoteHostView('ssh-1', 'Build Mac').pickerLabel, 'Build Mac');
    expect(
      remoteHostView(
        'ssh-2',
        'Office Linux',
        status: const RemoteHostOffline(),
      ).pickerLabel,
      'Office Linux',
    );
    expect(
      remoteHostView(
        'ssh-3',
        'Windows Box',
        status: const RemoteHostNeedsSetup(),
      ).pickerLabel,
      'Windows Box (Needs Setup)',
    );
    expect(
      remoteHostView(
        'ssh-4',
        'GPU Rig',
        status: const RemoteHostError(detail: 'boom'),
      ).pickerLabel,
      'GPU Rig (Error)',
    );
  });

  test('user-facing mapper maps unknown files/hostid requests to missing capability', () {
    expect(
      remoteWorkspaceFilesMissingCapabilityMessage(),
      contains('cannot browse files on a remote workspace'),
    );
    expect(
      userFacingExceptionMessage(
        Exception('unknown terminal host request: workspace.files.list'),
      ),
      remoteWorkspaceFilesMissingCapabilityMessage(),
    );
    expect(
      userFacingExceptionMessage(
        Exception('unknown terminal host request: workspace.files.read'),
      ),
      remoteWorkspaceFilesMissingCapabilityMessage(),
    );
    expect(
      userFacingExceptionMessage(
        StateError('unknown terminal host request: hostId is not supported'),
      ),
      remoteWorkspaceFilesMissingCapabilityMessage(),
    );
    expect(
      remoteWorkspaceErrorMessage(
        Exception('unknown terminal host request without a files verb'),
      ),
      isNull,
    );
    expect(
      userFacingExceptionMessage(
        Exception(remoteWorkspaceFilesMissingCapabilityMessage()),
      ),
      remoteWorkspaceFilesMissingCapabilityMessage(),
    );
  });
}

Workspace _workspace({required String hostId}) {
  final now = DateTime.utc(2026, 9, 8);
  return Workspace(
    id: 'workspace-1',
    projectId: 'project-1',
    name: 'Feature',
    path: '/remote/feature',
    createdAt: now,
    updatedAt: now,
    kind: WorkspaceKind.linked,
    status: WorkspaceStatus.active,
    hostId: hostId,
  );
}
