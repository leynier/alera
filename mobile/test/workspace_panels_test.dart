import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_providers.dart';
import 'package:alera_mobile/src/features/terminal/presentation/workspace_tabs_screen.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_panels_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_terminal_client.dart';

void main() {
  test('parses explorer, search, git, and pull request payloads', () {
    final entry = MobileExplorerEntry.fromJson(const <String, Object?>{
      'relativePath': 'lib/main.dart',
      'name': 'main.dart',
      'kind': 'file',
      'size': 12,
      'isHidden': false,
      'hasChildrenHint': false,
    });
    expect(entry.isFile, isTrue);
    final search = MobileWorkspaceSearchResult.fromJson(const <String, Object?>{
      'totalMatches': 1,
      'truncated': false,
      'files': <Object?>[
        <String, Object?>{
          'relativePath': 'lib/main.dart',
          'matches': <Object?>[
            <String, Object?>{
              'id': 'lib/main.dart:1:1',
              'line': 1,
              'column': 1,
              'matchLength': 4,
              'lineContent': 'void main() {}',
            },
          ],
        },
      ],
    });
    expect(search.files.single.matches.single.line, 1);
    final git = MobileGitStatusSnapshot.fromJson(const <String, Object?>{
      'isRepository': true,
      'branch': 'main',
      'writable': false,
      'entries': <Object?>[
        <String, Object?>{
          'path': 'lib/main.dart',
          'area': 'unstaged',
          'status': 'modified',
          'added': 1,
          'removed': 1,
        },
      ],
    });
    expect(git.writable, isFalse);
    expect(git.entries.single.status, 'modified');
    expect(git.changedFileCount, 1);
    expect(git.addedLineCount, 1);
    expect(git.removedLineCount, 1);
    final pr = MobilePullRequestSnapshot.fromJson(const <String, Object?>{
      'branch': 'feat/panels',
      'provider': 'github',
      'authStatus': 'authenticated',
      'identity': <String, Object?>{
        'provider': 'github',
        'host': 'github.com',
        'owner': 'leynier',
        'repo': 'alera',
      },
      'review': <String, Object?>{
        'number': 639,
        'title': 'Add mobile panels',
        'state': 'OPEN',
        'url': 'https://github.com/leynier/alera/pull/639',
        'author': 'leynier',
        'checks': <Object?>[
          <String, Object?>{'name': 'CI', 'bucket': 'pass'},
        ],
        'comments': <Object?>[
          <String, Object?>{
            'id': 1,
            'author': 'reviewer',
            'body': 'Looks good',
          },
        ],
      },
    });
    expect(pr.identity?.label, 'leynier/alera');
    expect(pr.review?.number, 639);
    expect(pr.review?.title, 'Add mobile panels');
    expect(pr.review?.state, 'OPEN');
    expect(pr.review?.checks.single.bucket, 'pass');
    expect(pr.review?.comments.single.body, 'Looks good');
  });

  testWidgets('shows the four panels when the host advertises them', (
    tester,
  ) async {
    final client = FakeTerminalClient()
      ..tabs = <WorkspaceTabSummary>[fakeTab(id: 'tab-1', title: 'Terminal 1')]
      ..explorerSupported = true
      ..workspaceSearchSupported = true
      ..sourceControlSupported = true
      ..pullRequestsSupported = true
      ..explorerEntries = const <MobileExplorerEntry>[
        MobileExplorerEntry(
          relativePath: 'readme.md',
          name: 'readme.md',
          kind: 'file',
        ),
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
    expect(find.text('Terminal'), findsWidgets);
    expect(find.text('Explorer'), findsOneWidget);
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Source Control'), findsOneWidget);
    expect(find.text('Pull Request'), findsOneWidget);

    await tester.tap(find.text('Explorer'));
    await tester.pumpAndSettle();
    expect(find.text('readme.md'), findsOneWidget);
  });

  testWidgets('hides panel navigation on older hosts', (tester) async {
    final client = FakeTerminalClient()
      ..tabs = <WorkspaceTabSummary>[fakeTab(id: 'tab-1', title: 'Terminal 1')];
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
    expect(find.byType(NavigationBar), findsNothing);
    expect(
      ProviderScope.containerOf(
        tester.element(find.byType(WorkspaceTabsScreen)),
      ).read(selectedWorkspacePanelControllerProvider('host-1', 'workspace-1')),
      WorkspacePanelDestination.terminal,
    );
  });
}
