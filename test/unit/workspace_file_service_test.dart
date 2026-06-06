import 'package:alera/src/features/workbench/application/workspace_file_service.dart';
import 'package:alera/src/rust/api/workspace_files.dart' as native;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EditorSessionRegistry', () {
    test(
      'keeps dirty document state after the editor widget unregisters',
      () async {
        final registry = EditorSessionRegistry();
        final document = registry.documentFor('tab-1')
          ..acceptLoaded(
            _editorFile(rawContent: 'original', displayContent: 'original'),
          )
          ..updateCurrentText('changed');
        var saveCount = 0;
        final handle = EditorSessionHandle(
          isDirty: () => document.isDirty,
          save: () async {
            saveCount += 1;
          },
          discard: () async {},
        );

        registry.register('tab-1', handle);
        expect(registry.isDirty('tab-1'), isTrue);
        await registry.save('tab-1');
        expect(saveCount, 1);

        registry.unregister('tab-1', handle);
        expect(registry.isDirty('tab-1'), isTrue);
        await registry.save('tab-1');
        expect(saveCount, 1);

        registry.forget('tab-1');
        expect(registry.isDirty('tab-1'), isFalse);
      },
    );

    test('load errors clear dirty and saveable document state', () {
      final registry = EditorSessionRegistry();
      final document = registry.documentFor('tab-1')
        ..acceptLoaded(
          _editorFile(rawContent: 'original', displayContent: 'original'),
        )
        ..updateCurrentText('changed');

      expect(document.isDirty, isTrue);
      expect(document.canSave, isTrue);

      document.acceptLoadError(StateError('failed to load'));

      expect(document.isDirty, isFalse);
      expect(document.canSave, isFalse);
      expect(document.loadedText, isNull);
      expect(document.currentText, isNull);
      expect(document.contentToken, isNull);
      expect(document.loadError, isA<StateError>());
    });

    test(
      'saveAll writes dirty documents without live editor widgets',
      () async {
        final registry = EditorSessionRegistry();
        final service = _FakeWorkspaceFileService();
        registry.documentFor('tab-1')
          ..attachFile(workspacePath: '/repo/alera', relativePath: 'note.txt')
          ..acceptLoaded(
            _editorFile(rawContent: 'original', displayContent: 'original'),
          )
          ..updateCurrentText('changed');

        final savedCount = await registry.saveAll(service);

        expect(savedCount, 1);
        expect(service.writes.single.relativePath, 'note.txt');
        expect(service.writes.single.currentDisplayContent, 'changed');
        expect(service.writes.single.originalRawContent, 'original');
        expect(service.writes.single.originalDisplayContent, 'original');
        expect(registry.isDirty('tab-1'), isFalse);
      },
    );

    test('saveAll preserves raw tabs on unchanged lines', () async {
      final registry = EditorSessionRegistry();
      final service = _FakeWorkspaceFileService();
      registry.documentFor('tab-1')
        ..attachFile(workspacePath: '/repo/alera', relativePath: 'note.txt')
        ..acceptLoaded(
          _editorFile(
            rawContent: '\talpha\n\tbeta\n\tgamma\n',
            displayContent: '    alpha\n    beta\n    gamma\n',
          ),
          tabSize: 4,
        )
        ..updateCurrentText('    alpha\n    beta changed\n    gamma\n');

      final savedCount = await registry.saveAll(service);

      expect(savedCount, 1);
      expect(service.writes.single.relativePath, 'note.txt');
      expect(
        service.writes.single.currentDisplayContent,
        '    alpha\n'
        '    beta changed\n'
        '    gamma\n',
      );
      expect(
        service.writes.single.originalRawContent,
        '\talpha\n'
        '\tbeta\n'
        '\tgamma\n',
      );
      expect(
        service.writes.single.originalDisplayContent,
        '    alpha\n'
        '    beta\n'
        '    gamma\n',
      );
      expect(service.writes.single.tabSize, 4);
      expect(registry.isDirty('tab-1'), isFalse);
    });

    test('updates cached document paths after a folder move', () {
      final registry = EditorSessionRegistry();
      final document = registry.documentFor('tab-1')
        ..attachFile(
          workspacePath: '/repo/alera',
          relativePath: 'src/main.dart',
        );

      registry.updateDocumentPathsAfterMove(
        workspacePath: '/repo/alera',
        oldRelativePath: 'src',
        newRelativePath: 'lib/src',
      );

      expect(document.relativePath, 'lib/src/main.dart');
    });
  });
}

class _FakeWorkspaceFileService extends WorkspaceFileService {
  final List<_EditorWrite> writes = <_EditorWrite>[];

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
    writes.add(
      _EditorWrite(
        relativePath: relativePath,
        currentDisplayContent: currentDisplayContent,
        originalRawContent: originalRawContent,
        originalDisplayContent: originalDisplayContent,
        tabSize: tabSize,
      ),
    );
    return native.WorkspaceEditorTextFile(
      rawContent: currentDisplayContent,
      displayContent: currentDisplayContent,
      contentToken: '$relativePath-saved',
      modifiedMillis: 1,
      size: BigInt.from(currentDisplayContent.length),
    );
  }
}

native.WorkspaceEditorTextFile _editorFile({
  required String rawContent,
  required String displayContent,
  String contentToken = 'token-1',
}) {
  return native.WorkspaceEditorTextFile(
    rawContent: rawContent,
    displayContent: displayContent,
    contentToken: contentToken,
    modifiedMillis: 0,
    size: BigInt.from(rawContent.length),
  );
}

class _EditorWrite {
  const _EditorWrite({
    required this.relativePath,
    required this.currentDisplayContent,
    required this.originalRawContent,
    required this.originalDisplayContent,
    required this.tabSize,
  });

  final String relativePath;
  final String currentDisplayContent;
  final String? originalRawContent;
  final String? originalDisplayContent;
  final int tabSize;
}
