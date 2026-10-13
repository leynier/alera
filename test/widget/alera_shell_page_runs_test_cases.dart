part of 'alera_shell_page_test.dart';

void registerNativeRunBoardEditorLifecycleTest() {
  setUpAll(() => code_forge.RustLib.init());
  testWidgets(
    'Board preserves editor selection and undo history without hidden focus',
    (tester) async {
      final seed = _populatedWorkbenchState();
      final workspace = seed.activeWorkspace!;
      final tab = seed
          .tabsFor(workspace.id)
          .first
          .copyWith(
            kind: WorkspaceTabKind.editor,
            payload: {'filePath': 'notes.txt'},
          );
      final registry = EditorSessionRegistry();
      addTearDown(registry.dispose);
      registry.documentFor(tab.id)
        ..loadedText = 'hello world'
        ..currentText = 'hello world';
      final repository = FakeRunRepository();
      addTearDown(repository.dispose);
      await _pumpShell(
        tester,
        state: seed.copyWith(
          tabsByWorkspace: {
            workspace.id: [tab],
          },
          layoutByWorkspace: {},
          activeTabIdByWorkspace: {workspace.id: tab.id},
        ),
        editorSessionRegistry: registry,
        boardRepository: repository,
      );
      await tester.pump();
      final editor = tester.widget<code_forge.CodeForge>(
        find.byType(code_forge.CodeForge),
      );
      final editorState = tester.state(find.byType(WorkspaceEditorSurface));
      editor.controller!.selection = const TextSelection.collapsed(offset: 5);
      editor.controller!.insertAtCurrentCursor(' edited');
      await tester.pump();
      expect(editor.undoController!.canUndo, isTrue);
      const selection = TextSelection(baseOffset: 2, extentOffset: 7);
      editor.controller!.selection = selection;
      editor.focusNode!.requestFocus();
      await tester.pump();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AleraShellPage)),
      );
      final navigation = container.read(activityNavigationProvider.notifier);
      navigation.open();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      // The real desktop harness may show the one-time star prompt above the
      // shell; dismiss it before exercising the Board's pointer action.
      if (find.text('Support Alera').evaluate().isNotEmpty) {
        await tester.tap(find.text('Not Now'));
        await tester.pumpAndSettle();
      }
      expect(find.byType(ActivityPage), findsOneWidget);
      expect(find.byType(WorkspaceEditorSurface), findsNothing);
      expect(
        tester.state(find.byType(WorkspaceEditorSurface, skipOffstage: false)),
        same(editorState),
      );
      expect(editor.focusNode!.canRequestFocus, isFalse);
      await tester.showKeyboard(find.byType(TextField).first);
      await tester.enterText(find.byType(TextField).first, 'search');
      await tester.pump(const Duration(milliseconds: 400));
      expect(editor.focusNode!.hasFocus, isFalse);
      expect(editor.controller!.selection, selection);
      expect(editor.controller!.text, 'hello edited world');
      await tester.tap(find.text('Return to Workspace'));
      await tester.pump();
      await tester.pump();
      final restored = tester.widget<code_forge.CodeForge>(
        find.byType(code_forge.CodeForge),
      );
      expect(editor.focusNode!.hasFocus, isTrue);
      expect(restored.controller, same(editor.controller));
      expect(restored.undoController, same(editor.undoController));
      expect(restored.controller!.selection, selection);
      expect(restored.undoController!.undo(), isTrue);
      expect(restored.controller!.text, 'hello world');
      expect(restored.undoController!.redo(), isTrue);
      expect(restored.controller!.text, 'hello edited world');
      await tester.pump();
      expect(find.byType(ActivityPage), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

/// One project, its workspace holding only the worker's terminal, so the
/// active pane is that terminal.
WorkbenchState _runsShellSeed() {
  final seed = runsWorkbenchState();
  return seed.copyWith(
    activeProjectId: 'project-1',
    activeWorkspaceId: 'ws-1',
    tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
      'ws-1': seed.tabsFor('ws-1').where((tab) => tab.id == 'w-3').toList(),
    },
  );
}

void _registerAleraShellRunsTests() {
  for (final action in [
    'Open Workspace',
    'Return to Workspace',
    'Navigation',
    'Escape',
  ]) {
    testWidgets('Board $action restores the active pane after hiding', (
      tester,
    ) async {
      // Wide enough for the run list beside the run, next to the rail.
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repository = FakeRunRepository();
      addTearDown(repository.dispose);
      final seed = _runsShellSeed();
      final harness = await _pumpShell(
        tester,
        state: seed,
        boardRepository: repository,
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AleraShellPage)),
      );
      final navigation = container.read(activityNavigationProvider.notifier);
      navigation
        ..open()
        ..selectRun('run-1');
      // Open Workspace sits at the top of the task inspector; on Overview it
      // is below the fold of a lazy list.
      if (action == 'Open Workspace') navigation.selectTask('task-2');
      for (var frame = 0; frame < 5; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(find.byType(TextField).first);
      await tester.pump();
      final tab = seed.tabsFor(seed.activeWorkspaceId!).single;
      final session = harness.runtime._sessions[tab.id]!;
      final before = session.requestFocusCalls;
      if (action == 'Navigation') {
        navigation.close();
      } else if (action == 'Escape') {
        // The first Esc leaves the focused search field, the second closes.
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(container.read(activityNavigationProvider).visible, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      } else {
        await tester.ensureVisible(find.text(action).first);
        await tester.tap(find.text(action).first);
      }
      await tester.pump();
      await tester.pump();
      expect(container.read(activityNavigationProvider).visible, isFalse);
      expect(session.requestFocusCalls, greaterThan(before));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Board Open Terminal focuses the retained shell session', (
    tester,
  ) async {
    final repository = FakeRunRepository();
    addTearDown(repository.dispose);
    final seed = _runsShellSeed();
    final harness = await _pumpShell(
      tester,
      state: seed,
      boardRepository: repository,
    );
    final executionWorkspace = seed.activeWorkspace!;
    final session = harness.runtime.sessionFor(
      workspace: executionWorkspace,
      tab: seed.tabsFor(executionWorkspace.id).single,
    ) as _FakeTerminalSessionHandle;
    await session.ensureStarted();
    final requestsBefore = session.requestFocusCalls;
    final visibilityLeasesBefore = session.visibilityLeases;
    expect(visibilityLeasesBefore, greaterThan(0));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AleraShellPage)),
    );
    container.read(activityNavigationProvider.notifier)
      ..open()
      ..selectRun('run-1')
      ..selectTask('task-2');
    for (var frame = 0; frame < 5; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(session.visibilityLeases, 0);
    expect(session.requestFocusCalls, requestsBefore);
    await Scrollable.ensureVisible(
      tester.element(find.text('Open Terminal')),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open Terminal'));
    await tester.pump();
    await tester.pump();
    expect(container.read(activityNavigationProvider).visible, isFalse);
    expect(harness.runtime._sessions['w-3'], same(session));
    expect(session.visibilityLeases, visibilityLeasesBefore);
    // The workspace panel may remount more than one retained terminal view;
    // explicit Open Terminal must focus the same session, not create another.
    expect(session.requestFocusCalls, greaterThan(requestsBefore));
    expect(harness.runtime.closedTabIds, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Board suspends terminal visibility without stopping its session',
    (tester) async {
      final harness = await _pumpShell(
        tester,
        state: _populatedWorkbenchState(),
      );
      final sessions = harness.runtime._sessions.values.toList();
      final visible = sessions
          .where((session) => session.visibilityLeases > 0)
          .toList();
      expect(visible, isNotEmpty);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AleraShellPage)),
      );
      final navigation = container.read(activityNavigationProvider.notifier);
      navigation.open();
      await tester.pump();
      expect(
        sessions.every((session) => session.visibilityLeases == 0),
        isTrue,
      );
      expect(visible.every((session) => session.isRunning), isTrue);
      navigation.close();
      await tester.pump();
      expect(visible.every((session) => session.visibilityLeases == 1), isTrue);
      expect(harness.runtime.closedTabIds, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
