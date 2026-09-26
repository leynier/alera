import 'package:alera/src/design_system/icons/alera_host_os_icon.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target_host_os.dart';
import 'package:flutter_test/flutter_test.dart';

SshTarget _target({String? platform, String? runtimePlatform}) {
  final now = DateTime.utc(2026, 1, 1);
  return SshTarget(
    id: 'build-mac',
    alias: 'Build Mac',
    host: 'mac.example.test',
    port: 22,
    username: 'leynier',
    authKind: SshAuthKind.agent,
    createdAt: now,
    updatedAt: now,
    platform: platform,
    runtimePlatform: runtimePlatform,
  );
}

void main() {
  test('HostOs.parse accepts sidecar and probe spellings', () {
    expect(HostOs.parse('macos'), HostOs.macos);
    expect(HostOs.parse('darwin'), HostOs.macos);
    expect(HostOs.parse('Windows'), HostOs.windows);
    expect(HostOs.parse('win32'), HostOs.windows);
    expect(HostOs.parse('linux'), HostOs.linux);
    expect(HostOs.parse(null), HostOs.unknown);
    expect(HostOs.parse('freebsd'), HostOs.unknown);
  });

  test('probed runtime platform wins over the user-entered hint', () {
    expect(
      sshTargetHostOs(_target(platform: 'linux', runtimePlatform: 'windows')),
      HostOs.windows,
    );
    expect(sshTargetHostOs(_target(platform: 'macos')), HostOs.macos);
    expect(sshTargetHostOs(_target()), HostOs.unknown);
    expect(sshTargetHostOs(null), HostOs.unknown);
  });

  test('tooltip names the host alias and falls back to the raw id', () {
    expect(
      workspaceHostTooltip(
        hostId: 'build-mac',
        target: _target(runtimePlatform: 'darwin'),
      ),
      'Build Mac (macOS)',
    );
    expect(
      workspaceHostTooltip(hostId: 'build-mac', target: _target()),
      'Build Mac',
    );
    expect(workspaceHostTooltip(hostId: 'gone-host'), 'gone-host');
  });

  test('sshTargetsById indexes by id', () {
    final index = sshTargetsById(<SshTarget>[_target()]);
    expect(index.keys, <String>['build-mac']);
    expect(index['build-mac']?.alias, 'Build Mac');
  });
}
