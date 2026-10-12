import 'package:alera/src/features/activity/application/activity_navigation.dart';
import 'package:alera/src/features/inbox/presentation/ask_agent_dialog.dart';
import 'package:alera/src/features/inbox/presentation/question_status.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/questions_harness.dart';

Future<void> _openAndFill(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey<String>('activityPrimaryAction')));
  await tester.pumpAndSettle();
  expect(find.byType(AskAgentDialog), findsOneWidget);
  await tester.tap(find.byKey(const ValueKey<String>('inboxComposerTarget')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Claude: Fix Login').last);
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey<String>('inboxComposerBody')),
    'Which tests cover login?',
  );
  await tester.pump();
}

Future<void> _ask(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey<String>('inboxComposerSend')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an inboxV1 host gets no delivery and reports host errors', (
    tester,
  ) async {
    final client = questionsTestClient();
    var attempts = 0;
    client.handlers['inbox.ask'] = (_) {
      attempts++;
      if (attempts == 1) {
        throw const TerminalHostConflictException(
          code: 'inbox_pending_limit',
          message: 'limit',
        );
      }
      return <String, Object?>{'threadId': 'msg_new'};
    };
    final container = await pumpQuestionsActivity(tester, client);
    await tester.tap(
      find.byKey(const ValueKey<String>('activityPrimaryAction')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('inboxComposerTarget')));
    await tester.pumpAndSettle();
    // Grouped by workspace, each target saying how a question reaches it.
    expect(find.text('ws-1'), findsOneWidget);
    expect(find.text('Delivers when its turn ends'), findsOneWidget);
    await tester.tap(find.text('Claude: Fix Login').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('inboxComposerBody')),
      'Which tests cover login?',
    );
    await tester.pump();
    expect(find.text('Deliver'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(AskAgentDialog),
        matching: find.text(questionLegacyDeliveryCaption),
      ),
      findsOneWidget,
    );

    await _ask(tester);
    expect(
      find.text(
        'This agent already has 100 questions waiting. Wait for it to read them or cancel some.',
      ),
      findsOneWidget,
    );

    await _ask(tester);
    expect(find.byType(AskAgentDialog), findsNothing);
    expect(client.callsTo('inbox.ask').last, {
      'body': 'Which tests cover login?',
      'inbox': 'ext:user',
      'to': 'term-1',
    });
    expect(
      container.read(activityNavigationProvider).questions.selectedThreadId,
      'msg_new',
    );
  });

  testWidgets('an inboxV2 host gets the Deliver choice', (tester) async {
    final client = questionsTestClient(targetDeliveryMode: 'pasted_now')
      ..deliverySupported = true
      ..respond('inbox.ask', <String, Object?>{'threadId': 'msg_new'});
    await pumpQuestionsActivity(tester, client);
    await _openAndFill(tester);
    expect(find.text(questionDeliverNowHelper), findsOneWidget);
    await _ask(tester);
    expect(client.callsTo('inbox.ask').single, {
      'body': 'Which tests cover login?',
      'inbox': 'ext:user',
      'to': 'term-1',
      'delivery': 'now',
    });
  });

  testWidgets('Now is disabled for an agent that queues at turn end', (
    tester,
  ) async {
    final client = questionsTestClient(targetDeliveryMode: 'queued_at_turn_end')
      ..deliverySupported = true
      ..respond('inbox.ask', <String, Object?>{'threadId': 'msg_new'});
    await pumpQuestionsActivity(tester, client);
    await _openAndFill(tester);
    expect(
      find.textContaining('cannot take input while it works'),
      findsOneWidget,
    );
    expect(
      find.textContaining('receives the question when it finishes its turn'),
      findsOneWidget,
    );
    await tester.tap(find.text('Now'));
    await tester.pumpAndSettle();
    expect(find.text(questionDeliverNowHelper), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey<String>('inboxComposerAdvanced')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('inboxComposerExpiry')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 Day').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('within 1 day'), findsOneWidget);

    await _ask(tester);
    expect(client.callsTo('inbox.ask').single, {
      'body': 'Which tests cover login?',
      'inbox': 'ext:user',
      'to': 'term-1',
      'expiresInMs': const Duration(days: 1).inMilliseconds,
      'delivery': 'turnEnd',
    });
  });

  testWidgets('Cmd+Enter asks from the question field', (tester) async {
    final client = questionsTestClient()
      ..respond('inbox.ask', <String, Object?>{'threadId': 'msg_new'});
    await pumpQuestionsActivity(tester, client);
    await _openAndFill(tester);
    await tester.sendKeyDownEvent(.controlLeft);
    await tester.sendKeyEvent(.enter);
    await tester.sendKeyUpEvent(.controlLeft);
    await tester.pumpAndSettle();
    expect(client.callsTo('inbox.ask'), hasLength(1));
    expect(find.byType(AskAgentDialog), findsNothing);
  });
}
