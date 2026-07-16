import 'package:alera/src/features/pull_requests/application/workspace_pull_request_state.dart';
import 'package:alera/src/features/pull_requests/domain/git_hosting_provider.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/review_check.dart';
import 'package:alera/src/features/pull_requests/domain/review_check_details.dart';
import 'package:alera/src/features/pull_requests/domain/update_review_input.dart';
import 'package:alera/src/features/pull_requests/domain/update_review_result.dart';
import 'package:alera/src/features/pull_requests/presentation/pull_request_review_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _review = HostedReview(
  provider: GitHostingProvider.github,
  number: 42,
  title: 'feat: original',
  state: HostedReviewState.open,
  url: 'https://github.com/leynier/alera/pull/42',
  author: 'leynier',
  baseBranch: 'main',
  headBranch: 'feature',
);

class _Callbacks {
  int unlinkCalls = 0;
  UpdateReviewInput? lastInput;
  UpdateReviewResult updateResult = const UpdateReviewSuccess(_review);
}

Widget _wrap(
  _Callbacks callbacks, {
  PullRequestAction? action,
  List<ReviewCheck> checks = const <ReviewCheck>[],
}) {
  return MaterialApp(
    home: Scaffold(
      body: PullRequestReviewView(
        review: _review,
        checks: checks,
        baseBranches: const <String>['develop', 'main'],
        action: action,
        onOpenUrl: (_) async {},
        onUnlink: () => callbacks.unlinkCalls++,
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
  testWidgets('shows a labeled Unlink button at the bottom', (tester) async {
    final callbacks = _Callbacks();
    await tester.pumpWidget(_wrap(callbacks));

    final unlink = find.widgetWithText(FilledButton, 'Unlink Pull Request');
    expect(unlink, findsOneWidget);
    await tester.tap(unlink);
    expect(callbacks.unlinkCalls, 1);
  });

  testWidgets('disables Unlink while an action is in flight', (tester) async {
    final callbacks = _Callbacks();
    await tester.pumpWidget(
      _wrap(callbacks, action: PullRequestAction.unlink),
    );

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Unlink Pull Request'),
    );
    expect(button.onPressed, isNull);
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
        code: UpdateReviewErrorCode.unknown,
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
}
