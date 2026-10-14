import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera_mobile/src/features/chat_tasks/application/mobile_chat_task_providers.dart';
import 'package:alera_mobile/src/features/chat_tasks/presentation/chat_task_detail_screen.dart';
import 'package:alera_mobile/src/features/chat_tasks/presentation/chat_task_notice.dart';
import 'package:alera_mobile/src/features/runs/domain/activity_section.dart';
import 'package:alera_mobile/src/features/runs/presentation/activity_screen.dart';
import 'package:alera_mobile/src/features/runtime/domain/project_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/terminal/presentation/workspace_tabs_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_chat_task_transport.dart';

FakeChatTaskTransport _transport({bool orchestration = true}) =>
    FakeChatTaskTransport(orchestration: orchestration)
      ..tasks['task-input'] = chatTaskJson(
        taskId: 'task-input',
        status: 'needs_input',
        title: 'Approve the migration',
      )
      ..tasks['task-running'] = chatTaskJson(
        taskId: 'task-running',
        title: 'Review the parser',
      )
      ..tasks['task-done'] = chatTaskJson(
        taskId: 'task-done',
        status: 'completed',
        title: 'Write the changelog',
        parentChatId: null,
      );

Widget _app(
  FakeChatTaskTransport transport,
  Widget home, {
  bool supported = true,
}) {
  var ids = 0;
  return ProviderScope(
    overrides: [
      mobileChatTasksSupportedProvider('host')
          .overrideWith((ref) async => supported),
      mobileChatTaskRepositoryProvider('host').overrideWith(
        (ref) async => RuntimeAgentChatOrchestrationRepository(transport),
      ),
      agentChatRepositoryProvider('host')
          .overrideWith((ref) async => RuntimeAgentChatRepository(transport)),
      mobileChatTaskPlacesProvider('host').overrideWith(
        (ref) async => const MobileChatTaskPlaces(
          projects: <ProjectSummary>[
            ProjectSummary(id: 'project-1', name: 'alera', repoPath: '/a'),
          ],
          workspaces: <WorkspaceSummary>[
            WorkspaceSummary(
              id: 'ws-1',
              projectId: 'project-1',
              name: 'feature-oauth',
              path: '/a',
            ),
          ],
        ),
      ),
      mobileChatTaskIdGeneratorProvider.overrideWithValue(() => 'id-${ids++}'),
    ],
    child: MaterialApp(home: home),
  );
}

void main() {
  testWidgets('Chat Tasks groups tasks and a tap opens only the task', (
    tester,
  ) async {
    final transport = _transport();
    addTearDown(transport.dispose);
    await tester.pumpWidget(
      _app(
        transport,
        const ActivityScreen(
          hostId: 'host',
          initialSection: ActivitySection.chatTasks,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ATTENTION (1)'), findsOneWidget);
    expect(find.text('ACTIVE (1)'), findsOneWidget);
    expect(find.text('HISTORY (1)'), findsOneWidget);
    expect(find.text('Delegate Task'), findsOneWidget);

    await tester.tap(find.text('Review the parser'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatTaskDetailScreen), findsOneWidget);
    expect(find.text('Do Review the parser and report back.'), findsOneWidget);
    expect(find.byType(WorkspaceTabsScreen), findsNothing);
    expect(
      transport
          .sent(AgentChatOrchestrationWire.task)
          .where((payload) => payload['acknowledge'] == true),
      isEmpty,
    );
  });

  testWidgets('the detail acknowledges a person-owned result once', (
    tester,
  ) async {
    final transport = _transport();
    addTearDown(transport.dispose);
    await tester.pumpWidget(
      _app(
        transport,
        const ChatTaskDetailScreen(hostId: 'host', taskId: 'task-done'),
      ),
    );
    await tester.pumpAndSettle();
    final acknowledged = transport
        .sent(AgentChatOrchestrationWire.task)
        .where((payload) => payload['acknowledge'] == true);
    expect(acknowledged.single['taskId'], 'task-done');
  });

  testWidgets('cancel asks first, then cancels the task', (tester) async {
    final transport = _transport();
    addTearDown(transport.dispose);
    await tester.pumpWidget(
      _app(
        transport,
        const ChatTaskDetailScreen(hostId: 'host', taskId: 'task-running'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('chatTaskCancel')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep Task'));
    await tester.pumpAndSettle();
    expect(transport.sent(AgentChatOrchestrationWire.cancel), isEmpty);

    await tester.tap(find.byKey(const ValueKey<String>('chatTaskCancel')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Cancel Task'));
    await tester.pumpAndSettle();
    final cancel = transport.sent(AgentChatOrchestrationWire.cancel).single;
    expect(cancel, <String, Object?>{
      'requestId': 'id-0',
      'taskId': 'task-running',
    });
    expect(find.text('Cancelling'), findsOneWidget);
  });

  testWidgets('Delegate Task sends an explicit target and opens the task', (
    tester,
  ) async {
    final transport = _transport();
    addTearDown(transport.dispose);
    await tester.pumpWidget(
      _app(
        transport,
        const ActivityScreen(
          hostId: 'host',
          initialSection: ActivitySection.chatTasks,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delegate Task'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey<String>('delegateTask')),
        matching: find.byType(TextField),
      ),
      'Summarize the open pull requests',
    );
    await tester.tap(find.byKey(const ValueKey<String>('delegateProject')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('alera').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('delegateWorkspace')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('feature-oauth').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('delegateSubmit')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey<String>('delegateSubmit')));
    await tester.pumpAndSettle();

    final delegate = transport.sent(AgentChatOrchestrationWire.delegate).single;
    expect(delegate['mode'], 'async');
    expect(delegate['target'], <String, Object?>{
      'workspace': <String, Object?>{'workspaceId': 'ws-1'},
    });
    expect(delegate['agent'], <String, Object?>{
      'providerInstanceId': 'codex',
      'model': 'gpt-5',
    });
    expect(find.byType(ChatTaskDetailScreen), findsOneWidget);
    expect(find.byType(WorkspaceTabsScreen), findsNothing);
  });

  testWidgets('an older host shows Update Required and no Delegate Task', (
    tester,
  ) async {
    final transport = _transport(orchestration: false);
    addTearDown(transport.dispose);
    await tester.pumpWidget(
      _app(
        transport,
        const ActivityScreen(
          hostId: 'host',
          initialSection: ActivitySection.chatTasks,
        ),
        supported: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Update Required'), findsOneWidget);
    expect(find.text('Delegate Task'), findsNothing);
    expect(transport.requests, isEmpty);
  });

  testWidgets('chat notices show wake outcomes, the banner and the dock', (
    tester,
  ) async {
    final transport = _transport();
    addTearDown(transport.dispose);
    await tester.pumpWidget(
      _app(
        transport,
        const Scaffold(
          body: Column(
            children: <Widget>[
              ChatTaskOriginNotice(
                hostId: 'host',
                chatId: 'chat-parent',
                origin: AgentChatItemOrigin(
                  kind: AgentChatItemOriginKind.orchestrationWake,
                  taskIds: <String>['task-done'],
                ),
              ),
              ChatTasksForChat(hostId: 'host', chatId: 'chat-parent'),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Write the changelog'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('chatTaskOutcome:task-done')),
      findsOneWidget,
    );
    expect(find.text('Tasks · 1 running · 1 needs input'), findsOneWidget);
    expect(
      find.text('Task needs input: Approve the migration'),
      findsOneWidget,
    );
    expect(find.text('Review the parser'), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('chatTaskDockToggle')));
    await tester.pumpAndSettle();
    expect(find.text('Review the parser'), findsOneWidget);
    expect(find.text('Approve the migration'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('chatTaskNoticeView:task-done')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ChatTaskDetailScreen), findsOneWidget);
    expect(find.byType(WorkspaceTabsScreen), findsNothing);
  });

  testWidgets('the banner yields to the parent chat\'s own requests', (
    tester,
  ) async {
    final transport = _transport();
    addTearDown(transport.dispose);
    await tester.pumpWidget(
      _app(
        transport,
        const Scaffold(
          body: ChatTasksForChat(
            hostId: 'host',
            chatId: 'chat-parent',
            parentHasPendingRequest: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tasks · 1 running · 1 needs input'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('chatTaskInputBanner:task-input')),
      findsNothing,
    );
  });

  testWidgets('Answer Here resolves a child approval in place', (tester) async {
    final transport = _transport()
      ..pendingRequests.add(<String, Object?>{
        'chatId': 'chat-child',
        'taskId': 'task-input',
        'workspaceId': 'ws-1',
        'request': <String, Object?>{
          'requestId': 'request-1',
          'kind': 'commandExecutionApproval',
          'command': 'cargo test',
          'decisions': <String>['accept', 'decline'],
          'createdAt': '2026-08-30T10:30:00Z',
        },
      });
    addTearDown(transport.dispose);
    await tester.pumpWidget(
      _app(
        transport,
        const Scaffold(
          body: ChatTasksForChat(hostId: 'host', chatId: 'chat-parent'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('chatTaskAnswerHere:task-input')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('chatTaskDecision:request-1:accept')),
    );
    await tester.pumpAndSettle();
    final responded = transport.sent(AgentChatOrchestrationWire.respond).single;
    expect(responded['chatId'], 'chat-child');
    expect(responded['runtimeRequestId'], 'request-1');
    expect(find.byType(WorkspaceTabsScreen), findsNothing);
    expect(find.byType(ChatTaskDetailScreen), findsNothing);
  });

  testWidgets('a task brief says who delegated it', (tester) async {
    final transport = _transport();
    addTearDown(transport.dispose);
    await tester.pumpWidget(
      _app(
        transport,
        const Scaffold(
          body: ChatTaskOriginNotice(
            hostId: 'host',
            chatId: 'chat-child',
            origin: AgentChatItemOrigin(
              kind: AgentChatItemOriginKind.chatMessage,
              taskIds: <String>['task-done'],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Delegated by you'), findsOneWidget);
    expect(find.textContaining('another chat'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('chatTaskOriginOpenParent')),
      findsNothing,
    );
  });
}
