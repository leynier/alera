import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/activity/application/activity_navigation.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_full_data.dart';
import 'package:alera/src/features/app_window/application/app_window_providers.dart';
import 'package:alera/src/features/app_window/domain/app_foreground.dart';
import 'package:alera/src/features/chat_tasks/application/chat_task_providers.dart';
import 'package:alera/src/features/chat_tasks/presentation/chat_task_plan_delegation.dart';
import 'package:alera/src/features/remote_hosts/application/remote_hosts_controller.dart';
import 'package:alera/src/features/remote_hosts/application/remote_hosts_state.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
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

final DateTime _at = DateTime.utc(2026, 8, 30, 11);

AgentChatItem _plan({
  AgentChatItemStatus status = AgentChatItemStatus.completed,
}) => AgentChatItem(
  id: 'plan-1',
  type: AgentChatItemType.plan,
  status: status,
  createdAt: _at,
  updatedAt: _at,
  text: '# Port the lexer\n\nMove the lexer into its own crate.',
  explanation: 'The parser port needs the lexer first.',
  planSteps: const <AgentChatPlanStep>[
    AgentChatPlanStep(
      step: 'Create the crate',
      status: AgentChatPlanStepStatus.pending,
    ),
  ],
);

FakeChatTaskTransport _transport({bool personParent = true}) =>
    FakeChatTaskTransport(personParent: personParent)
      ..chats = <Map<String, Object?>>[
        <String, Object?>{
          'chatId': 'chat-parent',
          'workspaceId': 'ws-1',
          'title': 'Planner',
          'provider': 'codex',
          'providerInstanceId': 'codex',
          'model': 'gpt-5',
          'status': 'ready',
        },
      ];

Future<(ProviderContainer, RunsTestWorkbench)> _pump(
  WidgetTester tester,
  FakeChatTaskTransport transport, {
  AgentChatItem? plan,
}) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  var ids = 0;
  final workbench = RunsTestWorkbench();
  final container = ProviderContainer(
    overrides: [
      chatTaskRepositoryProvider.overrideWithValue(
        RuntimeAgentChatOrchestrationRepository(transport),
      ),
      agentChatRepositoryProvider.overrideWithValue(
        RuntimeAgentChatRepository(transport),
      ),
      agentChatIdGeneratorProvider.overrideWithValue(() => 'request-${ids++}'),
      appForegroundProvider.overrideWithValue(const AlwaysForeground()),
      workbenchControllerProvider.overrideWith(() => workbench),
      remoteHostsControllerProvider.overrideWith(_NoRemoteHosts.new),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(transport.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildAleraDarkTheme(),
        home: Scaffold(
          body: Center(
            child: AgentChatFullDataScope(
              chat: const AgentChatRef(
                chatId: 'chat-parent',
                workspaceId: 'ws-1',
              ),
              child: ChatTaskImplementPlanButton(plan: plan ?? _plan()),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (container, workbench);
}

void main() {
  test('the draft targets a new worktree of the same project and host', () {
    final draft = chatTaskPlanDraft(
      plan: _plan(),
      workspaceId: 'ws-1',
      projectId: 'project-1',
      hostId: 'host-a',
      parentChatId: 'chat-parent',
      agent: const AgentChatSelection(
        providerInstanceId: 'codex',
        model: 'gpt-5',
      ),
    );
    expect(draft.targetKind, AgentChatTaskTargetKind.newWorkspace);
    expect(draft.mode, AgentChatWorkspaceMode.worktree);
    expect(draft.projectId, 'project-1');
    expect(draft.hostId, 'host-a');
    expect(draft.parentChatId, 'chat-parent');
    expect(draft.providerInstanceId, 'codex');
    expect(draft.task, agentChatPlanTaskBrief(_plan()));
    expect(draft.problem, isNull);
  });

  testWidgets('the form opens prefilled and nothing runs until Delegate', (
    tester,
  ) async {
    final transport = _transport();
    final (container, workbench) = await _pump(tester, transport);

    await tester.tap(
      find.byKey(
        const ValueKey<String>('agent-chat-implement-plan-in-workspace'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Delegate Task'), findsOneWidget);
    expect(find.text(agentChatPlanTaskTitle(_plan())), findsOneWidget);
    expect(transport.sent(AgentChatOrchestrationWire.delegate), isEmpty);

    await tester.tap(find.byKey(const ValueKey<String>('delegateSubmit')));
    await tester.pumpAndSettle();
    final delegate = transport.sent(AgentChatOrchestrationWire.delegate).single;
    expect(delegate['task'], agentChatPlanTaskBrief(_plan()));
    expect(delegate['parentChatId'], 'chat-parent');
    final target = delegate['target']! as Map<String, Object?>;
    final created = target['newWorkspace']! as Map<String, Object?>;
    expect(created['projectId'], 'project-1');
    expect(created['mode'], 'worktree');
    expect(
      (delegate['agent']! as Map<String, Object?>)['providerInstanceId'],
      'codex',
    );
    expect(container.read(activityNavigationProvider).visible, isFalse);
    expect(workbench.actions, isEmpty);
  });

  testWidgets('an older runtime leaves the parent out', (tester) async {
    final transport = _transport(personParent: false);
    await _pump(tester, transport);
    await tester.tap(
      find.byKey(
        const ValueKey<String>('agent-chat-implement-plan-in-workspace'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('delegateSubmit')));
    await tester.pumpAndSettle();
    final delegate = transport.sent(AgentChatOrchestrationWire.delegate).single;
    expect(delegate.containsKey('parentChatId'), isFalse);
  });

  testWidgets('a plan still being drafted offers nothing', (tester) async {
    await _pump(
      tester,
      _transport(),
      plan: _plan(status: AgentChatItemStatus.inProgress),
    );
    expect(
      find.byKey(
        const ValueKey<String>('agent-chat-implement-plan-in-workspace'),
      ),
      findsNothing,
    );
  });
}
