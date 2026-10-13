import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/activity/application/activity_navigation.dart';
import 'package:alera/src/features/activity/domain/activity_section.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/app_window/application/app_window_providers.dart';
import 'package:alera/src/features/app_window/domain/app_foreground.dart';
import 'package:alera/src/features/chat_tasks/application/chat_task_providers.dart';
import 'package:alera/src/features/chat_tasks/presentation/chat_task_notice.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
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
      )
      ..tasks['task-input'] = chatTaskJson(
        taskId: 'task-input',
        status: 'needs_input',
        title: 'Approve the migration',
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
  testWidgets('a wake lists its tasks and View Task opens only Activity', (
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
    expect(find.text('Write the changelog'), findsOneWidget);
    expect(find.text('Review the parser'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
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

  testWidgets('the dock lists open tasks the chat delegated', (tester) async {
    await _pump(
      tester,
      _transport(),
      const ChatTasksForChat(chatId: 'chat-parent'),
    );
    expect(find.text('Delegated Tasks'), findsOneWidget);
    expect(find.text('Review the parser'), findsOneWidget);
    expect(find.text('Approve the migration'), findsOneWidget);
    expect(find.text('Write the changelog'), findsNothing);
  });

  testWidgets('both hide on a runtime without chat tasks', (tester) async {
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
    expect(find.text('Delegated Tasks'), findsNothing);
    expect(find.text('Write the changelog'), findsNothing);
    expect(
      transport.requests.where(
        (request) => request.$1.startsWith('chatOrchestration.'),
      ),
      isEmpty,
    );
  });
}
