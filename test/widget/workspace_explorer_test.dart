import 'dart:async';

import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/projects/application/project_providers.dart';
import 'package:alera/src/features/workbench/application/workbench_providers.dart';
import 'package:alera/src/features/workbench/application/workspace_file_service.dart';
import 'package:alera/src/features/workbench/application/workspace_folder_opener.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/presentation/workspace_context_sidebar.dart';
import 'package:alera/src/features/workbench/presentation/workspace_explorer.dart';
import 'package:alera/src/rust/api/workspace_files.dart' as native;
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('single click toggles folders and rows expose click cursors', (
    tester,
  ) async {
    final service = _FakeWorkspaceFileService()
      ..childrenByDirectory[''] = <native.WorkspaceFileEntry>[
        _directory('src', hasChildrenHint: true),
        _file('readme.md'),
      ]
      ..childrenByDirectory['src'] = <native.WorkspaceFileEntry>[
        _file('src/main.dart'),
      ];
    final opened = <String>[];

    await _pumpExplorer(tester, service, onOpenFile: opened.add);

    expect(find.text('src'), findsOneWidget);
    expect(find.text('main.dart'), findsNothing);
    expect(find.byType(SvgPicture), findsNWidgets(2));
    expect(
      find.ancestor(
        of: find.text('src'),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is MouseRegion &&
              widget.cursor == SystemMouseCursors.click,
        ),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('src'));
    await tester.pumpAndSettle();
    expect(find.text('main.dart'), findsOneWidget);

    await tester.tap(find.text('src'));
    await tester.pumpAndSettle();
    expect(find.text('main.dart'), findsNothing);

    await tester.tap(find.text('readme.md'));
    await tester.pumpAndSettle();
    expect(opened, <String>['readme.md']);
  });

  testWidgets(
    'refresh prunes stale expanded children after a folder disappears',
    (tester) async {
      final service = _FakeWorkspaceFileService()
        ..childrenByDirectory[''] = <native.WorkspaceFileEntry>[
          _directory('src', hasChildrenHint: true),
        ]
        ..childrenByDirectory['src'] = <native.WorkspaceFileEntry>[
          _file('src/main.dart'),
        ];

      await _pumpExplorer(tester, service);
      await tester.tap(find.text('src'));
      await tester.pumpAndSettle();
      expect(find.text('main.dart'), findsOneWidget);

      service.childrenByDirectory[''] = const <native.WorkspaceFileEntry>[];
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();

      expect(find.text('src'), findsNothing);
      expect(find.text('main.dart'), findsNothing);
    },
  );

  testWidgets('native watcher refreshes loaded directories after changes', (
    tester,
  ) async {
    final service = _FakeWorkspaceFileService()
      ..childrenByDirectory[''] = <native.WorkspaceFileEntry>[
        _file('readme.md'),
      ];

    await _pumpExplorer(tester, service);
    expect(find.text('external.dart'), findsNothing);

    service.childrenByDirectory[''] = <native.WorkspaceFileEntry>[
      _file('external.dart'),
      _file('readme.md'),
    ];
    service.emitWatchBatch(<String>['']);
    await tester.pumpAndSettle();

    expect(find.text('external.dart'), findsOneWidget);
    expect(service.watchedPathUpdates.last, contains(''));
  });

  testWidgets(
    'context sidebar loads the next workspace explorer without manual refresh',
    (tester) async {
      final stopGate = Completer<void>();
      final service = _FakeWorkspaceFileService(stopGate: stopGate)
        ..childrenByWorkspacePath['/repo/alera'] =
            <String, List<native.WorkspaceFileEntry>>{
              '': <native.WorkspaceFileEntry>[_file('main.dart')],
            }
        ..childrenByWorkspacePath['/repo/alera-feature'] =
            <String, List<native.WorkspaceFileEntry>>{
              '': <native.WorkspaceFileEntry>[_file('feature.dart')],
            };

      await tester.pumpWidget(
        _withWorkspaceFiles(
          service,
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 360,
                height: 520,
                child: _workspaceContextSidebar(_workspace()),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('main.dart'), findsOneWidget);
      expect(find.text('feature.dart'), findsNothing);

      await tester.pumpWidget(
        _withWorkspaceFiles(
          service,
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 360,
                height: 520,
                child: _workspaceContextSidebar(
                  _workspace(
                    id: 'workspace-2',
                    name: 'Feature',
                    path: '/repo/alera-feature',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();

      expect(find.text('main.dart'), findsNothing);
      expect(find.text('feature.dart'), findsOneWidget);

      stopGate.complete();
    },
  );

  testWidgets(
    'ignored files toggle refreshes the listing without manual refresh',
    (tester) async {
      final service = _FakeWorkspaceFileService()
        ..childrenByDirectory[''] = <native.WorkspaceFileEntry>[
          _file('tracked.dart'),
        ]
        ..showAllChildrenByDirectory[''] = <native.WorkspaceFileEntry>[
          _file('ignored.dart'),
          _file('tracked.dart'),
        ];

      await tester.pumpWidget(
        _withWorkspaceFiles(
          service,
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 320,
                height: 480,
                child: const _WorkspaceExplorerModeHarness(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('tracked.dart'), findsOneWidget);
      expect(find.text('ignored.dart'), findsNothing);
      expect(service.listChildrenCalls.last.hideIgnored, isTrue);

      await tester.tap(find.byTooltip('Show ignored files'));
      await tester.pumpAndSettle();

      expect(find.text('tracked.dart'), findsOneWidget);
      expect(find.text('ignored.dart'), findsOneWidget);
      expect(
        service.listChildrenCalls.map((call) => call.hideIgnored),
        containsAllInOrder(<bool>[true, false]),
      );
    },
  );

  testWidgets(
    'ignored files toggle reloads expanded directories with the new filter',
    (tester) async {
      final service = _FakeWorkspaceFileService()
        ..childrenByDirectory[''] = <native.WorkspaceFileEntry>[
          _directory('src', hasChildrenHint: true),
        ]
        ..childrenByDirectory['src'] = <native.WorkspaceFileEntry>[
          _file('src/main.dart'),
        ]
        ..showAllChildrenByDirectory[''] = <native.WorkspaceFileEntry>[
          _directory('src', hasChildrenHint: true),
        ]
        ..showAllChildrenByDirectory['src'] = <native.WorkspaceFileEntry>[
          _file('src/generated.dart'),
          _file('src/main.dart'),
        ];

      await tester.pumpWidget(
        _withWorkspaceFiles(
          service,
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 320,
                height: 480,
                child: const _WorkspaceExplorerModeHarness(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('src'));
      await tester.pumpAndSettle();
      expect(find.text('main.dart'), findsOneWidget);
      expect(find.text('generated.dart'), findsNothing);

      await tester.tap(find.byTooltip('Show ignored files'));
      await tester.pumpAndSettle();

      expect(find.text('main.dart'), findsOneWidget);
      expect(find.text('generated.dart'), findsOneWidget);
      expect(
        service.listChildrenCalls,
        contains(
          const _ListChildrenCall(relativePath: 'src', hideIgnored: false),
        ),
      );
    },
  );

  testWidgets('ignored files toggle clears stale rows when root reload fails', (
    tester,
  ) async {
    final service = _FakeWorkspaceFileService()
      ..childrenByDirectory[''] = <native.WorkspaceFileEntry>[
        _file('tracked.dart'),
      ]
      ..failingListChildrenCalls.add(
        const _ListChildrenCall(relativePath: '', hideIgnored: false),
      );

    await tester.pumpWidget(
      _withWorkspaceFiles(
        service,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              height: 480,
              child: const _WorkspaceExplorerModeHarness(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('tracked.dart'), findsOneWidget);

    await tester.tap(find.byTooltip('Show ignored files'));
    await tester.pumpAndSettle();

    expect(find.text('tracked.dart'), findsNothing);
  });

  testWidgets(
    'ignored files toggle clears stale children when expanded directory reload fails',
    (tester) async {
      final service = _FakeWorkspaceFileService()
        ..childrenByDirectory[''] = <native.WorkspaceFileEntry>[
          _directory('src', hasChildrenHint: true),
        ]
        ..childrenByDirectory['src'] = <native.WorkspaceFileEntry>[
          _file('src/main.dart'),
        ]
        ..showAllChildrenByDirectory[''] = <native.WorkspaceFileEntry>[
          _directory('src', hasChildrenHint: true),
        ]
        ..failingListChildrenCalls.add(
          const _ListChildrenCall(relativePath: 'src', hideIgnored: false),
        );

      await tester.pumpWidget(
        _withWorkspaceFiles(
          service,
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 320,
                height: 480,
                child: const _WorkspaceExplorerModeHarness(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('src'));
      await tester.pumpAndSettle();
      expect(find.text('src'), findsOneWidget);
      expect(find.text('main.dart'), findsOneWidget);

      await tester.tap(find.byTooltip('Show ignored files'));
      await tester.pumpAndSettle();

      expect(find.text('src'), findsOneWidget);
      expect(find.text('main.dart'), findsNothing);
      expect(
        service.listChildrenCalls,
        contains(
          const _ListChildrenCall(relativePath: 'src', hideIgnored: false),
        ),
      );
    },
  );

  testWidgets('save all writes dirty editor documents that are not mounted', (
    tester,
  ) async {
    final service = _FakeWorkspaceFileService();
    final registry = EditorSessionRegistry();
    registry.documentFor('tab-1')
      ..attachFile(workspacePath: _workspace().path, relativePath: 'note.txt')
      ..acceptLoaded(
        native.WorkspaceEditorTextFile(
          rawContent: 'original',
          displayContent: 'original',
          contentToken: 'token-1',
          modifiedMillis: 0,
          size: BigInt.from(8),
        ),
      )
      ..updateCurrentText('changed');

    await _pumpExplorer(tester, service, registry: registry);
    await tester.tap(find.byTooltip('Save all files'));
    await tester.pumpAndSettle();

    expect(service.writtenFiles, <String, String>{'note.txt': 'changed'});
    expect(registry.isDirty('tab-1'), isFalse);
  });

  testWidgets('rows show git status indicators', (tester) async {
    final service = _FakeWorkspaceFileService()
      ..childrenByDirectory[''] = <native.WorkspaceFileEntry>[
        _file('added.dart', gitStatus: native.WorkspaceFileGitStatus.added),
        _file(
          'modified.dart',
          gitStatus: native.WorkspaceFileGitStatus.modified,
        ),
        _file(
          'untracked.dart',
          gitStatus: native.WorkspaceFileGitStatus.untracked,
        ),
      ];

    await _pumpExplorer(tester, service);

    expect(find.text('A'), findsOneWidget);
    expect(find.text('M'), findsOneWidget);
    expect(find.text('U'), findsOneWidget);
  });

  testWidgets('background context menu creates items at workspace root', (
    tester,
  ) async {
    final service = _FakeWorkspaceFileService();
    await _pumpExplorer(tester, service);

    await tester.tapAt(const Offset(250, 220), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('New file'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'root.txt');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(service.createdFiles, <String>['root.txt']);
  });

  testWidgets('context menu copies relative paths and duplicates entries', (
    tester,
  ) async {
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText =
              (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });
    final service = _FakeWorkspaceFileService()
      ..childrenByDirectory[''] = <native.WorkspaceFileEntry>[
        _file('readme.md'),
      ];
    await _pumpExplorer(tester, service);

    await tester.tap(find.text('readme.md'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy relative path'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(copiedText, 'readme.md');

    await tester.tap(find.text('readme.md'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplicate'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(service.copiedFiles, <String>['readme.md->']);
  });

  testWidgets('context menu reveals entries in the file manager', (
    tester,
  ) async {
    final service = _FakeWorkspaceFileService()
      ..childrenByDirectory[''] = <native.WorkspaceFileEntry>[
        _file('readme.md'),
      ];
    final opener = _FakeWorkspaceFolderOpener();
    await _pumpExplorer(tester, service, folderOpener: opener);

    await tester.tap(find.text('readme.md'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reveal in Finder'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(opener.revealedPaths, <String>['/repo/alera/readme.md']);
  });

  testWidgets('context menu focuses and clears source control root', (
    tester,
  ) async {
    final service = _FakeWorkspaceFileService()
      ..childrenByDirectory[''] = <native.WorkspaceFileEntry>[
        _directory('packages', hasChildrenHint: true),
      ]
      ..childrenByDirectory['packages'] = <native.WorkspaceFileEntry>[
        _directory('packages/app', hasChildrenHint: false),
      ];
    final focused = <String>[];
    var cleared = false;

    await _pumpExplorer(
      tester,
      service,
      onFocusSourceControlFolder: (relativePath) async {
        focused.add(relativePath);
        return true;
      },
      onClearSourceControlRoot: () => cleared = true,
    );

    if (find.text('app').evaluate().isEmpty) {
      await tester.tap(find.text('packages'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('app'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use As Source Control Root'));
    await tester.pumpAndSettle();

    expect(focused, <String>['packages/app']);

    await _pumpExplorer(
      tester,
      service,
      focusedSourceControlRoot: 'packages/app',
      onFocusSourceControlFolder: (relativePath) async {
        focused.add(relativePath);
        return true;
      },
      onClearSourceControlRoot: () => cleared = true,
    );
    if (find.text('app').evaluate().isEmpty) {
      await tester.tap(find.text('packages'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('app'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear Source Control Root'));
    await tester.pumpAndSettle();

    expect(cleared, isTrue);
  });

  testWidgets(
    'context menu hides source control root action without callback',
    (tester) async {
      final service = _FakeWorkspaceFileService()
        ..childrenByDirectory[''] = <native.WorkspaceFileEntry>[
          _directory('packages', hasChildrenHint: true),
        ]
        ..childrenByDirectory['packages'] = <native.WorkspaceFileEntry>[
          _directory('packages/app', hasChildrenHint: false),
        ];

      await _pumpExplorer(tester, service);

      if (find.text('app').evaluate().isEmpty) {
        await tester.tap(find.text('packages'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('app'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();

      expect(find.text('Use As Source Control Root'), findsNothing);
      expect(find.text('Clear Source Control Root'), findsNothing);
    },
  );

  testWidgets('creating a file does not use disposed state after unmount', (
    tester,
  ) async {
    final createGate = Completer<void>();
    final service = _FakeWorkspaceFileService(createGate: createGate);

    await _pumpExplorer(tester, service);
    await tester.tap(find.byTooltip('New file'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'created.dart');
    await tester.tap(find.text('Create'));
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    createGate.complete();
    await tester.pumpAndSettle();

    expect(service.createdFiles, <String>['created.dart']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('context sidebar uses rail only while collapsed', (tester) async {
    final service = _FakeWorkspaceFileService();

    await tester.pumpWidget(
      _withWorkspaceFiles(
        service,
        child: MaterialApp(
          home: Scaffold(
            body: WorkspaceContextSidebar(
              workspace: _workspace(),
              prefs: WorkbenchViewPrefs.defaults.copyWith(
                rightSidebarVisible: false,
              ),
              onToggleVisible: () {},
              onResize: (_) {},
              onSetContextPanelTab: (_) {},
              onSetExplorerMode: (_) {},
              onSetGitDiffViewMode: (_) {},
              onOpenFile: (_) {},
              onOpenGitDiff:
                  ({relativePath, area, gitDiffRoot, required scope}) async {},
              onOpenGitCommitDiff:
                  ({
                    relativePath,
                    oldPath,
                    required scope,
                    gitDiffRoot,
                    required commitOid,
                    parentOid,
                    required compareRef,
                    subject,
                    message,
                  }) async {},
              onOpenSearchMatch: (_) {},
              onPathMoved: (_, _) async {},
            ),
          ),
        ),
      ),
    );

    expect(find.byTooltip('Expand panel'), findsOneWidget);
    expect(find.byTooltip('Explorer'), findsOneWidget);
    expect(find.byTooltip('Search'), findsOneWidget);
    expect(find.byTooltip('Source Control'), findsOneWidget);
    expect(find.byIcon(AleraIcons.gitBranch), findsOneWidget);
    expect(
      tester.getTopLeft(find.byTooltip('Explorer')).dy,
      lessThan(tester.getTopLeft(find.byTooltip('Search')).dy),
    );
    expect(
      tester.getTopLeft(find.byTooltip('Search')).dy,
      lessThan(tester.getTopLeft(find.byTooltip('Source Control')).dy),
    );
    expect(find.byType(WorkspaceExplorer), findsNothing);

    await tester.pumpWidget(
      _withWorkspaceFiles(
        service,
        child: MaterialApp(
          home: Scaffold(
            body: WorkspaceContextSidebar(
              workspace: _workspace(),
              prefs: WorkbenchViewPrefs.defaults,
              onToggleVisible: () {},
              onResize: (_) {},
              onSetContextPanelTab: (_) {},
              onSetExplorerMode: (_) {},
              onSetGitDiffViewMode: (_) {},
              onOpenFile: (_) {},
              onOpenGitDiff:
                  ({relativePath, area, gitDiffRoot, required scope}) async {},
              onOpenGitCommitDiff:
                  ({
                    relativePath,
                    oldPath,
                    required scope,
                    gitDiffRoot,
                    required commitOid,
                    parentOid,
                    required compareRef,
                    subject,
                    message,
                  }) async {},
              onOpenSearchMatch: (_) {},
              onPathMoved: (_, _) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Expand panel'), findsNothing);
    expect(find.byTooltip('Collapse panel'), findsOneWidget);
    expect(find.byIcon(AleraIcons.gitBranch), findsOneWidget);
    expect(find.byType(WorkspaceExplorer), findsOneWidget);
  });

  testWidgets('context sidebar hides source control when unavailable', (
    tester,
  ) async {
    final service = _FakeWorkspaceFileService();

    await tester.pumpWidget(
      _withWorkspaceFiles(
        service,
        child: MaterialApp(
          home: Scaffold(
            body: WorkspaceContextSidebar(
              workspace: _workspace(),
              prefs: WorkbenchViewPrefs.defaults.copyWith(
                activeContextPanelTab: WorkbenchContextPanelTab.gitDiff,
              ),
              sourceControlAvailable: false,
              onToggleVisible: () {},
              onResize: (_) {},
              onSetContextPanelTab: (_) {},
              onSetExplorerMode: (_) {},
              onSetGitDiffViewMode: (_) {},
              onOpenFile: (_) {},
              onOpenGitDiff:
                  ({relativePath, area, gitDiffRoot, required scope}) async {},
              onOpenGitCommitDiff:
                  ({
                    relativePath,
                    oldPath,
                    required scope,
                    gitDiffRoot,
                    required commitOid,
                    parentOid,
                    required compareRef,
                    subject,
                    message,
                  }) async {},
              onOpenSearchMatch: (_) {},
              onPathMoved: (_, _) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Explorer'), findsOneWidget);
    expect(find.byTooltip('Search'), findsOneWidget);
    expect(find.byTooltip('Source Control'), findsNothing);
    expect(find.byIcon(AleraIcons.gitBranch), findsNothing);
    expect(find.byType(WorkspaceExplorer), findsOneWidget);

    await tester.pumpWidget(
      _withWorkspaceFiles(
        service,
        child: MaterialApp(
          home: Scaffold(
            body: WorkspaceContextSidebar(
              workspace: _workspace(),
              prefs: WorkbenchViewPrefs.defaults.copyWith(
                activeContextPanelTab: WorkbenchContextPanelTab.gitDiff,
                rightSidebarVisible: false,
              ),
              sourceControlAvailable: false,
              onToggleVisible: () {},
              onResize: (_) {},
              onSetContextPanelTab: (_) {},
              onSetExplorerMode: (_) {},
              onSetGitDiffViewMode: (_) {},
              onOpenFile: (_) {},
              onOpenGitDiff:
                  ({relativePath, area, gitDiffRoot, required scope}) async {},
              onOpenGitCommitDiff:
                  ({
                    relativePath,
                    oldPath,
                    required scope,
                    gitDiffRoot,
                    required commitOid,
                    parentOid,
                    required compareRef,
                    subject,
                    message,
                  }) async {},
              onOpenSearchMatch: (_) {},
              onPathMoved: (_, _) async {},
            ),
          ),
        ),
      ),
    );

    expect(find.byTooltip('Expand panel'), findsOneWidget);
    expect(find.byTooltip('Source Control'), findsNothing);
    expect(find.byIcon(AleraIcons.gitBranch), findsNothing);
  });
}

Future<void> _pumpExplorer(
  WidgetTester tester,
  _FakeWorkspaceFileService service, {
  ValueChanged<String>? onOpenFile,
  EditorSessionRegistry? registry,
  WorkspaceFolderOpener? folderOpener,
  String? focusedSourceControlRoot,
  Future<bool> Function(String relativePath)? onFocusSourceControlFolder,
  VoidCallback? onClearSourceControlRoot,
}) async {
  await tester.pumpWidget(
    _withWorkspaceFiles(
      service,
      registry: registry,
      folderOpener: folderOpener,
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 480,
            child: WorkspaceExplorer(
              workspace: _workspace(),
              mode: WorkspaceExplorerMode.hideIgnored,
              onModeChanged: (_) {},
              onOpenFile: onOpenFile ?? (_) {},
              focusedSourceControlRoot: focusedSourceControlRoot,
              onFocusSourceControlFolder: onFocusSourceControlFolder,
              onClearSourceControlRoot: onClearSourceControlRoot,
              onPathMoved: (_, _) async {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _WorkspaceExplorerModeHarness extends StatefulWidget {
  const _WorkspaceExplorerModeHarness();

  @override
  State<_WorkspaceExplorerModeHarness> createState() =>
      _WorkspaceExplorerModeHarnessState();
}

class _WorkspaceExplorerModeHarnessState
    extends State<_WorkspaceExplorerModeHarness> {
  WorkspaceExplorerMode _mode = WorkspaceExplorerMode.hideIgnored;

  @override
  Widget build(BuildContext context) {
    return WorkspaceExplorer(
      workspace: _workspace(),
      mode: _mode,
      onModeChanged: (mode) => setState(() => _mode = mode),
      onOpenFile: (_) {},
      onPathMoved: (_, _) async {},
    );
  }
}

Widget _withWorkspaceFiles(
  _FakeWorkspaceFileService service, {
  required Widget child,
  EditorSessionRegistry? registry,
  WorkspaceFolderOpener? folderOpener,
}) {
  return ProviderScope(
    overrides: [
      workspaceFileServiceProvider.overrideWithValue(service),
      if (folderOpener != null)
        workspaceFolderOpenerProvider.overrideWithValue(folderOpener),
      if (registry != null)
        editorSessionRegistryProvider.overrideWithValue(registry),
    ],
    child: child,
  );
}

Widget _workspaceContextSidebar(Workspace workspace) {
  return WorkspaceContextSidebar(
    workspace: workspace,
    prefs: WorkbenchViewPrefs.defaults,
    onToggleVisible: () {},
    onResize: (_) {},
    onSetContextPanelTab: (_) {},
    onSetExplorerMode: (_) {},
    onSetGitDiffViewMode: (_) {},
    onOpenFile: (_) {},
    onOpenGitDiff: ({relativePath, area, gitDiffRoot, required scope}) async {},
    onOpenGitCommitDiff:
        ({
          relativePath,
          oldPath,
          required scope,
          gitDiffRoot,
          required commitOid,
          parentOid,
          required compareRef,
          subject,
          message,
        }) async {},
    onOpenSearchMatch: (_) {},
    onPathMoved: (_, _) async {},
  );
}

class _FakeWorkspaceFileService extends WorkspaceFileService {
  _FakeWorkspaceFileService({this.createGate, this.stopGate});

  final Completer<void>? createGate;
  final Completer<void>? stopGate;
  final StreamController<native.WorkspaceExplorerWatchBatch> _watchController =
      StreamController<native.WorkspaceExplorerWatchBatch>.broadcast();
  final Map<String, List<native.WorkspaceFileEntry>> childrenByDirectory =
      <String, List<native.WorkspaceFileEntry>>{};
  final Map<String, Map<String, List<native.WorkspaceFileEntry>>>
  childrenByWorkspacePath =
      <String, Map<String, List<native.WorkspaceFileEntry>>>{};
  final Map<String, List<native.WorkspaceFileEntry>>
  showAllChildrenByDirectory = <String, List<native.WorkspaceFileEntry>>{};
  final Map<String, Map<String, List<native.WorkspaceFileEntry>>>
  showAllChildrenByWorkspacePath =
      <String, Map<String, List<native.WorkspaceFileEntry>>>{};
  final Set<_ListChildrenCall> failingListChildrenCalls = <_ListChildrenCall>{};
  final List<String> createdFiles = <String>[];
  final List<String> copiedFiles = <String>[];
  final List<_ListChildrenCall> listChildrenCalls = <_ListChildrenCall>[];
  final List<List<String>> watchedPathUpdates = <List<String>>[];
  final Map<String, String> writtenFiles = <String, String>{};

  void emitWatchBatch(List<String> directoryRelativePaths) {
    _watchController.add(
      native.WorkspaceExplorerWatchBatch(
        directoryRelativePaths: directoryRelativePaths,
        changedRelativePaths: const <String>[],
        coalescedEventCount: 0,
      ),
    );
  }

  @override
  Future<List<native.WorkspaceFileEntry>> listChildren({
    required String workspacePath,
    required String relativePath,
    required bool hideIgnored,
  }) async {
    final call = _ListChildrenCall(
      relativePath: relativePath,
      hideIgnored: hideIgnored,
    );
    listChildrenCalls.add(call);
    if (failingListChildrenCalls.contains(call)) {
      throw StateError('Failed to list $relativePath');
    }
    final workspaceChildren = childrenByWorkspacePath[workspacePath];
    final workspaceShowAllChildren =
        showAllChildrenByWorkspacePath[workspacePath];
    final workspaceModeChildren = hideIgnored
        ? workspaceChildren
        : workspaceShowAllChildren;
    return workspaceModeChildren?[relativePath] ??
        workspaceChildren?[relativePath] ??
        (hideIgnored
            ? childrenByDirectory[relativePath]
            : showAllChildrenByDirectory[relativePath]) ??
        childrenByDirectory[relativePath] ??
        const <native.WorkspaceFileEntry>[];
  }

  @override
  Future<native.WorkspaceExplorerTreeProjection> projectExplorerTree({
    required String workspaceName,
    required String workspacePath,
    required List<native.WorkspaceExplorerDirectoryChildren> directories,
    native.WorkspaceExplorerDirectoryChildren? replacement,
  }) async {
    return _projectExplorerTree(
      workspaceName: workspaceName,
      workspacePath: workspacePath,
      directories: directories,
      replacement: replacement,
    );
  }

  @override
  Future<native.WorkspaceExplorerWatcherHandle> startExplorerWatcher({
    required String workspacePath,
  }) async {
    return const native.WorkspaceExplorerWatcherHandle(id: 'watcher-1');
  }

  @override
  Future<void> updateExplorerWatcher({
    required native.WorkspaceExplorerWatcherHandle handle,
    required List<String> watchedRelativePaths,
  }) async {
    watchedPathUpdates.add(watchedRelativePaths);
  }

  @override
  Stream<native.WorkspaceExplorerWatchBatch> watchExplorerEvents({
    required native.WorkspaceExplorerWatcherHandle handle,
  }) {
    return _watchController.stream;
  }

  @override
  Future<void> stopExplorerWatcher({
    required native.WorkspaceExplorerWatcherHandle handle,
  }) async {
    await stopGate?.future;
  }

  @override
  Future<native.WorkspaceFileEntry> createFile({
    required String workspacePath,
    required String parentRelativePath,
    required String name,
  }) async {
    createdFiles.add(name);
    await createGate?.future;
    final relativePath = parentRelativePath.isEmpty
        ? name
        : '$parentRelativePath/$name';
    final entry = _file(relativePath);
    childrenByDirectory[parentRelativePath] = <native.WorkspaceFileEntry>[
      ...?childrenByDirectory[parentRelativePath],
      entry,
    ];
    return entry;
  }

  @override
  Future<native.WorkspaceEditorTextFile> writeEditorTextFile({
    required String workspacePath,
    required String relativePath,
    required String currentDisplayContent,
    required String? originalRawContent,
    required String? originalDisplayContent,
    required String? expectedContentToken,
    required bool overwriteIfChanged,
    required int tabSize,
  }) async {
    writtenFiles[relativePath] = currentDisplayContent;
    return native.WorkspaceEditorTextFile(
      rawContent: currentDisplayContent,
      displayContent: currentDisplayContent,
      contentToken: '$relativePath-saved-token',
      modifiedMillis: 1,
      size: BigInt.from(currentDisplayContent.length),
    );
  }

  @override
  Future<native.WorkspaceFileEntry> copyEntry({
    required String workspacePath,
    required String relativePath,
    required String targetParentRelativePath,
  }) async {
    copiedFiles.add('$relativePath->$targetParentRelativePath');
    final copyName = '${relativePath.split('/').last} copy';
    final copyPath = targetParentRelativePath.isEmpty
        ? copyName
        : '$targetParentRelativePath/$copyName';
    final entry = _file(copyPath);
    childrenByDirectory[targetParentRelativePath] = <native.WorkspaceFileEntry>[
      ...?childrenByDirectory[targetParentRelativePath],
      entry,
    ];
    return entry;
  }
}

class _ListChildrenCall {
  const _ListChildrenCall({
    required this.relativePath,
    required this.hideIgnored,
  });

  final String relativePath;
  final bool hideIgnored;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _ListChildrenCall &&
          other.relativePath == relativePath &&
          other.hideIgnored == hideIgnored;

  @override
  int get hashCode => Object.hash(relativePath, hideIgnored);
}

native.WorkspaceExplorerTreeProjection _projectExplorerTree({
  required String workspaceName,
  required String workspacePath,
  required List<native.WorkspaceExplorerDirectoryChildren> directories,
  native.WorkspaceExplorerDirectoryChildren? replacement,
}) {
  final directoriesByPath = <String, List<native.WorkspaceFileEntry>>{
    for (final directory in directories)
      directory.relativePath: directory.children,
  };
  if (replacement != null) {
    final previous = directoriesByPath[replacement.relativePath];
    if (previous != null) {
      final nextPaths = replacement.children
          .map((entry) => entry.relativePath)
          .toSet();
      for (final entry in previous) {
        if (!nextPaths.contains(entry.relativePath)) {
          _removeProjectedSubtree(directoriesByPath, entry.relativePath);
        }
      }
    }
    directoriesByPath[replacement.relativePath] = replacement.children;
  }
  final knownPaths = directoriesByPath.values
      .expand((children) => children.map((entry) => entry.relativePath))
      .toSet();
  directoriesByPath.removeWhere(
    (path, _) => path.isNotEmpty && !knownPaths.contains(path),
  );

  final nodes = <String, native.WorkspaceExplorerTreeNode>{
    'workspace-root': native.WorkspaceExplorerTreeNode(
      id: 'workspace-root',
      name: workspaceName,
      kind: native.WorkspaceExplorerTreeNodeKind.root,
      parentId: '',
      virtualPath: '/',
      sourcePath: workspacePath,
      childIds: <String>[],
      isExpanded: true,
      isVirtual: false,
    ),
  };
  final entryBindings = <native.WorkspaceExplorerEntryBinding>[];
  for (final entries in directoriesByPath.values) {
    for (final entry in entries) {
      _addProjectedEntry(nodes, entryBindings, entry);
      if (entry.kind == native.WorkspaceFileKind.directory &&
          entry.hasChildrenHint &&
          !directoriesByPath.containsKey(entry.relativePath)) {
        _addProjectedPlaceholder(nodes, entry.relativePath);
      }
    }
  }

  return native.WorkspaceExplorerTreeProjection(
    directories: directoriesByPath.entries
        .map(
          (entry) => native.WorkspaceExplorerDirectoryChildren(
            relativePath: entry.key,
            children: entry.value,
          ),
        )
        .toList(growable: false),
    nodes: nodes.values.toList(growable: false),
    entryBindings: entryBindings,
  );
}

void _removeProjectedSubtree(
  Map<String, List<native.WorkspaceFileEntry>> directoriesByPath,
  String relativePath,
) {
  final prefix = '$relativePath/';
  directoriesByPath.removeWhere(
    (path, _) => path == relativePath || path.startsWith(prefix),
  );
  for (final entry in directoriesByPath.entries.toList()) {
    directoriesByPath[entry.key] = entry.value
        .where(
          (child) =>
              child.relativePath != relativePath &&
              !child.relativePath.startsWith(prefix),
        )
        .toList(growable: false);
  }
}

void _addProjectedEntry(
  Map<String, native.WorkspaceExplorerTreeNode> nodes,
  List<native.WorkspaceExplorerEntryBinding> entryBindings,
  native.WorkspaceFileEntry entry,
) {
  final parts = entry.relativePath.split('/');
  var parentId = 'workspace-root';
  var currentPath = '';
  for (var index = 0; index < parts.length; index += 1) {
    final part = parts[index];
    currentPath = currentPath.isEmpty ? part : '$currentPath/$part';
    final isLeaf = index == parts.length - 1;
    final nodeId = 'path:$currentPath';
    if (!nodes.containsKey(nodeId)) {
      nodes[nodeId] = native.WorkspaceExplorerTreeNode(
        id: nodeId,
        name: part,
        kind: isLeaf && entry.kind != native.WorkspaceFileKind.directory
            ? native.WorkspaceExplorerTreeNodeKind.file
            : native.WorkspaceExplorerTreeNodeKind.folder,
        parentId: parentId,
        virtualPath: '/$currentPath',
        sourcePath: currentPath,
        entryId: isLeaf ? entry.relativePath : null,
        childIds: <String>[],
        isExpanded: false,
        isVirtual: false,
      );
      _appendProjectedChild(nodes, parentId, nodeId);
    }
    if (isLeaf) {
      entryBindings.add(
        native.WorkspaceExplorerEntryBinding(
          nodeId: nodeId,
          relativePath: entry.relativePath,
        ),
      );
    }
    parentId = nodeId;
  }
}

void _addProjectedPlaceholder(
  Map<String, native.WorkspaceExplorerTreeNode> nodes,
  String parentPath,
) {
  final parentId = 'path:$parentPath';
  final nodeId = '__alera_placeholder__:$parentPath';
  if (!nodes.containsKey(parentId) || nodes.containsKey(nodeId)) {
    return;
  }
  nodes[nodeId] = native.WorkspaceExplorerTreeNode(
    id: nodeId,
    name: '',
    kind: native.WorkspaceExplorerTreeNodeKind.file,
    parentId: parentId,
    virtualPath: '/$parentPath/.alera-placeholder',
    sourcePath: '',
    childIds: <String>[],
    isExpanded: false,
    isVirtual: true,
  );
  _appendProjectedChild(nodes, parentId, nodeId);
}

void _appendProjectedChild(
  Map<String, native.WorkspaceExplorerTreeNode> nodes,
  String parentId,
  String childId,
) {
  final parent = nodes[parentId];
  if (parent != null && !parent.childIds.contains(childId)) {
    parent.childIds.add(childId);
  }
}

class _FakeWorkspaceFolderOpener extends WorkspaceFolderOpener {
  _FakeWorkspaceFolderOpener() : super(processRunner: _NoopProcessRunner());

  final List<String> revealedPaths = <String>[];

  @override
  Future<WorkspaceFolderOpenResult> reveal(String path) async {
    revealedPaths.add(path);
    return const WorkspaceFolderOpenResult.success();
  }
}

class _NoopProcessRunner implements ProcessRunner {
  @override
  Future<ProcessRunOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    return const ProcessRunOutput(exitCode: 0, stdout: '', stderr: '');
  }

  @override
  Future<StartedProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) {
    throw UnimplementedError();
  }
}

Workspace _workspace({
  String id = 'workspace-1',
  String name = 'alera',
  String path = '/repo/alera',
}) {
  final now = DateTime.utc(2026);
  return Workspace(
    id: id,
    projectId: 'project-1',
    name: name,
    path: path,
    createdAt: now,
    updatedAt: now,
    kind: WorkspaceKind.main,
    status: WorkspaceStatus.active,
  );
}

native.WorkspaceFileEntry _file(
  String relativePath, {
  native.WorkspaceFileGitStatus? gitStatus,
}) {
  return _entry(
    relativePath: relativePath,
    kind: native.WorkspaceFileKind.file,
    hasChildrenHint: false,
    gitStatus: gitStatus,
  );
}

native.WorkspaceFileEntry _directory(
  String relativePath, {
  required bool hasChildrenHint,
  native.WorkspaceFileGitStatus? gitStatus,
}) {
  return _entry(
    relativePath: relativePath,
    kind: native.WorkspaceFileKind.directory,
    hasChildrenHint: hasChildrenHint,
    gitStatus: gitStatus,
  );
}

native.WorkspaceFileEntry _entry({
  required String relativePath,
  required native.WorkspaceFileKind kind,
  required bool hasChildrenHint,
  native.WorkspaceFileGitStatus? gitStatus,
}) {
  return native.WorkspaceFileEntry(
    relativePath: relativePath,
    name: relativePath.split('/').last,
    kind: kind,
    size: BigInt.zero,
    modifiedMillis: 0,
    contentToken: '$relativePath-token',
    isIgnored: false,
    isHidden: false,
    isSymlink: false,
    isProtected: false,
    hasChildrenHint: hasChildrenHint,
    gitStatus: gitStatus,
  );
}
