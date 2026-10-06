import 'package:alera_mobile/src/features/inbox/application/mobile_inbox_providers.dart';
import 'package:alera_mobile/src/features/inbox/domain/agent_conversation_models.dart';
import 'package:alera_mobile/src/features/inbox/infra/mobile_runtime_inbox_repository.dart';
import 'package:alera_mobile/src/features/inbox/presentation/inbox_entry_points.dart';
import 'package:alera_mobile/src/features/inbox/presentation/inbox_screen.dart';
import 'package:alera_mobile/src/features/inbox/presentation/inbox_thread_screen.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_inbox_client.dart';

const Set<String> _readOnlyVerbs = <String>{
  'inbox.conversations',
  'inbox.conversation',
  'inbox.targets',
  'inbox.threads',
  'inbox.summary',
};

FakeInboxClient _client() => FakeInboxClient()
  ..workspaces = const <WorkspaceSummary>[
    WorkspaceSummary(id: 'ws-1', projectId: 'p', name: 'Auth', path: '/a'),
    WorkspaceSummary(id: 'ws-2', projectId: 'p', name: 'Billing', path: '/b'),
  ];

Widget _app(FakeInboxClient client) => ProviderScope(
  overrides: [
    mobileInboxClientProvider('host').overrideWith((ref) async => client),
  ],
  child: const MaterialApp(home: InboxScreen(hostId: 'host')),
);

Future<void> _openConversations(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.tap(find.text('Agent Conversations'));
  await tester.pumpAndSettle();
}

void main() {
  test('parses conversations and their messages', () {
    final conversation = AgentConversation.fromJson(
      agentConversationJson(group: true, messageCount: 3),
    );
    expect(conversation.group, isTrue);
    expect(conversation.participants, <String>['claude-term', 'codex-term']);
    expect(conversation.messageCount, 3);
    expect(conversation.lastActivityAt, DateTime.utc(2026, 10, 6, 9, 30));

    final message = AgentConversationMessage.fromJson(agentMessageJson());
    expect(message.from, 'claude-term');
    expect(message.typeLabel, 'Decision Gate');
    expect(
      agentConversationHandleLabel('codex-term', <String, String>{
        'codex-term': 'codex · Review',
      }),
      'codex · Review',
    );
    expect(agentConversationHandleLabel('shell', const {}), 'shell');
  });

  test('repository reads conversations with the runtime contract', () async {
    final client = _client();
    addTearDown(client.dispose);
    final repository = MobileRuntimeInboxRepository(client);
    final page = await repository.conversations(workspaceId: 'ws-2');
    expect(page.items.single.threadId, 'thread_2');
    expect(client.callsOf('inbox.conversations').single.payload, {
      'workspaceId': 'ws-2',
      'limit': 100,
    });
    final detail = await repository.conversation('thread_1');
    expect(detail.messages, hasLength(2));
    expect(client.callsOf('inbox.conversation').single.payload, {
      'threadId': 'thread_1',
    });
  });

  test('conversations reload on conversationsChanged only', () async {
    final client = _client();
    addTearDown(client.dispose);
    final container = ProviderContainer(
      overrides: [
        mobileInboxClientProvider('host').overrideWith((ref) async => client),
      ],
    );
    addTearDown(container.dispose);
    final provider = mobileAgentConversationsProvider('host');
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    expect((await container.read(provider.future)).items, hasLength(2));
    client.emit(inboxChangedEvent);
    await Future<void>.delayed(Duration.zero);
    expect(client.callsOf('inbox.conversations'), hasLength(1));
    client.conversations = [agentConversationJson()];
    client.emit(conversationsChangedEvent, {'revision': 8});
    await Future<void>.delayed(Duration.zero);
    expect((await container.read(provider.future)).items, hasLength(1));
  });

  testWidgets('the inbox lists agent conversations with names and groups', (
    tester,
  ) async {
    final client = _client();
    addTearDown(client.dispose);
    await tester.pumpWidget(_app(client));
    await _openConversations(tester);
    expect(find.text('Split the migration'), findsOneWidget);
    expect(find.text('claude · Fix Login, codex · Review'), findsOneWidget);
    expect(
      find.text('claude · Fix Login, codex · Review, shell-term'),
      findsOneWidget,
    );
    expect(find.text('Group'), findsOneWidget);
    expect(find.textContaining('3 messages · Billing'), findsOneWidget);
    expect(find.text('Ask Agent'), findsNothing);
    expect(find.byTooltip('More Actions'), findsNothing);

    await tester.tap(find.text('Billing'));
    await tester.pumpAndSettle();
    expect(find.text('Split the migration'), findsNothing);
    expect(find.text('Status to everyone'), findsOneWidget);
    expect(
      client.callsOf('inbox.conversations').last.payload['workspaceId'],
      'ws-2',
    );
  });

  testWidgets('a conversation shows its messages in order and stays read '
      'only', (tester) async {
    final client = _client();
    addTearDown(client.dispose);
    await tester.pumpWidget(_app(client));
    await _openConversations(tester);
    await tester.tap(find.text('Split the migration'));
    await tester.pumpAndSettle();
    expect(
      find.text('Agents exchanged these messages. This view is read only.'),
      findsOneWidget,
    );
    final first = tester.getTopLeft(find.text('Can you take the schema half?'));
    final second = tester.getTopLeft(find.text('Taking it.'));
    expect(first.dy, lessThan(second.dy));
    expect(find.text('claude · Fix Login to codex · Review'), findsOneWidget);
    expect(find.text('Decision Gate'), findsOneWidget);
    expect(find.text('Status'), findsOneWidget);
    expect(
      client.calls.map((call) => call.type).toSet().difference(_readOnlyVerbs),
      isEmpty,
    );
  });

  testWidgets('the conversation list loads more pages', (tester) async {
    final client = _client()
      ..conversations = [
        for (var index = 0; index < inboxThreadPageSize + 2; index++)
          agentConversationJson(
            threadId: 'thread_$index',
            subject: 'Topic $index',
            lastSequence: 500 - index,
          ),
      ];
    addTearDown(client.dispose);
    await tester.pumpWidget(_app(client));
    await _openConversations(tester);
    final loadMore = find.text('Load More');
    await tester.scrollUntilVisible(loadMore, 400);
    await tester.tap(loadMore);
    await tester.pumpAndSettle();
    expect(find.text('Load More'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Topic ${inboxThreadPageSize + 1}'),
      400,
    );
    expect(
      client.callsOf('inbox.conversations').last.payload['before'],
      500 - inboxThreadPageSize + 1,
    );
  });

  testWidgets('asking from a workspace switches the inbox to questions', (
    tester,
  ) async {
    final client = _client();
    addTearDown(client.dispose);
    final container = ProviderContainer(
      overrides: [
        mobileInboxClientProvider('host').overrideWith((ref) async => client),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(mobileInboxSectionControllerProvider('host').notifier)
        .select(InboxSection.conversations);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => askAgentAndOpenThread(
                context,
                ref,
                hostId: 'host',
                workspaceId: 'ws-1',
                preselectedHandle: 'claude-term',
              ),
              child: const Text('Ask From Workspace'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Ask From Workspace'));
    await tester.pumpAndSettle();
    expect(
      container.read(mobileInboxSectionControllerProvider('host')),
      InboxSection.questions,
    );
    await tester.enterText(find.byType(TextField).last, 'Ready?');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(find.byType(InboxThreadScreen), findsOneWidget);
  });
}
