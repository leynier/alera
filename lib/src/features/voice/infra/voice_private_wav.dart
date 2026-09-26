import 'dart:io';

import 'package:alera/src/shared/infra/files/posix_file_mode.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Writes [bytes] into an exclusive 0700 directory before creating the WAV.
class VoicePrivateWav {
  VoicePrivateWav._(this.directory, this.path);

  final Directory directory;
  final String path;

  static Future<VoicePrivateWav> write(
    List<int> bytes, {
    String prefix = 'alera-voice',
  }) async {
    final parent = await getTemporaryDirectory();
    final directory = await parent.createTemp('$prefix-');
    try {
      if (!Platform.isWindows &&
          !setPosixFileMode(directory.path, posixPrivateDirectoryMode)) {
        throw FileSystemException(
          'Could not set private permissions on the voice temp directory.',
          directory.path,
        );
      }
      final path = p.join(directory.path, 'audio.wav');
      await File(path).writeAsBytes(bytes, flush: true);
      return VoicePrivateWav._(directory, path);
    } on Object {
      await directory.delete(recursive: true).catchError((_) => directory);
      rethrow;
    }
  }

  Future<void> delete() async {
    try {
      await directory.delete(recursive: true);
    } on FileSystemException {
      // Best-effort cleanup of the private temp WAV directory.
    }
  }
}
