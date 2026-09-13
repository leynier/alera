import 'package:alera_mobile/src/app/theme/alera_theme.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_providers.dart';
import 'package:alera_mobile/src/features/terminal/presentation/workspace_tabs_screen.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workbench/domain/mobile_view_prefs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_terminal_client.dart';

void main() {
  testWidgets('source control tree view nests files and collapses', (
    tester,
  ) async {
    final client = _panelClient()
      ..gitStatusSnapshot = const MobileGitStatusSnapshot(
        isRepository: true,
        branch: 'main',
        entries: <MobileGitChange>[
          MobileGitChange(
            path: 'lib/main.dart',
            area: 'unstaged',
            status: 'modified',
          ),
          MobileGitChange(path: 'readme.md', area: 'staged', status: 'added'),
        ],
      );
    addTearDown(client.dispose);

    await _pumpWorkspace(tester, client, surface: const Size(390, 844));
    await _openWorkspacePanel(tester, 'Source Control');

    expect(find.text('lib'), findsOneWidget);
    expect(find.text('main.dart'), findsOneWidget);
    await tester.tap(find.text('lib'));
    await tester.pumpAndSettle();
    expect(find.text('main.dart'), findsNothing);

    await tester.tap(find.byTooltip('View Options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show All Changes'));
    await tester.pumpAndSettle();
    expect(client.viewPrefs.gitDiffGroupMode, MobileGitDiffGroupMode.unified);
    expect(find.text('CHANGES'), findsOneWidget);
    expect(find.text('STAGED'), findsNothing);

    await tester.tap(find.byTooltip('Filter Files'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'readme');
    await tester.pumpAndSettle();
    expect(find.text('readme.md'), findsOneWidget);
    expect(find.text('lib'), findsNothing);
  });

  testWidgets('search replace previews and confirms replace all', (
    tester,
  ) async {
    final client = _panelClient()
      ..workspaceReplaceSupported = true
      ..searchResult = const MobileWorkspaceSearchResult(
        totalMatches: 1,
        files: <MobileWorkspaceSearchFile>[
          MobileWorkspaceSearchFile(
            relativePath: 'lib/main.dart',
            contentToken: '1:1',
            matches: <MobileWorkspaceSearchMatch>[
              MobileWorkspaceSearchMatch(
                id: 'lib/main.dart:1:6:0',
                line: 1,
                column: 6,
                matchLength: 3,
                lineContent: 'void foo() {}',
                replacementPreview: 'bar',
              ),
            ],
          ),
        ],
      )
      ..replaceResult = const MobileWorkspaceReplaceResult(
        filesChanged: 1,
        matchesReplaced: 1,
      );
    addTearDown(client.dispose);

    await _pumpWorkspace(tester, client, surface: const Size(390, 844));
    await _openWorkspacePanel(tester, 'Search');
    await tester.enterText(find.byType(TextField).first, 'foo');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('1 match in 1 file'), findsOneWidget);

    await tester.tap(find.text('Replace'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), 'bar');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Replace Match'), findsOneWidget);
    expect(find.byTooltip('Replace in File'), findsOneWidget);

    await tester.tap(find.byTooltip('Replace All'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Replace 1 match in 1 file'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Replace'));
    await tester.pumpAndSettle();

    expect(client.replaceRequests.single['matchIds'], isEmpty);
    expect(find.text('Replaced 1 match.'), findsOneWidget);
  });

  testWidgets('search hides replace on a host without the capability', (
    tester,
  ) async {
    final client = _panelClient();
    addTearDown(client.dispose);

    await _pumpWorkspace(tester, client, surface: const Size(390, 844));
    await _openWorkspacePanel(tester, 'Search');

    expect(find.text('Replace'), findsNothing);
    await tester.tap(find.byTooltip('View Options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search Ignored Files'));
    await tester.pumpAndSettle();
    expect(client.viewPrefs.searchIncludeIgnored, isTrue);
  });
}

FakeTerminalClient _panelClient() => FakeTerminalClient()
  ..tabs = <WorkspaceTabSummary>[fakeTab(id: 'tab-1', title: 'Terminal 1')]
  ..explorerSupported = true
  ..workspaceSearchSupported = true
  ..sourceControlSupported = true
  ..pullRequestsSupported = true;

Future<void> _pumpWorkspace(
  WidgetTester tester,
  FakeTerminalClient client, {
  Size? surface,
}) async {
  if (surface != null) {
    await tester.binding.setSurfaceSize(surface);
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        terminalClientProvider('host-1').overrideWith((ref) async => client),
        workspaceClientProvider('host-1').overrideWith((ref) async => client),
      ],
      child: MaterialApp(
        theme: buildAleraMobileDarkTheme(),
        home: const WorkspaceTabsScreen(
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
}

Future<void> _openWorkspacePanel(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('More Actions'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}
