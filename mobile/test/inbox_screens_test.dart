import 'package:alera_mobile/src/features/inbox/application/mobile_inbox_providers.dart';
import 'package:alera_mobile/src/features/inbox/presentation/inbox_compose_screen.dart';
import 'package:alera_mobile/src/features/inbox/presentation/inbox_screen.dart';
import 'package:alera_mobile/src/features/inbox/presentation/inbox_thread_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_inbox_client.dart';

Widget _app(FakeInboxClient client, Widget child) => ProviderScope(
  overrides: [
    mobileInboxClientProvider('host').overrideWith((ref) async => client),
  ],
  child: MaterialApp(home: child),
);

void main() {
  testWidgets('lists threads with status, recipient and unread replies', (
    tester,
  ) async {
    final client = FakeInboxClient()
      ..threads = [
        inboxThreadJson(unread: 2),
        inboxThreadJson(
          threadId: 'msg_2',
          inbox: 'ext:ci',
          status: 'answered',
          subject: 'Release notes?',
        ),
      ];
    addTearDown(client.dispose);
    await tester.pumpWidget(_app(client, const InboxScreen(hostId: 'host')));
    await tester.pumpAndSettle();
    expect(find.text('Which tests cover login?'), findsOneWidget);
    expect(find.text('2 New Replies'), findsOneWidget);
    expect(find.text('claude · Fix Login'), findsNWidgets(2));
    expect(find.text('Release notes?'), findsOneWidget);
    expect(find.text('Ask Agent'), findsOneWidget);

    await tester.tap(find.text('ext:ci').first);
    await tester.pumpAndSettle();
    expect(find.text('Which tests cover login?'), findsNothing);
    expect(find.text('Release notes?'), findsOneWidget);
  });

  testWidgets('an empty inbox invites asking an agent', (tester) async {
    final client = FakeInboxClient()..threads = [];
    addTearDown(client.dispose);
    await tester.pumpWidget(_app(client, const InboxScreen(hostId: 'host')));
    await tester.pumpAndSettle();
    expect(
      find.text('No questions yet. Ask an agent to start a conversation.'),
      findsOneWidget,
    );
  });

  testWidgets('purging an inbox asks for confirmation first', (tester) async {
    final client = FakeInboxClient();
    addTearDown(client.dispose);
    await tester.pumpWidget(_app(client, const InboxScreen(hostId: 'host')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More Actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Purge ext:user'));
    await tester.pumpAndSettle();
    expect(client.callsOf('inbox.purge'), isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, 'Purge'));
    await tester.pumpAndSettle();
    expect(client.callsOf('inbox.purge').single.payload, <String, Object?>{
      'inbox': 'ext:user',
    });
  });

  testWidgets('a thread shows its messages, marks read and cancels a pending '
      'question', (tester) async {
    final client = FakeInboxClient()
      ..threads = [inboxThreadJson(status: 'pending')];
    addTearDown(client.dispose);
    await tester.pumpWidget(
      _app(client, const InboxThreadScreen(hostId: 'host', threadId: 'msg_1')),
    );
    await tester.pumpAndSettle();
    expect(
      client.callsOf('inbox.thread').first.payload.containsKey('markRead'),
      isFalse,
    );
    expect(find.text('Question'), findsOneWidget);
    expect(find.text('To claude · Fix Login'), findsOneWidget);
    expect(
      find.text('From ext:user via Alera mobile on Pixel'),
      findsOneWidget,
    );
    expect(find.textContaining('Expires in'), findsOneWidget);
    expect(
      find.textContaining(
        'Questions reach this agent when it finishes its turn.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(TextButton, 'Cancel Question'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Cancel Question'));
    await tester.pumpAndSettle();
    expect(client.callsOf('inbox.cancel').single.payload, <String, Object?>{
      'questionId': 'msg_1',
    });
  });

  testWidgets('a follow-up continues the thread', (tester) async {
    final client = FakeInboxClient()
      ..messages['msg_1'] = [inboxMessageJson(status: 'delivered')];
    addTearDown(client.dispose);
    await tester.pumpWidget(
      _app(client, const InboxThreadScreen(hostId: 'host', threadId: 'msg_1')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Cancel Question'), findsNothing);
    await tester.enterText(find.byType(TextField), 'And the rollback?');
    await tester.tap(find.byTooltip('Send Follow-Up'));
    await tester.pumpAndSettle();
    final ask = client.callsOf('inbox.ask').single.payload;
    expect(ask['threadId'], 'msg_1');
    expect(ask['body'], 'And the rollback?');
  });

  testWidgets('the composer asks the chosen agent and returns the thread', (
    tester,
  ) async {
    final client = FakeInboxClient();
    addTearDown(client.dispose);
    String? result;
    await tester.pumpWidget(
      _app(
        client,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await Navigator.of(context).push<String>(
                MaterialPageRoute<String>(
                  builder: (_) => const InboxComposeScreen(
                    hostId: 'host',
                    workspaceId: 'ws-1',
                    preselectedHandle: 'codex-term',
                  ),
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('claude · Fix Login'), findsOneWidget);
    expect(find.text('codex · Review'), findsOneWidget);
    expect(
      client.callsOf('inbox.targets').single.payload['workspaceId'],
      'ws-1',
    );
    await tester.enterText(find.byType(TextField).last, 'What changed?');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    final ask = client.callsOf('inbox.ask').single.payload;
    expect(ask['to'], 'codex-term');
    expect(ask['inbox'], 'ext:user');
    expect(ask['body'], 'What changed?');
    expect(result, 'msg_new');
  });

  testWidgets('a preselected terminal that is not an agent is not used', (
    tester,
  ) async {
    final client = FakeInboxClient();
    addTearDown(client.dispose);
    await tester.pumpWidget(
      _app(
        client,
        const InboxComposeScreen(hostId: 'host', preselectedHandle: 'shell'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Hello?');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(client.callsOf('inbox.ask'), isEmpty);
  });

  testWidgets('a follow-up in a CLI thread keeps the thread inbox', (
    tester,
  ) async {
    final client = FakeInboxClient()
      ..threads = [inboxThreadJson(inbox: 'ext:ci')]
      ..messages['msg_1'] = [
        inboxMessageJson(from: 'ext:ci', status: 'delivered'),
      ];
    addTearDown(client.dispose);
    await tester.pumpWidget(
      _app(client, const InboxThreadScreen(hostId: 'host', threadId: 'msg_1')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Any update?');
    await tester.tap(find.byTooltip('Send Follow-Up'));
    await tester.pumpAndSettle();
    final ask = client.callsOf('inbox.ask').single.payload;
    expect(ask['threadId'], 'msg_1');
    expect(ask.containsKey('inbox'), isFalse);
    expect(find.textContaining('Could not send the follow-up'), findsNothing);
  });

  testWidgets('the thread list loads more pages and restarts on a filter', (
    tester,
  ) async {
    final client = FakeInboxClient()
      ..threads = [
        for (var index = 0; index < inboxThreadPageSize + 3; index++)
          inboxThreadJson(
            threadId: 'msg_$index',
            subject: 'Question $index',
            lastSequence: 1000 - index,
            status: index.isEven ? 'delivered' : 'answered',
          ),
      ];
    addTearDown(client.dispose);
    await tester.pumpWidget(_app(client, const InboxScreen(hostId: 'host')));
    await tester.pumpAndSettle();
    final loadMore = find.text('Load More');
    await tester.scrollUntilVisible(loadMore, 400);
    client.failure = StateError('host is gone');
    await tester.tap(loadMore);
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not load more'), findsOneWidget);
    expect(loadMore, findsOneWidget);
    client.failure = null;
    ScaffoldMessenger.of(tester.element(loadMore)).hideCurrentSnackBar();
    await tester.pumpAndSettle();
    await tester.tap(loadMore);
    await tester.pumpAndSettle();
    expect(find.text('Load More'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Question ${inboxThreadPageSize + 2}'),
      400,
    );
    expect(
      client.callsOf('inbox.threads').last.payload['before'],
      1000 - inboxThreadPageSize + 1,
    );

    await tester.drag(find.byType(Scrollable).first, const Offset(0, 20000));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Answered').first);
    await tester.pumpAndSettle();
    final filtered = client.callsOf('inbox.threads').last.payload;
    expect(filtered['status'], 'answered');
    expect(filtered.containsKey('before'), isFalse);
  });
}
