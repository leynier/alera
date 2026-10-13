import 'dart:async';

import 'package:alera/src/features/app_window/application/app_window_providers.dart';
import 'package:alera/src/features/app_window/domain/app_foreground.dart';
import 'package:alera/src/features/pull_requests/application/forge_provider_registry.dart';
import 'package:alera/src/features/pull_requests/application/pull_request_providers.dart';
import 'package:alera/src/features/pull_requests/application/workspace_pull_request_controller.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/workspace_pull_request_scope.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_forge_provider.dart';
import 'fake_git_backend.dart';

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
  testWidgets(
    'hidden windows park visual PR polling but preserve Watch and Fix',
    (tester) async {
      final foreground = _Foreground();
      addTearDown(foreground.dispose);
      final git = FakeGitBackend()
        ..remotesByName = {'origin': 'https://github.com/leynier/alera.git'};
      final forge = FakeForgeProvider()
        ..branchReview = const HostedReview(
          provider: .github,
          number: 42,
          title: 'Change',
          state: .open,
          url: 'https://github.com/leynier/alera/pull/42',
          headBranch: 'feature',
        );
      final container = ProviderContainer(
        overrides: [
          gitBackendProvider.overrideWithValue(git),
          appForegroundProvider.overrideWithValue(foreground),
          forgeProviderRegistryProvider.overrideWithValue(
            ForgeProviderRegistry([forge]),
          ),
          linkedReviewRepositoryProvider.overrideWithValue(
            FakeLinkedReviewRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);
      const scope = WorkspacePullRequestScope(
        workspaceId: 'w',
        repoPath: '/repo',
        branch: 'feature',
      );
      final provider = workspacePullRequestControllerProvider(scope);
      await container.read(provider.future);
      final controller = container.read(provider.notifier)..attachPanel();
      await tester.pump();
      await tester.pump();
      final initial = forge.branchReviewCalls;
      foreground.setVisible(false);
      await tester.pump();
      await tester.pump(const Duration(seconds: 120));
      expect(forge.branchReviewCalls, initial);
      foreground.setVisible(true);
      await tester.pump();
      await tester.pump();
      expect(forge.branchReviewCalls, initial + 1);
      controller.attachWatcher();
      foreground.setVisible(false);
      await tester.pump();
      final beforeBackground = forge.branchReviewCalls;
      await tester.pump(const Duration(seconds: 30));
      await tester.pump();
      expect(forge.branchReviewCalls, greaterThan(beforeBackground));
      controller.detachWatcher();
      final detached = forge.branchReviewCalls;
      await tester.pump(const Duration(seconds: 120));
      expect(forge.branchReviewCalls, detached);
    },
  );
}
