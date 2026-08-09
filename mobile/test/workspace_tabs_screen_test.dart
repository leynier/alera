import 'dart:async';

import 'package:alera_mobile/src/design_system/forms/alera_rename_dialog.dart';
import 'package:alera_mobile/src/features/codex_chat/application/mobile_codex_controller.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_providers.dart';
import 'package:alera_mobile/src/features/terminal/presentation/terminal_keys_settings_screen.dart';
import 'package:alera_mobile/src/features/terminal/presentation/workspace_tabs_screen.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_terminal_client.dart';
import 'support/fake_mobile_codex_client.dart';

void main() {
  testWidgets('Completes tab closure after the tabs screen unmounts', (
    tester,
  ) async {
    final close = Completer<void>();
    final terminalClient = FakeTerminalClient()
      ..tabs = <WorkspaceTabSummary>[
        fakeTab(id: 'codex-1', title: 'Codex Chat', kind: 'codex'),
      ]
      ..removeTabCompletion = close.future;
    final codexClient = FakeMobileCodexClient();
    addTearDown(terminalClient.dispose);
    addTearDown(codexClient.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          terminalClientProvider(
            'host-1',
          ).overrideWith((ref) async => terminalClient),
          workspaceClientProvider(
            'host-1',
          ).overrideWith((ref) async => terminalClient),
          mobileCodexClientProvider(
            'host-1',
          ).overrideWith((ref) async => codexClient),
        ],
        child: const MaterialApp(
          home: WorkspaceTabsScreen(
            hostId: 'host-1',
            workspace: WorkspaceSummary(
              id: 'workspace-1',
              projectId: 'project-1',
              name: 'Workspace',
              path: '/repo',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Close Tab'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Close'));
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    close.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('Does Not Attach A Terminal Session For A Codex Tab', (
    tester,
  ) async {
    final terminalClient = FakeTerminalClient()
      ..tabs = <WorkspaceTabSummary>[
        fakeTab(id: 'codex-1', title: 'Codex Chat', kind: 'codex'),
      ];
    final codexClient = FakeMobileCodexClient();
    addTearDown(terminalClient.dispose);
    addTearDown(codexClient.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          terminalClientProvider(
            'host-1',
          ).overrideWith((ref) async => terminalClient),
          workspaceClientProvider(
            'host-1',
          ).overrideWith((ref) async => terminalClient),
          mobileCodexClientProvider(
            'host-1',
          ).overrideWith((ref) async => codexClient),
        ],
        child: const MaterialApp(
          home: WorkspaceTabsScreen(
            hostId: 'host-1',
            workspace: WorkspaceSummary(
              id: 'workspace-1',
              projectId: 'project-1',
              name: 'Workspace',
              path: '/repo',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(terminalClient.attachments, isEmpty);
  });

  testWidgets('Does Not Offer Generic Rename For A Codex Tab', (tester) async {
    final terminalClient = FakeTerminalClient()
      ..tabs = <WorkspaceTabSummary>[
        fakeTab(id: 'codex-1', title: 'Codex Chat', kind: 'codex'),
      ];
    final codexClient = FakeMobileCodexClient();
    addTearDown(terminalClient.dispose);
    addTearDown(codexClient.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          terminalClientProvider(
            'host-1',
          ).overrideWith((ref) async => terminalClient),
          workspaceClientProvider(
            'host-1',
          ).overrideWith((ref) async => terminalClient),
          mobileCodexClientProvider(
            'host-1',
          ).overrideWith((ref) async => codexClient),
        ],
        child: const MaterialApp(
          home: WorkspaceTabsScreen(
            hostId: 'host-1',
            workspace: WorkspaceSummary(
              id: 'workspace-1',
              projectId: 'project-1',
              name: 'Workspace',
              path: '/repo',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Codex Chat'));
    await tester.pumpAndSettle();

    expect(find.text('Rename Tab'), findsNothing);
    expect(find.text('Close Tab'), findsOneWidget);
  });

  testWidgets('Shows automatic titles in the tab chip and tab dialogs', (
    tester,
  ) async {
    final client = FakeTerminalClient()
      ..tabs = <WorkspaceTabSummary>[
        fakeTab(id: 'tab-1', title: 'Terminal 1', runtimeTitle: 'Initial Task'),
      ];
    addTearDown(client.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          terminalClientProvider('host-1').overrideWith((ref) async => client),
          workspaceClientProvider('host-1').overrideWith((ref) async => client),
        ],
        child: const MaterialApp(
          home: WorkspaceTabsScreen(
            hostId: 'host-1',
            workspace: WorkspaceSummary(
              id: 'workspace-1',
              projectId: 'project-1',
              name: 'Workspace',
              path: '/repo',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Initial Task'), findsOneWidget);
    expect(tester.widget<InputChip>(find.byType(InputChip)).avatar, isNull);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byTooltip('Configure Quick Keys'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Configure Quick Keys'));
    await tester.pumpAndSettle();
    expect(find.byType(TerminalKeysSettingsScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    client.emitTerminalTitle(
      workspaceId: 'workspace-1',
      tabId: 'tab-1',
      title: 'Updated Task',
    );
    await tester.pumpAndSettle();
    expect(find.text('Updated Task'), findsOneWidget);

    await tester.tap(find.byTooltip('Close Tab'));
    await tester.pumpAndSettle();
    expect(find.text('Updated Task'), findsNWidgets(2));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Updated Task'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename Tab'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byType(AleraRenameDialog),
        matching: find.byType(TextField),
      ),
    );
    expect(field.controller?.text, 'Updated Task');
  });
}
