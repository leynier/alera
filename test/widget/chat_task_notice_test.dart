import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/activity/application/activity_navigation.dart';
import 'package:alera/src/features/activity/domain/activity_section.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/app_window/application/app_window_providers.dart';
import 'package:alera/src/features/app_window/domain/app_foreground.dart';
import 'package:alera/src/features/chat_tasks/application/chat_task_dock_expansion.dart';
import 'package:alera/src/features/chat_tasks/application/chat_task_providers.dart';
import 'package:alera/src/features/chat_tasks/presentation/chat_task_notice.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chat_task_fakes.dart';
import '../support/runs_harness.dart';

FakeChatTaskTransport _transport({bool orchestration = true}) =>
    FakeChatTaskTransport(orchestration: orchestration)
      ..tasks['task-running'] = chatTaskJson(
        taskId: 'task-running',
        title: 'Review the parser',
      )
      ..tasks['task-done'] = chatTaskJson(
        taskId: 'task-done',
        status: 'completed',
        title: 'Write the changelog',
        result: <String, Object?>{'text': 'The changelog is in docs/.'},
      )
      ..tasks['task-input'] = chatTaskJson(
        taskId: 'task-input',
        status: 'needs_input',
        title: 'Approve the migration',
        pendingRequestCount: 1,
      )
      ..tasks['task-mine'] = chatTaskJson(
        taskId: 'task-mine',
        title: 'Port the lexer',
        parentChatId: null,
      )
      ..tasks['task-from-planner'] = chatTaskJson(
        taskId: 'task-from-planner',
        title: 'Port the lexer',
        parentChatId: 'chat-planner',
      )
      ..chats = <Map<String, Object?>>[
        <String, Object?>{
          'chatId': 'chat-planner',
          'workspaceId': 'ws-1',
          'title': 'Planner',
          'provider': 'codex',
          'providerInstanceId': 'codex',
          'status': 'ready',
          'projectName': 'alera',
          'workspaceName': 'feature-oauth',
        },
      ];

Future<(ProviderContainer, RunsTestWorkbench)> _pump(
  WidgetTester tester,
  FakeChatTaskTransport transport,
  Widget child,
) async {
  final workbench = RunsTestWorkbench();
  final container = ProviderContainer(
    overrides: [
      chatTaskRepositoryProvider.overrideWithValue(
        RuntimeAgentChatOrchestrationRepository(transport),
      ),
      agentChatRepositoryProvider.overrideWithValue(
        RuntimeAgentChatRepository(transport),
      ),
      appForegroundProvider.overrideWithValue(const AlwaysForeground()),
      workbenchControllerProvider.overrideWith(() => workbench),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(transport.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildAleraDarkTheme(),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (container, workbench);
}

void main() {
  testWidgets('a wake shows one outcome card per task and opens nothing', (
    tester,
  ) async {
    final (container, workbench) = await _pump(
      tester,
      _transport(),
      const ChatTaskOriginNotice(
        chatId: 'chat-parent',
        origin: AgentChatItemOrigin(
          kind: AgentChatItemOriginKind.orchestrationWake,
          taskIds: <String>['task-done', 'task-running'],
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey<String>('chatTaskOutcome:task-done')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('chatTaskOutcome:task-running')),
      findsOneWidget,
    );
    expect(find.text('Write the changelog'), findsOneWidget);
    expect(find.text('The changelog is in docs/.'), findsOneWidget);
    expect(find.textContaining('Worked for'), findsOneWidget);
    expect(container.read(activityNavigationProvider).visible, isFalse);

    await tester.tap(
      find.byKey(const ValueKey<String>('chatTaskNoticeView:task-done')),
    );
    await tester.pump();
    final location = container.read(activityNavigationProvider);
    expect(location.visible, isTrue);
    expect(location.section, ActivitySection.chatTasks);
    expect(location.chatTasks.taskId, 'task-done');
    expect(workbench.actions, isEmpty);
  });

  testWidgets('a message names the chat that sent it', (tester) async {
    final (_, workbench) = await _pump(
      tester,
      _transport(),
      const ChatTaskOriginNotice(
        chatId: 'chat-parent',
        origin: AgentChatItemOrigin(
          kind: AgentChatItemOriginKind.chatMessage,
          senderChatId: 'chat-planner',
        ),
      ),
    );
    expect(find.text('From Planner · alera / feature-oauth'), findsOneWidget);
    expect(workbench.actions, isEmpty);
  });

  testWidgets('a person\'s brief never says it came from another chat', (
    tester,
  ) async {
    await _pump(
      tester,
      _transport(),
      const ChatTaskOriginNotice(
        chatId: 'chat-child',
        origin: AgentChatItemOrigin(
          kind: AgentChatItemOriginKind.chatMessage,
          taskIds: <String>['task-mine'],
        ),
      ),
    );
    expect(find.text('Delegated by you'), findsOneWidget);
    expect(find.textContaining('another chat'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('chatTaskOriginOpenParent')),
      findsNothing,
    );
  });

  testWidgets('a delegated brief links its parent and opens it on a press', (
    tester,
  ) async {
    final (_, workbench) = await _pump(
      tester,
      _transport(),
      const ChatTaskOriginNotice(
        chatId: 'chat-child',
        origin: AgentChatItemOrigin(
          kind: AgentChatItemOriginKind.chatMessage,
          taskIds: <String>['task-from-planner'],
        ),
      ),
    );
    expect(find.text('Delegated by Planner'), findsOneWidget);
    expect(workbench.actions, isEmpty);

    await tester.tap(
      find.byKey(const ValueKey<String>('chatTaskOriginOpenParent')),
    );
    await tester.pumpAndSettle();
    expect(workbench.actions, isNotEmpty);
  });

  testWidgets('the dock counts tasks and expands for this session', (
    tester,
  ) async {
    final (container, workbench) = await _pump(
      tester,
      _transport(),
      const ChatTasksForChat(chatId: 'chat-parent'),
    );
    expect(
      find.text('Tasks · 1 running · 1 needs input · 1 done'),
      findsOneWidget,
    );
    expect(find.text('Review the parser'), findsNothing);
    expect(
      find.text('Task needs input: Approve the migration'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey<String>('chatTaskDockToggle')));
    await tester.pumpAndSettle();
    expect(find.text('Review the parser'), findsOneWidget);
    expect(find.text('Write the changelog'), findsOneWidget);
    expect(container.read(chatTaskDockExpansionProvider), {'chat-parent'});
    expect(workbench.actions, isEmpty);
    expect(container.read(activityNavigationProvider).visible, isFalse);
  });

  testWidgets('the banner yields to the chat\'s own pending request', (
    tester,
  ) async {
    await _pump(
      tester,
      _transport(),
      const ChatTasksForChat(
        chatId: 'chat-parent',
        parentHasPendingRequest: true,
      ),
    );
    expect(
      find.byKey(const ValueKey<String>('chatTaskInputBanner:task-input')),
      findsNothing,
    );
    expect(
      find.text('Tasks · 1 running · 1 needs input · 1 done'),
      findsOneWidget,
    );
  });

  testWidgets('Answer Here resolves a child approval in the parent', (
    tester,
  ) async {
    final transport = _transport()
      ..pendingRequests = <Map<String, Object?>>[
        <String, Object?>{
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
        },
      ];
    final (container, workbench) = await _pump(
      tester,
      transport,
      const ChatTasksForChat(chatId: 'chat-parent'),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('chatTaskAnswerHere:task-input')),
    );
    await tester.pumpAndSettle();
    expect(find.text('cargo test'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('chatTaskDecision:request-1:accept')),
    );
    await tester.pumpAndSettle();
    final respond = transport.sent(AgentChatOrchestrationWire.respond).single;
    expect(respond['chatId'], 'chat-child');
    expect(respond['runtimeRequestId'], 'request-1');
    expect(workbench.actions, isEmpty);
    expect(container.read(activityNavigationProvider).visible, isFalse);
  });

  testWidgets('Stop asks first, then cancels the task in place', (
    tester,
  ) async {
    final transport = _transport();
    final (container, workbench) = await _pump(
      tester,
      transport,
      const ChatTasksForChat(chatId: 'chat-parent'),
    );
    await tester.tap(find.byKey(const ValueKey<String>('chatTaskDockToggle')));
    await tester.pumpAndSettle();
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(
      location: tester.getCenter(
        find.byKey(const ValueKey<String>('chatTaskDockRow:task-running')),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('chatTaskDockStop:task-running')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Stop Task?'), findsOneWidget);
    expect(transport.sent(AgentChatOrchestrationWire.cancel), isEmpty);

    await tester.tap(find.text('Stop Task'));
    await tester.pumpAndSettle();
    expect(
      transport.sent(AgentChatOrchestrationWire.cancel).single['taskId'],
      'task-running',
    );
    expect(workbench.actions, isEmpty);
    expect(container.read(activityNavigationProvider).visible, isFalse);
  });

  testWidgets('everything hides on a runtime without chat tasks', (
    tester,
  ) async {
    final transport = _transport(orchestration: false);
    await _pump(
      tester,
      transport,
      const Column(
        children: <Widget>[
          ChatTasksForChat(chatId: 'chat-parent'),
          ChatTaskOriginNotice(
            chatId: 'chat-parent',
            origin: AgentChatItemOrigin(
              kind: AgentChatItemOriginKind.orchestrationWake,
              taskIds: <String>['task-done'],
            ),
          ),
        ],
      ),
    );
    expect(find.byKey(const ValueKey<String>('chatTaskDock')), findsNothing);
    expect(find.text('Write the changelog'), findsNothing);
    expect(
      transport.requests.where(
        (request) => request.$1.startsWith('chatOrchestration.'),
      ),
      isEmpty,
    );
  });
}
