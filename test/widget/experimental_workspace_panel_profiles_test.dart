import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
import 'package:alera/src/features/workbench/domain/experimental_workspace_panel.dart';
import 'package:alera/src/features/workbench/presentation/experimental_workspace_panel_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('add tab menu lists opted-in agent profiles after Terminal', (
    tester,
  ) async {
    final launched = <(String, String?)>[];
    final now = DateTime.utc(2026, 9, 10);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 800,
              height: 500,
              child: ExperimentalWorkspacePanelView(
                workspaceId: 'workspace',
                panel: const ExperimentalWorkspacePanel(
                  tabKeys: ['tool:search'],
                  activeKey: 'tool:search',
                ),
                tabs: const [],
                onSelect: (_) {},
                onClose: (_) {},
                onNewTerminal: () {},
                onHide: () {},
                content: const Text('Selected Surface'),
                newTabMenuProfiles: <AgentProfile>[
                  AgentProfile(
                    id: 'profile-hidden',
                    name: 'Hidden Codex',
                    agentType: 'codex',
                    command: 'codex',
                    createdAt: now,
                    updatedAt: now,
                  ),
                  AgentProfile(
                    id: 'profile-shown',
                    name: 'Shown Codex',
                    agentType: 'codex',
                    command: 'codex',
                    showInNewTabMenu: true,
                    createdAt: now,
                    updatedAt: now,
                  ),
                ],
                onLaunchAgentProfile: ({required profileId, targetGroupId}) {
                  launched.add((profileId, targetGroupId));
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Add Tab'));
    await tester.pumpAndSettle();

    expect(find.text('Terminal'), findsOneWidget);
    expect(find.text('Shown Codex'), findsOneWidget);
    expect(find.text('Hidden Codex'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Terminal')).dy,
      lessThan(tester.getTopLeft(find.text('Shown Codex')).dy),
    );

    await tester.tap(find.text('Shown Codex'));
    await tester.pumpAndSettle();
    expect(launched, <(String, String?)>[('profile-shown', 'workspace/main')]);
  });

  testWidgets('empty panel opens a profiles-only picker from Agents', (
    tester,
  ) async {
    final launched = <String>[];
    final now = DateTime.utc(2026, 9, 10);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExperimentalWorkspacePanelView(
            panel: const ExperimentalWorkspacePanel(),
            tabs: const [],
            onSelect: (_) {},
            onClose: (_) {},
            onNewTerminal: () {},
            onHide: () {},
            content: const Text('Must Not Mount'),
            newTabMenuProfiles: <AgentProfile>[
              AgentProfile(
                id: 'profile-hidden',
                name: 'Hidden Codex',
                agentType: 'codex',
                command: 'codex',
                createdAt: now,
                updatedAt: now,
              ),
              AgentProfile(
                id: 'profile-shown',
                name: 'Shown Codex',
                agentType: 'codex',
                command: 'codex',
                showInNewTabMenu: true,
                createdAt: now,
                updatedAt: now,
              ),
            ],
            onLaunchAgentProfile: ({required profileId, targetGroupId}) {
              launched.add(profileId);
            },
          ),
        ),
      ),
    );

    expect(find.text('Agents'), findsOneWidget);
    expect(find.text('Shown Codex'), findsNothing);
    expect(find.text('Hidden Codex'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Terminal')).dy,
      lessThan(tester.getTopLeft(find.text('Agents')).dy),
    );

    await tester.ensureVisible(find.text('Agents'));
    await tester.tap(find.text('Agents'));
    await tester.pumpAndSettle();

    expect(find.text('RUNNING AGENTS'), findsNothing);
    expect(find.text('AGENT PROFILES'), findsOneWidget);
    expect(find.text('Hidden Codex'), findsOneWidget);
    expect(find.text('Shown Codex'), findsOneWidget);

    await tester.tap(find.text('Hidden Codex'));
    await tester.pumpAndSettle();
    expect(launched, ['profile-hidden']);
  });
}
