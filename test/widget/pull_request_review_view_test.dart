import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/pull_requests/application/workspace_pull_request_state.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/review_check.dart';
import 'package:alera/src/features/pull_requests/domain/review_check_details.dart';
import 'package:alera/src/features/pull_requests/domain/review_comment.dart';
import 'package:alera/src/features/pull_requests/domain/review_merge_method.dart';
import 'package:alera/src/features/pull_requests/domain/update_review_input.dart';
import 'package:alera/src/features/pull_requests/domain/update_review_result.dart';
import 'package:alera/src/features/pull_requests/presentation/pull_request_comment_markdown.dart';
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
  int unlinkCalls = 0;
  int closeCalls = 0;
  bool? draftStatus;
  final List<String> commentBodies = <String>[];
  bool addCommentResult = true;
  ReviewMergeMethod? mergeMethod;
  UpdateReviewInput? lastInput;
  UpdateReviewResult updateResult = const UpdateReviewSuccess(_review);
}

Widget _wrap(
  _Callbacks callbacks, {
  HostedReview review = _review,
  PullRequestAction? action,
  List<ReviewCheck> checks = const <ReviewCheck>[],
  List<ReviewComment> comments = const <ReviewComment>[],
  List<ReviewMergeMethod> mergeMethods = const <ReviewMergeMethod>[
    ReviewMergeMethod.mergeCommit,
    ReviewMergeMethod.squash,
    ReviewMergeMethod.rebase,
  ],
  bool canCloseReview = true,
  bool canChangeDraftStatus = true,
  bool canComment = true,
}) {
  return MaterialApp(
    home: Scaffold(
      body: PullRequestReviewView(
        review: review,
        checks: checks,
        comments: comments,
        baseBranches: const <String>['develop', 'main'],
        mergeMethods: mergeMethods,
        canCloseReview: canCloseReview,
        canChangeDraftStatus: canChangeDraftStatus,
        canComment: canComment,
        action: action,
        onOpenUrl: (_) async {},
        onUnlink: () async {
          callbacks.unlinkCalls++;
        },
        onMerge: (method) async => callbacks.mergeMethod = method,
        onClose: () async => callbacks.closeCalls++,
        onDraftStatusChanged: (draft) async {
          callbacks.draftStatus = draft;
        },
        onAddComment: (body) async {
          callbacks.commentBodies.add(body);
          return callbacks.addCommentResult;
        },
        onUpdate: (input) async {
          callbacks.lastInput = input;
          return callbacks.updateResult;
        },
        onLoadCheckDetails: (_) async => const ReviewCheckDetails(),
      ),
    ),
  );
}

void main() {
  testWidgets('offers every available review action in one menu', (
    tester,
  ) async {
    final callbacks = _Callbacks();
    await tester.pumpWidget(_wrap(callbacks));

    expect(find.text('Create Merge Commit'), findsOneWidget);
    expect(find.text('Close Pull Request'), findsNothing);
    expect(find.text('Unlink Pull Request'), findsNothing);

    await tester.tap(find.byTooltip('Pull Request Actions'));
    await tester.pumpAndSettle();

    expect(find.text('Create Merge Commit'), findsWidgets);
    expect(find.text('Squash and Merge'), findsOneWidget);
    expect(find.text('Rebase and Merge'), findsOneWidget);
    expect(find.text('Convert To Draft'), findsOneWidget);
    expect(find.text('Close Pull Request'), findsOneWidget);
    expect(find.text('Unlink Pull Request'), findsOneWidget);
    expect(callbacks.mergeMethod, isNull);
    expect(callbacks.closeCalls, 0);
    expect(callbacks.unlinkCalls, 0);
  });

  testWidgets('confirms the primary merge method before invoking it', (
    tester,
  ) async {
    final callbacks = _Callbacks();
    await tester.pumpWidget(_wrap(callbacks));

    await tester.tap(find.text('Create Merge Commit'));
    await tester.pumpAndSettle();
    expect(find.text('Create Merge Commit PR #42?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Create Merge Commit'));
    await tester.pumpAndSettle();
    expect(callbacks.mergeMethod, ReviewMergeMethod.mergeCommit);
  });

  testWidgets('selecting a merge method only changes the primary action', (
    tester,
  ) async {
    final callbacks = _Callbacks();
    await tester.pumpWidget(_wrap(callbacks));

    await tester.tap(find.byTooltip('Pull Request Actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Squash and Merge'));
    await tester.pumpAndSettle();

    expect(find.text('Squash and Merge PR #42?'), findsNothing);
    expect(callbacks.mergeMethod, isNull);
    expect(find.text('Squash and Merge'), findsOneWidget);

    await tester.tap(find.text('Squash and Merge'));
    await tester.pumpAndSettle();
    expect(find.text('Squash and Merge PR #42?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Squash and Merge'));
    await tester.pumpAndSettle();
    expect(callbacks.mergeMethod, ReviewMergeMethod.squash);
  });

  testWidgets('confirms closing without merging', (tester) async {
    final callbacks = _Callbacks();
    await tester.pumpWidget(_wrap(callbacks));

    await tester.tap(find.byTooltip('Pull Request Actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close Pull Request'));
    await tester.pumpAndSettle();

    expect(find.text('Close Pull Request #42?'), findsNothing);
    expect(callbacks.closeCalls, 0);
    final closeButton = tester.widget<Material>(
      find.byKey(const ValueKey<String>('pull-request-action-button-close')),
    );
    expect(closeButton.color, AleraTokens.error);

    await tester.tap(find.text('Close Pull Request'));
    await tester.pumpAndSettle();
    expect(find.text('Close Pull Request #42?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(callbacks.closeCalls, 0);

    await tester.tap(find.text('Close Pull Request'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Close Pull Request'));
    await tester.pumpAndSettle();
    expect(callbacks.closeCalls, 1);
  });

  testWidgets('confirms unlinking without changing the remote pull request', (
    tester,
  ) async {
    final callbacks = _Callbacks();
    await tester.pumpWidget(_wrap(callbacks));

    await tester.tap(find.byTooltip('Pull Request Actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unlink Pull Request'));
    await tester.pumpAndSettle();

    expect(find.text('Unlink Pull Request #42?'), findsNothing);
    expect(callbacks.unlinkCalls, 0);
    final unlinkButton = tester.widget<Material>(
      find.byKey(const ValueKey<String>('pull-request-action-button-unlink')),
    );
    expect(unlinkButton.color, AleraTokens.accent);

    await tester.tap(find.text('Unlink Pull Request'));
    await tester.pumpAndSettle();
    expect(find.text('Unlink Pull Request #42?'), findsOneWidget);
    expect(
      find.textContaining('The pull request on GitHub will not be changed.'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Unlink Pull Request'));
    await tester.pumpAndSettle();
    expect(callbacks.unlinkCalls, 1);
  });

  testWidgets('keeps the action menu available when merge is blocked', (
    tester,
  ) async {
    final callbacks = _Callbacks();
    await tester.pumpWidget(
      _wrap(callbacks, review: _review.copyWith(mergeable: .conflicting)),
    );

    await tester.tap(find.text('Create Merge Commit'));
    await tester.pumpAndSettle();
    expect(find.text('Create Merge Commit PR #42?'), findsNothing);

    await tester.tap(find.byTooltip('Pull Request Actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close Pull Request'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close Pull Request'));
    await tester.pumpAndSettle();

    expect(find.text('Close Pull Request #42?'), findsOneWidget);
  });

  testWidgets('omits close when the provider does not support it', (
    tester,
  ) async {
    final callbacks = _Callbacks();
    await tester.pumpWidget(_wrap(callbacks, canCloseReview: false));

    await tester.tap(find.byTooltip('Pull Request Actions'));
    await tester.pumpAndSettle();

    expect(find.text('Close Pull Request'), findsNothing);
    expect(find.text('Unlink Pull Request'), findsOneWidget);
  });

  testWidgets('disables the unified action control while work is in flight', (
    tester,
  ) async {
    final callbacks = _Callbacks();
    await tester.pumpWidget(_wrap(callbacks));
    await tester.tap(find.byTooltip('Pull Request Actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unlink Pull Request'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_wrap(callbacks, action: .unlink));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.text('Unlink Pull Request'));
    await tester.tap(find.byTooltip('Pull Request Actions'));
    await tester.pump();

    expect(find.text('Unlink Pull Request #42?'), findsNothing);
    expect(callbacks.unlinkCalls, 0);
  });

  testWidgets('shows a single unlink action after the PR is merged', (
    tester,
  ) async {
    final callbacks = _Callbacks();
    await tester.pumpWidget(
      _wrap(callbacks, review: _review.copyWith(state: .merged)),
    );

    expect(find.text('Create Merge Commit'), findsNothing);
    expect(find.text('Close Pull Request'), findsNothing);
    expect(find.text('Unlink Pull Request'), findsOneWidget);
    expect(find.byTooltip('Pull Request Actions'), findsNothing);

    await tester.tap(find.text('Unlink Pull Request'));
    await tester.pumpAndSettle();
    expect(find.text('Unlink Pull Request #42?'), findsOneWidget);
  });

  testWidgets('edit mode sends only the changed fields on save', (
    tester,
  ) async {
    final callbacks = _Callbacks();
    await tester.pumpWidget(_wrap(callbacks));

    await tester.tap(find.byTooltip('Edit Pull Request'));
    await tester.pumpAndSettle();

    final titleField = find.byType(TextField);
    expect(titleField, findsOneWidget);
    expect(
      tester.widget<TextField>(titleField).controller?.text,
      'feat: original',
    );
    expect(find.text('Base Branch'), findsOneWidget);

    await tester.enterText(titleField, 'feat: renamed');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(callbacks.lastInput?.title, 'feat: renamed');
    expect(callbacks.lastInput?.baseBranch, isNull);
    // Success closes the editor.
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('saving without changes just closes the editor', (tester) async {
    final callbacks = _Callbacks();
    await tester.pumpWidget(_wrap(callbacks));

    await tester.tap(find.byTooltip('Edit Pull Request'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(callbacks.lastInput, isNull);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('a failed update keeps the editor open', (tester) async {
    final callbacks = _Callbacks()
      ..updateResult = const UpdateReviewFailure(
        code: .unknown,
        message: 'permission denied',
      );
    await tester.pumpWidget(_wrap(callbacks));

    await tester.tap(find.byTooltip('Edit Pull Request'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'feat: renamed');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('summary shows head and base branches', (tester) async {
    final callbacks = _Callbacks();
    await tester.pumpWidget(_wrap(callbacks));

    expect(find.text('leynier · feature → main'), findsOneWidget);
  });

  testWidgets('shows conversation and inline review comments', (tester) async {
    final callbacks = _Callbacks();
    await tester.pumpWidget(
      _wrap(
        callbacks,
        comments: <ReviewComment>[
          ReviewComment(
            id: '1',
            author: 'alice',
            body: 'General feedback',
            createdAt: .utc(2026, 7, 16, 12),
            kind: .conversation,
          ),
          ReviewComment(
            id: '2',
            author: 'bob',
            body: 'Please cover this branch',
            createdAt: .utc(2026, 7, 16, 13),
            kind: .review,
            path: 'lib/src/example.dart',
            line: 42,
            resolved: true,
          ),
        ],
      ),
    );

    expect(find.text('Comments (2)'), findsOneWidget);
    expect(find.byType(PullRequestCommentMarkdown), findsNWidgets(2));
    expect(find.text('General feedback'), findsOneWidget);
    expect(find.text('Please cover this branch'), findsOneWidget);
    expect(find.text('lib/src/example.dart:42'), findsOneWidget);
    expect(find.text('Resolved'), findsOneWidget);
  });

  testWidgets('posts a comment and closes the composer on success', (
    tester,
  ) async {
    final callbacks = _Callbacks();
    await tester.pumpWidget(_wrap(callbacks));

    await tester.tap(find.byTooltip('Start Conversation'));
    await tester.pumpAndSettle();
    expect(find.text('Post Comment'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Ready to merge');
    await tester.tap(find.widgetWithText(FilledButton, 'Post Comment'));
    await tester.pumpAndSettle();

    expect(callbacks.commentBodies, <String>['Ready to merge']);
    expect(find.text('Post Comment'), findsNothing);
  });

  testWidgets('keeps the comment draft open when posting fails', (
    tester,
  ) async {
    final callbacks = _Callbacks()..addCommentResult = false;
    await tester.pumpWidget(_wrap(callbacks));

    await tester.tap(find.byTooltip('Start Conversation'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Keep this draft');
    await tester.tap(find.widgetWithText(FilledButton, 'Post Comment'));
    await tester.pumpAndSettle();

    expect(find.text('Post Comment'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'Keep this draft',
    );
  });

  testWidgets('comments are read-only after the PR is merged', (tester) async {
    final callbacks = _Callbacks();
    await tester.pumpWidget(
      _wrap(callbacks, review: _review.copyWith(state: .merged)),
    );

    expect(find.byTooltip('Start Conversation'), findsNothing);
    expect(find.text('No comments yet'), findsOneWidget);
  });
}
