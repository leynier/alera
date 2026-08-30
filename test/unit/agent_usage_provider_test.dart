import 'dart:async';

import 'package:alera/src/features/agent_usage/application/agent_usage_loader.dart';
import 'package:alera/src/features/agent_usage/application/agent_usage_providers.dart';
import 'package:alera/src/features/agent_usage/application/agent_usage_snapshot_cache.dart';
import 'package:alera/src/features/remote_hosts/application/ssh_target_providers.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'shows a cached snapshot immediately and replaces it in background',
    () async {
      final cached = _snapshot(readAt: 1, records: 1);
      final fresh = _snapshot(readAt: 2, records: 2);
      final cache = _FakeCache(cached);
      final loader = _FakeLoader();
      final container = _container(cache: cache, loader: loader);
      addTearDown(container.dispose);
      final subscription = container.listen(
        agentUsageProvider(7),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      final initial = container.read(agentUsageProvider(7)).requireValue;
      expect(initial.snapshot.readAt.millisecondsSinceEpoch, 1);
      expect(initial.refreshing, isTrue);
      await _waitUntil(() => loader.calls == 1);

      loader.result.complete(fresh);
      await _waitUntil(
        () => container.read(agentUsageProvider(7)).value?.refreshing == false,
      );

      final updated = container.read(agentUsageProvider(7)).requireValue;
      expect(updated.snapshot.readAt.millisecondsSinceEpoch, 2);
      expect(updated.error, isNull);
      expect(cache.writes.single.snapshot, fresh);
    },
  );

  test('keeps a cached snapshot when background refresh fails', () async {
    final cached = _snapshot(readAt: 1, records: 1);
    final cache = _FakeCache(cached);
    final loader = _FakeLoader();
    final container = _container(cache: cache, loader: loader);
    addTearDown(container.dispose);
    final subscription = container.listen(
      agentUsageProvider(30),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    await _waitUntil(() => loader.calls == 1);
    loader.result.completeError(StateError('offline'));
    await _waitUntil(
      () => container.read(agentUsageProvider(30)).value?.error != null,
    );

    final state = container.read(agentUsageProvider(30)).requireValue;
    expect(state.snapshot.readAt.millisecondsSinceEpoch, 1);
    expect(state.refreshing, isFalse);
    expect(state.error, contains('offline'));
  });
}

ProviderContainer _container({
  required AgentUsageSnapshotCache cache,
  required AgentUsageLoader loader,
}) {
  return ProviderContainer(
    overrides: [
      workbenchControllerProvider.overrideWithValue(const WorkbenchState()),
      settingsControllerProvider.overrideWithValue(.defaults),
      sshTargetsProvider.overrideWith(
        (ref) => Stream<List<SshTarget>>.value(const <SshTarget>[]),
      ),
      agentUsageSnapshotCacheProvider.overrideWithValue(cache),
      agentUsageLoaderProvider.overrideWithValue(loader),
    ],
  );
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (condition()) return;
    await Future.pause(const Duration(milliseconds: 1));
  }
  fail('Condition was not met.');
}

class _FakeLoader implements AgentUsageLoader {
  final Completer<Map<String, Object?>> result =
      Completer<Map<String, Object?>>();
  int calls = 0;

  @override
  Future<Map<String, Object?>> fetch(AgentUsageRequest request) {
    calls += 1;
    return result.future;
  }
}

class const _CacheWrite(
  final String hostId,
  final int days,
  final Map<String, Object?> snapshot,
);

class _FakeCache(final Map<String, Object?>? snapshot)
    implements AgentUsageSnapshotCache {
  final List<_CacheWrite> writes = <_CacheWrite>[];

  @override
  Map<String, Object?>? peek({required String hostId, required int days}) {
    return snapshot;
  }

  @override
  Future<Map<String, Object?>?> read({
    required String hostId,
    required int days,
  }) async {
    return snapshot;
  }

  @override
  Future<void> write({
    required String hostId,
    required int days,
    required Map<String, Object?> snapshot,
  }) async {
    writes.add(_CacheWrite(hostId, days, snapshot));
  }
}

Map<String, Object?> _snapshot({required int readAt, required int records}) {
  return <String, Object?>{
    'readAt': readAt,
    'sinceDay': '2026-08-01',
    'untilDay': '2026-08-10',
    'scanDurationMs': 1,
    'pricing': <String, Object?>{},
    'sources': <Object?>[],
    'buckets': <Object?>[
      <String, Object?>{
        'provider': 'codex',
        'accountId': 'default',
        'displayName': 'Default',
        'model': 'gpt-5.6-codex',
        'day': '2026-08-10',
        'totals': <String, Object?>{
          'uncachedInputTokens': 1,
          'cachedInputTokens': 0,
          'cacheCreationTokens': 0,
          'outputTokens': 0,
          'reasoningTokens': 0,
        },
        'costUsd': 0.1,
        'cacheSavingsUsd': 0,
        'costSource': 'modelPriced',
        'records': records,
        'unpricedRecords': 0,
        'sessions': 1,
      },
    ],
  };
}
