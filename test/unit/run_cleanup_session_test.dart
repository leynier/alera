import 'dart:async';

import 'package:alera/src/features/runs/application/run_cleanup_session.dart';
import 'package:alera/src/features/runs/domain/run_cleanup.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/run_cleanup_catalog_fixture.dart';
import '../support/run_cleanup_fixture.dart';
import '../support/runs_fake_repository.dart';

void main() {
  test('Select All stops at 25 resources across pages', () async {
    final repository = FakeRunRepository()
      ..cleanupResourceItems = <Object?>[
        for (var index = 0; index < 25; index++) _resource('ws-$index'),
      ]
      ..moreCleanupResourceItems = <Object?>[
        for (var index = 25; index < 30; index++) _resource('ws-$index'),
      ];
    final session = RunCleanupSession(repository, 'run');
    addTearDown(session.dispose);
    await session.refresh();
    await session.loadMore(operations: false);
    expect(session.resources, hasLength(30));
    session.selectAll();
    expect(session.selection, hasLength(runCleanupSelectionLimit));
    session.select('ws-29', true);
    expect(session.selection.containsKey('ws-29'), isFalse);
    session.select('ws-0', false);
    session.select('ws-29', true);
    expect(session.selection.containsKey('ws-29'), isTrue);
    expect(session.selection, hasLength(runCleanupSelectionLimit));
  });

  test(
    'uncertain abandonment blocks apply and reconciles its receipt',
    () async {
      final repository = _Repository()..statusState = 'attention';
      final session = RunCleanupSession(
        repository,
        'run',
        cleanupId: 'cleanup',
      );
      addTearDown(session.dispose);
      await session.refresh();
      repository.failAbandon = true;
      await session.abandon();
      expect(session.abandonPending, true);
      expect(session.error, isNotNull);
      await session.apply(true);
      expect(repository.applications, isEmpty);
      repository.failAbandon = false;
      await session.abandon();
      expect(repository.abandonments, ['cleanup', 'cleanup']);
      expect(session.abandonPending, false);
      expect(session.status!.state, RunCleanupState.abandoned);
      expect(session.error, isNull);
      await session.apply(true);
      expect(repository.applications, isEmpty);
    },
  );

  test(
    'refresh settles a lost abandonment response without repeating it',
    () async {
      final repository = _Repository()..statusState = 'attention';
      final session = RunCleanupSession(
        repository,
        'run',
        cleanupId: 'cleanup',
      );
      addTearDown(session.dispose);
      await session.refresh();
      repository.failAbandon = true;
      await session.abandon();
      repository.statusState = 'abandoned';
      await session.refresh();
      expect(session.abandonPending, false);
      expect(session.error, isNull);
      expect(repository.abandonments, ['cleanup']);
    },
  );

  test(
    'response-loss retry preserves preview identity and branch choices',
    () async {
      final repository = _Repository()..failPrepare = true;
      final session = RunCleanupSession(
        repository,
        'run',
        newId: () => 'cleanup',
      );
      addTearDown(session.dispose);
      await session.refresh();
      session.select('workspace', true);
      expect(session.selection, {'workspace': false});
      await session.prepare();
      expect(session.previewPending, true);
      session.removeBranch('workspace', true);
      session.select('workspace', false);
      repository.failPrepare = false;
      await session.prepare();
      expect(repository.preparations.map((item) => item.$1), [
        'cleanup',
        'cleanup',
      ]);
      expect(repository.preparations.map((item) => item.$2), [
        {'workspace': false},
        {'workspace': false},
      ]);
      expect(session.selectedId, 'cleanup');
      expect(session.status!.state, RunCleanupState.preview);
      expect(repository.applications, isEmpty);
    },
  );
  test(
    'uncertain apply retries the same operation and accepts durable receipt',
    () async {
      final repository = _Repository()
        ..failApply = true
        ..failStatus = true;
      final session = RunCleanupSession(
        repository,
        'run',
        newId: () => 'cleanup',
      );
      addTearDown(session.dispose);
      await session.refresh();
      session.select('workspace', true);
      await session.prepare();
      await session.apply(false);
      expect(session.error, isNotNull);
      repository.failApply = false;
      repository.failStatus = false;
      repository.statusState = 'retired';
      await session.apply(true);
      expect(repository.applications, [false, false]);
      expect(session.status!.state, RunCleanupState.retired);
      expect(session.error, isNull);
    },
  );
  test(
    'pagination rejects changed revisions without discarding selection',
    () async {
      final repository = _Repository();
      final session = RunCleanupSession(repository, 'run');
      addTearDown(session.dispose);
      await session.refresh();
      session.select('workspace', true);
      await session.loadMore(operations: false);
      expect(session.error.toString(), contains('Resources changed'));
      expect(session.resources.length, 1);
      expect(session.selection, {'workspace': false});
    },
  );
  test('disposing the page ignores an in-flight read completion', () async {
    final repository = _Repository()
      ..delayed = Completer<RunCleanupPage<RunCleanupResource>>();
    final session = RunCleanupSession(repository, 'run');
    var notifications = 0;
    session.addListener(() => notifications++);
    final read = session.refresh();
    session.dispose();
    repository.delayed!.complete(
      RunCleanupPage.fromJson(
        cleanupResourcesFixture(),
        RunCleanupResource.fromJson,
      ),
    );
    await read;
    expect(notifications, 0);
  });
  test(
    'late pagination cannot overwrite a disconnect or append stale rows',
    () async {
      final repository = _Repository();
      final session = RunCleanupSession(repository, 'run');
      addTearDown(session.dispose);
      await session.refresh();
      repository.delayed = Completer<RunCleanupPage<RunCleanupResource>>();
      final more = session.loadMore(operations: false);
      final error = StateError('Disconnected');
      session.reportError(error);
      repository.delayed!.complete(
        RunCleanupPage.fromJson(
          cleanupResourcesFixture(),
          RunCleanupResource.fromJson,
        ),
      );
      await more;
      expect(session.error, same(error));
      expect(session.resources.length, 1);
    },
  );
}

class _Repository extends FakeRunRepository {
  bool failPrepare = false;
  bool failApply = false;
  bool failAbandon = false;
  bool failStatus = false;
  String statusState = 'preview';
  final preparations = <(String, Map<String, bool>)>[];
  final applications = <bool>[];
  final abandonments = <String>[];
  Completer<RunCleanupPage<RunCleanupResource>>? delayed;
  @override
  Future<RunCleanupPage<RunCleanupResource>> resources(
    String runId, {
    int? beforeRow,
  }) async => delayed != null
      ? delayed!.future
      : RunCleanupPage.fromJson(
          cleanupResourcesFixture(
            revision: beforeRow == null ? 4 : 5,
            nextRow: 10,
          ),
          RunCleanupResource.fromJson,
        );
  @override
  Future<RunCleanupPage<RunCleanupHistoryItem>> cleanups(
    String runId, {
    int? beforeRow,
  }) async => RunCleanupPage.fromJson(
    cleanupHistoryFixture(),
    RunCleanupHistoryItem.fromJson,
  );
  @override
  Future<RunCleanupPreview> previewCleanup(
    String id,
    String runId,
    Map<String, bool> resources,
  ) async {
    preparations.add((id, Map.of(resources)));
    if (failPrepare) throw StateError('Response lost');
    return RunCleanupPreview.fromJson(cleanupPreviewFixture());
  }

  @override
  Future<RunCleanupStatus> applyCleanup(
    RunCleanupPreview preview, {
    bool retry = false,
  }) async {
    applications.add(retry);
    if (failApply) throw StateError('Response lost');
    return RunCleanupStatus.fromJson(cleanupStatusFixture('retired'));
  }

  @override
  Future<RunCleanupStatus> abandonCleanup(RunCleanupPreview preview) async {
    abandonments.add(preview.id);
    if (failAbandon) throw StateError('Response lost');
    statusState = 'abandoned';
    return RunCleanupStatus.fromJson(cleanupStatusFixture(statusState));
  }

  @override
  Future<RunCleanupStatus> cleanupStatus(String id, String runId) async {
    if (failStatus) throw StateError('Disconnected');
    return RunCleanupStatus.fromJson(cleanupStatusFixture(statusState));
  }
}

Map<String, Object?> _resource(String id) {
  final item = Map<String, Object?>.from(
    (cleanupResourcesFixture()['items']! as List).single as Map,
  );
  final identity = Map<String, Object?>.from(item['identity']! as Map);
  identity['workspace'] = <String, Object?>{
    ...(identity['workspace']! as Map).cast<String, Object?>(),
    'id': id,
  };
  item['identity'] = identity;
  return item;
}
