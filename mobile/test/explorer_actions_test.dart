import 'package:alera_mobile/src/app/theme/alera_theme.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_providers.dart';
import 'package:alera_mobile/src/features/terminal/presentation/workspace_tabs_screen.dart';
import 'package:alera_mobile/src/features/workbench/application/explorer_preferences_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_panels_controller.dart';
import 'package:alera_mobile/src/features/workbench/domain/explorer_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_terminal_client.dart';
import 'support/memory_explorer_preferences_repository.dart';

const MobileExplorerEntry _lib = MobileExplorerEntry(
  relativePath: 'lib',
  name: 'lib',
  kind: 'directory',
);
const MobileExplorerEntry _main = MobileExplorerEntry(
  relativePath: 'lib/main.dart',
  name: 'main.dart',
  kind: 'file',
);
const MobileExplorerEntry _service = MobileExplorerEntry(
  relativePath: 'service',
  name: 'service',
  kind: 'directory',
);
const MobileExplorerEntry _build = MobileExplorerEntry(
  relativePath: 'build',
  name: 'build',
  kind: 'directory',
);

void main() {
  late FakeTerminalClient client;
  late MemoryExplorerPreferencesRepository preferences;

  setUp(() {
    client = FakeTerminalClient()
      ..tabs = <WorkspaceTabSummary>[fakeTab(id: 'tab-1', title: 'Terminal 1')]
      ..explorerSupported = true
      ..sourceControlSupported = true
      ..explorerEntries = const <MobileExplorerEntry>[_lib, _main, _service]
      ..ignoredExplorerEntries = const <MobileExplorerEntry>[_build];
    preferences = MemoryExplorerPreferencesRepository();
  });

  tearDown(() => client.dispose());

  testWidgets('hide ignored toggle persists and keeps folders open', (
    tester,
  ) async {
    await _pumpExplorer(tester, client, preferences);
    await tester.tap(find.text('lib'));
    await tester.pumpAndSettle();
    expect(find.text('main.dart'), findsOneWidget);
    expect(find.text('build'), findsNothing);

    client.calls.clear();
    await tester.tap(find.byTooltip('Show Ignored Files'));
    await tester.pumpAndSettle();

    expect(find.text('build'), findsOneWidget);
    expect(find.text('main.dart'), findsOneWidget);
    expect(
      client.calls,
      containsAll(<String>[
        'listExplorerChildren workspace-1  showAll',
        'listExplorerChildren workspace-1 lib showAll',
      ]),
    );
    expect(
      preferences.saved['host-1/workspace-1'],
      const ExplorerPreferences(hideIgnored: false),
    );
    expect(find.byTooltip('Hide Ignored Files'), findsOneWidget);
  });

  testWidgets('restores the saved ignore mode on open', (tester) async {
    preferences.saved['host-1/workspace-1'] = const ExplorerPreferences(
      hideIgnored: false,
    );
    await _pumpExplorer(tester, client, preferences);
    expect(find.text('build'), findsOneWidget);
  });

  testWidgets('collapse all closes folders without a request', (tester) async {
    await _pumpExplorer(tester, client, preferences);
    await tester.tap(find.text('lib'));
    await tester.pumpAndSettle();
    client.calls.clear();

    await tester.tap(find.byTooltip('Collapse All'));
    await tester.pumpAndSettle();

    expect(find.text('main.dart'), findsNothing);
    expect(client.calls, isEmpty);
  });

  testWidgets('refresh re-reads the root and open folders', (tester) async {
    await _pumpExplorer(tester, client, preferences);
    await tester.tap(find.text('lib'));
    await tester.pumpAndSettle();
    client.calls.clear();

    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();

    expect(client.calls, <String>[
      'listExplorerChildren workspace-1 ',
      'listExplorerChildren workspace-1 lib',
    ]);
    expect(find.text('main.dart'), findsOneWidget);
  });

  testWidgets('long press copies host and relative paths', (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await _pumpExplorer(tester, client, preferences);
    await tester.tap(find.text('lib'));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('main.dart'));
    await tester.pumpAndSettle();
    expect(find.text('Open File'), findsOneWidget);
    expect(find.text('Comment on File'), findsOneWidget);
    expect(find.text('Rename'), findsNothing);
    expect(find.text('Delete'), findsNothing);
    await tester.tap(find.text('Copy Path'));
    await tester.pumpAndSettle();
    expect(find.text('Path copied'), findsOneWidget);

    await tester.longPress(find.text('main.dart'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy Relative Path'));
    await tester.pumpAndSettle();

    expect(copied, <String>['/repo/lib/main.dart', 'lib/main.dart']);
  });

  testWidgets('comments queue in a draft bar', (tester) async {
    await _pumpExplorer(tester, client, preferences);
    await tester.tap(find.text('lib'));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('main.dart'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Comment on File'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Rename the entry point');
    await tester.tap(find.text('Add Comment'));
    await tester.pumpAndSettle();

    expect(find.text('1 comment'), findsOneWidget);
    expect(find.text('lib/main.dart: Rename the entry point'), findsOneWidget);
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(find.text('1 comment'), findsNothing);
  });

  testWidgets('source control root needs the host capability', (tester) async {
    await _pumpExplorer(tester, client, preferences);
    await tester.longPress(find.text('service'));
    await tester.pumpAndSettle();
    expect(find.text('Use As Source Control Root'), findsNothing);
    expect(find.text('Copy Path'), findsOneWidget);
  });

  testWidgets('a folder without its own repository is not saved as root', (
    tester,
  ) async {
    client.sourceControlRootSupported = true;
    await _pumpExplorer(tester, client, preferences);

    await tester.longPress(find.text('lib'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use As Source Control Root'));
    await tester.pumpAndSettle();

    expect(find.text('Folder is not a Git repository'), findsOneWidget);
    expect(client.calls, contains('gitStatus workspace-1 lib'));
    expect(preferences.saved['host-1/workspace-1']?.sourceControlRoot, isNull);
  });

  testWidgets('a nested repository becomes the Source Control root', (
    tester,
  ) async {
    client
      ..sourceControlRootSupported = true
      ..gitRepositoryRoots = const <String>{'service'}
      ..gitStatusSnapshot = const MobileGitStatusSnapshot(
        isRepository: true,
        branch: 'main',
        entries: <MobileGitChange>[
          MobileGitChange(path: 'api.rs', area: 'unstaged', status: 'modified'),
        ],
      );
    await _pumpExplorer(tester, client, preferences);

    await tester.longPress(find.text('service'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use As Source Control Root'));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(WorkspaceTabsScreen)),
    );
    expect(
      container.read(
        selectedWorkspacePanelControllerProvider('host-1', 'workspace-1'),
      ),
      WorkspacePanelDestination.sourceControl,
    );
    expect(find.text('Source control root: service'), findsOneWidget);
    expect(find.text('api.rs'), findsOneWidget);
    expect(
      preferences.saved['host-1/workspace-1']?.sourceControlRoot,
      'service',
    );

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(find.text('Source control root: service'), findsNothing);
    expect(client.calls.last, 'gitStatus workspace-1');
  });
}

Future<void> _pumpExplorer(
  WidgetTester tester,
  FakeTerminalClient client,
  MemoryExplorerPreferencesRepository preferences,
) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        terminalClientProvider('host-1').overrideWith((ref) async => client),
        workspaceClientProvider('host-1').overrideWith((ref) async => client),
        explorerPreferencesRepositoryProvider.overrideWithValue(preferences),
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
  await tester.tap(find.byTooltip('More Actions'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Explorer'));
  await tester.pumpAndSettle();
}
