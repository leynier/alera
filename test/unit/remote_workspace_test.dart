import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:alera/src/features/workbench/domain/remote_workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:flutter_test/flutter_test.dart';

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

  test('host selection errors name bootstrap and unreachable hosts', () {
    final installed = _target(
      id: 'ssh-1',
      alias: 'Build Mac',
      bootstrapStatus: SshBootstrapStatus.installed,
    );
    final missingSidecar = _target(
      id: 'ssh-2',
      alias: 'Office Linux',
      bootstrapStatus: SshBootstrapStatus.notInstalled,
    );
    final unreachable = _target(
      id: 'ssh-3',
      alias: 'Windows Box',
      bootstrapStatus: SshBootstrapStatus.installed,
      lastStatus: 'unreachable',
    );

    expect(
      remoteWorkspaceHostSelectionError(
        hostId: null,
        targets: <SshTarget>[installed],
        supportsRemoteSshWorkspaces: true,
      ),
      isNull,
    );
    expect(
      remoteWorkspaceHostSelectionError(
        hostId: 'ssh-1',
        targets: <SshTarget>[installed],
        supportsRemoteSshWorkspaces: false,
      ),
      remoteHostMissingCapabilityMessage(),
    );
    expect(
      remoteWorkspaceHostSelectionError(
        hostId: 'missing',
        targets: <SshTarget>[installed],
        supportsRemoteSshWorkspaces: true,
      ),
      contains('ssh target not found'),
    );
    expect(
      remoteWorkspaceHostSelectionError(
        hostId: 'ssh-2',
        targets: <SshTarget>[missingSidecar],
        supportsRemoteSshWorkspaces: true,
      ),
      contains('not bootstrapped'),
    );
    expect(
      remoteWorkspaceHostSelectionError(
        hostId: 'ssh-3',
        targets: <SshTarget>[unreachable],
        supportsRemoteSshWorkspaces: true,
      ),
      contains('unreachable'),
    );
  });

  test('user-facing mapper keeps host errors and strips Dart prefixes', () {
    expect(
      userFacingExceptionMessage(
        StateError(
          hostNotBootstrappedMessage(
            _target(id: 'ssh-2', alias: 'Office Linux'),
          ),
        ),
      ),
      contains('not bootstrapped'),
    );
    expect(
      userFacingExceptionMessage(Exception('source branch is required')),
      'source branch is required',
    );
  });

  test('user-facing mapper maps unknown files/hostid requests to missing capability', () {
    expect(
      userFacingExceptionMessage(
        Exception('unknown terminal host request: workspace.files.list'),
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
        Exception(remoteWorkspaceWriteUnsupportedMessage()),
      ),
      remoteWorkspaceWriteUnsupportedMessage(),
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

SshTarget _target({
  required String id,
  required String alias,
  SshBootstrapStatus bootstrapStatus = SshBootstrapStatus.installed,
  String? lastStatus,
}) {
  final now = DateTime.utc(2026, 9, 8);
  return SshTarget(
    id: id,
    alias: alias,
    host: '$alias.example.test',
    port: 22,
    username: 'leynier',
    authKind: SshAuthKind.agent,
    createdAt: now,
    updatedAt: now,
    bootstrapStatus: bootstrapStatus,
    lastStatus: lastStatus,
  );
}
