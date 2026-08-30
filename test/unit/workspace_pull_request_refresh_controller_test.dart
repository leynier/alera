import 'dart:async';

import 'package:alera/src/features/pull_requests/application/forge_exception.dart';
import 'package:alera/src/features/pull_requests/application/forge_provider.dart';
import 'package:alera/src/features/pull_requests/application/forge_provider_registry.dart';
import 'package:alera/src/features/pull_requests/application/pull_request_providers.dart';
import 'package:alera/src/features/pull_requests/application/workspace_pull_request_controller.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/linked_review.dart';
import 'package:alera/src/features/pull_requests/domain/review_check.dart';
import 'package:alera/src/features/pull_requests/domain/workspace_pull_request_scope.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_forge_provider.dart';
import 'fake_git_backend.dart';

HostedReview _review(int number) => HostedReview(
  provider: .github,
  number: number,
  title: 'feat: $number',
  state: .open,
  url: 'https://github.com/leynier/alera/pull/$number',
  headBranch: 'feature',
);

const _scope = WorkspacePullRequestScope(
  workspaceId: 'w1',
  repoPath: '/repo',
  branch: 'feature',
);

ProviderContainer _container({
  required FakeForgeProvider forge,
  bool visible = true,
  FakeLinkedReviewRepository? linkedReviews,
}) {
  final backend = FakeGitBackend()
    ..remotesByName = <String, String?>{
      'origin': 'https://github.com/leynier/alera.git',
    };
  final container = ProviderContainer(
    overrides: [
      gitBackendProvider.overrideWithValue(backend),
      forgeProviderRegistryProvider.overrideWithValue(
        ForgeProviderRegistry(<ForgeProvider>[forge]),
      ),
      linkedReviewRepositoryProvider.overrideWithValue(
        linkedReviews ?? FakeLinkedReviewRepository(),
      ),
    ],
  );
  if (visible) {
    container.listen(workspacePullRequestControllerProvider(_scope), (_, _) {});
    container
        .read(workspacePullRequestControllerProvider(_scope).notifier)
        .attachPanel();
  }
  return container;
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    if (condition()) {
      return;
    }
    await Future.pause(.zero);
  }
  fail('Condition was not reached after draining asynchronous work.');
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    if (condition()) {
      return;
    }
    await tester.pump();
  }
  fail('Condition was not reached after pumping asynchronous work.');
}

void main() {
  test(
    'refresh keeps the last snapshot and coalesces concurrent loads',
    () async {
      const initialCheck = ReviewCheck(
        name: 'build',
        status: .completed,
        conclusion: .success,
      );
      final forge = FakeForgeProvider()
        ..branchReview = _review(123)
        ..checks = <ReviewCheck>[initialCheck];
      final container = _container(forge: forge);
      addTearDown(container.dispose);

      await container.read(
        workspacePullRequestControllerProvider(_scope).future,
      );
      final gate = Completer<HostedReview?>();
      forge.branchReviewLoader = () => gate.future;
      final controller = container.read(
        workspacePullRequestControllerProvider(_scope).notifier,
      );

      final firstRefresh = controller.refresh();
      final secondRefresh = controller.refresh();
      await _waitUntil(() => forge.branchReviewCalls == 2);

      final refreshing = container
          .read(workspacePullRequestControllerProvider(_scope))
          .value!;
      expect(refreshing.isRefreshing, isTrue);
      expect(refreshing.review?.number, 123);
      expect(refreshing.checks, <ReviewCheck>[initialCheck]);
      expect(forge.branchReviewCalls, 2);

      gate.complete(_review(456));
      await Future.wait<void>(<Future<void>>[firstRefresh, secondRefresh]);

      final refreshed = container
          .read(workspacePullRequestControllerProvider(_scope))
          .value!;
      expect(refreshed.isRefreshing, isFalse);
      expect(refreshed.review?.number, 456);
    },
  );

  test(
    'refresh failure preserves the last snapshot and exposes the error',
    () async {
      final forge = FakeForgeProvider()
        ..branchReview = _review(123)
        ..checks = <ReviewCheck>[
          const ReviewCheck(
            name: 'build',
            status: .completed,
            conclusion: .success,
          ),
        ];
      final container = _container(forge: forge);
      addTearDown(container.dispose);

      await container.read(
        workspacePullRequestControllerProvider(_scope).future,
      );
      forge.branchReviewLoader = () async {
        throw const ForgeRequestFailed('network unavailable');
      };

      await container
          .read(workspacePullRequestControllerProvider(_scope).notifier)
          .refresh();

      final state = container
          .read(workspacePullRequestControllerProvider(_scope))
          .value!;
      expect(state.review?.number, 123);
      expect(state.checks, hasLength(1));
      expect(state.isRefreshing, isFalse);
      expect(state.errorMessage, 'network unavailable');
    },
  );

  testWidgets('polling pauses while detached and refreshes on resume', (
    tester,
  ) async {
    final forge = FakeForgeProvider()..branchReview = _review(123);
    final container = _container(forge: forge, visible: false);
    addTearDown(container.dispose);
    final provider = workspacePullRequestControllerProvider(_scope);
    final subscription = container.listen(provider, (_, _) {});
    final controller = container.read(provider.notifier)..attachPanel();

    await _pumpUntil(tester, () => container.read(provider).hasValue);
    expect(forge.branchReviewCalls, 1);

    final pollGate = Completer<HostedReview?>();
    forge.branchReviewLoader = () => pollGate.future;
    await tester.pump(const Duration(seconds: 30));
    await _pumpUntil(tester, () => forge.branchReviewCalls == 2);
    expect(container.read(provider).value!.isRefreshing, isTrue);
    expect(container.read(provider).value!.review?.number, 123);

    controller.detachPanel();
    pollGate.complete(_review(456));
    await _pumpUntil(
      tester,
      () => container.read(provider).value?.review?.number == 456,
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 121));
    expect(forge.branchReviewCalls, 2);

    final resumeGate = Completer<HostedReview?>();
    forge.branchReviewLoader = () => resumeGate.future;
    controller.attachPanel();
    await tester.pump(const Duration(milliseconds: 1));
    await _pumpUntil(tester, () => forge.branchReviewCalls == 3);

    final cached = container.read(provider).value!;
    expect(cached.review?.number, 456);
    expect(cached.isRefreshing, isTrue);

    resumeGate.complete(_review(789));
    await tester.pump();
    expect(container.read(provider).value!.review?.number, 789);
    controller.detachPanel();
    subscription.close();
  });

  testWidgets('polling detects a different PR after an exact dismissal', (
    tester,
  ) async {
    final forge = FakeForgeProvider()..branchReview = _review(123);
    final linkedReviews = FakeLinkedReviewRepository()
      ..store['w1'] = LinkedReview.dismissal(
        workspaceId: 'w1',
        provider: .github,
        number: 123,
        url: 'https://github.com/leynier/alera/pull/123',
      );
    final container = _container(forge: forge, linkedReviews: linkedReviews);
    addTearDown(container.dispose);
    final provider = workspacePullRequestControllerProvider(_scope);

    await _pumpUntil(tester, () => container.read(provider).hasValue);
    expect(container.read(provider).value?.suggestedReview?.number, 123);

    forge.branchReview = _review(456);
    await tester.pump(const Duration(seconds: 30));
    await _pumpUntil(
      tester,
      () => container.read(provider).value?.review?.number == 456,
    );

    expect(container.read(provider).value?.suggestedReview, isNull);
    container.read(provider.notifier).detachPanel();
    await tester.pump();
  });
}
