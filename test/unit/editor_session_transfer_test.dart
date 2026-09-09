import 'package:alera/src/features/workbench/application/workspace_file_service.dart';
import 'package:alera/src/rust/api/workspace_files.dart' as native;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('transfer preserves dirty content and token and leaves external documents alone', () {
    final registry = EditorSessionRegistry();
    final document = registry.documentFor('editor')
      ..attachFile(workspacePath: '/source', relativePath: 'file.txt')
      ..acceptLoaded(
        native.WorkspaceEditorTextFile(
          rawContent: 'original',
          displayContent: 'original',
          contentToken: 'unchanged-token',
          modifiedMillis: 0,
          size: .zero,
        ),
      )
      ..updateCurrentText('unsaved');
    final external = registry.documentFor('external')
      ..attachFile(workspacePath: '/external', relativePath: 'file.txt');
    registry.transferDocuments(
      ['editor', 'external'],
      '/source',
      '/destination',
    );
    expect(identical(registry.documentFor('editor'), document), isTrue);
    expect(document.currentText, 'unsaved');
    expect(document.loadedText, 'original');
    expect(document.contentToken, 'unchanged-token');
    expect(document.workspacePath, '/destination');
    expect(registry.isDirty('editor'), isTrue);
    expect(external.workspacePath, '/external');
    expect(
      registry.dirtyTextForPath(
        workspacePath: '/destination',
        relativePath: 'file.txt',
      ),
      'unsaved',
    );
    expect(
      registry.dirtyTextForPath(
        workspacePath: '/source',
        relativePath: 'file.txt',
      ),
      isNull,
    );
    registry.dispose();
  });
}
