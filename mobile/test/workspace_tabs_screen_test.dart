import 'dart:async';

import 'package:alera_mobile/src/design_system/forms/alera_rename_dialog.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_providers.dart';
import 'package:alera_mobile/src/features/terminal/presentation/terminal_keys_settings_screen.dart';
import 'package:alera_mobile/src/features/terminal/presentation/terminal_tab_view.dart';
import 'package:alera_mobile/src/features/terminal/presentation/workspace_tabs_screen.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_terminal_client.dart';

void main() {
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
        matching: find.byTooltip('More Actions'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('More Actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Terminal Quick Keys'));
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

  testWidgets('Keeps the tab body mounted while the host connection reloads', (
    tester,
  ) async {
    // Reconnecting used to swap the body for a spinner, which disposed the
    // tab's state along with any pick whose upload was still in flight.
    final client = FakeTerminalClient()
      ..tabs = <WorkspaceTabSummary>[fakeTab(id: 'tab-1', title: 'Terminal 1')];
    addTearDown(client.dispose);
    final reconnect = Completer<void>();
    var connections = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          terminalClientProvider('host-1').overrideWith((ref) async {
            connections += 1;
            if (connections > 1) await reconnect.future;
            return client;
          }),
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
    expect(find.byType(TerminalTabView), findsOneWidget);

    ProviderScope.containerOf(tester.element(find.byType(WorkspaceTabsScreen)))
        .invalidate(terminalClientProvider('host-1'));
    await tester.pump();

    expect(find.byType(TerminalTabView), findsOneWidget);

    reconnect.complete();
    await tester.pumpAndSettle();
    expect(find.byType(TerminalTabView), findsOneWidget);
  });
}
