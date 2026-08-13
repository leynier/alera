import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:alera/src/features/reading_diff/domain/reading_diff_models.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

abstract interface class ReadingDiffCache {
  Future<ReadingDiffResult?> read(String key);

  Future<void> write(String key, ReadingDiffResult result);

  Future<void> remove(String key);
}

extension ReadingDiffCachePersistence on ReadingDiffCache {
  Future<void> writeBestEffort(String key, ReadingDiffResult result) async {
    try {
      await write(key, result);
    } on Object {
      // Generation already consumed quota, so cache I/O must not discard it.
    }
  }

  Future<void> removeBestEffort(String key) async {
    try {
      await remove(key);
    } on Object {
      // Cancellation must still win when stale cache cleanup fails.
    }
  }
}

class FileReadingDiffCache implements ReadingDiffCache {
  const FileReadingDiffCache({
    this.directoryProvider = getApplicationSupportDirectory,
    this.maxEntries = 20,
    this.maxBytes = 64 * 1024 * 1024,
  }) : assert(maxEntries > 0),
       assert(maxBytes > 0);

  final Future<Directory> Function() directoryProvider;
  final int maxEntries;
  final int maxBytes;

  @override
  Future<ReadingDiffResult?> read(String key) async {
    try {
      final file = await _file(key);
      if (!await file.exists()) {
        return null;
      }
      final encoded = await file.readAsString();
      return Isolate.run(() => _decodeReadingDiffResult(encoded));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String key, ReadingDiffResult result) async {
    final file = await _file(key);
    await file.parent.create(recursive: true);
    final temporary = File(
      '${file.path}.tmp-$pid-${DateTime.now().microsecondsSinceEpoch}',
    );
    final encoded = await Isolate.run(() => _encodeReadingDiffResult(result));
    try {
      await temporary.writeAsString(encoded, flush: true);
      await temporary.rename(file.path);
      await _prune(file.parent, currentPath: file.path);
    } finally {
      if (await temporary.exists()) {
        await temporary.delete();
      }
    }
  }

  @override
  Future<void> remove(String key) async {
    final file = await _file(key);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<File> _file(String key) async {
    final root = await directoryProvider();
    return File(p.join(root.path, 'reading-diffs', '$key.json'));
  }

  Future<void> _prune(
    Directory directory, {
    required String currentPath,
  }) async {
    final entries = <_ReadingDiffCacheEntry>[];
    await for (final entity in directory.list()) {
      if (entity is! File || p.extension(entity.path) != '.json') {
        continue;
      }
      final stat = await entity.stat();
      entries.add(
        _ReadingDiffCacheEntry(
          file: entity,
          bytes: stat.size,
          modifiedAt: stat.modified,
        ),
      );
    }
    entries.sort((left, right) {
      final leftIsCurrent = p.equals(left.file.path, currentPath);
      final rightIsCurrent = p.equals(right.file.path, currentPath);
      if (leftIsCurrent != rightIsCurrent) {
        return leftIsCurrent ? -1 : 1;
      }
      return right.modifiedAt.compareTo(left.modifiedAt);
    });
    var retainedEntries = 0;
    var retainedBytes = 0;
    for (final entry in entries) {
      final withinCount = retainedEntries < maxEntries;
      final withinSize = retainedBytes + entry.bytes <= maxBytes;
      if (withinCount && (withinSize || retainedEntries == 0)) {
        retainedEntries += 1;
        retainedBytes += entry.bytes;
        continue;
      }
      await entry.file.delete();
    }
  }
}

class _ReadingDiffCacheEntry {
  const _ReadingDiffCacheEntry({
    required this.file,
    required this.bytes,
    required this.modifiedAt,
  });

  final File file;
  final int bytes;
  final DateTime modifiedAt;
}

ReadingDiffResult? _decodeReadingDiffResult(String encoded) {
  final value = jsonDecode(encoded);
  if (value is! Map<String, dynamic> ||
      !const <int>{1, 2}.contains(value['version'])) {
    return null;
  }
  final chunkSummaries = switch (value['chunkSummaries']) {
    final List<dynamic> entries => <ReadingDiffChunkSummary>[
      for (final entry in entries)
        if (entry case <String, dynamic>{
          'index': final int index,
          'summary': final String summary,
        })
          ReadingDiffChunkSummary(index: index, summary: summary),
    ],
    _ => const <ReadingDiffChunkSummary>[],
  };
  return ReadingDiffResult(
    diff: Uint8List.fromList(base64Decode(value['diff'] as String)),
    summary: value['summary'] as String,
    changedLines: value['changedLines'] as int,
    retainedChangedLines: value['retainedChangedLines'] as int,
    agentLabel: value['agentLabel'] as String,
    model: value['model'] as String?,
    effort: value['effort'] as String?,
    chunkSummaries: chunkSummaries,
    fromCache: true,
  );
}

String _encodeReadingDiffResult(ReadingDiffResult result) =>
    jsonEncode(<String, Object?>{
      'version': 2,
      'diff': base64Encode(result.diff),
      'summary': result.summary,
      'changedLines': result.changedLines,
      'retainedChangedLines': result.retainedChangedLines,
      'agentLabel': result.agentLabel,
      'model': result.model,
      'effort': result.effort,
      'chunkSummaries': <Map<String, Object>>[
        for (final chunk in result.chunkSummaries)
          <String, Object>{'index': chunk.index, 'summary': chunk.summary},
      ],
    });
