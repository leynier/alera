import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/inbox/application/conversation_participant_labels.dart';
import 'package:alera/src/features/inbox/application/inbox_navigation.dart';
import 'package:alera/src/features/inbox/infra/runtime_inbox_repository.dart';
import 'package:alera/src/features/inbox/presentation/inbox_page.dart';
import 'package:alera/src/shared/infra/runtime/runtime_change_coalescer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/inbox_test_client.dart';

Map<String, Object?> _conversation({
  String threadId = 'thread_1',
  bool group = false,
  int count = 2,
}) => <String, Object?>{
  'threadId': threadId,
  'subject': group ? 'Status for everyone' : 'Schema question',
  'startedBy': 'term-coord',
  'participants': ['term-coord', 'term-worker'],
  'workspaceId': 'ws-1',
  'createdAt': '2026-10-06 10:00:00',
  'lastActivityAt': '2026-10-06 10:05:00',
  'lastSequence': 20,
  'messageCount': count,
  'group': group,
};

InboxTestClient _client() => InboxTestClient()
  ..respond('inbox.summary', const <String, Object?>{'items': <Object?>[]})
  ..respond('inbox.threads', const <String, Object?>{'items': <Object?>[]})
  ..respond('inbox.conversations', <String, Object?>{
    'kind': 'conversations',
    'items': [
      _conversation(),
      _conversation(threadId: 'thread_2', group: true, count: 1),
    ],
    'revision': 4,
  })
  ..respond('inbox.conversation', <String, Object?>{
    'threadId': 'thread_1',
    'messages': [
      {
        'id': 'msg_1',
        'from_handle': 'term-coord',
        'to_handle': 'term-worker',
        'type': 'decision_gate',
        'subject': 'Schema question',
        'body': 'Which column holds the owner?',
        'sequence': 18,
        'created_at': '2026-10-06 10:00:00',
      },
      {
        'id': 'msg_2',
        'from_handle': 'term-worker',
        'to_handle': 'term-coord',
        'type': 'status',
        'subject': 'Re: Schema question',
        'body': 'owner_id.',
        'sequence': 20,
        'created_at': '2026-10-06 10:05:00',
      },
    ],
    'revision': 4,
  });

Future<ProviderContainer> _pump(
  WidgetTester tester,
  InboxTestClient client,
) async {
  tester.view.physicalSize = const Size(1600, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      ...inboxClientOverrides(client),
      conversationParticipantLabelsProvider.overrideWithValue(
        const <String, String>{'term-coord': 'Coordinator (Codex)'},
      ),
      conversationWorkspaceNamesProvider.overrideWithValue(
        const <String, String>{'ws-1': 'Auth', 'ws-2': 'Billing'},
      ),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(client.events.close);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildAleraDarkTheme(),
        home: const Scaffold(body: InboxPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('agent conversations list participants and show messages', (
    tester,
  ) async {
    final client = _client();
    final container = await _pump(tester, client);
    expect(client.callsTo('inbox.conversations'), isEmpty);

    await tester.tap(find.text('Agent Conversations'));
    await tester.pumpAndSettle();
    expect(
      container.read(inboxNavigationProvider).view,
      InboxView.conversations,
    );
    expect(find.text('Schema question'), findsOneWidget);
    expect(find.text('Coordinator (Codex), term-worker'), findsNWidgets(2));
    expect(find.text('Group'), findsOneWidget);
    expect(find.textContaining('2 messages · Auth'), findsOneWidget);
    expect(find.textContaining('1 message · Auth'), findsOneWidget);
    expect(find.text('New Question'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('inboxPurge')), findsNothing);

    await tester.tap(find.text('Schema question'));
    await tester.pumpAndSettle();
    expect(find.text('Which column holds the owner?'), findsOneWidget);
    expect(find.text('owner_id.'), findsOneWidget);
    expect(find.text('Coordinator (Codex) → term-worker'), findsOneWidget);
    expect(find.text('decision gate'), findsOneWidget);
    expect(client.callsTo('inbox.conversation').single, {
      'threadId': 'thread_1',
    });
    expect(
      client.calls.map((call) => call.$1),
      isNot(contains('inbox.markRead')),
    );

    final before = client.callsTo('inbox.conversations').length;
    client.emit('conversationsChanged');
    await tester.pumpAndSettle();
    expect(client.callsTo('inbox.conversations').length, before + 1);

    container
        .read(inboxNavigationProvider.notifier)
        .filterConversationWorkspace('ws-2');
    await tester.pumpAndSettle();
    expect(client.callsTo('inbox.conversations').last, {
      'workspaceId': 'ws-2',
      'limit': 100,
    });
    expect(
      container.read(inboxNavigationProvider).selectedConversationId,
      isNull,
    );
  });

  test('conversation payloads parse and watch their own event', () async {
    final client = _client();
    final coalescer = RuntimeChangeCoalescer(
      debounce: const Duration(milliseconds: 1),
      maxDelay: const Duration(milliseconds: 50),
    );
    addTearDown(coalescer.dispose);
    final repository = RuntimeInboxRepository(client, coalescer);
    final page = await repository.readConversations();
    expect(page.items.first.participants, ['term-coord', 'term-worker']);
    expect(page.items.last.group, isTrue);
    expect(page.items.first.lastActivityAt, DateTime.utc(2026, 10, 6, 10, 5));
    final detail = await repository.readConversation('thread_1');
    expect(detail.messages.map((message) => message.from), [
      'term-coord',
      'term-worker',
    ]);

    var reads = 0;
    final subscription = repository.watchConversations().listen((_) => reads++);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    client.emit('inboxChanged');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    client.emit('conversationsChanged');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await subscription.cancel();
    await client.events.close();
    expect(reads, 2);
  });

  testWidgets('conversations page with Load More and reset on refresh', (
    tester,
  ) async {
    final client = _client();
    client.handlers['inbox.conversations'] = (payload) =>
        payload['before'] == 20
        ? <String, Object?>{
            'items': [
              _conversation(),
              {..._conversation(threadId: 'thread_9'), 'subject': 'Old talk'},
            ],
            'nextBefore': null,
          }
        : <String, Object?>{
            'items': [_conversation()],
            'nextBefore': 20,
          };
    final container = await _pump(tester, client);
    container
        .read(inboxNavigationProvider.notifier)
        .showView(InboxView.conversations);
    await tester.pumpAndSettle();
    expect(find.text('Old talk'), findsNothing);
    await tester.tap(find.text('Load More'));
    await tester.pumpAndSettle();
    expect(client.callsTo('inbox.conversations').last, {
      'limit': 100,
      'before': 20,
    });
    expect(find.text('Schema question'), findsOneWidget);
    expect(find.text('Old talk'), findsOneWidget);
    expect(find.text('Load More'), findsNothing);
    client.emit('conversationsChanged');
    await tester.pumpAndSettle();
    expect(find.text('Old talk'), findsNothing);
    expect(find.text('Load More'), findsOneWidget);
  });

  testWidgets('a question sent from the conversations view opens Questions', (
    tester,
  ) async {
    final client = _client()
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
      })
      ..respond('inbox.ask', const <String, Object?>{'threadId': 'msg_q1'})
      ..respond('inbox.thread', inboxDetailJson());
    final container = await _pump(tester, client);
    await tester.tap(find.text('Agent Conversations'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Schema question'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New Question'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('inboxComposerTarget')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Claude: Fix Login').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('inboxComposerBody')),
      'Is login covered?',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('inboxComposerSend')));
    await tester.pumpAndSettle();
    expect(container.read(inboxNavigationProvider).view, InboxView.questions);
    expect(find.text('What could break?'), findsOneWidget);
    expect(find.text('Which column holds the owner?'), findsNothing);
  });
}
