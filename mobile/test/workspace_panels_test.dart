import 'package:alera_mobile/src/app/theme/alera_theme.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
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
    expect(find.byType(NavigationBar), findsNothing);

    await tester.tap(find.byTooltip('More Actions'));
    await tester.pumpAndSettle();
    expect(find.text('Terminal'), findsOneWidget);
    expect(find.text('Explorer'), findsOneWidget);
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Source Control'), findsOneWidget);
    expect(find.text('Pull Request'), findsOneWidget);
    expect(find.text('Terminal Quick Keys'), findsOneWidget);
    expect(find.byIcon(AleraIcons.folder), findsOneWidget);
    expect(find.byIcon(AleraIcons.search), findsOneWidget);
    expect(find.byIcon(AleraIcons.gitBranch), findsOneWidget);
    expect(find.byIcon(AleraIcons.gitPullRequest), findsOneWidget);

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
    await tester.tap(find.byTooltip('More Actions'));
    await tester.pumpAndSettle();
    expect(find.text('Explorer'), findsNothing);
    expect(find.text('Source Control'), findsNothing);
    expect(find.text('Pull Request'), findsNothing);
    expect(find.text('Terminal Quick Keys'), findsOneWidget);
    expect(
      ProviderScope.containerOf(
        tester.element(find.byType(WorkspaceTabsScreen)),
      ).read(selectedWorkspacePanelControllerProvider('host-1', 'workspace-1')),
      WorkspacePanelDestination.terminal,
    );
  });

  testWidgets('empty terminal state invites a new terminal', (tester) async {
    final client = FakeTerminalClient()
      ..tabs = const <WorkspaceTabSummary>[]
      ..explorerSupported = true
      ..workspaceSearchSupported = true
      ..sourceControlSupported = true
      ..pullRequestsSupported = true;
    addTearDown(client.dispose);

    await _pumpWorkspace(tester, client);
    expect(find.text('No terminals'), findsOneWidget);
    expect(
      find.text('Open a terminal to start working in this workspace.'),
      findsOneWidget,
    );
    expect(find.text('New Terminal'), findsOneWidget);
    expect(find.text('No tabs yet'), findsNothing);
  });

  testWidgets(
    'source control shows compact file names instead of wrapping paths',
    (tester) async {
      const path =
          'lib/src/features/pull_requests/domain/review_stack_workspace_models.dart';
      final client = FakeTerminalClient()
        ..tabs = <WorkspaceTabSummary>[
          fakeTab(id: 'tab-1', title: 'Terminal 1'),
        ]
        ..explorerSupported = true
        ..workspaceSearchSupported = true
        ..sourceControlSupported = true
        ..pullRequestsSupported = true
        ..gitStatusSnapshot = const MobileGitStatusSnapshot(
          isRepository: true,
          branch: 'main',
          entries: <MobileGitChange>[
            MobileGitChange(
              path: path,
              area: 'unstaged',
              status: 'modified',
              added: 1,
              removed: 0,
            ),
          ],
        );
      addTearDown(client.dispose);

      await _pumpWorkspace(tester, client, surface: const Size(390, 844));
      await _openWorkspacePanel(tester, 'Source Control');

      expect(find.text('review_stack_workspace_models.dart'), findsOneWidget);
      expect(find.text('pull_requests/domain'), findsOneWidget);
      expect(find.text(path), findsNothing);
      expect(find.text('UNSTAGED'), findsOneWidget);
      expect(find.text('+1'), findsWidgets);
      expect(find.text('-0'), findsNothing);
      expect(
        find.text(
          'Read-only on mobile. Stage, unstage, and commit stay on desktop.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('pull request checks ellipsize names and color status', (
    tester,
  ) async {
    final client = FakeTerminalClient()
      ..tabs = <WorkspaceTabSummary>[fakeTab(id: 'tab-1', title: 'Terminal 1')]
      ..explorerSupported = true
      ..workspaceSearchSupported = true
      ..sourceControlSupported = true
      ..pullRequestsSupported = true
      ..pullRequest = MobilePullRequestSnapshot.fromJson(
        const <String, Object?>{
          'branch': 'feat/panels',
          'identity': <String, Object?>{'owner': 'leynier', 'repo': 'alera'},
          'review': <String, Object?>{
            'number': 629,
            'title':
                'fix: omit ignored-only directories from workspace listings',
            'state': 'MERGED',
            'url': 'https://github.com/leynier/alera/pull/629',
            'author': 'leynier',
            'headRefName':
                'ship/omit-ignored-only-directories-from-workspace-listings',
            'baseRefName': 'main',
            'checks': <Object?>[
              <String, Object?>{
                'name': r'build app ${{ matrix.platform }}',
                'bucket': 'skipping',
              },
              <String, Object?>{'name': 'cleanup', 'bucket': 'pass'},
            ],
            'comments': <Object?>[],
          },
        },
      );
    addTearDown(client.dispose);

    await _pumpWorkspace(tester, client, surface: const Size(390, 844));
    await _openWorkspacePanel(tester, 'Pull Request');

    expect(find.text('leynier/alera'), findsOneWidget);
    expect(find.text('Merged'), findsOneWidget);
    expect(find.text('MERGED'), findsNothing);
    expect(find.byTooltip('Open In Browser'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Open In Browser'), findsNothing);
    expect(find.text('build app {platform}'), findsOneWidget);
    expect(find.text(r'build app ${{ matrix.platform }}'), findsNothing);
    expect(find.text('Skipped'), findsOneWidget);
    expect(find.text('Pass'), findsOneWidget);
    expect(find.text('cleanup'), findsOneWidget);
    expect(find.text('1 passed · 1 skipped'), findsOneWidget);
    expect(
      tester.getSize(find.text('build app {platform}')).height,
      lessThan(24),
    );
  });
}

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
