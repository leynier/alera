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

    test('releases a path notifier once nothing references its path', () {
      final registry = EditorSessionRegistry();
      registry
          .documentFor('tab-1')
          .attachFile(
            workspacePath: '/repo/alera',
            relativePath: 'docs/readme.md',
          );
      final notifier = registry.documentChangesForPath(
        workspacePath: '/repo/alera',
        relativePath: 'docs/readme.md',
      );

      registry.forget('tab-1');

      // A rebuilt viewer obtains a fresh notifier: the old one was dropped
      // instead of accumulating one entry per file ever opened.
      final next = registry.documentChangesForPath(
        workspacePath: '/repo/alera',
        relativePath: 'docs/readme.md',
      );
      expect(identical(next, notifier), isFalse);
    });

    test('keeps a path notifier alive while a viewer is listening', () {
      final registry = EditorSessionRegistry();
      registry
          .documentFor('tab-1')
          .attachFile(
            workspacePath: '/repo/alera',
            relativePath: 'docs/readme.md',
          );
      final notifier = registry.documentChangesForPath(
        workspacePath: '/repo/alera',
        relativePath: 'docs/readme.md',
      );
      void listener() {}
      notifier.addListener(listener);

      registry.forget('tab-1');

      final next = registry.documentChangesForPath(
        workspacePath: '/repo/alera',
        relativePath: 'docs/readme.md',
      );
      expect(identical(next, notifier), isTrue);
      notifier.removeListener(listener);
    });

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

    test('returns dirty editor text for a matching document path', () {
      final registry = EditorSessionRegistry();
      registry.documentFor('tab-1')
        ..attachFile(
          workspacePath: '/repo/alera',
          relativePath: 'docs/readme.md',
        )
        ..acceptLoaded(
          _editorFile(rawContent: '# Saved', displayContent: '# Saved'),
        )
        ..updateCurrentText('# Dirty');

      expect(
        registry.dirtyTextForPath(
          workspacePath: '/repo/alera',
          relativePath: 'docs/readme.md',
        ),
        '# Dirty',
      );
      expect(
        registry.dirtyTextForPath(
          workspacePath: '/repo/alera',
          relativePath: 'docs/other.md',
        ),
        isNull,
      );
    });

    test('does not return clean editor text for a matching document path', () {
      final registry = EditorSessionRegistry();
      registry.documentFor('tab-1')
        ..attachFile(
          workspacePath: '/repo/alera',
          relativePath: 'docs/readme.md',
        )
        ..acceptLoaded(
          _editorFile(rawContent: '# Saved', displayContent: '# Saved'),
        );

      expect(
        registry.dirtyTextForPath(
          workspacePath: '/repo/alera',
          relativePath: 'docs/readme.md',
        ),
        isNull,
      );
    });

    test('does not return dirty text from a document with load errors', () {
      final registry = EditorSessionRegistry();
      registry.documentFor('tab-1')
        ..attachFile(
          workspacePath: '/repo/alera',
          relativePath: 'docs/readme.md',
        )
        ..acceptLoaded(
          _editorFile(rawContent: '# Saved', displayContent: '# Saved'),
        )
        ..updateCurrentText('# Dirty')
        ..acceptLoadError(StateError('failed to load'));

      expect(
        registry.dirtyTextForPath(
          workspacePath: '/repo/alera',
          relativePath: 'docs/readme.md',
        ),
        isNull,
      );
    });

    test(
      'notifies listeners when document content changes and is forgotten',
      () {
        final registry = EditorSessionRegistry();
        var notifications = 0;
        registry.addListener(() {
          notifications += 1;
        });

        registry.documentFor('tab-1')
          ..attachFile(
            workspacePath: '/repo/alera',
            relativePath: 'docs/readme.md',
          )
          ..acceptLoaded(
            _editorFile(rawContent: '# Saved', displayContent: '# Saved'),
          )
          ..updateCurrentText('# Dirty');
        registry.forget('tab-1');

        expect(notifications, 4);
      },
    );

    test('notifies only listeners for the changed document path', () {
      final registry = EditorSessionRegistry();
      var readmeNotifications = 0;
      var otherNotifications = 0;
      registry
          .documentChangesForPath(
            workspacePath: '/repo/alera',
            relativePath: 'docs/readme.md',
          )
          .addListener(() => readmeNotifications += 1);
      registry
          .documentChangesForPath(
            workspacePath: '/repo/alera',
            relativePath: 'docs/other.md',
          )
          .addListener(() => otherNotifications += 1);

      registry.documentFor('tab-1')
        ..attachFile(
          workspacePath: '/repo/alera',
          relativePath: 'docs/readme.md',
        )
        ..acceptLoaded(
          _editorFile(rawContent: '# Saved', displayContent: '# Saved'),
        )
        ..updateCurrentText('# Dirty');

      expect(readmeNotifications, 3);
      expect(otherNotifications, 0);
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

    test('keeps reveal pending when live session has no reveal callback', () {
      final registry = EditorSessionRegistry();
      const target = WorkspaceEditorRevealTarget(
        line: 3,
        column: 5,
        matchLength: 2,
      );
      registry.register(
        'tab-1',
        EditorSessionHandle(
          isDirty: () => false,
          save: () async {},
          discard: () async {},
        ),
      );

      registry.reveal('tab-1', target);

      expect(registry.takePendingReveal('tab-1'), target);
    });

    test('clears clean snapshot when live session has no reload callback', () {
      final registry = EditorSessionRegistry();
      final document = registry.documentFor('tab-1')
        ..attachFile(workspacePath: '/repo/alera', relativePath: 'note.txt')
        ..acceptLoaded(
          _editorFile(rawContent: 'original', displayContent: 'original'),
        );
      registry.register(
        'tab-1',
        EditorSessionHandle(
          isDirty: () => false,
          save: () async {},
          discard: () async {},
        ),
      );

      registry.reloadCleanFiles(
        workspacePath: '/repo/alera',
        relativePaths: const <String>['note.txt'],
      );

      expect(document.hasSnapshot, isFalse);
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
      size: .from(currentDisplayContent.length),
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
    size: .from(rawContent.length),
  );
}

class const _EditorWrite({
  required final String relativePath,
  required final String currentDisplayContent,
  required final String? originalRawContent,
  required final String? originalDisplayContent,
  required final int tabSize,
});
