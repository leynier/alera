import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

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

  /// Builds the archive without doing compression work on the UI isolate.
  ///
  /// Reading the files is asynchronous, and the collected bytes are then
  /// handed to a short-lived isolate for JSON encoding and ZIP compression.
  /// A diagnostics export can contain several megabytes of logs, so keeping
  /// the synchronous implementation above for small callers while routing
  /// the product path through this method avoids a visible frame stall.
  Future<List<int>> buildAsync({
    required DiagnosticsBundleMetadata metadata,
    Directory? appLogDirectory,
    Directory? runtimeLogDirectory,
  }) async {
    final appLogs = await _readDirectory(appLogDirectory);
    final runtimeLogs = await _readDirectory(runtimeLogDirectory);
    final metadataJson = const JsonEncoder.withIndent('  ')
        .convert(metadata.toJson());

    return Isolate.run(
      () => _encodeBundle(
        appLogs: appLogs,
        runtimeLogs: runtimeLogs,
        metadataJson: metadataJson,
      ),
    );
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

  Future<List<Map<String, Object?>>> _readDirectory(
    Directory? directory,
  ) async {
    if (directory == null) {
      return <Map<String, Object?>>[];
    }
    try {
      if (!await directory.exists()) {
        return <Map<String, Object?>>[];
      }
    } on FileSystemException {
      return <Map<String, Object?>>[];
    }
    final files = <File>[];
    try {
      await for (final entity in directory.list()) {
        if (entity is File && p.extension(entity.path) == '.log') {
          files.add(entity);
        }
      }
    } on FileSystemException {
      return <Map<String, Object?>>[];
    }
    files.sort((a, b) => a.path.compareTo(b.path));

    final logs = <Map<String, Object?>>[];
    for (final file in files) {
      try {
        logs.add(<String, Object?>{
          'name': p.basename(file.path),
          'bytes': await file.readAsBytes(),
        });
      } on FileSystemException {
        // Rotation may remove a file between list and read. Keep the rest of
        // the bundle useful instead of failing the entire export.
      }
    }
    return logs;
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

List<int> _encodeBundle({
  required List<Map<String, Object?>> appLogs,
  required List<Map<String, Object?>> runtimeLogs,
  required String metadataJson,
}) {
  final archive = Archive();
  _addEncodedLogs(archive, appLogs, DiagnosticsBundleBuilder.appLogPrefix);
  _addEncodedLogs(
    archive,
    runtimeLogs,
    DiagnosticsBundleBuilder.runtimeLogPrefix,
  );
  final metadata = utf8.encode(metadataJson);
  archive.addFile(
    ArchiveFile(
      DiagnosticsBundleBuilder.metadataEntryName,
      metadata.length,
      metadata,
    ),
  );
  return ZipEncoder().encode(archive);
}

void _addEncodedLogs(
  Archive archive,
  List<Map<String, Object?>> logs,
  String prefix,
) {
  for (final log in logs) {
    final name = log['name'];
    final bytes = log['bytes'];
    if (name is! String || bytes is! List<int>) {
      continue;
    }
    archive.addFile(ArchiveFile('$prefix/$name', bytes.length, bytes));
  }
}
