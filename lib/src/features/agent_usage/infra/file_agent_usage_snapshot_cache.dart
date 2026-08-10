import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:alera/src/features/agent_usage/application/agent_usage_snapshot_cache.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

typedef AgentUsageSupportDirectoryResolver = Future<Directory> Function();

class FileAgentUsageSnapshotCache implements AgentUsageSnapshotCache {
  FileAgentUsageSnapshotCache({
    AgentUsageSupportDirectoryResolver? applicationSupportDirectory,
  }) : _applicationSupportDirectory =
           applicationSupportDirectory ?? getApplicationSupportDirectory;

  static const int _schemaVersion = 1;

  final AgentUsageSupportDirectoryResolver _applicationSupportDirectory;
  final Map<String, Map<String, Object?>> _memory =
      <String, Map<String, Object?>>{};

  @override
  Map<String, Object?>? peek({required String hostId, required int days}) {
    return _memory[_cacheKey(hostId, days)];
  }

  @override
  Future<Map<String, Object?>?> read({
    required String hostId,
    required int days,
  }) async {
    final memory = peek(hostId: hostId, days: days);
    if (memory != null) return memory;
    try {
      final file = await _cacheFile(hostId, days);
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      final decoded = await Isolate.run<Object?>(() => jsonDecode(raw));
      if (decoded is! Map ||
          decoded['version'] != _schemaVersion ||
          decoded['hostId'] != hostId ||
          decoded['days'] != days ||
          decoded['snapshot'] is! Map) {
        return null;
      }
      final snapshot = Map<String, Object?>.from(decoded['snapshot'] as Map);
      _memory[_cacheKey(hostId, days)] = snapshot;
      return snapshot;
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write({
    required String hostId,
    required int days,
    required Map<String, Object?> snapshot,
  }) async {
    final cached = Map<String, Object?>.from(snapshot);
    _memory[_cacheKey(hostId, days)] = cached;
    final file = await _cacheFile(hostId, days);
    await file.parent.create(recursive: true);
    final serialized = await Isolate.run<String>(
      () => jsonEncode(<String, Object?>{
        'version': _schemaVersion,
        'hostId': hostId,
        'days': days,
        'snapshot': cached,
      }),
    );
    final temporary = File(
      p.join(file.parent.path, '.${DateTime.now().microsecondsSinceEpoch}.tmp'),
    );
    try {
      await temporary.writeAsString(serialized, flush: true);
      try {
        await temporary.rename(file.path);
      } on FileSystemException {
        if (await file.exists()) await file.delete();
        await temporary.rename(file.path);
      }
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<File> _cacheFile(String hostId, int days) async {
    final support = await _applicationSupportDirectory();
    return File(
      p.join(support.path, 'agent_usage', '${_cacheKey(hostId, days)}.json'),
    );
  }
}

String _cacheKey(String hostId, int days) {
  return sha256.convert(utf8.encode('$hostId\u0000$days')).toString();
}
