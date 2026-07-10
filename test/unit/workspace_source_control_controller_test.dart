import 'dart:async';

import 'package:alera/src/features/workbench/application/source_control_watcher.dart';
import 'package:alera/src/features/workbench/application/workspace_source_control_controller.dart';
import 'package:alera/src/features/workbench/application/workspace_submodule_status_provider.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_git_backend.dart';
import 'fake_source_control_watcher.dart';

const _workspacePath = '/tmp/workspace';

GitStatusResult _statusWith(int entryCount) {
  return GitStatusResult(
    entries: <GitChangeEntry>[
      for (var index = 0; index < entryCount; index += 1)
        GitChangeEntry(
          path: 'file_$index.dart',
          area: GitChangeArea.unstaged,
          status: GitChangeStatus.modified,
          added: 1,
          removed: 0,
        ),
    ],
  );
}

Future<(ProviderContainer, WorkspaceSourceControlController)> _boot(
  FakeGitBackend backend,
  FakeSourceControlWatcher watcher,
) async {
  final container = ProviderContainer(
    overrides: [
      gitBackendProvider.overrideWithValue(backend),
      sourceControlWatcherProvider.overrideWithValue(watcher),
    ],
  );
  final provider = workspaceSourceControlControllerProvider(_workspacePath);
  final subscription = container.listen(provider, (_, _) {});
  addTearDown(subscription.close);
  addTearDown(container.dispose);
  await container.read(provider.future);
  // Let the best-effort, unawaited watcher subscription attach.
  await Future<void>.delayed(const Duration(milliseconds: 10));
  return (container, container.read(provider.notifier));
}

void main() {
  test('a watch signal reloads source control state', () async {
    final backend = FakeGitBackend()..gitStatusResult = _statusWith(1);
    final watcher = FakeSourceControlWatcher();
    addTearDown(watcher.dispose);
    final (container, _) = await _boot(backend, watcher);
    final provider = workspaceSourceControlControllerProvider(_workspacePath);

    expect(container.read(provider).requireValue.status.entries, hasLength(1));
    expect(watcher.startCount, 1);

    // Simulate an external change picked up by the native watcher.
    backend.gitStatusResult = _statusWith(3);
    watcher.emitChange();
    await Future<void>.delayed(const Duration(milliseconds: 350));

    expect(container.read(provider).requireValue.status.entries, hasLength(3));
  });

  test('watch signals are deferred while an action is in flight', () async {
    final backend = _BlockingFetchGitBackend()
      ..gitStatusResult = _statusWith(1);
    final watcher = FakeSourceControlWatcher();
    addTearDown(watcher.dispose);
    final (container, controller) = await _boot(backend, watcher);
    final provider = workspaceSourceControlControllerProvider(_workspacePath);

    final fetchFuture = controller.fetch();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(container.read(provider).requireValue.isBusy, isTrue);

    // External change arrives mid-action: it must not reload yet.
    backend.gitStatusResult = _statusWith(5);
    watcher.emitChange();
    await Future<void>.delayed(const Duration(milliseconds: 350));
    expect(container.read(provider).requireValue.status.entries, hasLength(1));
    expect(container.read(provider).requireValue.isBusy, isTrue);

    // Action completes and reloads, surfacing the latest status.
    backend.gate.complete();
    await fetchFuture;
    expect(container.read(provider).requireValue.isBusy, isFalse);
    expect(container.read(provider).requireValue.status.entries, hasLength(5));
  });

  test(
    'watch signals queue a trailing reload while one is in flight',
    () async {
      final backend = _BlockingStatusGitBackend()
        ..gitStatusResult = _statusWith(1);
      final watcher = FakeSourceControlWatcher();
      addTearDown(watcher.dispose);
      final (container, _) = await _boot(backend, watcher);
      final provider = workspaceSourceControlControllerProvider(_workspacePath);
      final gate = Completer<void>();

      backend.statusGates.add(gate);
      backend.gitStatusResult = _statusWith(2);
      watcher.emitChange();
      await Future<void>.delayed(const Duration(milliseconds: 350));

      backend.gitStatusResult = _statusWith(3);
      watcher.emitChange();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 450));

      expect(
        container.read(provider).requireValue.status.entries,
        hasLength(3),
      );
      expect(
        backend.calls.where((call) => call.method == 'status').length,
        greaterThanOrEqualTo(3),
      );
    },
  );

  test('disposing the controller stops the watcher', () async {
    final backend = FakeGitBackend()..gitStatusResult = _statusWith(0);
    final watcher = FakeSourceControlWatcher();
    addTearDown(watcher.dispose);
    final container = ProviderContainer(
      overrides: [
        gitBackendProvider.overrideWithValue(backend),
        sourceControlWatcherProvider.overrideWithValue(watcher),
      ],
    );
    final provider = workspaceSourceControlControllerProvider(_workspacePath);
    final subscription = container.listen(provider, (_, _) {});
    await container.read(provider.future);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(watcher.startCount, 1);

    subscription.close();
    container.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(watcher.stopCount, 1);
  });

  test('parent actions ignore submodule worktree-only entries', () async {
    final backend = FakeGitBackend();
    final watcher = FakeSourceControlWatcher();
    addTearDown(watcher.dispose);
    final (_, controller) = await _boot(backend, watcher);
    const entry = GitChangeEntry(
      path: 'modules/sample',
      area: GitChangeArea.unstaged,
      status: GitChangeStatus.modified,
      submodule: GitSubmoduleStatus(
        commitChanged: false,
        trackedChanges: true,
        untrackedChanges: false,
        inspectable: true,
      ),
    );

    await controller.stageEntry(entry);
    await controller.discardEntry(entry);

    expect(backend.calls.where((call) => call.method == 'stage'), isEmpty);
    expect(backend.calls.where((call) => call.method == 'discard'), isEmpty);
  });

  test('one-sided submodule ranges are not expandable', () {
    const entry = GitChangeEntry(
      path: 'modules/sample',
      area: GitChangeArea.staged,
      status: GitChangeStatus.deleted,
      submodule: GitSubmoduleStatus(
        commitChanged: true,
        trackedChanges: false,
        untrackedChanges: false,
        inspectable: false,
      ),
    );

    expect(entry.isExpandableSubmodule, isFalse);
    expect(entry.canDiscardFromParent, isFalse);
  });

  test('submodule provider loads lazily and prefixes child paths', () async {
    final backend = FakeGitBackend()
      ..gitSubmoduleStatusResult = const GitStatusResult(
        entries: <GitChangeEntry>[
          GitChangeEntry(
            path: 'lib/child.dart',
            area: GitChangeArea.staged,
            status: GitChangeStatus.modified,
          ),
        ],
      );
    final watcher = FakeSourceControlWatcher();
    addTearDown(watcher.dispose);
    final (container, _) = await _boot(backend, watcher);
    final provider = workspaceSubmoduleStatusProvider(
      workspacePath: _workspacePath,
      submodulePath: 'modules/sample',
      area: GitChangeArea.staged,
    );

    expect(
      backend.calls.where((call) => call.method == 'submoduleStatus'),
      isEmpty,
    );
    final result = await container.read(provider.future);

    expect(result.entries.single.path, 'modules/sample/lib/child.dart');
    expect(result.entries.single.area, GitChangeArea.staged);
    expect(result.entries.single.submoduleRoot, 'modules/sample');
    expect(
      backend.calls
          .where((call) => call.method == 'submoduleStatus')
          .single
          .args,
      <String, Object?>{
        'path': _workspacePath,
        'submodulePath': 'modules/sample',
        'area': GitChangeArea.staged,
      },
    );
  });
}

class _BlockingFetchGitBackend extends FakeGitBackend {
  final Completer<void> gate = Completer<void>();

  @override
  Future<void> fetch(String path) async {
    await gate.future;
  }
}

class _BlockingStatusGitBackend extends FakeGitBackend {
  final List<Completer<void>> statusGates = <Completer<void>>[];

  @override
  Future<GitStatusResult> status(String path) async {
    calls.add(GitBackendCall('status', <String, Object?>{'path': path}));
    final result = gitStatusResult;
    if (statusGates.isNotEmpty) {
      await statusGates.removeAt(0).future;
    }
    return result;
  }
}
