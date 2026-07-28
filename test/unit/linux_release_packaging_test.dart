import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('packages Linux releases without desktop tarballs', () {
    final workflow = File(
      '.github/workflows/release-cut.yml',
    ).readAsStringSync();
    final packageScript = File(
      'tool/release/package_linux.sh',
    ).readAsStringSync();

    expect(workflow, contains('- name: Package Linux release'));
    expect(workflow, isNot(contains('- name: Package RC Linux release')));
    expect(workflow, isNot(contains('alera-\${RELEASE_VERSION}-linux.tar.gz')));
    expect(
      workflow,
      contains('if [[ "\$PLATFORM" != "linux" ]]; then'),
      reason:
          'Linux is the one platform excluded from automatic installation, '
          'because dpkg and rpm do not resolve the libmpv dependency closure',
    );
    expect(
      workflow,
      isNot(
        contains(
          '[[ "\$PLATFORM" == "linux" \\\n'
          '            && -n "\${ALERA_LINUX_GPG_PRIVATE_KEY_BASE64:-}"',
        ),
      ),
    );
    expect(
      packageScript,
      isNot(contains('Linux packages are only published for stable releases')),
    );
    expect(packageScript, contains('Depends:'));
    expect(packageScript, contains('libmpv2'));
    expect(packageScript, contains('Requires: mpv-libs'));
  });

  test(
    'packages Linux RC metadata with dependency-safe versions',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'alera-linux-package-',
      );
      addTearDown(() => temp.deleteSync(recursive: true));
      final bundle = Directory(p.join(temp.path, 'bundle'))..createSync();
      File(p.join(bundle.path, 'alera')).writeAsStringSync('binary');
      final output = Directory(p.join(temp.path, 'output'))..createSync();
      final fakeBin = Directory(p.join(temp.path, 'bin'))..createSync();
      final capturedSpec = File(p.join(temp.path, 'alera.spec'));
      final fakeRpmbuild = File(p.join(fakeBin.path, 'rpmbuild'))
        ..writeAsStringSync('''
#!/bin/sh
set -eu
for argument do
  spec="\$argument"
done
topdir=\$(dirname "\$(dirname "\$spec")")
mkdir -p "\$topdir/RPMS/x86_64"
cp "\$spec" "\$ALERA_CAPTURE_SPEC"
printf 'rpm fixture\\n' >"\$topdir/RPMS/x86_64/alera-test.rpm"
''');
      final chmod = await Process.run('chmod', <String>[
        '+x',
        fakeRpmbuild.path,
      ]);
      expect(chmod.exitCode, 0);

      final package = await Process.run(
        'bash',
        <String>[
          'tool/release/package_linux.sh',
          bundle.path,
          output.path,
          '1.2.3-rc.0',
          '1.2.3',
          '99',
        ],
        workingDirectory: Directory.current.path,
        environment: <String, String>{
          'PATH': '${fakeBin.path}:${Platform.environment['PATH']}',
          'ALERA_CAPTURE_SPEC': capturedSpec.path,
        },
      );

      expect(
        package.exitCode,
        0,
        reason: 'stdout:\n${package.stdout}\nstderr:\n${package.stderr}',
      );
      final deb = p.join(output.path, 'alera-1.2.3-rc.0-linux.deb');
      final control = await Process.run('dpkg-deb', <String>['--field', deb]);
      expect(control.exitCode, 0);
      expect(control.stdout, contains('Version: 1.2.3~rc.0-99'));
      expect(control.stdout, contains('libmpv2'));
      final spec = capturedSpec.readAsStringSync();
      expect(spec, contains('Version: 1.2.3'));
      expect(spec, contains('Release: 0.rc.0.99%{?dist}'));
      expect(spec, contains('Requires: mpv-libs'));
      expect(
        File(p.join(output.path, 'alera-1.2.3-rc.0-linux.rpm')).lengthSync(),
        greaterThan(0),
      );
    },
    skip: !Platform.isLinux,
  );

  group('build_linux_repositories.sh', () {
    test('publishes the public key that signs the repositories', () async {
      final fixture = await _LinuxRepositoryFixture.create();
      addTearDown(fixture.dispose);

      final result = await fixture.run(keyId: fixture.fingerprint);
      expect(
        result.exitCode,
        0,
        reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
      );

      final keyring = File(
        p.join(fixture.publicDir.path, 'linux', 'alera-archive-keyring.asc'),
      );
      expect(keyring.existsSync(), isTrue);
      expect(
        keyring.readAsStringSync(),
        startsWith('-----BEGIN PGP PUBLIC KEY BLOCK-----'),
      );
      expect(await fixture.fingerprintOfKeyring(keyring), fixture.fingerprint);
    });

    test('fails when the signing key id resolves to no key', () async {
      final fixture = await _LinuxRepositoryFixture.create();
      addTearDown(fixture.dispose);

      final result = await fixture.run(
        keyId: 'DEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEF',
      );

      expect(result.exitCode, 65);
      expect(result.stderr, contains('Could not resolve a fingerprint'));
      expect(
        Directory(p.join(fixture.publicDir.path, 'linux')).existsSync(),
        isFalse,
      );
    });

    test('removes the temporary directory holding the private key', () async {
      final fixture = await _LinuxRepositoryFixture.create();
      addTearDown(fixture.dispose);

      await fixture.run(keyId: fixture.fingerprint);

      final leftovers = fixture.tempRoot
          .listSync()
          .map((entity) => p.basename(entity.path))
          .where((name) => name.startsWith('alera-linux-gpg.'))
          .toList();
      expect(leftovers, isEmpty);
    });
  }, skip: !Platform.isLinux);
}

/// Drives the real `build_linux_repositories.sh` against a throwaway GPG key.
///
/// `apt-ftparchive` and `createrepo_c` are stubbed on `PATH` because the script
/// only needs them to produce files it then signs, and neither is installed on
/// a developer machine by default.
class _LinuxRepositoryFixture {
  _LinuxRepositoryFixture._({
    required this.root,
    required this.publicDir,
    required this.tempRoot,
    required this.gpgHome,
    required this.fingerprint,
    required this.privateKeyBase64,
    required this.fakeBin,
  });

  final Directory root;
  final Directory publicDir;
  final Directory tempRoot;
  final Directory gpgHome;
  final String fingerprint;
  final String privateKeyBase64;
  final Directory fakeBin;

  static Future<_LinuxRepositoryFixture> create() async {
    final root = await Directory.systemTemp.createTemp('alera-linux-repo-');
    final gpgHome = Directory(p.join(root.path, 'gpg'))..createSync();
    await Process.run('chmod', <String>['700', gpgHome.path]);

    final generated = await Process.run('gpg', <String>[
      '--homedir',
      gpgHome.path,
      '--batch',
      '--passphrase',
      '',
      '--quick-generate-key',
      'Alera Repository Test <repository@example.invalid>',
      'default',
      'default',
      'never',
    ]);
    expect(generated.exitCode, 0, reason: generated.stderr.toString());

    final listed = await Process.run('gpg', <String>[
      '--homedir',
      gpgHome.path,
      '--batch',
      '--with-colons',
      '--list-keys',
    ]);
    final fingerprint = _firstFingerprint(listed.stdout.toString());
    expect(fingerprint, isNotEmpty);

    final exported = await Process.run('gpg', <String>[
      '--homedir',
      gpgHome.path,
      '--batch',
      '--armor',
      '--export-secret-keys',
      fingerprint,
    ], stdoutEncoding: null);
    final privateKey = base64.encode(exported.stdout as List<int>);

    final publicDir = Directory(p.join(root.path, 'public'))..createSync();
    final staged = Directory(
      p.join(publicDir.path, 'updates', 'stable', '1.0.0+1-linux'),
    )..createSync(recursive: true);
    File(p.join(staged.path, 'alera-1.0.0-linux.deb')).writeAsStringSync('deb');
    File(p.join(staged.path, 'alera-1.0.0-linux.rpm')).writeAsStringSync('rpm');

    final fakeBin = Directory(p.join(root.path, 'bin'))..createSync();
    _writeExecutable(p.join(fakeBin.path, 'apt-ftparchive'), '''
#!/bin/sh
printf 'Origin: Alera\\n'
''');
    _writeExecutable(p.join(fakeBin.path, 'createrepo_c'), r'''
#!/bin/sh
mkdir -p "$1/repodata"
printf '<repomd/>\n' >"$1/repodata/repomd.xml"
''');

    final tempRoot = Directory(p.join(root.path, 'tmp'))..createSync();

    return _LinuxRepositoryFixture._(
      root: root,
      publicDir: publicDir,
      tempRoot: tempRoot,
      gpgHome: gpgHome,
      fingerprint: fingerprint,
      privateKeyBase64: privateKey,
      fakeBin: fakeBin,
    );
  }

  Future<ProcessResult> run({required String keyId}) {
    return Process.run(
      'bash',
      <String>['tool/release/build_linux_repositories.sh', publicDir.path],
      workingDirectory: Directory.current.path,
      environment: <String, String>{
        'PATH': '${fakeBin.path}:${Platform.environment['PATH']}',
        'RUNNER_TEMP': tempRoot.path,
        'TMPDIR': tempRoot.path,
        'ALERA_LINUX_GPG_PRIVATE_KEY_BASE64': privateKeyBase64,
        'ALERA_LINUX_GPG_KEY_ID': keyId,
      },
    );
  }

  Future<String> fingerprintOfKeyring(File keyring) async {
    final shown = await Process.run('gpg', <String>[
      '--homedir',
      gpgHome.path,
      '--batch',
      '--with-colons',
      '--show-keys',
      keyring.path,
    ]);
    return _firstFingerprint(shown.stdout.toString());
  }

  void dispose() {
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  }

  static String _firstFingerprint(String colonListing) {
    for (final line in colonListing.split('\n')) {
      if (line.startsWith('fpr:')) {
        return line.split(':')[9];
      }
    }
    return '';
  }

  static void _writeExecutable(String path, String contents) {
    File(path).writeAsStringSync(contents);
    Process.runSync('chmod', <String>['+x', path]);
  }
}
