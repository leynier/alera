import 'dart:async';

import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/workbench/application/source_control_watcher.dart';
import 'package:alera/src/features/workbench/application/workspace_file_service.dart';
import 'package:alera/src/features/workbench/application/workbench_providers.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_source_control_scope.dart';
import 'package:alera/src/features/workbench/presentation/terminal_path_drop.dart';
import 'package:alera/src/features/workbench/presentation/workspace_explorer.dart';
import 'package:alera/src/features/workbench/presentation/workspace_git_diff_panel.dart';
import 'package:alera/src/rust/api/workspace_files.dart' as native;
import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../unit/fake_git_backend.dart';
import '../unit/fake_source_control_watcher.dart';

void main() {
  testWidgets('Explorer exposes absolute file and folder drag paths', (
    tester,
  ) async {
    final service = _PathDragWorkspaceFileService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceFileServiceProvider.overrideWithValue(service),
          gitBackendProvider.overrideWithValue(FakeGitBackend()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              height: 480,
              child: WorkspaceExplorer(
                workspace: _workspace(),
                mode: WorkspaceExplorerMode.hideIgnored,
                onModeChanged: (_) {},
                onOpenFile: (_) {},
                onPathMoved: (_, _) async {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(_terminalDragPaths(tester), <String>{
      '/tmp/project/src',
      '/tmp/project/readme.md',
    });

    final source = tester.getCenter(find.text('readme.md'));
    final target = tester.getCenter(find.text('src'));
    final gesture = await tester.startGesture(source);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await gesture.moveTo(target);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(service.moves, <String>['readme.md->src']);
  });

  for (final viewMode in <GitDiffViewMode>[
    GitDiffViewMode.flat,
    GitDiffViewMode.tree,
  ]) {
    testWidgets(
      'Source Control exposes absolute paths in ${viewMode.name} view',
      (tester) async {
        final backend = FakeGitBackend()
          ..gitStatusResult = const GitStatusResult(
            entries: <GitChangeEntry>[
              GitChangeEntry(
                path: 'lib/main.dart',
                area: GitChangeArea.unstaged,
                status: GitChangeStatus.modified,
              ),
              GitChangeEntry(
                path: 'lib/old file.dart',
                area: GitChangeArea.staged,
                status: GitChangeStatus.deleted,
              ),
            ],
          );

        await _pumpSourceControl(tester, backend, viewMode: viewMode);

        final paths = _terminalDragPaths(tester);
        expect(paths, contains('/tmp/project/lib/main.dart'));
        expect(paths, contains('/tmp/project/lib/old file.dart'));
        if (viewMode == GitDiffViewMode.tree) {
          expect(paths, contains('/tmp/project/lib'));
        } else {
          expect(paths, isNot(contains('/tmp/project/lib')));
        }
      },
    );
  }

  testWidgets('Source Control exposes expanded submodule child paths', (
    tester,
  ) async {
    final backend = FakeGitBackend()
      ..gitStatusResult = const GitStatusResult(
        entries: <GitChangeEntry>[
          GitChangeEntry(
            path: 'modules/sample',
            area: GitChangeArea.unstaged,
            status: GitChangeStatus.modified,
            submodule: GitSubmoduleStatus(
              commitChanged: false,
              trackedChanges: true,
              untrackedChanges: false,
              inspectable: true,
            ),
          ),
        ],
      )
      ..gitSubmoduleStatusResult = const GitStatusResult(
        entries: <GitChangeEntry>[
          GitChangeEntry(
            path: 'README.md',
            area: GitChangeArea.unstaged,
            status: GitChangeStatus.modified,
          ),
        ],
      );

    await _pumpSourceControl(tester, backend, viewMode: GitDiffViewMode.flat);
    await tester.tap(find.text('modules/sample'));
    await tester.pumpAndSettle();

    expect(
      _terminalDragPaths(tester),
      containsAll(<String>[
        '/tmp/project/modules/sample',
        '/tmp/project/modules/sample/README.md',
      ]),
    );
  });
}

Future<void> _pumpSourceControl(
  WidgetTester tester,
  FakeGitBackend backend, {
  required GitDiffViewMode viewMode,
}) async {
  final workspace = _workspace();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        gitBackendProvider.overrideWithValue(backend),
        sourceControlWatcherProvider.overrideWithValue(
          FakeSourceControlWatcher(),
        ),
        settingsControllerProvider.overrideWith(
          _PathDragSettingsController.new,
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 440,
            height: 540,
            child: WorkspaceGitDiffPanel(
              workspace: workspace,
              sourceControlScope: WorkspaceSourceControlScope(
                workspaceId: workspace.id,
                workspacePath: workspace.path,
                path: workspace.path,
              ),
              viewMode: viewMode,
              onViewModeChanged: (_) {},
              onOpenGitDiff:
                  ({area, relativePath, gitDiffRoot, required scope}) async {},
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
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Set<String> _terminalDragPaths(WidgetTester tester) {
  final finder = find.byWidgetPredicate(
    (widget) => widget is TerminalPathLongPressDraggable,
  );
  return <String>{
    for (final element in finder.evaluate())
      ...(element.widget as TerminalPathLongPressDraggable).data.paths,
  };
}

Workspace _workspace() {
  final now = DateTime.utc(2026);
  return Workspace(
    id: 'workspace-1',
    projectId: 'project-1',
    name: 'Main',
    path: '/tmp/project',
    createdAt: now,
    updatedAt: now,
    kind: WorkspaceKind.main,
    status: WorkspaceStatus.active,
  );
}

class _PathDragSettingsController extends SettingsController {
  @override
  AleraSettings build() => AleraSettings.defaults;
}

class _PathDragWorkspaceFileService extends WorkspaceFileService {
  final StreamController<native.WorkspaceExplorerWatchBatch> _events =
      StreamController<native.WorkspaceExplorerWatchBatch>.broadcast();

  static final List<native.WorkspaceFileEntry> _entries =
      <native.WorkspaceFileEntry>[
        _entry('src', native.WorkspaceFileKind.directory),
        _entry('readme.md', native.WorkspaceFileKind.file),
      ];
  final List<String> moves = <String>[];

  @override
  Future<List<native.WorkspaceFileEntry>> listChildren({
    required String workspacePath,
    required String relativePath,
    required bool hideIgnored,
  }) async {
    return relativePath.isEmpty
        ? _entries
        : const <native.WorkspaceFileEntry>[];
  }

  @override
  Future<native.WorkspaceExplorerTreeProjection> projectExplorerTree({
    required String workspaceName,
    required String workspacePath,
    required List<native.WorkspaceExplorerDirectoryChildren> directories,
    native.WorkspaceExplorerDirectoryChildren? replacement,
  }) async {
    final root = native.WorkspaceExplorerTreeNode(
      id: 'workspace-root',
      name: workspaceName,
      kind: native.WorkspaceExplorerTreeNodeKind.root,
      parentId: '',
      virtualPath: '/',
      sourcePath: workspacePath,
      childIds: <String>['path:src', 'path:readme.md'],
      isExpanded: true,
      isVirtual: false,
    );
    return native.WorkspaceExplorerTreeProjection(
      directories: <native.WorkspaceExplorerDirectoryChildren>[
        native.WorkspaceExplorerDirectoryChildren(
          relativePath: '',
          children: _entries,
        ),
      ],
      nodes: <native.WorkspaceExplorerTreeNode>[
        root,
        _node(_entries[0], native.WorkspaceExplorerTreeNodeKind.folder),
        _node(_entries[1], native.WorkspaceExplorerTreeNodeKind.file),
      ],
      entryBindings: <native.WorkspaceExplorerEntryBinding>[
        for (final entry in _entries)
          native.WorkspaceExplorerEntryBinding(
            nodeId: 'path:${entry.relativePath}',
            relativePath: entry.relativePath,
          ),
      ],
    );
  }

  @override
  Future<native.WorkspaceExplorerWatcherHandle> startExplorerWatcher({
    required String workspacePath,
  }) async {
    return const native.WorkspaceExplorerWatcherHandle(id: 'watcher');
  }

  @override
  Future<void> updateExplorerWatcher({
    required native.WorkspaceExplorerWatcherHandle handle,
    required List<String> watchedRelativePaths,
  }) async {}

  @override
  Stream<native.WorkspaceExplorerWatchBatch> watchExplorerEvents({
    required native.WorkspaceExplorerWatcherHandle handle,
  }) {
    return _events.stream;
  }

  @override
  Future<void> stopExplorerWatcher({
    required native.WorkspaceExplorerWatcherHandle handle,
  }) async {}

  @override
  Future<native.WorkspaceFileEntry> moveEntry({
    required String workspacePath,
    required String relativePath,
    required String targetParentRelativePath,
  }) async {
    moves.add('$relativePath->$targetParentRelativePath');
    return _entry(
      '$targetParentRelativePath/${relativePath.split('/').last}',
      native.WorkspaceFileKind.file,
    );
  }
}

native.WorkspaceFileEntry _entry(
  String relativePath,
  native.WorkspaceFileKind kind,
) {
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
    hasChildrenHint: false,
  );
}

native.WorkspaceExplorerTreeNode _node(
  native.WorkspaceFileEntry entry,
  native.WorkspaceExplorerTreeNodeKind kind,
) {
  return native.WorkspaceExplorerTreeNode(
    id: 'path:${entry.relativePath}',
    name: entry.name,
    kind: kind,
    parentId: 'workspace-root',
    virtualPath: '/${entry.relativePath}',
    sourcePath: entry.relativePath,
    entryId: entry.relativePath,
    childIds: <String>[],
    isExpanded: false,
    isVirtual: false,
  );
}
