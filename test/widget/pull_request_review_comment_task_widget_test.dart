import 'package:alera/src/design_system/forms/alera_checkbox.dart';
import 'package:alera/src/shared/git_hosting/domain/git_hosting_provider.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/review_check.dart';
import 'package:alera/src/features/pull_requests/domain/review_check_details.dart';
import 'package:alera/src/features/pull_requests/domain/review_comment.dart';
import 'package:alera/src/features/pull_requests/domain/review_merge_method.dart';
import 'package:alera/src/features/pull_requests/domain/update_review_result.dart';
import 'package:alera/src/features/pull_requests/presentation/pull_request_review_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _review = HostedReview(
  provider: GitHostingProvider.github,
  number: 42,
  title: 'feat: tasks',
  state: HostedReviewState.open,
  url: 'https://github.com/leynier/alera/pull/42',
);

Widget _wrap({
  required List<ReviewComment> comments,
  required bool canEditComments,
  Set<String> savingCommentIds = const <String>{},
  required Future<void> Function(String commentId, int itemIndex) onToggle,
}) {
  return MaterialApp(
    home: Scaffold(
      body: PullRequestReviewView(
        review: _review,
        checks: const <ReviewCheck>[],
        comments: comments,
        baseBranches: const <String>['main'],
        mergeMethods: const <ReviewMergeMethod>[ReviewMergeMethod.mergeCommit],
        canCloseReview: false,
        canChangeDraftStatus: false,
        canComment: false,
        canEditComments: canEditComments,
        savingCommentIds: savingCommentIds,
        action: null,
        onOpenUrl: (_) async {},
        onUnlink: () async {},
        onMerge: (_) async {},
        onClose: () async {},
        onDraftStatusChanged: (_) async {},
        onAddComment: (_) async => true,
        onToggleTask: onToggle,
        onUpdate: (_) async => const UpdateReviewSuccess(_review),
        onLoadCheckDetails: (_) async => const ReviewCheckDetails(),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'task-list controls invoke the callback when editing is allowed',
    (tester) async {
      final toggles = <String>[];
      await tester.pumpWidget(
        _wrap(
          canEditComments: true,
          comments: <ReviewComment>[
            ReviewComment(
              id: 'task-comment',
              author: 'alice',
              body: '- [ ] First\n- [x] Second',
              createdAt: DateTime.utc(2026, 7, 16),
              kind: ReviewCommentKind.conversation,
              locator: const ReviewCommentLocator(
                source: ReviewCommentSource.conversation,
                commentId: '10',
              ),
            ),
          ],
          onToggle: (commentId, itemIndex) async {
            toggles.add('$commentId:$itemIndex');
          },
        ),
      );

      expect(find.byType(AleraCheckbox), findsNWidgets(2));
      expect(
        tester.widget<AleraCheckbox>(find.byType(AleraCheckbox).first).enabled,
        isTrue,
      );
      await tester.tap(find.byType(AleraCheckbox).first);
      await tester.pump();
      expect(toggles, <String>['task-comment:0']);
    },
  );

  testWidgets('task-list controls disable unsupported and saving comments', (
    tester,
  ) async {
    final comments = <ReviewComment>[
      ReviewComment(
        id: 'saving',
        author: 'alice',
        body: '- [ ] Saving',
        createdAt: DateTime.utc(2026, 7, 16),
        kind: ReviewCommentKind.conversation,
        locator: const ReviewCommentLocator(
          source: ReviewCommentSource.conversation,
          commentId: '11',
        ),
      ),
      ReviewComment(
        id: 'available',
        author: 'bob',
        body: '- [ ] Available',
        createdAt: DateTime.utc(2026, 7, 16, 1),
        kind: ReviewCommentKind.review,
        locator: const ReviewCommentLocator(
          source: ReviewCommentSource.reviewThread,
          commentId: '12',
          parentId: 'thread-12',
        ),
      ),
    ];
    await tester.pumpWidget(
      _wrap(
        canEditComments: true,
        savingCommentIds: const <String>{'saving'},
        comments: comments,
        onToggle: (_, _) async {},
      ),
    );

    final controls = tester.widgetList<AleraCheckbox>(
      find.byType(AleraCheckbox),
    );
    expect(controls.elementAt(0).enabled, isFalse);
    expect(controls.elementAt(1).enabled, isTrue);

    await tester.pumpWidget(
      _wrap(
        canEditComments: false,
        comments: <ReviewComment>[comments.first],
        onToggle: (_, _) async {},
      ),
    );
    expect(
      tester.widget<AleraCheckbox>(find.byType(AleraCheckbox)).enabled,
      isFalse,
    );
  });
}
