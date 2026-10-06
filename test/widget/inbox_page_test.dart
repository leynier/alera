import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/inbox/application/inbox_navigation.dart';
import 'package:alera/src/features/inbox/presentation/inbox_attention_control.dart';
import 'package:alera/src/features/inbox/presentation/inbox_composer_dialog.dart';
import 'package:alera/src/features/inbox/presentation/inbox_page.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/inbox_test_client.dart';

InboxTestClient _client() => InboxTestClient()
  ..respond('inbox.summary', <String, Object?>{
    'items': [
      {'inbox': 'ext:user', 'threadCount': 2, 'unreadReplyCount': 1},
      {'inbox': 'ext:ci', 'threadCount': 1, 'unreadReplyCount': 0},
    ],
    'revision': 3,
  })
  ..respond('inbox.threads', <String, Object?>{
    'items': [
      inboxThreadJson(status: 'answered', unread: 1),
      inboxThreadJson(
        threadId: 'msg_q2',
        status: 'pending',
        subject: 'Rollback plan',
      ),
    ],
    'revision': 3,
  })
  ..respond('inbox.targets', <String, Object?>{
    'items': [
      {
        'handle': 'term-1',
        'sessionLive': true,
        'workspaceId': 'ws-1',
        'agent': 'claude',
        'deliveryMode': 'paste',
        'tabTitle': 'Fix Login',
      },
    ],
  });

Future<ProviderContainer> _pumpPage(
  WidgetTester tester,
  InboxTestClient client, {
  Widget child = const InboxPage(),
}) async {
  tester.view.physicalSize = const Size(1600, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(overrides: inboxClientOverrides(client));
  addTearDown(container.dispose);
  addTearDown(client.events.close);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildAleraDarkTheme(),
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('selecting a thread shows its messages', (tester) async {
    final client = _client()
      ..respond(
        'inbox.thread',
        inboxDetailJson(
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
        ),
      );
    await _pumpPage(tester, client);
    expect(find.text('Migration risk'), findsOneWidget);
    expect(find.text('Rollback plan'), findsOneWidget);
    expect(find.text('Select A Question'), findsOneWidget);

    await tester.tap(find.text('Migration risk'));
    await tester.pumpAndSettle();
    expect(find.text('The session cache.'), findsOneWidget);
    expect(find.text('Question from ext:user'), findsOneWidget);
    expect(find.textContaining('via Alera mobile, Pixel'), findsOneWidget);
    expect(client.callsTo('inbox.thread').last, {
      'threadId': 'msg_q1',
      'markRead': false,
    });
    expect(find.text('Cancel Question'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey<String>('inboxFollowUpBody')),
      'And the rollback?',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('inboxFollowUpSend')));
    await tester.pumpAndSettle();
    expect(client.callsTo('inbox.ask').single, {
      'body': 'And the rollback?',
      'threadId': 'msg_q1',
    });
  });

  testWidgets('a pending question can be cancelled and explains delivery', (
    tester,
  ) async {
    final client = _client()
      ..respond(
        'inbox.thread',
        inboxDetailJson(status: 'pending', deliveryMode: 'unavailable'),
      );
    await _pumpPage(tester, client);
    await tester.tap(find.text('Rollback plan'));
    await tester.pumpAndSettle();
    expect(find.textContaining('does not report its turns'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('inboxCancelQuestion')));
    await tester.pumpAndSettle();
    expect(client.callsTo('inbox.cancel').single, {'questionId': 'msg_q1'});
  });

  testWidgets('the composer asks the chosen agent and reports host errors', (
    tester,
  ) async {
    final client = _client();
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
    final container = await _pumpPage(tester, client);
    await tester.tap(find.byKey(const ValueKey<String>('inboxNewQuestion')));
    await tester.pumpAndSettle();
    expect(find.byType(InboxComposerDialog), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('inboxComposerTarget')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Claude: Fix Login').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('inboxComposerBody')),
      'Which tests cover login?',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('inboxComposerSend')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('already has 20 questions waiting'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey<String>('inboxComposerSend')));
    await tester.pumpAndSettle();
    expect(find.byType(InboxComposerDialog), findsNothing);
    expect(client.callsTo('inbox.ask').last, {
      'body': 'Which tests cover login?',
      'inbox': 'ext:user',
      'to': 'term-1',
    });
    expect(container.read(inboxNavigationProvider).selectedThreadId, 'msg_new');
  });

  testWidgets('purging the filtered inbox asks for confirmation', (
    tester,
  ) async {
    final client = _client();
    final container = await _pumpPage(tester, client);
    expect(find.byKey(const ValueKey<String>('inboxPurge')), findsNothing);
    container.read(inboxNavigationProvider.notifier).filterInbox('ext:ci');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('inboxPurge')));
    await tester.pumpAndSettle();
    expect(find.text('Purge Inbox?'), findsOneWidget);
    await tester.tap(find.text('Purge'));
    await tester.pumpAndSettle();
    expect(client.callsTo('inbox.purge').single, {'inbox': 'ext:ci'});
    expect(container.read(inboxNavigationProvider).inboxFilter, isNull);
  });

  testWidgets('an old runtime shows an update notice', (tester) async {
    final client = _client()..supported = false;
    await _pumpPage(tester, client);
    expect(find.text('Update the runtime to use the inbox.'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('New Question'),
        matching: find.byWidgetPredicate((widget) => widget is FilledButton),
      ),
    );
    expect(button.onPressed, isNull);
    expect(client.calls, isEmpty);
  });

  testWidgets('the status bar control counts unread replies and opens', (
    tester,
  ) async {
    final client = _client();
    final container = await _pumpPage(
      tester,
      client,
      child: const Align(
        alignment: Alignment.bottomLeft,
        child: InboxAttentionControl(),
      ),
    );
    expect(find.byTooltip('Open Inbox · 1 Unread Reply'), findsOneWidget);
    await tester.tap(find.byType(TextButton));
    await tester.pump();
    expect(container.read(inboxNavigationProvider).visible, isTrue);
  });

  testWidgets('the status bar control hides on an old runtime', (tester) async {
    await _pumpPage(
      tester,
      _client()..supported = false,
      child: const InboxAttentionControl(),
    );
    expect(find.byType(TextButton), findsNothing);
  });
}
