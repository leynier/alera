import 'dart:io';

import 'package:alera/src/shared/infra/files/posix_file_mode.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('posix file modes', () {
    test('spells the documented octal modes', () {
      expect(posixExecutableFileMode, 493); // 0o755
      expect(posixPrivateFileMode, 384); // 0o600
    });

    test('applies both modes to a real file', () {
      final directory = Directory.systemTemp.createTempSync(
        'alera-posix-file-mode',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File(p.join(directory.path, 'script.sh'))
        ..writeAsStringSync('#!/bin/sh\n');

      expect(setPosixFileMode(file.path, posixPrivateFileMode), isTrue);
      expect(file.statSync().mode & 0xFFF, posixPrivateFileMode);

      expect(setPosixFileMode(file.path, posixExecutableFileMode), isTrue);
      expect(file.statSync().mode & 0xFFF, posixExecutableFileMode);
    }, skip: Platform.isWindows);

    test(
      'reports failure instead of throwing for a missing path',
      () {
        final directory = Directory.systemTemp.createTempSync(
          'alera-posix-file-mode-missing',
        );
        addTearDown(() => directory.deleteSync(recursive: true));

        expect(
          setPosixFileMode(
            p.join(directory.path, 'absent.sh'),
            posixExecutableFileMode,
          ),
          isFalse,
        );
      },
      skip: Platform.isWindows,
    );

    test(
      'reports failure on Windows without resolving the symbol',
      () {
        expect(setPosixFileMode(r'C:\Windows\notepad.exe', 493), isFalse);
      },
      skip: !Platform.isWindows,
    );
  });
}
