import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:alera/src/features/settings/presentation/panes/remote_host_target_signatures.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final createdAt = DateTime.utc(2026, 1, 1);
  final target = SshTarget(
    id: 'target-1',
    alias: 'Server',
    host: 'example.test',
    port: 22,
    username: 'user',
    authKind: .agent,
    createdAt: createdAt,
    updatedAt: createdAt,
    installDir: '/opt/alera',
    projectsDir: '~/code',
  );

  test('editor signature changes with the projects folder', () {
    final signature = remoteHostEditorSignature(target);

    expect(
      remoteHostEditorSignature(target.copyWith(projectsDir: '/srv/projects')),
      isNot(signature),
    );
    expect(
      remoteHostEditorSignature(target.copyWith(installDir: '/srv/alera')),
      isNot(signature),
    );
  });

  test('editor signature ignores runtime status fields', () {
    final refreshed = SshTarget.fromJson(<String, Object?>{
      ...target.toJson(),
      'updatedAt': '2026-02-01T00:00:00Z',
      'bootstrapStatus': 'installed',
      'runtimeVersion': '0.14.0',
      'lastError': 'old warning',
    });

    expect(
      remoteHostEditorSignature(refreshed),
      remoteHostEditorSignature(target),
    );
    expect(
      remoteHostStatusSignature(refreshed),
      isNot(remoteHostStatusSignature(target)),
    );
  });
}
