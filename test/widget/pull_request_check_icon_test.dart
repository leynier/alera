import 'package:alera/src/features/pull_requests/domain/review_check.dart';
import 'package:alera/src/features/pull_requests/presentation/pull_request_check_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

// MaterialApp's page transition contains its own RotationTransition, so all
// finders stay scoped to the icon under test.
Finder _iconRotation() => find.descendant(
  of: find.byType(PullRequestCheckIcon),
  matching: find.byType(RotationTransition),
);

void main() {
  testWidgets('running check rotates its loader icon', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const PullRequestCheckIcon(
          status: ReviewCheckStatus.inProgress,
          conclusion: ReviewCheckConclusion.pending,
        ),
      ),
    );

    final rotation = tester.widget<RotationTransition>(_iconRotation());
    final before = rotation.turns.value;
    await tester.pump(const Duration(milliseconds: 300));
    expect(rotation.turns.value, isNot(before));
  });

  testWidgets('completed check renders a static icon', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const PullRequestCheckIcon(
          status: ReviewCheckStatus.completed,
          conclusion: ReviewCheckConclusion.success,
        ),
      ),
    );
    expect(_iconRotation(), findsNothing);
    expect(
      find.descendant(
        of: find.byType(PullRequestCheckIcon),
        matching: find.byType(Icon),
      ),
      findsOneWidget,
    );
  });

  testWidgets('stops spinning when the check completes', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const PullRequestCheckIcon(
          status: ReviewCheckStatus.inProgress,
          conclusion: ReviewCheckConclusion.pending,
        ),
      ),
    );
    expect(_iconRotation(), findsOneWidget);

    await tester.pumpWidget(
      _wrap(
        const PullRequestCheckIcon(
          status: ReviewCheckStatus.completed,
          conclusion: ReviewCheckConclusion.failure,
        ),
      ),
    );
    await tester.pump();
    expect(_iconRotation(), findsNothing);
  });
}
