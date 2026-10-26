import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_composer_drafts.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_tab_surface.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_agent_chat_repository.dart';

final Workspace _workspace = Workspace(
  id: 'ws-1',
  projectId: 'project-1',
  name: 'Alera',
  path: '/projects/alera',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  kind: WorkspaceKind.main,
  status: WorkspaceStatus.active,
);

final WorkspaceTabRecord _tab = WorkspaceTabRecord(
  id: 'tab-1',
  workspaceId: 'ws-1',
  title: 'Run the probe',
  kind: WorkspaceTabKind.agentChat,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  payload: const <String, Object?>{'chatId': 'chat-1', 'provider': 'claude'},
);

final class _Lifecycle extends AgentChatLifecycleRepository {
  final calls = <(String, Object)>[];

  @override
  Future<bool> supports(String capability) async => <String>{
    AgentChatWire.subagentThreadsCapability,
    AgentChatWire.workflowsCapability,
  }.contains(capability);

  @override
  Future<AgentChatSubagentTranscript> subagent(
    AgentChatRef chat, {
    required String itemId,
  }) async => AgentChatSubagentTranscript(
    call: AgentChatItem.fromJson(_call()),
    items: const <AgentChatItem>[],
  );

  @override
  Future<AgentChatWorkflowScript> workflowScript(
    AgentChatRef chat, {
    required String itemId,
  }) async {
    calls.add(('script', itemId));
    return const AgentChatWorkflowScript(
      scriptPath: '/claude/projects/p/run.js',
      contents: 'export const meta = {name: "probe-wf"};',
    );
  }

  @override
  Future<List<String>> workflowAgent(
    AgentChatRef chat, {
    required String itemId,
    required int agentIndex,
  }) async {
    calls.add(('agent', agentIndex));
    return <String>['The full answer of alpha one'];
  }
}

Map<String, Object?> _call() => agentChatItemFixture(
  'call',
  'dynamic_tool_call',
  status: 'completed',
  normalized: <String, Object?>{
    'toolName': 'Workflow',
    'subagent': <String, Object?>{
      'status': 'running',
      'taskId': 'wf',
      'taskType': 'local_workflow',
      'startedAt': '2026-10-12T10:00:00Z',
      'workflow': <String, Object?>{
        'name': 'probe-wf',
        'runHandles': <String, Object?>{'scriptPath': '/p/run.js'},
        'phases': <Object?>[
          <String, Object?>{'index': 1, 'title': 'Alpha'},
        ],
        'agents': <Object?>[
          <String, Object?>{
            'index': 1,
            'label': 'alpha:one',
            'state': 'running',
            'agentId': 'a1',
            'phaseIndex': 1,
            'prompt': 'Reply with exactly: A1',
          },
          <String, Object?>{
            'index': 2,
            'label': 'alpha:two',
            'state': 'completed',
            'phaseIndex': 1,
          },
        ],
        'totalTokens': 71141,
        'toolCalls': 3,
      },
    },
  },
);

Future<_Lifecycle> _pump(WidgetTester tester) async {
  final lifecycle = _Lifecycle();
  final repository = FakeAgentChatRepository()
    ..summaries = <AgentChatSummary>[
      AgentChatSummary.fromJson(<String, Object?>{
        'chatId': 'chat-1',
        'workspaceId': 'ws-1',
        'title': 'Run the probe',
        'provider': 'claude',
        'providerInstanceId': 'claude',
        'status': 'running',
        'updatedAt': '2026-10-12T10:00:00Z',
      }),
    ]
    ..snapshots.add(
      () => agentChatSnapshotFixture(
        capabilities: const <String, Object?>{'stopSubagent': true},
        items: <Map<String, Object?>>[
          agentChatItemFixture('u1', 'user_message', text: 'Run the probe'),
          _call(),
        ],
      ),
    );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        agentChatComposerDraftsProvider.overrideWithValue(
          AgentChatComposerDrafts(),
        ),
        agentChatRepositoryProvider.overrideWithValue(repository),
        agentChatLifecycleRepositoryProvider.overrideWithValue(lifecycle),
        agentChatClockProvider.overrideWithValue(
          () => DateTime.utc(2026, 10, 12, 10),
        ),
      ],
      child: MaterialApp(
        theme: buildAleraDarkTheme(),
        home: Scaffold(
          body: AgentChatTabSurface(workspace: _workspace, tab: _tab),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return lifecycle;
}

void main() {
  testWidgets('the timeline row names the workflow and unfolds its phases', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('Workflow: probe-wf'), findsOneWidget);
    expect(find.text('1 working'), findsOneWidget);
    await tester.tap(find.text('Workflow: probe-wf'));
    await tester.pump();
    // The running phase opens itself.
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('1/2 agents'), findsOneWidget);
    expect(find.text('alpha:one'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('agent-chat-workflow-phase-1')),
    );
    await tester.pump();
    expect(find.text('alpha:one'), findsNothing);
  });

  testWidgets('an opened workflow shows its script and member answers', (
    tester,
  ) async {
    final lifecycle = await _pump(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('agent-chat-subagent-open-call')),
    );
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('agent-chat-workflow-panel-call')),
      findsOneWidget,
    );
    expect(find.text('71k tokens · 3 tool calls'), findsOneWidget);
    expect(find.text('Stop Workflow'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('agent-chat-workflow-view-script')),
    );
    await tester.pumpAndSettle();
    expect(lifecycle.calls.last, ('script', 'call'));
    expect(find.text('Workflow Script'), findsOneWidget);
    expect(
      find.text('export const meta = {name: "probe-wf"};'),
      findsOneWidget,
    );
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('agent-chat-workflow-member-1')),
    );
    await tester.pumpAndSettle();
    expect(lifecycle.calls.last, ('agent', 1));
    expect(find.text('Reply with exactly: A1'), findsOneWidget);
    expect(
      find.text('The full answer of alpha one', findRichText: true),
      findsOne,
    );
  });

  testWidgets('lineage lists the workflow and unfolds its members', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.byKey(const ValueKey<String>('agent-chat-lineage')));
    await tester.pumpAndSettle();
    expect(find.text('Workflow · 1 working'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('agent-chat-lineage-expand-call')),
    );
    await tester.pumpAndSettle();
    expect(find.text('alpha:two'), findsWidgets);
  });
}
