import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:alera/src/features/reading_diff/domain/reading_diff_models.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

abstract interface class ReadingDiffCache {
  Future<ReadingDiffResult?> read(String key);

  Future<void> write(String key, ReadingDiffResult result);
}

class FileReadingDiffCache implements ReadingDiffCache {
  const FileReadingDiffCache({
    this.directoryProvider = getApplicationSupportDirectory,
  });

  final Future<Directory> Function() directoryProvider;

  @override
  Future<ReadingDiffResult?> read(String key) async {
    try {
      final file = await _file(key);
      if (!await file.exists()) {
        return null;
      }
      final value = jsonDecode(await file.readAsString());
      if (value is! Map<String, dynamic> || value['version'] != 1) {
        return null;
      }
      return ReadingDiffResult(
        diff: Uint8List.fromList(base64Decode(value['diff'] as String)),
        summary: value['summary'] as String,
        changedLines: value['changedLines'] as int,
        retainedChangedLines: value['retainedChangedLines'] as int,
        agentLabel: value['agentLabel'] as String,
        fromCache: true,
      );
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
    final encoded = jsonEncode(<String, Object>{
      'version': 1,
      'diff': base64Encode(result.diff),
      'summary': result.summary,
      'changedLines': result.changedLines,
      'retainedChangedLines': result.retainedChangedLines,
      'agentLabel': result.agentLabel,
    });
    try {
      await temporary.writeAsString(encoded, flush: true);
      await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) {
        await temporary.delete();
      }
    }
  }

  Future<File> _file(String key) async {
    final root = await directoryProvider();
    return File(p.join(root.path, 'reading-diffs', '$key.json'));
  }
}
