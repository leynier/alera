import 'package:alera/src/features/activity/application/activity_attention.dart';
import 'package:alera/src/features/activity/application/activity_navigation.dart';
import 'package:alera/src/features/activity/domain/activity_section.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_profiles/application/agent_profile_providers.dart';
import 'package:alera/src/features/app_window/application/app_window_providers.dart';
import 'package:alera/src/features/app_window/domain/app_foreground.dart';
import 'package:alera/src/features/chat_tasks/application/chat_task_providers.dart';
import 'package:alera/src/features/remote_hosts/application/remote_hosts_controller.dart';
import 'package:alera/src/features/remote_hosts/application/remote_hosts_state.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_providers.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chat_task_fakes.dart';
import '../support/runs_harness.dart';

class _NoRemoteHosts extends RemoteHostsController {
  @override
  RemoteHostsState build() => const RemoteHostsState(loading: false);
}

/// The runs workbench plus an agent chat tab for `chat-child` in ws-1.
RunsTestWorkbench _workbench() {
  final state = runsWorkbenchState();
  final now = DateTime.utc(2026, 8, 30);
  return RunsTestWorkbench(
    seed: state.copyWith(
      tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
        ...state.tabsByWorkspace,
        'ws-1': <WorkspaceTabRecord>[
          ...state.tabsFor('ws-1'),
          WorkspaceTabRecord(
            id: 'tab-chat',
            workspaceId: 'ws-1',
            title: 'Docs Chat',
            createdAt: now,
            updatedAt: now,
            kind: WorkspaceTabKind.agentChat,
            payload: const <String, Object?>{'chatId': 'chat-child'},
          ),
        ],
      },
    ),
  );
}

ProviderContainer _container(
  FakeChatTaskTransport transport,
  RunsTestWorkbench workbench,
) {
  var ids = 0;
  final container = ProviderContainer(
    overrides: [
      chatTaskRepositoryProvider.overrideWithValue(
        RuntimeAgentChatOrchestrationRepository(transport),
      ),
      agentChatRepositoryProvider.overrideWithValue(
        RuntimeAgentChatRepository(transport),
      ),
      agentChatClockProvider.overrideWithValue(
        () => DateTime.utc(2026, 8, 30, 12),
      ),
      agentChatIdGeneratorProvider.overrideWithValue(() => 'request-${ids++}'),
      appForegroundProvider.overrideWithValue(const AlwaysForeground()),
      agentProfilesProvider.overrideWith(RunsTestAgentProfiles.new),
      terminalRuntimeProvider.overrideWith((ref) {
        final runtime = XtermTerminalRuntime();
        ref.onDispose(runtime.dispose);
        return runtime;
      }),
      workbenchControllerProvider.overrideWith(() => workbench),
      activityAttentionProvider.overrideWithValue(const ActivityAttention()),
      remoteHostsControllerProvider.overrideWith(_NoRemoteHosts.new),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(transport.dispose);
  return container;
}

Future<void> _pump(WidgetTester tester, ProviderContainer container) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  container
      .read(activityNavigationProvider.notifier)
      .open(ActivitySection.chatTasks);
  await tester.pumpWidget(RunsTestApp(container: container));
  await tester.pumpAndSettle();
}

FakeChatTaskTransport _transport() => FakeChatTaskTransport()
  ..tasks['task-input'] = chatTaskJson(
    taskId: 'task-input',
    status: 'needs_input',
    title: 'Approve the migration',
    pendingRequestCount: 1,
    updatedAt: '2026-08-30T11:50:00Z',
  )
  ..tasks['task-running'] = chatTaskJson(
    taskId: 'task-running',
    title: 'Review the parser',
    updatedAt: '2026-08-30T11:40:00Z',
  )
  ..tasks['task-done'] = chatTaskJson(
    taskId: 'task-done',
    status: 'completed',
    title: 'Write the changelog',
    parentChatId: null,
    result: <String, Object?>{'text': 'Changelog written.', 'truncated': true},
    updatedAt: '2026-08-30T11:30:00Z',
  );

void main() {
  testWidgets('groups tasks and selecting one never changes the workspace', (
    tester,
  ) async {
    final workbench = _workbench();
    final container = _container(_transport(), workbench);
    await _pump(tester, container);

    expect(find.text('ATTENTION (1)'), findsOneWidget);
    expect(find.text('ACTIVE (1)'), findsOneWidget);
    expect(find.text('HISTORY (1)'), findsOneWidget);

    await tester.tap(find.text('Review the parser'));
    await tester.pumpAndSettle();
    expect(
      container.read(activityNavigationProvider).chatTasks.taskId,
      'task-running',
    );
    expect(find.text('Do Review the parser and report back.'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('chatTaskWait')), findsOneWidget);
    expect(workbench.actions, isEmpty);
    expect(
      container.read(workbenchControllerProvider).activeWorkspaceId,
      'ws-2',
    );
  });

  testWidgets('a change event reads the list again', (tester) async {
    final transport = _transport();
    final container = _container(transport, _workbench());
    await _pump(tester, container);
    final reads = transport.sent(AgentChatOrchestrationWire.tasksList).length;

    transport.put(
      chatTaskJson(
        taskId: 'task-running',
        status: 'failed',
        title: 'Review the parser',
        updatedAt: '2026-08-30T11:55:00Z',
      ),
    );
    await tester.pumpAndSettle();

    expect(
      transport.sent(AgentChatOrchestrationWire.tasksList).length,
      greaterThan(reads),
    );
    expect(find.text('ATTENTION (2)'), findsOneWidget);
    expect(find.textContaining('Failed, not reviewed yet'), findsOneWidget);
  });

  testWidgets(
    'a person-owned result is acknowledged once, a child result never',
    (tester) async {
      final transport = _transport();
      final container = _container(transport, _workbench());
      await _pump(tester, container);

      await tester.tap(find.text('Approve the migration'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Write the changelog'));
      await tester.pumpAndSettle();

      final acknowledged = transport
          .sent(AgentChatOrchestrationWire.task)
          .where((payload) => payload['acknowledge'] == true)
          .map((payload) => payload['taskId'])
          .toList();
      expect(acknowledged, <Object?>['task-done']);
      expect(
        find.byKey(const ValueKey<String>('chatTaskResult')),
        findsOneWidget,
      );
      expect(find.textContaining('The result was shortened'), findsOneWidget);
    },
  );

  testWidgets('cancel asks first and never navigates', (tester) async {
    final transport = _transport();
    final workbench = _workbench();
    final container = _container(transport, workbench);
    await _pump(tester, container);
    await tester.tap(find.text('Review the parser'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('chatTaskCancel')));
    await tester.pumpAndSettle();
    expect(find.text('Cancel Task?'), findsOneWidget);
    await tester.tap(find.text('Keep Task'));
    await tester.pumpAndSettle();
    expect(transport.sent(AgentChatOrchestrationWire.cancel), isEmpty);

    await tester.tap(find.byKey(const ValueKey<String>('chatTaskCancel')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Cancel Task'));
    await tester.pumpAndSettle();
    final cancel = transport.sent(AgentChatOrchestrationWire.cancel).single;
    expect(cancel['taskId'], 'task-running');
    expect(cancel['requestId'], isA<String>());
    expect(find.text('Cancelling'), findsWidgets);
    expect(workbench.actions, isEmpty);
  });

  testWidgets('requests are answered with the offered decisions', (
    tester,
  ) async {
    final transport = _transport()
      ..pendingRequests = <Map<String, Object?>>[
        <String, Object?>{
          'chatId': 'chat-child',
          'taskId': 'task-input',
          'request': <String, Object?>{
            'requestId': 'runtime-request-1',
            'kind': 'command_execution_approval',
            'command': 'cargo test',
            'decisions': <String>['accept', 'decline'],
          },
        },
      ];
    final container = _container(transport, _workbench());
    await _pump(tester, container);
    await tester.tap(find.text('Approve the migration'));
    await tester.pumpAndSettle();

    expect(find.text('Run Command?'), findsOneWidget);
    await tester.tap(find.text('Allow Once'));
    await tester.pumpAndSettle();
    final respond = transport.sent(AgentChatOrchestrationWire.respond).single;
    expect(respond['chatId'], 'chat-child');
    expect(respond['runtimeRequestId'], 'runtime-request-1');
    expect(respond['response'], <String, Object?>{
      'type': 'approval',
      'decision': 'accept',
    });
  });

  testWidgets('Open Chat selects the chat tab only when pressed', (
    tester,
  ) async {
    final workbench = _workbench();
    final container = _container(_transport(), workbench);
    await _pump(tester, container);
    await tester.tap(find.text('Review the parser'));
    await tester.pumpAndSettle();
    expect(workbench.actions, isEmpty);

    await tester.tap(find.byKey(const ValueKey<String>('chatTaskOpenChat')));
    await tester.pumpAndSettle();
    expect(workbench.actions, <String>['terminal:tab-chat']);
    expect(container.read(activityNavigationProvider).visible, isFalse);
  });

  testWidgets('Delegate Task names its target and selects only the task', (
    tester,
  ) async {
    final transport = _transport();
    final workbench = _workbench();
    final container = _container(transport, workbench);
    await _pump(tester, container);

    await tester.tap(
      find.byKey(const ValueKey<String>('activityPrimaryAction')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('delegateSubmit')));
    await tester.pumpAndSettle();
    expect(find.text('Describe the task.'), findsOneWidget);

    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey<String>('delegateTask')),
        matching: find.byType(TextField),
      ),
      'Summarize the open pull requests',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('delegateSubmit')));
    await tester.pumpAndSettle();
    expect(find.text('Choose a workspace.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('delegateWorkspace')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('feature-oauth').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('delegateSubmit')));
    await tester.pumpAndSettle();

    final delegate = transport.sent(AgentChatOrchestrationWire.delegate).single;
    expect(delegate['mode'], 'async');
    expect(delegate['requestId'], isA<String>());
    expect(delegate['target'], <String, Object?>{
      'workspace': <String, Object?>{'workspaceId': 'ws-1'},
    });
    expect(delegate['agent'], <String, Object?>{
      'providerInstanceId': 'codex',
      'model': 'gpt-5',
    });
    final location = container.read(activityNavigationProvider);
    expect(location.chatTasks.taskId, 'task-new-1');
    expect(location.visible, isTrue);
    expect(workbench.actions, isEmpty);
  });

  testWidgets('an older runtime shows Update Required and no delegation', (
    tester,
  ) async {
    final container = _container(
      FakeChatTaskTransport(orchestration: false),
      _workbench(),
    );
    await _pump(tester, container);
    expect(find.text('Update Required'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey<String>('activityPrimaryAction')),
    );
    expect(button.onPressed, isNull);
  });
}
