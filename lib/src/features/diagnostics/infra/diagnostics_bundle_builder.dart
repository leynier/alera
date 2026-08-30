import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/diagnostics/domain/diagnostics_bundle_metadata.dart';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

/// Packs app logs, runtime logs and build metadata into one archive.
///
/// A single file is what actually gets attached to a report; asking a user to
/// find two log directories and note their versions loses most of the context
/// that makes a log readable.
class const DiagnosticsBundleBuilder() {
  static const String appLogPrefix = 'app';
  static const String runtimeLogPrefix = 'runtime';
  static const String metadataEntryName = 'meta.json';

  /// Builds the archive bytes. Missing directories are skipped rather than
  /// treated as an error: a runtime that never started has no logs, and that
  /// bundle is still worth producing.
  List<int> build({
    required DiagnosticsBundleMetadata metadata,
    Directory? appLogDirectory,
    Directory? runtimeLogDirectory,
  }) {
    final archive = Archive();

    _addDirectory(archive, appLogDirectory, appLogPrefix);
    _addDirectory(archive, runtimeLogDirectory, runtimeLogPrefix);

    final meta = utf8.encode(
      const JsonEncoder.withIndent('  ').convert(metadata.toJson()),
    );
    archive.addFile(ArchiveFile(metadataEntryName, meta.length, meta));

    return ZipEncoder().encode(archive);
  }

  void _addDirectory(Archive archive, Directory? directory, String prefix) {
    if (directory == null || !directory.existsSync()) {
      return;
    }
    final files =
        directory
            .listSync()
            .whereType<File>()
            .where((file) => p.extension(file.path) == '.log')
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      final bytes = file.readAsBytesSync();
      archive.addFile(
        ArchiveFile('$prefix/${p.basename(file.path)}', bytes.length, bytes),
      );
    }
  }

  /// Default file name for the saved bundle.
  static String suggestedFileName(DateTime now) {
    final stamp = now
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '')
        .replaceAll('-', '')
        .split('.')
        .first;
    return 'alera-diagnostics-$stamp.zip';
  }
}
