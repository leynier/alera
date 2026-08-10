import 'dart:io';

import 'package:path/path.dart' as p;

typedef InstallDirectoryWritabilityProbe = Future<bool> Function();

/// Whether the running installation can be replaced in place.
///
/// Asked before an in-place update on Linux, where the app is a directory the
/// user may have unpacked anywhere: one owned by root fails part way through
/// the swap, which is the single moment the user is left without an app. A
/// mode check would not answer it, because what matters is the effective user,
/// so the probe writes a file where the replacement would write.
Future<bool> canReplaceInstallDirectory(String resolvedExecutable) async {
  final directory = Directory(p.dirname(resolvedExecutable));
  final probe = File(
    p.join(
      directory.path,
      '.alera-update-probe-${DateTime.now().microsecondsSinceEpoch}',
    ),
  );
  try {
    await probe.writeAsString('', flush: true);
    return true;
  } on FileSystemException {
    return false;
  } finally {
    try {
      if (probe.existsSync()) {
        await probe.delete();
      }
    } on FileSystemException {
      // Leaving a zero-byte probe behind is preferable to failing the check
      // that decides whether an update may be offered at all.
    }
  }
}
