import 'package:alera/src/features/session/domain/pending_user_input.dart';
import 'package:alera/src/features/session/presentation/widgets/user_input_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpCard(
  WidgetTester tester, {
  required PendingUserInput pendingUserInput,
  required ValueChanged<Map<String, dynamic>> onSubmit,
  required VoidCallback onDismiss,
  Duration settleDuration = const Duration(milliseconds: 10),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: UserInputCard(
            pendingUserInput: pendingUserInput,
            onSubmit: onSubmit,
            onDismiss: onDismiss,
          ),
        ),
      ),
    ),
  );
  await tester.pump(settleDuration);
}

void main() {
  testWidgets(
    'local fallback submits with default yes option without manual selection',
    (tester) async {
      Map<String, dynamic>? submittedAnswers;
      var submitCount = 0;
      var dismissCount = 0;
      await _pumpCard(
        tester,
        pendingUserInput: const PendingUserInput(
          requestId: 'local-plan-fallback-turn-1',
          threadId: 'thread-1',
          turnId: 'turn-1',
          itemId: 'turn-1-local-plan-fallback',
          questions: <UserInputQuestion>[
            UserInputQuestion(
              id: 'implement_plan',
              header: 'Implementation',
              question: 'Implement this plan?',
              isOther: true,
              options: <UserInputOption>[
                UserInputOption(
                  label: 'Yes, implement this plan',
                  description: 'Proceed with implementation',
                ),
              ],
              otherLabel: 'No, and tell Alera what to do differently',
            ),
          ],
          source: PendingUserInputSource.localPlanFallback,
          localPlanTurnId: 'turn-1',
        ),
        onSubmit: (answers) {
          submittedAnswers = answers;
          submitCount += 1;
        },
        onDismiss: () => dismissCount += 1,
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Submit'));
      await tester.pump();

      expect(submitCount, 1);
      expect(dismissCount, 0);
      expect(submittedAnswers, isNotNull);
      expect(submittedAnswers?['implement_plan'], <String, dynamic>{
        'answers': <String>['Yes, implement this plan'],
      });
    },
  );

  testWidgets('backend form blocks submit until required text is provided', (
    tester,
  ) async {
    Map<String, dynamic>? submittedAnswers;
    var submitCount = 0;
    await _pumpCard(
      tester,
      pendingUserInput: const PendingUserInput(
        requestId: 4001,
        threadId: 'thread-1',
        turnId: 'turn-1',
        itemId: 'item-1',
        questions: <UserInputQuestion>[
          UserInputQuestion(
            id: 'free_text',
            header: 'Implementation',
            question: 'Describe what should change',
          ),
        ],
      ),
      onSubmit: (answers) {
        submittedAnswers = answers;
        submitCount += 1;
      },
      onDismiss: () {},
    );

    final submitFinder = find.widgetWithText(FilledButton, 'Submit');
    var submitButton = tester.widget<FilledButton>(submitFinder);
    expect(submitButton.onPressed, isNull);

    await tester.tap(submitFinder);
    await tester.pump();
    expect(submitCount, 0);

    await tester.enterText(find.byType(TextField), 'Please proceed');
    await tester.pump();

    submitButton = tester.widget<FilledButton>(submitFinder);
    expect(submitButton.onPressed, isNotNull);

    await tester.tap(submitFinder);
    await tester.pump();
    expect(submitCount, 1);
    expect(submittedAnswers?['free_text'], <String, dynamic>{
      'answers': <String>['Please proceed'],
    });
  });
}
