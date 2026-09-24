import 'package:alera/src/features/pull_requests/application/workspace_pull_request_state.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/review_check_details.dart';
import 'package:alera/src/features/pull_requests/domain/review_merge_method.dart';
import 'package:alera/src/features/pull_requests/domain/update_review_result.dart';
import 'package:alera/src/features/pull_requests/presentation/pull_request_composer.dart';
import 'package:alera/src/features/pull_requests/presentation/pull_request_review_view.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../unit/fake_git_backend.dart';

const _restackKey = Key('pull-request-restack-button');

const _review = HostedReview(
  provider: .github,
  number: 42,
  title: 'feat: original',
  state: .open,
  url: 'https://github.com/leynier/alera/pull/42',
  author: 'leynier',
  baseBranch: 'main',
  headBranch: 'feature',
);

Future<void> _pumpComposer(
  WidgetTester tester, {
  VoidCallback? onRestack,
  bool busy = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        gitBackendProvider.overrideWithValue(FakeGitBackend()),
        settingsControllerProvider.overrideWithValue(.defaults),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 640,
            child: PullRequestComposer(
              repoPath: '/repo',
              headBranch: 'feat/restack',
              baseBranches: const <String>['main'],
              suggestedBaseBranch: 'main',
              canCreate: true,
              busy: busy,
              suggestedReview: null,
              createAction: .publish,
              onCreate: (_) {},
              onShip: ({
                required baseBranch,
                required draft,
                required scope,
              }) async {},
              onRestack: onRestack,
              onLink: (_) {},
              onCreateActionChanged: (_) {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Widget _reviewView({
  HostedReview review = _review,
  VoidCallback? onRestack,
  PullRequestAction? action,
}) {
  return MaterialApp(
    home: Scaffold(
      body: PullRequestReviewView(
        review: review,
        checks: const [],
        comments: const [],
        baseBranches: const <String>['main'],
        mergeMethods: const <ReviewMergeMethod>[ReviewMergeMethod.mergeCommit],
        canCloseReview: true,
        canChangeDraftStatus: true,
        canComment: false,
        action: action,
        onOpenUrl: (_) async {},
        onUnlink: () async {},
        onMerge: (_) async {},
        onClose: () async {},
        onDraftStatusChanged: (_) async {},
        onAddComment: (_) async => true,
        onUpdate: (_) async => const UpdateReviewSuccess(_review),
        onLoadCheckDetails: (_) async => const ReviewCheckDetails(),
        onRestack: onRestack,
      ),
    ),
  );
}

void main() {
  testWidgets('hides restack on the create form without a callback', (
    tester,
  ) async {
    await _pumpComposer(tester);
    expect(find.byKey(_restackKey), findsNothing);
  });

  testWidgets('restack on the create form sits above ship and dispatches', (
    tester,
  ) async {
    var restackCalls = 0;
    await _pumpComposer(tester, onRestack: () => restackCalls++);

    final restack = tester.getTopLeft(find.byKey(_restackKey));
    final ship = tester.getTopLeft(
      find.byKey(const Key('pull-request-ship-button')),
    );
    expect(restack.dy, lessThan(ship.dy));
    expect(find.text('Restack Changes'), findsOneWidget);

    await tester.tap(find.byKey(_restackKey));
    await tester.pump();
    expect(restackCalls, 1);
  });

  testWidgets('disables restack on the create form while busy', (tester) async {
    var restackCalls = 0;
    await _pumpComposer(tester, busy: true, onRestack: () => restackCalls++);

    await tester.tap(find.byKey(_restackKey));
    await tester.pump();
    expect(restackCalls, 0);
  });

  testWidgets('restack on an open review sits above merge and dispatches', (
    tester,
  ) async {
    var restackCalls = 0;
    await tester.pumpWidget(_reviewView(onRestack: () => restackCalls++));

    final restack = tester.getTopLeft(find.byKey(_restackKey));
    final merge = tester.getTopLeft(find.text('Create Merge Commit'));
    expect(restack.dy, lessThan(merge.dy));

    await tester.tap(find.byKey(_restackKey));
    await tester.pump();
    expect(restackCalls, 1);
  });

  testWidgets('hides restack on a merged review', (tester) async {
    await tester.pumpWidget(
      _reviewView(
        review: _review.copyWith(state: .merged),
        onRestack: () {},
      ),
    );
    expect(find.byKey(_restackKey), findsNothing);
  });

  testWidgets('disables restack on an open review while an action runs', (
    tester,
  ) async {
    var restackCalls = 0;
    await tester.pumpWidget(
      _reviewView(
        action: PullRequestAction.merge,
        onRestack: () => restackCalls++,
      ),
    );

    await tester.tap(find.byKey(_restackKey));
    await tester.pump();
    expect(restackCalls, 0);
  });
}
