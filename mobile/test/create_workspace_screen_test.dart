import 'package:alera_mobile/src/features/ai_dictation/application/mobile_ai_dictation_settings_controller.dart';
import 'package:alera_mobile/src/features/ai_dictation/domain/mobile_ai_dictation_settings.dart';
import 'package:alera_mobile/src/features/runtime/domain/project_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_providers.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workbench/presentation/create_workspace_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_ai_dictation_settings.dart';
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
    expect(find.text('Workspace created'), findsOneWidget);
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
    final scrollState = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    scrollState.position.jumpTo(scrollState.position.maxScrollExtent);
    await tester.pump();
    final targetElement = tester.element(find.text('Create And Start Agent'));
    final targetScrollState = targetElement
        .findAncestorStateOfType<ScrollableState>();
    if (targetScrollState != null) {
      targetScrollState.position.jumpTo(
        targetScrollState.position.maxScrollExtent,
      );
    }
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
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
    expect(find.text('Workspace created'), findsOneWidget);
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

  testWidgets('Prompt exposes a configurable cross-project Parent', (
    tester,
  ) async {
    final client = FakeTerminalClient()
      ..projectBranches = const <String>['main'];
    addTearDown(client.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceClientProvider('host-1').overrideWith((ref) async => client),
          terminalClientProvider('host-1').overrideWith((ref) async => client),
        ],
        child: MaterialApp(
          home: CreateWorkspaceScreen(
            hostId: 'host-1',
            projects: const <ProjectSummary>[
              ProjectSummary(
                id: 'project-1',
                name: 'Alera',
                repoPath: '/repo/alera',
              ),
              ProjectSummary(
                id: 'folder-1',
                name: 'Notes',
                repoPath: '/notes',
                kind: 'folder',
              ),
            ],
            workspaces: const <WorkspaceSummary>[
              WorkspaceSummary(
                id: 'main-1',
                projectId: 'project-1',
                name: 'Main',
                path: '/workspaces/alera',
                branch: 'main',
                kind: 'main',
              ),
              WorkspaceSummary(
                id: 'notes-1',
                projectId: 'folder-1',
                name: 'Shared',
                path: '/workspaces/notes',
                branch: 'feature/shared',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Alera / Main - main'), findsOneWidget);
    await tester.tap(find.text('Alera / Main - main'));
    await tester.pumpAndSettle();
    expect(find.text('Notes / Shared - feature/shared'), findsOneWidget);
    await tester.tap(find.text('Notes / Shared - feature/shared'));
    await tester.pumpAndSettle();
    expect(find.text('Notes / Shared - feature/shared'), findsOneWidget);

    await tester.tap(find.text('Alera'));
    await tester.pumpAndSettle();
    expect(find.text('Notes'), findsNothing);
  });

  testWidgets('From Prompt shows AI Dictation when it is enabled', (
    tester,
  ) async {
    final client = FakeTerminalClient()
      ..projectBranches = const <String>['main'];
    addTearDown(client.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceClientProvider('host-1').overrideWith((ref) async => client),
          terminalClientProvider('host-1').overrideWith((ref) async => client),
          mobileAiDictationSettingsControllerProvider.overrideWith(
            () => FakeMobileAiDictationSettingsController(
              const MobileAiDictationSettings(enabled: true),
            ),
          ),
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

    final promptField = tester.getRect(
      find.widgetWithText(TextField, 'Initial Prompt'),
    );
    final dictationControl = tester.getRect(
      find.byKey(const ValueKey<String>('prompt-workspace-dictation-control')),
    );
    expect(find.byTooltip('Start Dictation'), findsOneWidget);
    expect(promptField.right - dictationControl.right, lessThan(48));
    expect(promptField.bottom - dictationControl.bottom, lessThan(48));

    await tester.tap(find.text('Manual'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('prompt-workspace-dictation-control')),
      findsNothing,
    );
  });

  testWidgets('From Prompt hides AI Dictation when it is disabled', (
    tester,
  ) async {
    final client = FakeTerminalClient()
      ..projectBranches = const <String>['main'];
    addTearDown(client.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceClientProvider('host-1').overrideWith((ref) async => client),
          terminalClientProvider('host-1').overrideWith((ref) async => client),
          mobileAiDictationSettingsControllerProvider.overrideWith(
            () => FakeMobileAiDictationSettingsController(),
          ),
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

    expect(
      find.byKey(const ValueKey<String>('prompt-workspace-dictation-control')),
      findsNothing,
    );
  });
}
