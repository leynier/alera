import 'dart:async';

import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_providers.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/application/workspace_file_service.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/presentation/workbench_dialog_launchers.dart';
import 'package:alera/src/rust/api/workspace_files.dart' as native;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets('shows loading, filters files, and opens the selected file', (
    tester,
  ) async {
    final workspace = _workspace('workspace-1', 'Main', '/repo/main');
    final controller = _QuickOpenTestController(_state(workspace));
    final files = Completer<List<native.WorkspaceFileEntry>>();
    final service = _QuickOpenFileService(files: files);
    await _pumpQuickOpen(tester, controller: controller, service: service);

    await tester.tap(find.text('Open Quick Open'));
    await tester.pump();
    expect(find.text('Loading workspace files...'), findsOneWidget);

    files.complete(<native.WorkspaceFileEntry>[
      _file('lib/main.dart'),
      _file('lib/main_test.dart'),
      _file('notes.txt'),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('lib/main.dart'), findsOneWidget);
    expect(find.text('lib/main_test.dart'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'main_test.dart');
    await tester.pump();
    expect(find.text('lib/main.dart'), findsNothing);
    expect(find.text('lib/main_test.dart'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(controller.openedFiles, <String>['lib/main_test.dart']);
  });

  testWidgets('arrow navigation, Escape, and focus restoration work', (
    tester,
  ) async {
    final workspace = _workspace('workspace-1', 'Main', '/repo/main');
    final controller = _QuickOpenTestController(_state(workspace));
    final anchorFocus = FocusNode();
    addTearDown(anchorFocus.dispose);
    await _pumpQuickOpen(
      tester,
      controller: controller,
      service: _QuickOpenFileService(
        entries: <native.WorkspaceFileEntry>[_file('a.dart'), _file('b.dart')],
      ),
      anchorFocus: anchorFocus,
    );
    anchorFocus.requestFocus();
    await tester.pump();

    await tester.tap(find.text('Open Quick Open'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(controller.openedFiles, <String>['b.dart']);
    expect(anchorFocus.hasFocus, isTrue);

    await tester.tap(find.text('Open Quick Open'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Quick Open'), findsNothing);
    expect(anchorFocus.hasFocus, isTrue);
  });

  testWidgets('shows empty and error states', (tester) async {
    final workspace = _workspace('workspace-1', 'Main', '/repo/main');
    final controller = _QuickOpenTestController(_state(workspace));
    await _pumpQuickOpen(
      tester,
      controller: controller,
      service: _QuickOpenFileService(
        entries: const <native.WorkspaceFileEntry>[],
      ),
    );

    await tester.tap(find.text('Open Quick Open'));
    await tester.pumpAndSettle();
    expect(
      find.text('No files are available in this workspace.'),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await _pumpQuickOpen(
      tester,
      controller: controller,
      service: _QuickOpenFileService(error: StateError('enumeration failed')),
    );
    await tester.tap(find.text('Open Quick Open'));
    await tester.pumpAndSettle();
    expect(find.text('Could not load workspace files.'), findsOneWidget);
  });

  testWidgets('restarts the search when the active workspace changes', (
    tester,
  ) async {
    final first = _workspace('workspace-1', 'Main', '/repo/main');
    final second = _workspace('workspace-2', 'Feature', '/repo/feature');
    final controller = _QuickOpenTestController(
      _state(first, extraWorkspaces: <Workspace>[second]),
    );
    final service = _QuickOpenFileService(
      entriesByWorkspacePath: <String, List<native.WorkspaceFileEntry>>{
        first.path: <native.WorkspaceFileEntry>[_file('old.dart')],
        second.path: <native.WorkspaceFileEntry>[_file('new.dart')],
      },
    );
    await _pumpQuickOpen(tester, controller: controller, service: service);

    await tester.tap(find.text('Open Quick Open'));
    await tester.pumpAndSettle();
    expect(find.text('old.dart'), findsOneWidget);

    controller.switchWorkspace(second.id);
    await tester.pumpAndSettle();
    expect(find.text('old.dart'), findsNothing);
    expect(find.text('new.dart'), findsOneWidget);
  });
}

Future<void> _pumpQuickOpen(
  WidgetTester tester, {
  required _QuickOpenTestController controller,
  required _QuickOpenFileService service,
  FocusNode? anchorFocus,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        workbenchControllerProvider.overrideWith(() => controller),
        workspaceFileServiceProvider.overrideWithValue(service),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Focus(
            focusNode: anchorFocus,
            child: Consumer(
              builder: (context, ref, _) => FilledButton(
                onPressed: () => showQuickOpenFlow(context, ref),
                child: const Text('Open Quick Open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

WorkbenchState _state(
  Workspace active, {
  List<Workspace> extraWorkspaces = const <Workspace>[],
}) {
  return WorkbenchState(
    workspacesByProject: <String, List<Workspace>>{
      active.projectId: <Workspace>[active, ...extraWorkspaces],
    },
    activeWorkspaceId: active.id,
  );
}

Workspace _workspace(String id, String name, String path) {
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

native.WorkspaceFileEntry _file(String relativePath) {
  return native.WorkspaceFileEntry(
    relativePath: relativePath,
    name: relativePath.split('/').last,
    kind: native.WorkspaceFileKind.file,
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

class _QuickOpenFileService extends WorkspaceFileService {
  _QuickOpenFileService({
    this.entries = const <native.WorkspaceFileEntry>[],
    this.error,
    this.files,
    this.entriesByWorkspacePath =
        const <String, List<native.WorkspaceFileEntry>>{},
  });

  final List<native.WorkspaceFileEntry> entries;
  final Object? error;
  final Completer<List<native.WorkspaceFileEntry>>? files;
  final Map<String, List<native.WorkspaceFileEntry>> entriesByWorkspacePath;

  @override
  Future<List<native.WorkspaceFileEntry>> listFiles({
    required String workspacePath,
    int maxResults = 10000,
  }) {
    if (error != null) {
      return Future<List<native.WorkspaceFileEntry>>.error(error!);
    }
    if (files != null) {
      return files!.future;
    }
    return Future.value(entriesByWorkspacePath[workspacePath] ?? entries);
  }
}

class _QuickOpenTestController extends WorkbenchController {
  _QuickOpenTestController(this._seed);

  final WorkbenchState _seed;
  final List<String> openedFiles = <String>[];

  @override
  WorkbenchState build() => _seed;

  @override
  Future<void> bootstrap() async {}

  @override
  Future<WorkspaceTabRecord> openFileTab({
    required Workspace workspace,
    required String relativePath,
    String? targetGroupId,
  }) async {
    openedFiles.add(relativePath);
    final now = DateTime.utc(2026);
    return WorkspaceTabRecord(
      id: 'tab-${openedFiles.length}',
      workspaceId: workspace.id,
      kind: WorkspaceTabKind.editor,
      title: relativePath,
      createdAt: now,
      updatedAt: now,
    );
  }

  void switchWorkspace(String workspaceId) {
    state = state.copyWith(activeWorkspaceId: workspaceId);
  }
}
