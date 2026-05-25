import 'dart:async';

import 'package:alera/src/app/dependencies.dart';
import 'package:alera/src/features/settings/application/github_star_controller.dart';
import 'package:alera/src/features/settings/infra/github_star_service.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GitHubStarController', () {
    test('refresh hides the prompt when star status cannot be resolved', () async {
      final service = _FakeGitHubStarService(checkStarredResult: null);
      final container = ProviderContainer(
        overrides: [gitHubStarServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);
      final controller = container.read(gitHubStarControllerProvider.notifier);

      await controller.refresh();

      expect(container.read(gitHubStarControllerProvider), GitHubStarState.hidden);
    });

    test('star does nothing while the controller is still loading', () async {
      final completer = Completer<bool?>();
      final service = _FakeGitHubStarService(checkStarredFuture: completer.future);
      final container = ProviderContainer(
        overrides: [gitHubStarServiceProvider.overrideWithValue(service)],
      );
      addTearDown(() async {
        if (!completer.isCompleted) {
          completer.complete(false);
        }
        container.dispose();
      });
      final controller = container.read(gitHubStarControllerProvider.notifier);

      expect(container.read(gitHubStarControllerProvider), GitHubStarState.loading);
      await controller.star();

      expect(service.starCalls, 0);
    });

    test('refresh can expose not-starred and star can promote to starred', () async {
      final service = _FakeGitHubStarService(
        checkStarredResult: false,
        starResult: true,
      );
      final container = ProviderContainer(
        overrides: [gitHubStarServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);
      final controller = container.read(gitHubStarControllerProvider.notifier);

      await controller.refresh();
      expect(
        container.read(gitHubStarControllerProvider),
        GitHubStarState.notStarred,
      );

      await controller.star();

      expect(container.read(gitHubStarControllerProvider), GitHubStarState.starred);
    });

    test('star moves to error when the service fails', () async {
      final service = _FakeGitHubStarService(
        checkStarredResult: false,
        starResult: false,
      );
      final container = ProviderContainer(
        overrides: [gitHubStarServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);
      final controller = container.read(gitHubStarControllerProvider.notifier);

      await controller.refresh();
      await controller.star();

      expect(container.read(gitHubStarControllerProvider), GitHubStarState.error);
    });
  });
}

class _FakeGitHubStarService extends GitHubStarService {
  _FakeGitHubStarService({
    bool? checkStarredResult,
    Future<bool?>? checkStarredFuture,
    this.starResult = true,
  }) : _checkStarredResult = checkStarredResult,
       _checkStarredFuture = checkStarredFuture,
       super(_NoopProcessRunner());

  final bool? _checkStarredResult;
  final Future<bool?>? _checkStarredFuture;
  final bool starResult;
  int starCalls = 0;

  @override
  Future<bool?> checkStarred() async {
    if (_checkStarredFuture case final Future<bool?> future) {
      return future;
    }
    return _checkStarredResult;
  }

  @override
  Future<bool> star() async {
    starCalls += 1;
    return starResult;
  }
}

class _NoopProcessRunner implements ProcessRunner {
  @override
  Future<ProcessRunOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<StartedProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) {
    throw UnimplementedError();
  }
}
