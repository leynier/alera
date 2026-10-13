import 'dart:async';

import 'package:alera/src/features/app_window/application/app_window_providers.dart';
import 'package:alera/src/features/app_window/domain/app_foreground.dart';
import 'package:alera/src/features/workbench/application/source_control_watcher.dart';
import 'package:alera/src/features/workbench/application/workspace_source_control_controller.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_git_backend.dart';
import 'fake_source_control_watcher.dart';

class _Foreground implements AppForeground {
  final updates = StreamController<bool>.broadcast();
  bool visible = true;
  @override
  bool get isForeground => visible;
  @override
  Stream<bool> get changes => updates.stream;
  void setVisible(bool value) {
    visible = value;
    updates.add(value);
  }

  @override
  void dispose() {
    unawaited(updates.close());
  }
}

void main() {
  test('only visible surfaces observe, and resuming reloads once', () async {
    final git = FakeGitBackend();
    final watcher = FakeSourceControlWatcher();
    final foreground = _Foreground();
    addTearDown(watcher.dispose);
    addTearDown(foreground.dispose);
    final container = ProviderContainer(
      overrides: [
        gitBackendProvider.overrideWithValue(git),
        sourceControlWatcherProvider.overrideWithValue(watcher),
        appForegroundProvider.overrideWithValue(foreground),
      ],
    );
    addTearDown(container.dispose);
    final provider = workspaceSourceControlControllerProvider('/repo');
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    await container.read(provider.future);
    final controller = container.read(provider.notifier);
    expect(watcher.startCount, 0);
    controller.attachView();
    await Future.pause(const Duration(milliseconds: 350));
    expect(watcher.startCount, 1);
    final initial = git.calls.length;
    foreground.setVisible(false);
    await Future.pause(const Duration(milliseconds: 10));
    expect(watcher.stopCount, 1);
    watcher.emitChange();
    await Future.pause(const Duration(milliseconds: 350));
    expect(git.calls.length, initial);
    foreground.setVisible(true);
    await Future.pause(const Duration(milliseconds: 350));
    expect(watcher.startCount, 2);
    expect(git.calls.where((call) => call.method == 'status').length, 3);
    controller.detachView();
    await Future.pause(const Duration(milliseconds: 10));
    expect(watcher.stopCount, 2);
    final parked = git.calls.length;
    watcher.emitChange();
    await Future.pause(const Duration(milliseconds: 350));
    expect(git.calls.length, parked);
    await controller.stage('a.dart');
    expect(git.calls.any((call) => call.method == 'stage'), isTrue);
    expect(watcher.startCount, 2);
  });

  test(
    'file changes reuse repository metadata and preserve catalog revision',
    () async {
      final git = FakeGitBackend();
      final watcher = FakeSourceControlWatcher();
      addTearDown(watcher.dispose);
      final container = ProviderContainer(
        overrides: [
          gitBackendProvider.overrideWithValue(git),
          sourceControlWatcherProvider.overrideWithValue(watcher),
        ],
      );
      addTearDown(container.dispose);
      final provider = workspaceSourceControlControllerProvider('/repo');
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      await container.read(provider.future);
      container.read(provider.notifier).attachView();
      await Future.pause(const Duration(milliseconds: 350));
      final before = container.read(provider).requireValue;
      git.calls.clear();
      for (var i = 0; i < 50; i++) {
        watcher.emitChange(repository: false, catalog: false);
      }
      await Future.pause(const Duration(milliseconds: 350));
      expect(git.calls.where((call) => call.method == 'status').length, 1);
      expect(
        git.calls.where((call) => call.method == 'repositoryState'),
        isEmpty,
      );
      expect(git.calls.where((call) => call.method == 'listStashes'), isEmpty);
      final after = container.read(provider).requireValue;
      expect(after.comparisonRevision, greaterThan(before.comparisonRevision));
      expect(after.catalogRevision, before.catalogRevision);
      watcher.emitChange();
      await Future.pause(const Duration(milliseconds: 350));
      expect(
        container.read(provider).requireValue.catalogRevision,
        greaterThan(after.catalogRevision),
      );
    },
  );
}
