import 'package:alera/src/features/remote_hosts/domain/remote_host_form_values.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_address.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseSshAddress', () {
    test('parses user@host with the default port', () {
      final address = parseSshAddress('  leynier@mac.local ');
      expect(address.username, 'leynier');
      expect(address.host, 'mac.local');
      expect(address.port, 22);
      expect(address.format(), 'leynier@mac.local');
    });

    test('parses an explicit port', () {
      final address = parseSshAddress('deploy@10.0.0.4:2222');
      expect(address.host, '10.0.0.4');
      expect(address.port, 2222);
      expect(address.format(), 'deploy@10.0.0.4:2222');
    });

    test('parses IPv6 hosts with and without brackets', () {
      final bracketed = parseSshAddress('root@[fe80::1]:2200');
      expect(bracketed.host, 'fe80::1');
      expect(bracketed.port, 2200);
      expect(bracketed.format(), 'root@[fe80::1]:2200');

      final bracketedNoPort = parseSshAddress('root@[::1]');
      expect(bracketedNoPort.host, '::1');
      expect(bracketedNoPort.port, 22);
      expect(bracketedNoPort.format(), 'root@::1');

      final bare = parseSshAddress('root@fe80::1');
      expect(bare.host, 'fe80::1');
      expect(bare.port, 22);
    });

    test('keeps an @ inside the username', () {
      final address = parseSshAddress('me@corp.example@bastion');
      expect(address.username, 'me@corp.example');
      expect(address.host, 'bastion');
    });

    test('rejects malformed addresses with a readable reason', () {
      expect(sshAddressError(''), 'Enter an SSH address such as user@host.');
      expect(
        sshAddressError('mac.local'),
        'Include the username, as in user@host.',
      );
      expect(
        sshAddressError('@mac.local'),
        'Include the username, as in user@host.',
      );
      expect(sshAddressError('leynier@'), 'Include the host, as in user@host.');
      expect(
        sshAddressError('leynier@mac :22'),
        'The SSH address cannot contain spaces.',
      );
      expect(
        sshAddressError('leynier@mac:0'),
        'Port must be between 1 and 65535.',
      );
      expect(
        sshAddressError('leynier@mac:70000'),
        'Port must be between 1 and 65535.',
      );
      expect(
        sshAddressError('leynier@mac:ssh'),
        'Port must be between 1 and 65535.',
      );
      expect(sshAddressError('root@[::1'), isNotNull);
      expect(sshAddressError('root@[::1]x'), isNotNull);
      expect(tryParseSshAddress('nope'), isNull);
      expect(sshAddressError('leynier@mac.local'), isNull);
    });
  });

  group('sshCommandFor', () {
    test('omits the default port and adds an identity file', () {
      expect(sshCommandFor(_target()), 'ssh leynier@mac.local');
      expect(
        sshCommandFor(_target(port: 2222, identityFile: '~/.ssh/build_mac')),
        'ssh -p 2222 -i ~/.ssh/build_mac leynier@mac.local',
      );
      expect(
        sshCommandFor(_target(identityFile: r'C:\Users\Ley Nier\.ssh\id')),
        r'ssh -i "C:\Users\Ley Nier\.ssh\id" leynier@mac.local',
      );
    });

    test('labels the address with the port only when it is not 22', () {
      expect(sshAddressLabel(_target()), 'leynier@mac.local');
      expect(sshAddressLabel(_target(port: 2222)), 'leynier@mac.local:2222');
    });
  });

  group('RemoteHostConnectionValues', () {
    test('validates the name, duplicates and address', () {
      final existing = <SshTarget>[_target()];
      expect(
        const RemoteHostConnectionValues(
          alias: ' ',
          address: 'a@b',
        ).validate(existing: existing),
        'Enter a name for this host.',
      );
      expect(
        const RemoteHostConnectionValues(
          alias: 'build mac',
          address: 'a@b',
        ).validate(existing: existing),
        'A host named build mac already exists.',
      );
      expect(
        const RemoteHostConnectionValues(
          alias: 'Build Mac',
          address: 'a@b',
        ).validate(existing: existing, editingId: 'mac'),
        isNull,
      );
      expect(
        const RemoteHostConnectionValues(
          alias: 'Linux Box',
          address: 'box',
        ).validate(existing: existing),
        'Include the username, as in user@host.',
      );
    });

    test('builds a target and keeps an identity file only for key auth', () {
      final now = DateTime.utc(2026, 10, 11);
      final keyTarget = const RemoteHostConnectionValues(
        alias: ' Linux Box ',
        address: 'deploy@box:2200',
        authKind: .key,
        identityFile: ' ~/.ssh/box ',
      ).toTarget(now: now);
      expect(keyTarget.alias, 'Linux Box');
      expect(keyTarget.username, 'deploy');
      expect(keyTarget.host, 'box');
      expect(keyTarget.port, 2200);
      expect(keyTarget.identityFile, '~/.ssh/box');
      expect(keyTarget.id, startsWith('ssh-'));

      final agentTarget =
          const RemoteHostConnectionValues(
            alias: 'Build Mac',
            address: 'leynier@mac.local',
            identityFile: '~/.ssh/ignored',
          ).toTarget(
            existing: _target(installDir: '/opt/alera'),
            now: now,
          );
      expect(agentTarget.id, 'mac');
      expect(agentTarget.identityFile, isNull);
      expect(agentTarget.installDir, '/opt/alera');
    });

    test('round-trips a target', () {
      final values = RemoteHostConnectionValues.fromTarget(
        _target(port: 2222, identityFile: '~/.ssh/key'),
      );
      expect(values.address, 'leynier@mac.local:2222');
      expect(values.identityFile, '~/.ssh/key');
    });
  });

  test('RemoteHostAdvancedValues normalizes and clears blank values', () {
    final values = RemoteHostAdvancedValues.fromTarget(
      _target(installDir: '/opt/alera')
          .copyWith(platform: 'Darwin', arch: 'aarch64'),
    );
    expect(values.platform, 'macos');
    expect(values.arch, 'arm64');

    final cleared = const RemoteHostAdvancedValues(installDir: '  ').applyTo(
      _target(installDir: '/opt/alera'),
      now: DateTime.utc(2026, 10, 11),
    );
    expect(cleared.installDir, isNull);
    expect(cleared.platform, isNull);
    expect(parseRemoteHostPort(''), 22);
    expect(parseRemoteHostPort('70000'), isNull);
  });
}

SshTarget _target({int port = 22, String? identityFile, String? installDir}) {
  final now = DateTime.utc(2026, 10);
  return SshTarget(
    id: 'mac',
    alias: 'Build Mac',
    host: 'mac.local',
    port: port,
    username: 'leynier',
    authKind: .key,
    createdAt: now,
    updatedAt: now,
    identityFile: identityFile,
    installDir: installDir,
  );
}
