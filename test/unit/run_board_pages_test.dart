import 'dart:async';
import 'package:alera/src/features/app_window/application/app_window_providers.dart';
import 'package:alera/src/features/orchestration/application/run_board_navigation.dart';
import 'package:alera/src/features/orchestration/application/run_board_pages.dart';
import 'package:alera/src/features/orchestration/application/run_board_providers.dart';
import 'package:alera/src/features/orchestration/domain/run_board_snapshot.dart';
import 'package:alera/src/features/orchestration/domain/run_snapshot.dart';
import 'package:alera/src/features/orchestration/domain/task_inspection.dart';
import 'package:alera/src/features/orchestration/infra/runtime_run_board_repository.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/run_board_fixtures.dart';

void main() {
  for (final pageFails in [false, true]) {
    test(
      'late pagination cannot replace watcher errors (fails: $pageFails)',
      () {
        fakeAsync((time) {
          final f = _Fixture();
          f.repository.board = boardSnapshot(
            nextCursor: const RunBoardCursor('now', 'r1', 1),
          );
          f.repository.run = boardRunDetail(nextTaskId: 'task-3');
          f.repository.task = boardTask(
            nextCursor: const TaskHistoryCursor('now', 'a', 1),
          );
          final board = Completer<RunBoardSnapshot>();
          final run = Completer<RunSnapshot>();
          final task = Completer<TaskInspection>();
          f.repository.nextBoard = board.future;
          f.repository.nextRun = run.future;
          f.repository.nextTask = task.future;
          final boardProvider = runBoardListPageProvider();
          final runProvider = runTaskPageProvider('run-1');
          final taskProvider = runTaskInspectionPageProvider('run-1', 'task-2');
          f.container.listen(boardProvider, (_, _) {});
          f.container.listen(runProvider, (_, _) {});
          f.container.listen(taskProvider, (_, _) {});
          time.flushMicrotasks();
          unawaited(f.container.read(boardProvider.notifier).loadMore());
          unawaited(f.container.read(runProvider.notifier).loadMore());
          unawaited(f.container.read(taskProvider.notifier).loadMore());
          final disconnect = StateError('host disconnected');
          f.repository.error = disconnect;
          f.repository.events.add(null);
          time.flushMicrotasks();
          expect(f.container.read(boardProvider).error, same(disconnect));
          expect(f.container.read(runProvider).error, same(disconnect));
          expect(f.container.read(taskProvider).error, same(disconnect));
          if (pageFails) {
            board.completeError(StateError('page failed'));
            run.completeError(StateError('page failed'));
            task.completeError(StateError('page failed'));
          } else {
            board.complete(boardSnapshot());
            run.complete(boardRunDetail());
            task.complete(boardTask());
          }
          time.flushMicrotasks();
          expect(f.container.read(boardProvider).error, same(disconnect));
          expect(f.container.read(runProvider).error, same(disconnect));
          expect(f.container.read(taskProvider).error, same(disconnect));
          f.dispose();
          time.flushMicrotasks();
        });
      },
    );
  }

  test('pagination cannot start from retained data in a watcher error', () {
    fakeAsync((time) {
      final f = _Fixture();
      f.repository.board = boardSnapshot(
        nextCursor: const RunBoardCursor('now', 'r1', 1),
      );
      f.repository.run = boardRunDetail(nextTaskId: 'task-3');
      f.repository.task = boardTask(
        nextCursor: const TaskHistoryCursor('now', 'a', 1),
      );
      final board = runBoardListPageProvider();
      final run = runTaskPageProvider('run-1');
      final task = runTaskInspectionPageProvider('run-1', 'task-2');
      f.container.listen(board, (_, _) {});
      f.container.listen(run, (_, _) {});
      f.container.listen(task, (_, _) {});
      time.flushMicrotasks();
      final disconnect = StateError('host disconnected');
      f.repository.error = disconnect;
      f.repository.events.add(null);
      time.flushMicrotasks();
      final reads = [
        f.repository.boardReads,
        f.repository.runReads,
        f.repository.taskReads,
      ];
      unawaited(f.container.read(board.notifier).loadMore());
      unawaited(f.container.read(run.notifier).loadMore());
      unawaited(f.container.read(task.notifier).loadMore());
      time.flushMicrotasks();
      expect([
        f.repository.boardReads,
        f.repository.runReads,
        f.repository.taskReads,
      ], reads);
      expect(f.container.read(board).error, same(disconnect));
      expect(f.container.read(run).error, same(disconnect));
      expect(f.container.read(task).error, same(disconnect));
      f.dispose();
      time.flushMicrotasks();
    });
  });

  test(
    'navigation survives closing without retaining a runtime subscription',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final nav = container.read(runBoardNavigationProvider.notifier);
      nav.open();
      nav.selectProject('p');
      nav.selectWorkspace('w');
      nav.search('contract');
      nav.selectBucket(RunBoardBucket.attention);
      nav.selectRun('r');
      nav.selectTask('t');
      nav.close();
      final closed = container.read(runBoardNavigationProvider);
      expect(closed.visible, isFalse);
      expect(closed.taskId, 't');
      nav.open();
      expect(container.read(runBoardNavigationProvider).runId, 'r');
      nav.selectProject('other');
      expect(container.read(runBoardNavigationProvider).workspaceId, isNull);
      nav.clearFilters();
      final cleared = container.read(runBoardNavigationProvider);
      expect(cleared.search, isEmpty);
      expect(cleared.bucket, isNull);
      expect(cleared.runId, 'r');
    },
  );

  test(
    'board pagination keeps counts, sends cursor and resets on new evidence',
    () {
      fakeAsync((time) {
        final f = _Fixture();
        f.repository.board = boardSnapshot(
          nextCursor: const RunBoardCursor('now', 'r1', 1),
        );
        f.repository.nextBoard = Future.value(
          boardSnapshot(items: [boardRun(id: 'r4')]),
        );
        final provider = runBoardListPageProvider(
          projectId: 'p',
          workspaceId: 'w',
          search: 'fix',
        );
        final sub = f.container.listen(provider, (_, _) {});
        time.flushMicrotasks();
        unawaited(f.container.read(provider.notifier).loadMore());
        unawaited(f.container.read(provider.notifier).loadMore());
        time.flushMicrotasks();
        final page = f.container.read(provider).requireValue;
        expect(page.data.items.length, 4);
        expect(page.data.counts.attention, 1);
        expect(f.repository.boardReads, 2);
        expect(
          f.repository.queries.last.toJson(),
          containsPair('project_id', 'p'),
        );
        expect(f.repository.queries.last.cursor?.revision, 1);
        f.repository.board = boardSnapshot(revision: 2);
        f.repository.events.add(null);
        time.flushMicrotasks();
        expect(f.container.read(provider).requireValue.data.items.length, 3);
        sub.close();
        f.dispose();
        time.flushMicrotasks();
        expect(f.repository.watchers, 0);
      });
    },
  );

  test(
    'late pages cannot overwrite newer snapshots and failures retain rows',
    () {
      fakeAsync((time) {
        final f = _Fixture();
        f.repository.board = boardSnapshot(
          nextCursor: const RunBoardCursor('now', 'r1', 1),
        );
        final pending = Completer<RunBoardSnapshot>();
        f.repository.nextBoard = pending.future;
        final provider = runBoardListPageProvider();
        f.container.listen(provider, (_, _) {});
        time.flushMicrotasks();
        unawaited(f.container.read(provider.notifier).loadMore());
        f.repository.board = boardSnapshot(
          revision: 2,
          nextCursor: const RunBoardCursor('now', 'r2', 2),
        );
        f.repository.events.add(null);
        time.flushMicrotasks();
        pending.complete(boardSnapshot(items: [boardRun(id: 'stale')]));
        time.flushMicrotasks();
        expect(f.container.read(provider).requireValue.data.revision, 2);
        expect(
          f.container
              .read(provider)
              .requireValue
              .data
              .items
              .any((r) => r.id == 'stale'),
          isFalse,
        );
        f.repository.nextBoard = Future.error(StateError('stale cursor'));
        unawaited(f.container.read(provider.notifier).loadMore());
        time.flushMicrotasks();
        expect(
          f.container.read(provider).requireValue.pageError,
          isA<StateError>(),
        );
        expect(f.container.read(provider).requireValue.data.items.length, 3);
        f.dispose();
        time.flushMicrotasks();
      });
    },
  );

  test('hidden app cancels all watchers and refreshes once on return', () {
    fakeAsync((time) {
      final f = _Fixture();
      f.container.listen(runBoardAttentionProvider, (_, _) {});
      f.container.listen(runBoardListPageProvider(), (_, _) {});
      f.container.listen(runTaskPageProvider('run-1'), (_, _) {});
      f.container.listen(
        runTaskInspectionPageProvider('run-1', 'task-2'),
        (_, _) {},
      );
      time.flushMicrotasks();
      expect(f.repository.watchers, 4);
      f.foreground.setVisible(false);
      time.flushMicrotasks();
      expect(f.repository.watchers, 0);
      final reads = f.repository.boardReads;
      f.repository.events.add(null);
      time.elapse(const Duration(minutes: 5));
      expect(f.repository.boardReads, reads);
      f.foreground.setVisible(true);
      time.flushMicrotasks();
      expect(f.repository.watchers, 4);
      expect(f.repository.boardReads, reads + 2);
      f.dispose();
      time.flushMicrotasks();
      expect(f.repository.watchers, 0);
    });
  });

  test(
    'old host is explicit without automatic retries and recovers by event',
    () {
      fakeAsync((time) {
        final f = _Fixture();
        f.repository.error = const RunBoardUpdateRequired();
        final provider = runBoardListPageProvider();
        f.container.listen(provider, (_, _) {});
        time.flushMicrotasks();
        expect(f.container.read(provider).error, isA<RunBoardUpdateRequired>());
        time.elapse(const Duration(minutes: 2));
        expect(f.repository.boardReads, 1);
        f.repository.error = null;
        f.repository.events.add(null);
        time.flushMicrotasks();
        expect(f.container.read(provider).hasValue, isTrue);
        f.dispose();
        time.flushMicrotasks();
      });
    },
  );

  test('task pages and inspection history append only matching revisions', () {
    fakeAsync((time) {
      final f = _Fixture();
      f.repository.run = boardRunDetail(nextTaskId: 'task-3');
      f.repository.nextRun = Future.value(boardRunDetail(tasks: const []));
      f.repository.task = boardTask(
        nextCursor: const TaskHistoryCursor('now', 'a', 1),
      );
      f.repository.nextTask = Future.value(
        boardTask(
          history: const [
            TaskHistoryEntry(
              id: 'older',
              occurredAt: 'earlier',
              kind: 'audit',
              status: 'created',
            ),
          ],
        ),
      );
      final runProvider = runTaskPageProvider('run-1');
      final taskProvider = runTaskInspectionPageProvider('run-1', 'task-2');
      f.container.listen(runProvider, (_, _) {});
      f.container.listen(taskProvider, (_, _) {});
      time.flushMicrotasks();
      unawaited(f.container.read(runProvider.notifier).loadMore());
      unawaited(f.container.read(taskProvider.notifier).loadMore());
      time.flushMicrotasks();
      expect(f.container.read(runProvider).requireValue.data.tasks.length, 3);
      expect(
        f.container.read(runProvider).requireValue.data.nextTaskId,
        isNull,
      );
      expect(
        f.container.read(taskProvider).requireValue.data.history.length,
        2,
      );
      expect(
        f.container.read(taskProvider).requireValue.data.inspection.baseSha,
        isNull,
      );
      f.dispose();
      time.flushMicrotasks();
    });
  });
}

class _Fixture {
  _Fixture() {
    container = ProviderContainer(
      overrides: [
        runBoardRepositoryProvider.overrideWithValue(repository),
        appForegroundProvider.overrideWithValue(foreground),
      ],
    );
  }
  final repository = BoardTestRepository();
  final foreground = BoardTestForeground();
  late final ProviderContainer container;
  void dispose() {
    container.dispose();
    repository.dispose();
    foreground.dispose();
  }
}
