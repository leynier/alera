import 'dart:async';

import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/features/keyboard/application/keyboard_command_dispatcher.dart';
import 'package:alera/src/features/keyboard/domain/keyboard_action.dart';
import 'package:alera/src/features/orchestration/application/run_board_navigation.dart';
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
  for (final outcome in ['success', 'cancel', 'failure']) {
    testWidgets('Quick Open from Board preserves selection on $outcome', (
      tester,
    ) async {
      final controller = _QuickOpenTestController(
        _state(_workspace('workspace-1', 'Main', '/repo/main')),
      )..openGate = Completer<void>();
      final container = await _pumpQuickOpen(
        tester,
        controller: controller,
        service: _QuickOpenFileService(entries: ['main.dart']),
        viaKeyboard: true,
      );
      final navigation = container.read(runBoardNavigationProvider.notifier);
      navigation.open();
      navigation.selectRun('run-1');
      navigation.selectTask('task-1');
      final toasts = <AleraToastData>[];
      final subscription = AleraToast.stream.listen(toasts.add);
      addTearDown(subscription.cancel);
      await tester.tap(find.text('Open Quick Open'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(
        outcome == 'cancel'
            ? LogicalKeyboardKey.escape
            : LogicalKeyboardKey.enter,
      );
      await tester.pumpAndSettle();
      expect(container.read(runBoardNavigationProvider).visible, isTrue);
      if (outcome == 'success') {
        controller.openGate!.complete();
      } else if (outcome == 'failure') {
        controller.openGate!.completeError(StateError('cannot open'));
      }
      await tester.pumpAndSettle();
      final location = container.read(runBoardNavigationProvider);
      expect(location.visible, outcome != 'success');
      expect(location.runId, 'run-1');
      expect(location.taskId, 'task-1');
      expect(controller.openedFiles, outcome == 'cancel' ? [] : ['main.dart']);
      if (outcome == 'failure') {
        expect(toasts.single.message, 'Could not open the selected file.');
      } else {
        expect(toasts, isEmpty);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('shows loading, filters files, and opens the selected file', (
    tester,
  ) async {
    final workspace = _workspace('workspace-1', 'Main', '/repo/main');
    final controller = _QuickOpenTestController(_state(workspace));
    final session = Completer<native.WorkspaceQuickOpenSession>();
    final service = _QuickOpenFileService(
      session: session,
      entries: <String>['lib/main.dart', 'lib/main_test.dart', 'notes.txt'],
    );
    await _pumpQuickOpen(tester, controller: controller, service: service);

    await tester.tap(find.text('Open Quick Open'));
    await tester.pump();
    expect(find.text('Loading workspace files...'), findsOneWidget);

    session.complete(_session('workspace-1', 3));
    await tester.pumpAndSettle();
    expect(find.text('lib/main.dart'), findsOneWidget);
    expect(find.text('lib/main_test.dart'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'main_test.dart');
    await tester.pump();
    expect(find.text('lib/main.dart'), findsNothing);
    expect(find.text('lib/main_test.dart'), findsOneWidget);

    await tester.sendKeyEvent(.enter);
    await tester.pumpAndSettle();
    expect(controller.openedFiles, <String>['lib/main_test.dart']);
  });

  testWidgets('ignores stale searches', (tester) async {
    final workspace = _workspace('workspace-1', 'Main', '/repo/main');
    final controller = _QuickOpenTestController(_state(workspace));
    final oldSearch = Completer<List<native.WorkspaceQuickOpenMatch>>();
    final newSearch = Completer<List<native.WorkspaceQuickOpenMatch>>();
    final service = _QuickOpenFileService(
      entries: <String>['old.dart', 'new.dart'],
      searchGates: <String, Completer<List<native.WorkspaceQuickOpenMatch>>>{
        'old': oldSearch,
        'new': newSearch,
      },
    );
    await _pumpQuickOpen(tester, controller: controller, service: service);

    await tester.tap(find.text('Open Quick Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'old');
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'new');
    await tester.pump();

    oldSearch.complete(<native.WorkspaceQuickOpenMatch>[_match('old.dart')]);
    await tester.pump();
    expect(find.text('old.dart'), findsNothing);

    newSearch.complete(<native.WorkspaceQuickOpenMatch>[_match('new.dart')]);
    await tester.pumpAndSettle();
    expect(find.text('new.dart'), findsOneWidget);
  });

  testWidgets('stops a session whose start completes after disposal', (
    tester,
  ) async {
    final workspace = _workspace('workspace-1', 'Main', '/repo/main');
    final controller = _QuickOpenTestController(_state(workspace));
    final session = Completer<native.WorkspaceQuickOpenSession>();
    final service = _QuickOpenFileService(session: session);
    await _pumpQuickOpen(tester, controller: controller, service: service);

    await tester.tap(find.text('Open Quick Open'));
    await tester.pump();
    await tester.sendKeyEvent(.escape);
    await tester.pumpAndSettle();

    session.complete(_session('late-session', 0));
    await tester.pump();
    expect(service.stoppedSessionIds, <String>['late-session']);
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
      service: _QuickOpenFileService(entries: <String>['a.dart', 'b.dart']),
      anchorFocus: anchorFocus,
    );
    anchorFocus.requestFocus();
    await tester.pump();

    await tester.tap(find.text('Open Quick Open'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(.arrowDown);
    await tester.sendKeyEvent(.enter);
    await tester.pumpAndSettle();
    expect(controller.openedFiles, <String>['b.dart']);
    expect(anchorFocus.hasFocus, isTrue);

    await tester.tap(find.text('Open Quick Open'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(.escape);
    await tester.pumpAndSettle();
    expect(find.text('Quick Open'), findsNothing);
    expect(anchorFocus.hasFocus, isTrue);
  });

  testWidgets('scrolls the selected result into view', (tester) async {
    final workspace = _workspace('workspace-1', 'Main', '/repo/main');
    final controller = _QuickOpenTestController(_state(workspace));
    final service = _QuickOpenFileService(
      entries: <String>[for (var i = 0; i < 50; i++) 'file_$i.dart'],
    );
    await _pumpQuickOpen(tester, controller: controller, service: service);

    await tester.tap(find.text('Open Quick Open'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 49; i++) {
      await tester.sendKeyEvent(.arrowDown);
    }
    await tester.pumpAndSettle();

    expect(find.text('file_49.dart'), findsOneWidget);
  });

  testWidgets('shows empty and error states', (tester) async {
    final workspace = _workspace('workspace-1', 'Main', '/repo/main');
    final controller = _QuickOpenTestController(_state(workspace));
    await _pumpQuickOpen(
      tester,
      controller: controller,
      service: _QuickOpenFileService(entries: const <String>[]),
    );

    await tester.tap(find.text('Open Quick Open'));
    await tester.pumpAndSettle();
    expect(
      find.text('No files are available in this workspace.'),
      findsOneWidget,
    );
    await tester.sendKeyEvent(.escape);
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
      entriesByWorkspacePath: <String, List<String>>{
        first.path: <String>['old.dart'],
        second.path: <String>['new.dart'],
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

Future<ProviderContainer> _pumpQuickOpen(
  WidgetTester tester, {
  required _QuickOpenTestController controller,
  required _QuickOpenFileService service,
  FocusNode? anchorFocus,
  bool viaKeyboard = false,
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
                onPressed: () {
                  if (viaKeyboard) {
                    KeyboardCommandDispatcher(
                      context: context,
                      ref: ref,
                    ).dispatch(KeyboardActionId.openQuickOpen);
                  } else {
                    unawaited(showQuickOpenFlow(context, ref));
                  }
                },
                child: const Text('Open Quick Open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return ProviderScope.containerOf(
    tester.element(find.text('Open Quick Open')),
  );
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
    kind: .main,
    status: .active,
  );
}

native.WorkspaceQuickOpenMatch _match(String relativePath) {
  return native.WorkspaceQuickOpenMatch(relativePath: relativePath, score: 0);
}

native.WorkspaceQuickOpenSession _session(String id, int indexedFileCount) {
  return native.WorkspaceQuickOpenSession(
    id: id,
    indexedFileCount: indexedFileCount,
  );
}

class _QuickOpenFileService({
  final List<String> entries = const <String>[],
  final Object? error,
  final Completer<native.WorkspaceQuickOpenSession>? session,
  final Map<String, List<String>> entriesByWorkspacePath =
      const <String, List<String>>{},
  final Map<String, Completer<List<native.WorkspaceQuickOpenMatch>>>
      searchGates =
      const <String, Completer<List<native.WorkspaceQuickOpenMatch>>>{},
}) extends WorkspaceFileService {
  final List<String> stoppedSessionIds = <String>[];
  final Map<String, List<String>> _entriesBySessionId =
      <String, List<String>>{};

  @override
  Future<native.WorkspaceQuickOpenSession> startQuickOpenSession({
    required String workspacePath,
  }) {
    if (error != null) {
      return Future<native.WorkspaceQuickOpenSession>.error(error!);
    }
    if (session != null) {
      return session!.future.then((value) {
        _entriesBySessionId[value.id] =
            entriesByWorkspacePath[workspacePath] ?? entries;
        return value;
      });
    }
    final value = _session(
      workspacePath,
      entriesByWorkspacePath[workspacePath]?.length ?? entries.length,
    );
    _entriesBySessionId[value.id] =
        entriesByWorkspacePath[workspacePath] ?? entries;
    return Future.value(value);
  }

  @override
  Future<List<native.WorkspaceQuickOpenMatch>> searchQuickOpenSession({
    required native.WorkspaceQuickOpenSession session,
    required String query,
    int limit = 50,
  }) {
    final gate = searchGates[query];
    if (gate != null) {
      return gate.future;
    }
    final normalizedQuery = query.trim().toLowerCase();
    final paths = _entriesBySessionId[session.id] ?? entries;
    final matches =
        paths
            .where(
              (path) =>
                  normalizedQuery.isEmpty ||
                  path.toLowerCase().contains(normalizedQuery),
            )
            .toList()
          ..sort();
    return Future.value(
      matches.take(limit).map(_match).toList(growable: false),
    );
  }

  @override
  Future<void> stopQuickOpenSession({
    required native.WorkspaceQuickOpenSession session,
  }) async {
    stoppedSessionIds.add(session.id);
  }
}

class _QuickOpenTestController(final WorkbenchState _seed)
    extends WorkbenchController {
  final List<String> openedFiles = <String>[];
  Completer<void>? openGate;

  @override
  WorkbenchState build() => _seed;

  @override
  Future<void> bootstrap() async {}

  @override
  Future<WorkspaceTabRecord> openFileTab({
    required Workspace workspace,
    required String relativePath,
    String? targetGroupId,
    bool preview = false,
  }) async {
    openedFiles.add(relativePath);
    await openGate?.future;
    final now = DateTime.utc(2026);
    return WorkspaceTabRecord(
      id: 'tab-${openedFiles.length}',
      workspaceId: workspace.id,
      kind: .editor,
      title: relativePath,
      createdAt: now,
      updatedAt: now,
    );
  }

  void switchWorkspace(String workspaceId) {
    state = state.copyWith(activeWorkspaceId: workspaceId);
  }
}
