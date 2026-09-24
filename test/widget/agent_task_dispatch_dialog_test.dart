import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_task_dispatch/domain/agent_task_dispatch.dart';
import 'package:alera/src/features/agent_task_dispatch/presentation/agent_task_dispatch_dialog.dart';
import 'package:alera/src/features/workbench/application/workspace_agent_status_projection.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 9, 7);
  final tab = WorkspaceTabRecord(
    id: 'tab-1',
    workspaceId: 'workspace-1',
    title: 'Codex',
    createdAt: DateTime.utc(2026, 9, 7),
    updatedAt: DateTime.utc(2026, 9, 7),
  );

  AgentTaskDispatchCatalog catalog() {
    return AgentTaskDispatchCatalog(
      runningAgents: <WorkspaceAgentRun>[
        WorkspaceAgentRun(
          tab: tab,
          status: AgentStatusEntry(
            terminalSessionId: tab.terminalSessionId,
            workspaceId: tab.workspaceId,
            tabId: tab.id,
            agentType: .codex,
            state: .done,
            prompt: '',
            updatedAt: now,
            stateStartedAt: now,
          ),
        ),
      ],
      profiles: <AgentProfile>[
        AgentProfile(
          id: 'profile-1',
          name: 'Codex Builder',
          agentType: 'codex',
          command: 'codex',
          description: 'Implementation',
          createdAt: now,
          updatedAt: now,
        ),
      ],
      defaultProfileId: 'profile-1',
    );
  }

  Future<AgentTaskDispatchSelection?> openDialog(WidgetTester tester) async {
    AgentTaskDispatchSelection? selection;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                selection = await showDialog<AgentTaskDispatchSelection>(
                  context: context,
                  builder: (_) => AgentTaskDispatchDialog(
                    request: const AgentTaskDispatchRequest(
                      workspaceId: 'workspace-1',
                      prompt: 'Fix the failing checks.',
                      message: 'Choose a running agent or open a new tab from a profile.',
                    ),
                    catalog: catalog(),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    return selection;
  }

  testWidgets('lists running agents and profiles', (tester) async {
    await openDialog(tester);
    expect(find.text('Send To Agent'), findsOneWidget);
    expect(find.text('Codex'), findsOneWidget);
    expect(find.text('Codex Builder'), findsOneWidget);
    expect(find.text('Implementation'), findsOneWidget);
    expect(
      find.text('Choose a running agent or open a new tab from a profile.'),
      findsOneWidget,
    );
  });

  testWidgets('selecting a running agent returns that tab', (tester) async {
    AgentTaskDispatchSelection? selection;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                selection = await showDialog<AgentTaskDispatchSelection>(
                  context: context,
                  builder: (_) => AgentTaskDispatchDialog(
                    request: const AgentTaskDispatchRequest(
                      workspaceId: 'workspace-1',
                      prompt: 'Fix the failing checks.',
                    ),
                    catalog: catalog(),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Codex'));
    await tester.pumpAndSettle();
    expect(
      selection,
      isA<AgentTaskDispatchRunningAgentSelection>().having(
        (value) => value.tabId,
        'tabId',
        'tab-1',
      ),
    );
  });

  testWidgets('profiles-only mode hides running agents', (tester) async {
    AgentTaskDispatchSelection? selection;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                selection = await showDialog<AgentTaskDispatchSelection>(
                  context: context,
                  builder: (_) => AgentTaskDispatchDialog(
                    request: const AgentTaskDispatchRequest(
                      workspaceId: 'workspace-1',
                      prompt: '',
                      title: 'Agents',
                    ),
                    catalog: catalog(),
                    includeRunningAgents: false,
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Agents'), findsOneWidget);
    expect(find.text('RUNNING AGENTS'), findsNothing);
    expect(find.text('NEW TAB'), findsNothing);
    expect(find.text('AGENT PROFILES'), findsOneWidget);
    expect(find.text('Codex'), findsNothing);
    expect(find.text('Codex Builder'), findsOneWidget);

    await tester.tap(find.text('Codex Builder'));
    await tester.pumpAndSettle();
    expect(
      selection,
      isA<AgentTaskDispatchNewTabSelection>().having(
        (value) => value.profileId,
        'profileId',
        'profile-1',
      ),
    );
  });

  testWidgets('selecting a profile returns a new-tab selection', (
    tester,
  ) async {
    AgentTaskDispatchSelection? selection;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                selection = await showDialog<AgentTaskDispatchSelection>(
                  context: context,
                  builder: (_) => AgentTaskDispatchDialog(
                    request: const AgentTaskDispatchRequest(
                      workspaceId: 'workspace-1',
                      prompt: 'Fix the failing checks.',
                    ),
                    catalog: catalog(),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Codex Builder'));
    await tester.pumpAndSettle();
    expect(
      selection,
      isA<AgentTaskDispatchNewTabSelection>().having(
        (value) => value.profileId,
        'profileId',
        'profile-1',
      ),
    );
  });
}
