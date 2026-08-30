import 'package:alera/src/features/workbench/application/workspace_activity_controller.dart';
import 'package:alera/src/features/workbench/application/workspace_activity_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeWorkspaceActivityRepository implements WorkspaceActivityRepository {
  final Map<String, DateTime> stored = <String, DateTime>{};
  int upsertCalls = 0;

  @override
  Future<Map<String, DateTime>> loadAll() async =>
      Map<String, DateTime>.from(stored);

  @override
  Future<void> upsertAll(Map<String, DateTime> entries) async {
    upsertCalls++;
    stored.addAll(entries);
  }

  @override
  Future<void> remove(String workspaceId) async {
    stored.remove(workspaceId);
  }
}

void main() {
  test('recordActivity updates in-memory state immediately', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(
      workspaceActivityControllerProvider.notifier,
    );
    final at = DateTime.utc(2026, 7, 4, 12);

    controller.recordActivity('w-1', at);

    expect(container.read(workspaceActivityControllerProvider), {'w-1': at});
  });

  test('older activity does not overwrite a newer timestamp', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(
      workspaceActivityControllerProvider.notifier,
    );
    final newer = DateTime.utc(2026, 7, 4, 12);
    final older = DateTime.utc(2026, 7, 4, 11);

    controller.recordActivity('w-1', newer);
    controller.recordActivity('w-1', older);

    expect(container.read(workspaceActivityControllerProvider), {'w-1': newer});
  });

  test(
    'attachRepository seeds persisted entries under newer in-memory ones',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final repository = _FakeWorkspaceActivityRepository()
        ..stored['w-persisted'] = DateTime.utc(2026, 7, 1)
        ..stored['w-live'] = DateTime.utc(2026, 7, 1);
      final controller = container.read(
        workspaceActivityControllerProvider.notifier,
      );
      final live = DateTime.utc(2026, 7, 4);
      controller.recordActivity('w-live', live);

      await controller.attachRepository(repository);

      final state = container.read(workspaceActivityControllerProvider);
      expect(state['w-persisted'], DateTime.utc(2026, 7, 1));
      expect(state['w-live'], live);
    },
  );

  test('recorded activity is flushed to the repository in one batch', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final repository = _FakeWorkspaceActivityRepository();
    final controller = container.read(
      workspaceActivityControllerProvider.notifier,
    );
    await controller.attachRepository(repository);

    controller.recordActivity('w-1', .utc(2026, 7, 4, 12));
    controller.recordActivity('w-2', .utc(2026, 7, 4, 13));

    await Future.pause(
      workspaceActivityFlushDelay + const Duration(milliseconds: 100),
    );
    expect(repository.upsertCalls, 1);
    expect(repository.stored.keys, containsAll(<String>['w-1', 'w-2']));
  });

  test('removeWorkspace drops the entry from state and persistence', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final repository = _FakeWorkspaceActivityRepository()
      ..stored['w-1'] = DateTime.utc(2026, 7, 1);
    final controller = container.read(
      workspaceActivityControllerProvider.notifier,
    );
    await controller.attachRepository(repository);

    controller.removeWorkspace('w-1');
    await Future.pause(.zero);

    expect(container.read(workspaceActivityControllerProvider), isEmpty);
    expect(repository.stored, isEmpty);
  });
}
