import 'dart:io';

import 'package:path/path.dart' as p;

Future<void> deleteOwnedStagedUpdate({
  required String stagingPath,
  required String platform,
  required String artifactKind,
}) async {
  final staged = Directory(stagingPath);
  final isMacOSApp =
      platform == 'macos' && (artifactKind == 'zip' || artifactKind == 'dmg');
  final root = isMacOSApp ? staged.parent : staged;
  if (!p.basename(root.path).startsWith('desktop_updater_stage_')) {
    return;
  }
  try {
    if (await FileSystemEntity.type(root.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      return;
    }
    final temporaryRoot = await Directory.systemTemp.resolveSymbolicLinks();
    final ownedRoot = await root.resolveSymbolicLinks();
    if (!p.isWithin(temporaryRoot, ownedRoot)) {
      return;
    }
    await root.delete(recursive: true);
  } on Object {
    // Disposal cleanup is best effort and must only remove a verified owned
    // staging directory, including when a path was replaced by a symlink.
  }
}
