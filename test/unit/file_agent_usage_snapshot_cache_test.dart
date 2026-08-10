import 'dart:io';

import 'package:alera/src/features/agent_usage/infra/file_agent_usage_snapshot_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory supportDirectory;

  setUp(() async {
    supportDirectory = await Directory.systemTemp.createTemp(
      'alera-agent-usage-cache-',
    );
  });

  tearDown(() async {
    if (await supportDirectory.exists()) {
      await supportDirectory.delete(recursive: true);
    }
  });

  FileAgentUsageSnapshotCache createCache() {
    return FileAgentUsageSnapshotCache(
      applicationSupportDirectory: () async => supportDirectory,
    );
  }

  test('persists snapshots independently by host and period', () async {
    final cache = createCache();
    final local7 = _snapshot(readAt: 7);
    final local30 = _snapshot(readAt: 30);
    final remote7 = _snapshot(readAt: 107);

    await cache.write(hostId: 'local', days: 7, snapshot: local7);
    await cache.write(hostId: 'local', days: 30, snapshot: local30);
    await cache.write(hostId: 'remote-dev', days: 7, snapshot: remote7);

    expect(cache.peek(hostId: 'local', days: 7), local7);

    final restored = createCache();
    expect(await restored.read(hostId: 'local', days: 7), local7);
    expect(await restored.read(hostId: 'local', days: 30), local30);
    expect(await restored.read(hostId: 'remote-dev', days: 7), remote7);
    expect(await restored.read(hostId: 'remote-dev', days: 30), isNull);
  });

  test('ignores a corrupt persisted snapshot', () async {
    final cache = createCache();
    await cache.write(
      hostId: 'local',
      days: 90,
      snapshot: _snapshot(readAt: 90),
    );
    final files = await Directory(
      '${supportDirectory.path}${Platform.pathSeparator}agent_usage',
    ).list().where((entry) => entry is File).cast<File>().toList();
    expect(files, hasLength(1));
    await files.single.writeAsString('{not json');

    expect(await createCache().read(hostId: 'local', days: 90), isNull);
  });
}

Map<String, Object?> _snapshot({required int readAt}) {
  return <String, Object?>{
    'readAt': readAt,
    'sinceDay': '2026-08-01',
    'untilDay': '2026-08-10',
    'scanDurationMs': 1,
    'pricing': <String, Object?>{},
    'sources': <Object?>[],
    'buckets': <Object?>[],
  };
}
