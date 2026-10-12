import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/features/activity/application/activity_navigation.dart';
import 'package:alera/src/features/inbox/presentation/question_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/inbox_test_client.dart';
import '../support/questions_harness.dart';

Map<String, Object?> _answeredDetail() => inboxDetailJson(
  status: 'answered',
  messages: [
    inboxMessageJson(
      kind: 'question',
      id: 'msg_q1',
      body: 'What could break?',
      status: 'answered',
    ),
    inboxMessageJson(
      kind: 'reply',
      id: 'msg_r1',
      body: 'The session cache.',
      from: 'term-1',
      to: 'ext:user',
    ),
  ],
);

Future<void> _followUp(WidgetTester tester, String body) async {
  await tester.enterText(
    find.byKey(const ValueKey<String>('inboxFollowUpBody')),
    body,
  );
  await tester.pump();
}

void main() {
  testWidgets('selecting a thread shows its messages on an inboxV1 host', (
    tester,
  ) async {
    final client = questionsTestClient()
      ..respond('inbox.thread', _answeredDetail());
    await pumpQuestionsActivity(tester, client);
    expect(find.text('Migration risk'), findsOneWidget);
    expect(find.text('Rollback plan'), findsOneWidget);
    expect(find.text('Select A Question'), findsOneWidget);
    expect(find.text(questionLegacyDeliveryCaption), findsOneWidget);

    await tester.tap(find.text('Migration risk'));
    await tester.pumpAndSettle();
    expect(find.text('The session cache.'), findsOneWidget);
    expect(find.text('Question · ext:user'), findsOneWidget);
    expect(find.text('Reply · Claude'), findsOneWidget);
    expect(
      find.text('To Claude · Fix Login · Auth · from ext:user'),
      findsOneWidget,
    );
    expect(find.text('Asked from Alera mobile, Pixel'), findsOneWidget);
    expect(client.callsTo('inbox.thread').last, {
      'threadId': 'msg_q1',
      'markRead': false,
    });
    expect(find.text('Cancel Question'), findsNothing);
    expect(find.text('Deliver'), findsNothing);

    await _followUp(tester, 'And the rollback?');
    await tester.tap(find.byKey(const ValueKey<String>('inboxFollowUpSend')));
    await tester.pumpAndSettle();
    expect(client.callsTo('inbox.ask').single, {
      'body': 'And the rollback?',
      'threadId': 'msg_q1',
    });
  });

  testWidgets('a legacy received status renders as Delivered', (tester) async {
    final client = questionsTestClient(secondStatus: 'received')
      ..respond('inbox.thread', inboxDetailJson(status: 'received'));
    await pumpQuestionsActivity(tester, client);
    await tester.tap(find.text('Rollback plan'));
    await tester.pumpAndSettle();
    expect(find.text('Received'), findsNothing);
    // List row, header badge and question bubble.
    expect(find.text('Delivered'), findsNWidgets(3));
  });

  testWidgets('Cancel Question asks for confirmation first', (tester) async {
    final client = questionsTestClient()
      ..respond(
        'inbox.thread',
        inboxDetailJson(status: 'pending', deliveryMode: 'unavailable'),
      );
    await pumpQuestionsActivity(tester, client);
    await tester.tap(find.text('Rollback plan'));
    await tester.pumpAndSettle();
    expect(find.textContaining('does not report its turns'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('inboxCancelQuestion')));
    await tester.pumpAndSettle();
    expect(find.text('Cancel Question?'), findsOneWidget);
    await tester.tap(find.text('Keep Question'));
    await tester.pumpAndSettle();
    expect(client.callsTo('inbox.cancel'), isEmpty);

    await tester.tap(find.byKey(const ValueKey<String>('inboxCancelQuestion')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AleraConfirmDialog),
        matching: find.text('Cancel Question'),
      ),
    );
    await tester.pumpAndSettle();
    expect(client.callsTo('inbox.cancel').single, {'questionId': 'msg_q1'});
  });

  testWidgets('an inboxV2 follow-up sends the chosen delivery', (tester) async {
    final client = questionsTestClient()
      ..deliverySupported = true
      ..respond('inbox.thread', <String, Object?>{
        ..._answeredDetail(),
        'thread': <String, Object?>{
          ...inboxThreadJson(status: 'answered'),
          'deliveryMode': 'pasted_now',
        },
        'recipient': <String, Object?>{
          'handle': 'term-1',
          'sessionLive': true,
          'agent': 'claude',
          'deliveryMode': 'pasted_now',
          'acceptsQueuedInput': true,
        },
      });
    await pumpQuestionsActivity(tester, client);
    expect(find.text(questionLegacyDeliveryCaption), findsNothing);
    await tester.tap(find.text('Migration risk'));
    await tester.pumpAndSettle();
    expect(
      find.text('Asked from Alera mobile, Pixel · Delivered now'),
      findsOneWidget,
    );
    expect(find.text(questionDeliverNowHelper), findsOneWidget);

    await tester.tap(find.text('When the Agent Finishes Its Turn'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('receives the question when it finishes its turn'),
      findsOneWidget,
    );
    await _followUp(tester, 'And the rollback?');
    await tester.tap(find.byKey(const ValueKey<String>('inboxFollowUpSend')));
    await tester.pumpAndSettle();
    expect(client.callsTo('inbox.ask').single, {
      'body': 'And the rollback?',
      'threadId': 'msg_q1',
      'delivery': 'turnEnd',
    });
  });

  testWidgets('Cmd+Enter sends a follow-up', (tester) async {
    final client = questionsTestClient()
      ..respond('inbox.thread', _answeredDetail());
    await pumpQuestionsActivity(tester, client);
    await tester.tap(find.text('Migration risk'));
    await tester.pumpAndSettle();
    await _followUp(tester, 'Ship it?');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(client.callsTo('inbox.ask').single, {
      'body': 'Ship it?',
      'threadId': 'msg_q1',
    });
  });

  testWidgets('a follow-up to a closed terminal is disabled', (tester) async {
    final client = questionsTestClient()
      ..deliverySupported = true
      ..respond('inbox.thread', inboxDetailJson(sessionLive: false));
    await pumpQuestionsActivity(tester, client);
    await tester.tap(find.text('Migration risk'));
    await tester.pumpAndSettle();
    expect(find.textContaining('no longer running'), findsOneWidget);
    final send = tester.widget<ButtonStyleButton>(
      find.byKey(const ValueKey<String>('inboxFollowUpSend')),
    );
    expect(send.onPressed, isNull);
  });

  testWidgets('purging the filtered inbox asks for confirmation', (
    tester,
  ) async {
    final client = questionsTestClient();
    final container = await pumpQuestionsActivity(tester, client);
    expect(find.byKey(const ValueKey<String>('inboxPurge')), findsNothing);
    container.read(activityNavigationProvider.notifier).filterInbox('ext:ci');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('inboxPurge')));
    await tester.pumpAndSettle();
    expect(find.text('Purge Inbox?'), findsOneWidget);
    await tester.tap(find.text('Purge'));
    await tester.pumpAndSettle();
    expect(client.callsTo('inbox.purge').single, {'inbox': 'ext:ci'});
    expect(
      container.read(activityNavigationProvider).questions.inboxFilter,
      isNull,
    );
  });

  testWidgets('an old runtime shows an update notice', (tester) async {
    final client = questionsTestClient()..supported = false;
    await pumpQuestionsActivity(tester, client);
    expect(find.text('Update the runtime to use the inbox.'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Ask Agent'),
        matching: find.byWidgetPredicate((widget) => widget is FilledButton),
      ),
    );
    expect(button.onPressed, isNull);
    expect(client.calls, isEmpty);
  });
}
