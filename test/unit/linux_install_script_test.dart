import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const String _script = 'landing/public/install.sh';
const String _pinnedFingerprint = '01DAF16E430AF8B2607BA44D457D8143C91B4732';

void main() {
  test('pins the fingerprint of the published repository key', () {
    final source = File(_script).readAsStringSync();

    expect(source, contains('ALERA_KEY_FINGERPRINT="$_pinnedFingerprint"'));
    expect(source, startsWith('#!/bin/sh'));
    expect(source, contains('set -eu'));
    expect(source, isNot(contains('\u2014')));
  });

  test('keeps the pinned fingerprint in step with the release script', () {
    final releaseScript = File(
      'tool/release/build_linux_repositories.sh',
    ).readAsStringSync();

    expect(
      releaseScript,
      contains('alera-archive-keyring.asc'),
      reason: 'the installer downloads the key this script publishes',
    );
  });

  test('publishes one fingerprint everywhere it is quoted', () {
    // A rotation that updates the script but not the documentation leaves users
    // verifying against a key that no longer signs anything.
    for (final path in <String>[
      _script,
      'readme.md',
      'docs/release-trust.md',
      'landing/src/components/Install.astro',
    ]) {
      expect(
        File(path).readAsStringSync(),
        contains(_pinnedFingerprint),
        reason: '$path documents the repository signing key',
      );
    }
  });

  test('links the app install guide at an anchor the landing page has', () {
    expect(
      File('landing/src/components/Install.astro').readAsStringSync(),
      contains('id="install"'),
      reason:
          'AleraUpdateConfig.installGuideUrl targets https://alera.build/#install',
    );
    expect(
      File(
        'lib/src/features/updater/domain/alera_update.dart',
      ).readAsStringSync(),
      contains('https://alera.build/#install'),
    );
  });

  test('runs everything from main so a truncated download does nothing', () {
    final source = File(_script).readAsStringSync();

    expect(source.trimRight(), endsWith('main "\$@"'));
  });

  test('stays within POSIX sh', () {
    final source = File(_script).readAsStringSync();

    for (final bashism in <String>[
      '[[',
      'pipefail',
      'function ',
      'echo -e',
      'declare ',
      'mapfile',
      r"$'",
    ]) {
      expect(
        source,
        isNot(contains(bashism)),
        reason: '$bashism is not POSIX and dash does not support it',
      );
    }
  });

  group('install.sh', () {
    test('configures the apt repository and installs Alera', () async {
      final fixture = await _InstallFixture.create(
        packageManagers: <String>['apt-get'],
      );
      addTearDown(fixture.dispose);

      final result = await fixture.run();
      expect(
        result.exitCode,
        0,
        reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
      );

      expect(
        fixture.sysrootFile('/etc/apt/keyrings/alera-archive-keyring.asc'),
        contains('PGP PUBLIC KEY'),
      );
      expect(
        fixture.sysrootFile('/etc/apt/sources.list.d/alera.sources'),
        allOf(
          contains('Types: deb'),
          contains('URIs: https://updates.alera.build/linux/apt'),
          contains('Suites: stable'),
          contains('Components: main'),
          contains('Architectures: amd64'),
          contains('Signed-By: /etc/apt/keyrings/alera-archive-keyring.asc'),
        ),
      );
      expect(fixture.commands, contains('apt-get update'));
      expect(fixture.commands, contains('apt-get install -y alera'));
    });

    test('configures the dnf repository with metadata verification', () async {
      final fixture = await _InstallFixture.create(
        packageManagers: <String>['dnf', 'rpm'],
      );
      addTearDown(fixture.dispose);

      final result = await fixture.run();
      expect(result.exitCode, 0, reason: result.stderr.toString());

      expect(
        fixture.sysrootFile('/etc/yum.repos.d/alera.repo'),
        allOf(
          contains('[alera]'),
          contains('baseurl=https://updates.alera.build/linux/rpm/x86_64'),
          contains('repo_gpgcheck=1'),
          contains('gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-alera'),
        ),
      );
      expect(
        fixture.sysrootFile('/etc/yum.repos.d/alera.repo'),
        contains('gpgcheck=0'),
        reason:
            'the published RPMs carry no per-package signature, so '
            'gpgcheck=1 would make every install fail as unsigned',
      );
      expect(
        fixture.sysrootFile('/etc/pki/rpm-gpg/RPM-GPG-KEY-alera'),
        contains('PGP PUBLIC KEY'),
      );
      expect(
        fixture.commands.any((command) => command.startsWith('rpm --import')),
        isTrue,
      );
      expect(fixture.commands, contains('dnf install -y alera'));
    });

    test('refuses openSUSE by name instead of configuring a repo', () async {
      final fixture = await _InstallFixture.create(
        packageManagers: <String>['zypper', 'rpm'],
      );
      addTearDown(fixture.dispose);

      final result = await fixture.run();

      expect(result.exitCode, 3);
      expect(result.stderr, contains('openSUSE is not supported yet'));
      expect(
        fixture.sysrootIsEmpty,
        isTrue,
        reason:
            'the published RPM names Fedora dependencies that openSUSE '
            'does not provide, so the transaction could never resolve',
      );
    });

    test('refuses a key that does not match the pinned fingerprint', () async {
      final fixture = await _InstallFixture.create(
        packageManagers: <String>['apt-get'],
        servedFingerprints: <String>[
          'BADC0FFEE0DDF00DBADC0FFEE0DDF00DBADC0FFE',
        ],
      );
      addTearDown(fixture.dispose);

      final result = await fixture.run();

      expect(result.exitCode, 5);
      expect(
        result.stderr,
        contains('does not match the expected fingerprint'),
      );
      expect(fixture.sysrootIsEmpty, isTrue);
      expect(
        fixture.commands.any((command) => command.contains('install -y alera')),
        isFalse,
      );
    });

    test('refuses a keyring carrying more than one key', () async {
      final fixture = await _InstallFixture.create(
        packageManagers: <String>['apt-get'],
        servedFingerprints: <String>[
          _pinnedFingerprint,
          'BADC0FFEE0DDF00DBADC0FFEE0DDF00DBADC0FFE',
        ],
      );
      addTearDown(fixture.dispose);

      final result = await fixture.run();

      expect(
        result.exitCode,
        5,
        reason:
            'Signed-By trusts every key in the keyring it points at, so an '
            'appended second key would bypass the pin entirely',
      );
      expect(result.stderr, contains('Expected exactly one key'));
      expect(fixture.sysrootIsEmpty, isTrue);
    });

    test('refuses an architecture with no published packages', () async {
      final fixture = await _InstallFixture.create(
        packageManagers: <String>['apt-get'],
        architecture: 'aarch64',
      );
      addTearDown(fixture.dispose);

      final result = await fixture.run();

      expect(result.exitCode, 2);
      expect(result.stderr, contains('aarch64'));
      expect(fixture.commands, isEmpty);
    });

    test('gives up before asking for sudo on an unsupported distro', () async {
      final fixture = await _InstallFixture.create(packageManagers: <String>[]);
      addTearDown(fixture.dispose);

      final result = await fixture.run();

      expect(result.exitCode, 3);
      expect(result.stderr, contains('No supported package manager'));
      expect(
        fixture.commands.any((command) => command.startsWith('sudo')),
        isFalse,
        reason: 'an unsupported machine must not be prompted for a password',
      );
    });

    test('changes nothing under --dry-run', () async {
      final fixture = await _InstallFixture.create(
        packageManagers: <String>['apt-get'],
      );
      addTearDown(fixture.dispose);

      final result = await fixture.run(<String>['--dry-run']);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(fixture.sysrootIsEmpty, isTrue);
      expect(fixture.commands, isEmpty);
      expect(result.stdout, contains('+ sudo install'));
    });

    test(
      'configures the repository without installing under --repo-only',
      () async {
        final fixture = await _InstallFixture.create(
          packageManagers: <String>['apt-get'],
        );
        addTearDown(fixture.dispose);

        final result = await fixture.run(<String>['--repo-only']);

        expect(result.exitCode, 0, reason: result.stderr.toString());
        expect(
          fixture.sysrootExists('/etc/apt/sources.list.d/alera.sources'),
          isTrue,
        );
        expect(
          fixture.commands.any(
            (command) => command.contains('install -y alera'),
          ),
          isFalse,
        );
      },
    );

    test('is safe to re-run as the upgrade path', () async {
      final fixture = await _InstallFixture.create(
        packageManagers: <String>['apt-get'],
      );
      addTearDown(fixture.dispose);

      final first = await fixture.run();
      final second = await fixture.run();

      expect(first.exitCode, 0, reason: first.stderr.toString());
      expect(second.exitCode, 0, reason: second.stderr.toString());
      expect(
        fixture.sysrootFile('/etc/apt/sources.list.d/alera.sources'),
        contains('Suites: stable'),
      );
    });
  }, skip: !Platform.isLinux);
}

/// Runs the real `install.sh` against a temporary sysroot.
///
/// `PATH` is replaced rather than prepended so the script sees exactly the
/// package managers a case declares: probing for `apt-get` is the branch under
/// test, and the developer machine always has one.
class _InstallFixture {
  _InstallFixture._({
    required this.root,
    required this.sysroot,
    required this.binDir,
    required this.commandLog,
  });

  final Directory root;
  final Directory sysroot;
  final Directory binDir;
  final File commandLog;

  static const List<String> _borrowedTools = <String>[
    'awk',
    'cat',
    'chmod',
    'dirname',
    'grep',
    'id',
    'install',
    'mktemp',
    'rm',
    'tr',
  ];

  static Future<_InstallFixture> create({
    required List<String> packageManagers,
    String architecture = 'x86_64',
    List<String> servedFingerprints = const <String>[_pinnedFingerprint],
  }) async {
    final root = await Directory.systemTemp.createTemp('alera-install-');
    final sysroot = Directory(p.join(root.path, 'sysroot'))..createSync();
    final binDir = Directory(p.join(root.path, 'bin'))..createSync();
    final commandLog = File(p.join(root.path, 'commands.log'))
      ..writeAsStringSync('');

    for (final tool in _borrowedTools) {
      final resolved = _which(tool);
      if (resolved != null) {
        Link(p.join(binDir.path, tool)).createSync(resolved);
      }
    }

    _writeExecutable(p.join(binDir.path, 'uname'), '''
#!/bin/sh
if [ "\${1:-}" = "-m" ]; then
  printf '%s\\n' '$architecture'
else
  printf 'Linux\\n'
fi
''');

    // Records the invocation and then runs it, so the log shows the privileged
    // command while the real work (install, rpm) still happens in the sysroot.
    _writeExecutable(p.join(binDir.path, 'sudo'), r'''
#!/bin/sh
printf 'sudo %s\n' "$*" >>"$ALERA_TEST_COMMAND_LOG"
exec "$@"
''');

    _writeExecutable(p.join(binDir.path, 'curl'), '''
#!/bin/sh
destination=""
while [ "\$#" -gt 0 ]; do
  if [ "\$1" = "-o" ]; then
    destination="\$2"
    shift
  fi
  shift
done
cat >"\$destination" <<'KEY'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mDMEZfixtureKeyMaterialForTestingOnly=
-----END PGP PUBLIC KEY BLOCK-----
KEY
''');

    // gpg is stubbed rather than driven with a generated key because the script
    // compares against a fingerprint pinned to the production key, which a
    // freshly generated key can never equal.
    final emitted = servedFingerprints
        .map((fingerprint) => "printf 'fpr:::::::::%s:\\n' '$fingerprint'")
        .join('\n');
    _writeExecutable(p.join(binDir.path, 'gpg'), '''
#!/bin/sh
$emitted
''');

    for (final manager in packageManagers) {
      _writeExecutable(p.join(binDir.path, manager), '''
#!/bin/sh
printf '%s %s\\n' '$manager' "\$*" >>"\$ALERA_TEST_COMMAND_LOG"
''');
    }

    return _InstallFixture._(
      root: root,
      sysroot: sysroot,
      binDir: binDir,
      commandLog: commandLog,
    );
  }

  Future<ProcessResult> run([List<String> arguments = const <String>[]]) {
    // Absolute, because PATH is replaced by the fixture and no longer resolves
    // the shell itself.
    return Process.run(
      '/bin/sh',
      <String>[_script, ...arguments],
      workingDirectory: Directory.current.path,
      includeParentEnvironment: false,
      environment: <String, String>{
        'PATH': binDir.path,
        'HOME': root.path,
        'TMPDIR': root.path,
        'ALERA_INSTALL_ROOT': sysroot.path,
        'ALERA_TEST_COMMAND_LOG': commandLog.path,
      },
    );
  }

  /// Every command the script routed through sudo or a package manager.
  List<String> get commands => commandLog
      .readAsLinesSync()
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();

  bool get sysrootIsEmpty => sysroot.listSync().isEmpty;

  bool sysrootExists(String path) =>
      File(p.join(sysroot.path, path.substring(1))).existsSync();

  String sysrootFile(String path) =>
      File(p.join(sysroot.path, path.substring(1))).readAsStringSync();

  void dispose() {
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  }

  static String? _which(String tool) {
    final result = Process.runSync('which', <String>[tool]);
    if (result.exitCode != 0) {
      return null;
    }
    final path = result.stdout.toString().trim();
    return path.isEmpty ? null : path;
  }

  static void _writeExecutable(String path, String contents) {
    File(path).writeAsStringSync(contents);
    Process.runSync('chmod', <String>['+x', path]);
  }
}
