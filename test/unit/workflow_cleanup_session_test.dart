import 'dart:async';

import 'package:alera/src/features/orchestration/application/workflow_cleanup_session.dart';
import 'package:alera/src/features/orchestration/domain/workflow_cleanup_snapshot.dart';
import 'package:alera/src/features/orchestration/infra/workflow_cleanup_repository.dart';
import 'package:alera/src/features/orchestration/infra/workflow_lifecycle_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/workflow_cleanup_fixture.dart';
import '../support/workflow_cleanup_catalog_fixture.dart';

void main() {
  test(
    'uncertain abandonment blocks apply and reconciles its receipt',
    () async {
      final repository = _Repository()..statusState = 'attention';
      final session = WorkflowCleanupSession(
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
      expect(session.status!.state, WorkflowCleanupState.abandoned);
      expect(session.error, isNull);
      await session.apply(true);
      expect(repository.applications, isEmpty);
    },
  );

  test(
    'refresh settles a lost abandonment response without repeating it',
    () async {
      final repository = _Repository()..statusState = 'attention';
      final session = WorkflowCleanupSession(
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
      final session = WorkflowCleanupSession(
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
      expect(session.status!.state, WorkflowCleanupState.preview);
      expect(repository.applications, isEmpty);
    },
  );
  test(
    'uncertain apply retries the same operation and accepts durable receipt',
    () async {
      final repository = _Repository()
        ..failApply = true
        ..failStatus = true;
      final session = WorkflowCleanupSession(
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
      expect(session.status!.state, WorkflowCleanupState.retired);
      expect(session.error, isNull);
    },
  );
  test(
    'pagination rejects changed revisions without discarding selection',
    () async {
      final repository = _Repository();
      final session = WorkflowCleanupSession(repository, 'run');
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
      ..delayed = Completer<WorkflowCleanupPage<WorkflowCleanupResource>>();
    final session = WorkflowCleanupSession(repository, 'run');
    var notifications = 0;
    session.addListener(() => notifications++);
    final read = session.refresh();
    session.dispose();
    repository.delayed!.complete(
      WorkflowCleanupPage.fromJson(
        cleanupResourcesFixture(),
        WorkflowCleanupResource.fromJson,
      ),
    );
    await read;
    expect(notifications, 0);
  });
  test(
    'late pagination cannot overwrite a disconnect or append stale rows',
    () async {
      final repository = _Repository();
      final session = WorkflowCleanupSession(repository, 'run');
      addTearDown(session.dispose);
      await session.refresh();
      repository.delayed =
          Completer<WorkflowCleanupPage<WorkflowCleanupResource>>();
      final more = session.loadMore(operations: false);
      final error = StateError('Disconnected');
      session.reportError(error);
      repository.delayed!.complete(
        WorkflowCleanupPage.fromJson(
          cleanupResourcesFixture(),
          WorkflowCleanupResource.fromJson,
        ),
      );
      await more;
      expect(session.error, same(error));
      expect(session.resources.length, 1);
    },
  );
}

class _Repository implements WorkflowCleanupRepository {
  bool failPrepare = false;
  bool failApply = false;
  bool failAbandon = false;
  bool failStatus = false;
  String statusState = 'preview';
  final preparations = <(String, Map<String, bool>)>[];
  final applications = <bool>[];
  final abandonments = <String>[];
  Completer<WorkflowCleanupPage<WorkflowCleanupResource>>? delayed;
  @override
  Future<WorkflowCleanupPage<WorkflowCleanupResource>> resources(
    String runId, {
    int? beforeRow,
  }) async => delayed != null
      ? delayed!.future
      : WorkflowCleanupPage.fromJson(
          cleanupResourcesFixture(
            revision: beforeRow == null ? 4 : 5,
            nextRow: 10,
          ),
          WorkflowCleanupResource.fromJson,
        );
  @override
  Future<WorkflowCleanupPage<WorkflowCleanupSummary>> history(
    String runId, {
    int? beforeRow,
  }) async => WorkflowCleanupPage.fromJson(
    cleanupHistoryFixture(),
    WorkflowCleanupSummary.fromJson,
  );
  @override
  Future<WorkflowCleanupPreview> prepare(
    String id,
    String runId,
    Map<String, bool> resources,
  ) async {
    preparations.add((id, Map.of(resources)));
    if (failPrepare) throw StateError('Response lost');
    return WorkflowCleanupPreview.fromJson(cleanupPreviewFixture());
  }

  @override
  Future<WorkflowCleanupStatus> apply(
    WorkflowCleanupPreview preview, {
    bool retry = false,
  }) async {
    applications.add(retry);
    if (failApply) throw StateError('Response lost');
    return WorkflowCleanupStatus.fromJson(cleanupStatusFixture('retired'));
  }

  @override
  Future<WorkflowCleanupStatus> abandon(WorkflowCleanupPreview preview) async {
    abandonments.add(preview.id);
    if (failAbandon) throw StateError('Response lost');
    statusState = 'abandoned';
    return WorkflowCleanupStatus.fromJson(cleanupStatusFixture(statusState));
  }

  @override
  Future<WorkflowCleanupStatus> status(String id, String runId) async {
    if (failStatus) throw StateError('Disconnected');
    return WorkflowCleanupStatus.fromJson(cleanupStatusFixture(statusState));
  }

  @override
  WorkflowLifecycleRepository get lifecycle => throw UnimplementedError();
}
