import 'package:alera/src/app/providers.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/workbench/application/workspace_file_service.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/presentation/workspace_editor_surface.dart';
import 'package:alera/src/rust/api/workspace_files.dart' as native;
import 'package:code_forge/code_forge.dart' as code_forge;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(code_forge.RustLib.init);

  testWidgets('keeps editor chrome stable after the dirty transition', (
    tester,
  ) async {
    final workspace = _workspace();
    final tab = _editorTab();
    final registry = EditorSessionRegistry();
    addTearDown(registry.dispose);
    registry.documentFor(tab.id)
      ..attachFile(
        workspacePath: workspace.path,
        relativePath: tab.filePath!,
        workspace: workspace,
      )
      ..acceptLoaded(_editorFile('hello world'));
    final files = _EditorTestWorkspaceFileService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceFileServiceProvider.overrideWithValue(files),
          editorSessionRegistryProvider.overrideWithValue(registry),
          settingsControllerProvider.overrideWithValue(AleraSettings.defaults),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 720,
              height: 480,
              child: WorkspaceEditorSurface(
                workspace: workspace,
                tab: tab,
                autofocus: false,
                onOpenMarkdownViewerTab: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final editor = tester.widget<code_forge.CodeForge>(
      find.byType(code_forge.CodeForge),
    );
    final cleanPath = tester.widget<Text>(find.text('notes.txt').first);
    final cleanSaveButton = _saveButton(tester);
    expect(cleanSaveButton.onPressed, isNull);

    editor.controller!.selection = const TextSelection.collapsed(offset: 5);
    editor.controller!.insertAtCurrentCursor(' first');
    await tester.pump();

    final dirtyPath = tester.widget<Text>(find.text('notes.txt').first);
    final dirtySaveButton = _saveButton(tester);
    expect(identical(cleanPath, dirtyPath), isFalse);
    expect(dirtySaveButton.onPressed, isNotNull);
    expect(registry.isDirty(tab.id), isTrue);

    editor.controller!.insertAtCurrentCursor(' second');
    await tester.pump();

    final stillDirtyPath = tester.widget<Text>(find.text('notes.txt').first);
    expect(identical(dirtyPath, stillDirtyPath), isTrue);
    expect(registry.isDirty(tab.id), isTrue);

    await tester.tap(_saveButtonFinder());
    await tester.pump(const Duration(milliseconds: 100));

    expect(files.writeCalls, 1);
    expect(registry.isDirty(tab.id), isFalse);
    final cleanAgainSaveButton = _saveButton(tester);
    expect(cleanAgainSaveButton.onPressed, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets(
    'blocks manual saves while autosave conflict resolution is open',
    (tester) async {
      final workspace = _workspace();
      final tab = _editorTab();
      final registry = EditorSessionRegistry();
      addTearDown(registry.dispose);
      registry.documentFor(tab.id)
        ..attachFile(
          workspacePath: workspace.path,
          relativePath: tab.filePath!,
          workspace: workspace,
        )
        ..acceptLoaded(_editorFile('hello world'));
      final files = _EditorTestWorkspaceFileService()..conflictNextWrite = true;
      final settings = AleraSettings.defaults.copyWith(
        editor: EditorSettings.defaults.copyWith(autosaveEnabled: true),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            workspaceFileServiceProvider.overrideWithValue(files),
            editorSessionRegistryProvider.overrideWithValue(registry),
            settingsControllerProvider.overrideWithValue(settings),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 720,
                height: 480,
                child: WorkspaceEditorSurface(
                  workspace: workspace,
                  tab: tab,
                  autofocus: false,
                  onOpenMarkdownViewerTab: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final editor = tester.widget<code_forge.CodeForge>(
        find.byType(code_forge.CodeForge),
      );
      editor.controller!.selection = const TextSelection.collapsed(offset: 5);
      editor.controller!.insertAtCurrentCursor(' changed');
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(find.text('File changed on disk'), findsOneWidget);
      final saveButton = _saveButton(tester);
      expect(saveButton.onPressed, isNull);

      await tester.tap(_saveButtonFinder());
      await tester.pump();
      expect(files.writeCalls, 1);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}

IconButton _saveButton(WidgetTester tester) {
  return tester.widget<IconButton>(_saveButtonFinder());
}

Finder _saveButtonFinder() {
  final tooltip = find.byTooltip('Save File');
  // IconButton builds RawTooltip around its InkResponse, so the button is the
  // ancestor of the tooltip in Flutter's widget tree.
  return find.ancestor(of: tooltip, matching: find.byType(IconButton)).first;
}

Workspace _workspace() {
  final now = DateTime(2026, 6, 6);
  return Workspace(
    id: 'ws-1',
    projectId: 'project-1',
    name: 'alera',
    path: '/repo/alera',
    createdAt: now,
    updatedAt: now,
    kind: .main,
    status: .active,
  );
}

WorkspaceTabRecord _editorTab() {
  final now = DateTime(2026, 6, 6);
  return WorkspaceTabRecord(
    id: 'editor-1',
    workspaceId: 'ws-1',
    kind: .editor,
    title: 'Notes',
    createdAt: now,
    updatedAt: now,
    payload: const <String, Object?>{
      workspaceTabFilePathPayloadKey: 'notes.txt',
    },
  );
}

native.WorkspaceEditorTextFile _editorFile(
  String content, {
  String token = 'editor-token',
}) {
  return native.WorkspaceEditorTextFile(
    rawContent: content,
    displayContent: content,
    contentToken: token,
    modifiedMillis: 0,
    size: .from(content.length),
  );
}

class _EditorTestWorkspaceFileService extends WorkspaceFileService {
  int writeCalls = 0;
  bool conflictNextWrite = false;

  @override
  Future<native.WorkspaceEditorTextFile> readWorkspaceEditorTextFile({
    required Workspace workspace,
    required String relativePath,
    required int tabSize,
  }) async {
    return _editorFile('hello world');
  }

  @override
  Future<native.WorkspaceEditorTextFile> writeWorkspaceEditorTextFile({
    required Workspace workspace,
    required String relativePath,
    required String currentDisplayContent,
    required String? originalRawContent,
    required String? originalDisplayContent,
    required String? expectedContentToken,
    required bool overwriteIfChanged,
    required int tabSize,
  }) async {
    writeCalls += 1;
    if (conflictNextWrite) {
      conflictNextWrite = false;
      throw const native.WorkspaceFileError(
        kind: native.WorkspaceFileErrorKind.conflict,
        context: 'changed on disk',
      );
    }
    return _editorFile(currentDisplayContent, token: 'saved-$writeCalls');
  }
}
