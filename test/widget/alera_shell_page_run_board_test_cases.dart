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
      final repository = BoardTestRepository();
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
      final navigation = container.read(runBoardNavigationProvider.notifier);
      navigation.open();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(RunBoardPage), findsOneWidget);
      expect(find.byType(WorkspaceEditorSurface), findsNothing);
      expect(
        tester.state(find.byType(WorkspaceEditorSurface, skipOffstage: false)),
        same(editorState),
      );
      expect(editor.focusNode!.canRequestFocus, isFalse);
      await tester.tap(find.byType(TextField).first);
      await tester.enterText(find.byType(TextField).first, 'search');
      await tester.pump(const Duration(milliseconds: 400));
      expect(editor.controller!.selection, selection);
      expect(editor.controller!.text, 'hello edited world');
      navigation.close();
      await tester.pump();
      final restored = tester.widget<code_forge.CodeForge>(
        find.byType(code_forge.CodeForge),
      );
      expect(restored.controller, same(editor.controller));
      expect(restored.undoController, same(editor.undoController));
      expect(restored.controller!.selection, selection);
      expect(restored.undoController!.undo(), isTrue);
      expect(restored.controller!.text, 'hello world');
      expect(restored.undoController!.redo(), isTrue);
      expect(restored.controller!.text, 'hello edited world');
      await tester.pump();
      expect(find.byType(RunBoardPage), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

void _registerAleraShellRunBoardTests() {
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
      final navigation = container.read(runBoardNavigationProvider.notifier);
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
