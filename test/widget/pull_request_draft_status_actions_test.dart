import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/review_check_details.dart';
import 'package:alera/src/features/pull_requests/domain/review_merge_method.dart';
import 'package:alera/src/features/pull_requests/domain/update_review_result.dart';
import 'package:alera/src/features/pull_requests/presentation/pull_request_review_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

class _Callbacks {
  bool? draftStatus;
}

Widget _wrap(
  _Callbacks callbacks, {
  HostedReview review = _review,
  bool canChangeDraftStatus = true,
}) {
  return MaterialApp(
    home: Scaffold(
      body: PullRequestReviewView(
        review: review,
        checks: const [],
        comments: const [],
        baseBranches: const ['develop', 'main'],
        mergeMethods: const [
          ReviewMergeMethod.mergeCommit,
          ReviewMergeMethod.squash,
          ReviewMergeMethod.rebase,
        ],
        canCloseReview: true,
        canChangeDraftStatus: canChangeDraftStatus,
        canComment: true,
        action: null,
        onOpenUrl: (_) async {},
        onUnlink: () async {},
        onMerge: (_) async {},
        onClose: () async {},
        onDraftStatusChanged: (draft) async {
          callbacks.draftStatus = draft;
        },
        onAddComment: (_) async => true,
        onUpdate: (_) async => const UpdateReviewSuccess(_review),
        onLoadCheckDetails: (_) async => const ReviewCheckDetails(),
      ),
    ),
  );
}

void main() {
  testWidgets('defaults a draft PR to Mark Ready For Review', (tester) async {
    final callbacks = _Callbacks();
    await tester.pumpWidget(
      _wrap(callbacks, review: _review.copyWith(state: .draft)),
    );

    expect(find.text('Mark Ready For Review'), findsOneWidget);
    expect(find.text('Create Merge Commit'), findsNothing);

    await tester.tap(find.text('Mark Ready For Review'));
    await tester.pumpAndSettle();
    expect(find.text('Mark Ready For Review PR #42?'), findsOneWidget);
    expect(callbacks.draftStatus, isNull);

    await tester.tap(
      find.widgetWithText(FilledButton, 'Mark Ready For Review'),
    );
    await tester.pumpAndSettle();
    expect(callbacks.draftStatus, isFalse);
  });

  testWidgets('keeps merge, close, and unlink available for a draft PR', (
    tester,
  ) async {
    final callbacks = _Callbacks();
    await tester.pumpWidget(
      _wrap(callbacks, review: _review.copyWith(state: .draft)),
    );

    await tester.tap(find.byTooltip('Pull Request Actions'));
    await tester.pumpAndSettle();
    expect(find.text('Mark Ready For Review'), findsWidgets);
    expect(find.text('Create Merge Commit'), findsOneWidget);
    expect(find.text('Close Pull Request'), findsOneWidget);
    expect(find.text('Unlink Pull Request'), findsOneWidget);
  });

  testWidgets('converts an open PR to draft from the action menu', (
    tester,
  ) async {
    final callbacks = _Callbacks();
    await tester.pumpWidget(_wrap(callbacks));

    await tester.tap(find.byTooltip('Pull Request Actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Convert To Draft'));
    await tester.pumpAndSettle();

    expect(find.text('Convert To Draft PR #42?'), findsNothing);
    expect(callbacks.draftStatus, isNull);

    await tester.tap(find.text('Convert To Draft'));
    await tester.pumpAndSettle();
    expect(find.text('Convert To Draft PR #42?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Convert To Draft'));
    await tester.pumpAndSettle();
    expect(callbacks.draftStatus, isTrue);
  });

  testWidgets('omits draft conversion when the provider does not support it', (
    tester,
  ) async {
    final callbacks = _Callbacks();
    await tester.pumpWidget(_wrap(callbacks, canChangeDraftStatus: false));

    await tester.tap(find.byTooltip('Pull Request Actions'));
    await tester.pumpAndSettle();

    expect(find.text('Convert To Draft'), findsNothing);
  });
}
