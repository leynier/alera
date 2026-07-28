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
      contains('[[ "\$CHANNEL" == "rc" && "\$PLATFORM" != "linux" ]]'),
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
}
