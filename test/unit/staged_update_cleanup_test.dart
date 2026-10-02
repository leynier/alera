import 'dart:io';

import 'package:alera/src/features/updater/infra/staged_update_cleanup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'deletes an owned temporary staging root and preserves siblings',
    () async {
      final parent = await Directory.systemTemp.createTemp(
        'alera-staged-cleanup-owned_',
      );
      final staging = Directory(
        p.join(parent.path, 'desktop_updater_stage_zip'),
      );
      final sibling = Directory(p.join(parent.path, 'keep-me'));
      await staging.create();
      await sibling.create();
      await File(p.join(staging.path, 'payload')).writeAsString('payload');

      try {
        await deleteOwnedStagedUpdate(
          stagingPath: staging.path,
          platform: 'linux',
          artifactKind: 'zip',
        );

        expect(staging.existsSync(), isFalse);
        expect(sibling.existsSync(), isTrue);
        expect(parent.existsSync(), isTrue);
      } finally {
        if (parent.existsSync()) {
          await parent.delete(recursive: true);
        }
      }
    },
  );

  test(
    'deletes the owned macOS staging parent while preserving siblings',
    () async {
      final parent = await Directory.systemTemp.createTemp(
        'alera-staged-cleanup-macos_',
      );
      final staging = Directory(
        p.join(parent.path, 'desktop_updater_stage_macos'),
      );
      final app = Directory(p.join(staging.path, 'Alera.app'));
      final sibling = Directory(p.join(parent.path, 'keep-me'));
      await app.create(recursive: true);
      await sibling.create();
      await File(p.join(app.path, 'Contents')).writeAsString('bundle');

      try {
        await deleteOwnedStagedUpdate(
          stagingPath: app.path,
          platform: 'macos',
          artifactKind: 'zip',
        );

        expect(staging.existsSync(), isFalse);
        expect(sibling.existsSync(), isTrue);
        expect(parent.existsSync(), isTrue);
      } finally {
        if (parent.existsSync()) {
          await parent.delete(recursive: true);
        }
      }
    },
  );

  test('preserves a prefixed staging root outside systemTemp', () async {
    final staging = Directory(
      p.join(
        Directory.current.path,
        'desktop_updater_stage_outside_temp_${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    await staging.create();
    await File(p.join(staging.path, 'payload')).writeAsString('payload');

    try {
      await deleteOwnedStagedUpdate(
        stagingPath: staging.path,
        platform: 'linux',
        artifactKind: 'zip',
      );

      expect(staging.existsSync(), isTrue);
    } finally {
      if (staging.existsSync()) {
        await staging.delete(recursive: true);
      }
    }
  });

  test('preserves a staging symlink and its sibling target', () async {
    final parent = await Directory.systemTemp.createTemp(
      'alera-staged-cleanup-link_',
    );
    final target = Directory(p.join(parent.path, 'sibling-target'));
    final link = Link(p.join(parent.path, 'desktop_updater_stage_link'));
    await target.create();
    await File(p.join(target.path, 'payload')).writeAsString('payload');

    try {
      try {
        await link.create(target.path);
      } on FileSystemException {
        markTestSkipped('Symlink creation is not available on this platform.');
        return;
      }

      await deleteOwnedStagedUpdate(
        stagingPath: link.path,
        platform: 'linux',
        artifactKind: 'zip',
      );

      expect(
        FileSystemEntity.typeSync(link.path, followLinks: false),
        FileSystemEntityType.link,
      );
      expect(target.existsSync(), isTrue);
      expect(File(p.join(target.path, 'payload')).existsSync(), isTrue);
    } finally {
      if (FileSystemEntity.typeSync(link.path, followLinks: false) ==
          FileSystemEntityType.link) {
        await link.delete();
      }
      if (parent.existsSync()) {
        await parent.delete(recursive: true);
      }
    }
  });
}
