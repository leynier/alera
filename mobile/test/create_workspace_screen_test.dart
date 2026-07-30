import 'package:alera_mobile/src/features/runtime/domain/project_summary.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_providers.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workbench/presentation/create_workspace_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_terminal_client.dart';

void main() {
  testWidgets('Create Another keeps the mobile form open and resets it', (
    tester,
  ) async {
    final client = FakeTerminalClient()
      ..projectBranches = const <String>['main']
      ..deferredSetupCommand = '/bin/sh "/runtime/setup.sh"';
    addTearDown(client.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceClientProvider('host-1').overrideWith((ref) async => client),
          terminalClientProvider('host-1').overrideWith((ref) async => client),
        ],
        child: const MaterialApp(
          home: CreateWorkspaceScreen(
            hostId: 'host-1',
            projects: <ProjectSummary>[
              ProjectSummary(
                id: 'project-1',
                name: 'Alera',
                repoPath: '/repo/alera',
              ),
            ],
            workspaces: [],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Manual'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Branch Name'),
      'feature/one',
    );
    await tester.tap(find.text('Create Another'));
    await tester.pump();
    expect(
      tester
          .widget<CheckboxListTile>(
            find.widgetWithText(CheckboxListTile, 'Create Another'),
          )
          .value,
      isTrue,
    );
    await tester.drag(find.byType(ListView), const Offset(0, -240));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create Workspace'));
    await tester.pump();
    for (var attempt = 0; attempt < 100; attempt += 1) {
      if (client.calls.contains('detach session-created-1')) {
        break;
      }
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pump(const Duration(milliseconds: 300));

    expect(client.calls, contains('create created Setup'));
    expect(client.calls, contains('detach session-created-1'));
    expect(find.text('New Workspace'), findsOneWidget);
    expect(find.text('Workspace Created'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, 500));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Branch Name'))
          .controller
          ?.text,
      isEmpty,
    );
    expect(client.writes, hasLength(1));
  });

  testWidgets('Create Another resets the mobile prompt flow', (tester) async {
    final client = FakeTerminalClient()
      ..projectBranches = const <String>['main'];
    addTearDown(client.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceClientProvider('host-1').overrideWith((ref) async => client),
          terminalClientProvider('host-1').overrideWith((ref) async => client),
        ],
        child: const MaterialApp(
          home: CreateWorkspaceScreen(
            hostId: 'host-1',
            projects: <ProjectSummary>[
              ProjectSummary(
                id: 'project-1',
                name: 'Alera',
                repoPath: '/repo/alera',
              ),
            ],
            workspaces: [],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Initial Prompt'),
      'Build offline support',
    );
    await tester.ensureVisible(find.text('Create Another'));
    await tester.tap(find.text('Create Another'));
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create And Start Agent'));
    for (var attempt = 0; attempt < 100; attempt += 1) {
      if (client.calls.any((call) => call.startsWith('launchAgentProfile'))) {
        break;
      }
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      client.calls,
      contains('launchAgentProfile created profile-1 Build offline support'),
    );
    expect(find.text('New Workspace'), findsOneWidget);
    expect(find.text('Workspace Created'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, 500));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Initial Prompt'))
          .controller
          ?.text,
      isEmpty,
    );
  });
}
