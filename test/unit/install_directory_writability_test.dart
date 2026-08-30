import 'dart:io';

import 'package:alera/src/features/updater/infra/install_directory_writability.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('install directory writability', () {
    test(
      'accepts a directory the user owns and leaves nothing behind',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'alera-install-',
        );
        addTearDown(() => directory.deleteSync(recursive: true));

        final writable = await canReplaceInstallDirectory(
          p.join(directory.path, 'alera'),
        );

        expect(writable, isTrue);
        expect(directory.listSync(), isEmpty);
      },
    );

    test('refuses a read-only directory', () async {
      final directory = await Directory.systemTemp.createTemp('alera-install-');
      addTearDown(() {
        Process.runSync('chmod', <String>['u+w', directory.path]);
        directory.deleteSync(recursive: true);
      });
      final chmod = Process.runSync('chmod', <String>['a-w', directory.path]);
      expect(chmod.exitCode, 0, reason: chmod.stderr.toString());

      expect(
        await canReplaceInstallDirectory(p.join(directory.path, 'alera')),
        isFalse,
      );
    }, skip: Platform.isWindows ? 'POSIX permissions only' : false);

    test('refuses a directory that does not exist', () async {
      expect(
        await canReplaceInstallDirectory(
          p.join(Directory.systemTemp.path, 'alera-absent-install', 'alera'),
        ),
        isFalse,
      );
    });
  });
}
