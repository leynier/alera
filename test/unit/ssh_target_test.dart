import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('copies an SSH target while preserving runtime state', () {
    final createdAt = DateTime.utc(2026, 1, 1);
    final target = SshTarget(
      id: 'target-1',
      alias: 'Server',
      host: 'example.test',
      port: 22,
      username: 'user',
      authKind: .key,
      createdAt: createdAt,
      updatedAt: createdAt,
      platform: 'linux',
      arch: 'x64',
      lastStatus: 'online',
      installDir: '/opt/alera',
      runtimeVersion: '0.14.0',
      runtimePlatform: 'linux',
      runtimeArch: 'x64',
      bootstrapStatus: .installed,
      lastBootstrapAt: createdAt,
      lastCheckedAt: createdAt,
      lastError: 'old warning',
    );

    final copied = target.copyWith(
      alias: 'Updated',
      host: 'new.example.test',
      port: 2222,
      username: 'other',
      platform: 'macos',
      arch: 'arm64',
      authKind: .agent,
      installDir: '/srv/alera',
    );

    expect(copied.alias, 'Updated');
    expect(copied.host, 'new.example.test');
    expect(copied.port, 2222);
    expect(copied.username, 'other');
    expect(copied.platform, 'macos');
    expect(copied.arch, 'arm64');
    expect(copied.authKind, SshAuthKind.agent);
    expect(copied.installDir, '/srv/alera');
    expect(copied.createdAt, createdAt);
    expect(copied.updatedAt.isAfter(createdAt), isTrue);
    expect(copied.runtimeVersion, '0.14.0');
    expect(copied.bootstrapStatus, SshBootstrapStatus.installed);
    expect(copied.lastError, 'old warning');

    final preserved = target.copyWith();
    expect(preserved.alias, target.alias);
    expect(preserved.host, target.host);
    expect(preserved.port, target.port);
    expect(preserved.username, target.username);
    expect(preserved.platform, target.platform);
    expect(preserved.arch, target.arch);
    expect(preserved.authKind, target.authKind);
    expect(preserved.installDir, target.installDir);
  });

  test('parses numeric ports and validates required fields', () {
    final target = SshTarget.fromJson(<String, Object?>{
      'id': 'target-1',
      'alias': 'Server',
      'host': 'example.test',
      'port': 2200.8,
      'username': 'user',
      'createdAt': '2026-01-01T00:00:00Z',
      'updatedAt': '2026-01-02T00:00:00Z',
    });

    expect(target.port, 2200);
    expect(
      () => SshTarget.fromJson(<String, Object?>{
        'id': '',
        'alias': 'Server',
        'host': 'example.test',
        'username': 'user',
        'createdAt': '2026-01-01T00:00:00Z',
        'updatedAt': '2026-01-02T00:00:00Z',
      }),
      throwsFormatException,
    );
  });
}
