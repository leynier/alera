import 'dart:async';

import 'package:alera/src/features/workbench/application/workspace_file_service.dart';
import 'package:alera/src/rust/api/workspace_files.dart' as native;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'retired editors remain frozen until their persisted tabs disappear',
    () {
      final registry = EditorSessionRegistry();
      final editor = document(registry, 'editor', '/repo');
      registry.acquireBufferGuard(
        'remove',
        const EditorBufferGuardScope(tabIds: {'editor'}, workspacePaths: {}),
      );
      registry.releaseBufferGuard('remove', retired: true);
      editor.updateCurrentText('late keystroke');
      expect(editor.currentText, 'saved');
      expect(registry.isBufferGuarded('editor'), isTrue);
      registry.forget('editor');
      expect(registry.isBufferGuarded('editor'), isFalse);
      registry.dispose();
    },
  );
  test(
    'guarded task buffers stay frozen while unrelated editors remain writable',
    () async {
      final registry = EditorSessionRegistry();
      final target = document(registry, 'target', '/repo');
      final sibling = document(registry, 'sibling', '/repo');
      final blockers = registry.acquireBufferGuard(
        'remove',
        const EditorBufferGuardScope(tabIds: {'target'}, workspacePaths: {}),
      );
      expect(blockers, isEmpty);
      target.updateCurrentText('blocked');
      sibling.updateCurrentText('allowed');
      expect(target.currentText, 'saved');
      expect(sibling.currentText, 'allowed');
      await expectLater(registry.save('target'), throwsStateError);
      registry.releaseBufferGuard('remove');
      target.updateCurrentText('editable again');
      expect(target.currentText, 'editable again');
      registry.dispose();
    },
  );

  test('checkout guards include every task and newly attached documents', () {
    final registry = EditorSessionRegistry();
    document(registry, 'first', '/repo').updateCurrentText('dirty');
    document(registry, 'second', '/repo');
    document(registry, 'outside', '/other').updateCurrentText('unrelated');
    final scope = EditorBufferGuardScope(
      tabIds: {'alias'},
      workspacePaths: {'/repo'},
    );
    final blockers = registry.acquireBufferGuard('relocate', scope);
    expect(blockers.map((blocker) => blocker.tabId), ['first']);
    expect(registry.isBufferGuarded('second'), isTrue);
    expect(registry.isBufferGuarded('outside'), isFalse);
    final later = document(registry, 'later', '/repo');
    later.updateCurrentText('blocked');
    expect(later.currentText, 'saved');
    expect(registry.isBufferGuarded('alias'), isTrue);
    expect(
      () => registry.acquireBufferGuard(
        'relocate',
        const EditorBufferGuardScope(tabIds: {}, workspacePaths: {}),
      ),
      throwsStateError,
    );
    expect(registry.isBufferGuarded('first'), isTrue);
    registry.releaseBufferGuard('relocate');
    registry.dispose();
  });

  test('overlapping guards require each operation to release its lock', () {
    final registry = EditorSessionRegistry();
    document(registry, 'editor', '/repo');
    const scope = EditorBufferGuardScope(
      tabIds: {'editor'},
      workspacePaths: {},
    );
    registry.acquireBufferGuard('first', scope);
    registry.acquireBufferGuard('second', scope);
    registry.releaseBufferGuard('first');
    expect(registry.isBufferGuarded('editor'), isTrue);
    registry.releaseBufferGuard('second');
    expect(registry.isBufferGuarded('editor'), isFalse);
    registry.dispose();
  });

  test('in-flight saves block relocation and preserve edits made before the freeze', () async {
    final registry = EditorSessionRegistry();
    final editor = document(registry, 'editor', '/repo')
      ..updateCurrentText('saving');
    final files = DelayedFileService();
    final saving = registry.saveDocument('editor', files);
    editor.updateCurrentText('newer edit');
    final blockers = registry.acquireBufferGuard(
      'relocate',
      const EditorBufferGuardScope(tabIds: {'editor'}, workspacePaths: {}),
    );
    expect(blockers.single.reason, contains('in progress'));
    files.completion.complete(file('saving'));
    await saving;
    expect(editor.loadedText, 'saving');
    expect(editor.currentText, 'newer edit');
    expect(editor.isDirty, isTrue);
    registry.releaseBufferGuard('relocate');
    registry.dispose();
  });
}

EditorDocumentSession document(
  EditorSessionRegistry registry,
  String id,
  String path,
) => registry.documentFor(id)
  ..attachFile(workspacePath: path, relativePath: 'notes.md')
  ..acceptLoaded(file('saved'));

native.WorkspaceEditorTextFile file(String content) =>
    native.WorkspaceEditorTextFile(
      rawContent: content,
      displayContent: content,
      contentToken: content,
      modifiedMillis: 0,
      size: BigInt.from(content.length),
    );

class DelayedFileService extends WorkspaceFileService {
  final completion = Completer<native.WorkspaceEditorTextFile>();

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
  }) => completion.future;
}
