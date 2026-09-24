part of 'workbench_controller_test.dart';

void _registerWorkbenchControllerPreviewCloseTests() {
  test('a dirty preview tab is pinned instead of being retargeted', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);

    final preview = await _controller.openFileTab(
      workspace: workspace,
      relativePath: 'lib/a.dart',
      preview: true,
    );
    await _flush();
    final registry = _harness.container.read(editorSessionRegistryProvider);
    final document = registry.documentFor(preview.id);
    document.loadedText = 'original';
    document.currentText = 'edited';
    expect(registry.isDirty(preview.id), isTrue);

    final next = await _controller.openFileTab(
      workspace: workspace,
      relativePath: 'lib/b.dart',
      preview: true,
    );
    await _flush();

    final kept = _controller.state
        .tabsFor(workspace.id)
        .firstWhere((tab) => tab.id == preview.id);
    expect(next.id, isNot(preview.id));
    expect(kept.isPreview, isFalse);
    expect(kept.filePath, 'lib/a.dart');
    expect(next.isPreview, isTrue);
    expect(next.filePath, 'lib/b.dart');
  });

  test(
    'replacing a preview after the watcher lands forgets the old document',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      final first = await _controller.openFileTab(
        workspace: workspace,
        relativePath: 'lib/a.dart',
        preview: true,
      );
      await _flush();
      final registry = _harness.container.read(editorSessionRegistryProvider);
      final document = registry.documentFor(first.id);
      document.loadedText = 'contents of a';
      document.currentText = 'contents of a';

      final gate = Completer<void>();
      _harness.workbenchRepository.upsertWorkspaceTabGate = gate;
      final delayed = _controller.openFileTab(
        workspace: workspace,
        relativePath: 'lib/b.dart',
        preview: true,
      );
      await _flush();
      gate.complete();
      await delayed;
      await _flush();

      final replaced = registry.documentFor(first.id);
      expect(identical(replaced, document), isFalse);
      expect(replaced.currentText, isNull);
    },
  );

  test(
    'a watcher-retargeted preview keeps the new document after open completes',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      final first = await _controller.openFileTab(
        workspace: workspace,
        relativePath: 'lib/a.dart',
        preview: true,
      );
      await _flush();
      final registry = _harness.container.read(editorSessionRegistryProvider);
      final document = registry.documentFor(first.id);
      document.loadedText = 'contents of a';
      document.currentText = 'contents of a';
      document.attachFile(
        workspacePath: workspace.path,
        relativePath: 'lib/a.dart',
      );

      final gate = Completer<void>();
      _harness.workbenchRepository.upsertWorkspaceTabGate = gate;
      final delayed = _controller.openFileTab(
        workspace: workspace,
        relativePath: 'lib/b.dart',
        preview: true,
      );
      await _flush();
      document.attachFile(
        workspacePath: workspace.path,
        relativePath: 'lib/b.dart',
      );
      document.loadedText = 'contents of b';
      document.currentText = 'edited b';
      registry.register(
        first.id,
        EditorSessionHandle(
          isDirty: () => document.isDirty,
          save: () async {},
          discard: () async {},
        ),
      );
      gate.complete();
      await delayed;
      await _flush();

      expect(identical(registry.documentFor(first.id), document), isTrue);
      expect(document.relativePath, 'lib/b.dart');
      expect(document.currentText, 'edited b');
      expect(registry.isDirty(first.id), isTrue);
    },
  );

  test(
    'preview-opening an already-open dirty editor does not forget its document',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      final permanent = await _controller.openFileTab(
        workspace: workspace,
        relativePath: 'lib/a.dart',
      );
      await _flush();
      final preview = await _controller.openFileTab(
        workspace: workspace,
        relativePath: 'lib/b.dart',
        preview: true,
      );
      await _flush();
      final registry = _harness.container.read(editorSessionRegistryProvider);
      final document = registry.documentFor(permanent.id);
      document.loadedText = 'original a';
      document.currentText = 'dirty a';

      final reopened = await _controller.openFileTab(
        workspace: workspace,
        relativePath: 'lib/a.dart',
        preview: true,
      );
      await _flush();

      expect(reopened.id, permanent.id);
      expect(identical(registry.documentFor(permanent.id), document), isTrue);
      expect(document.currentText, 'dirty a');
      expect(preview.id, isNot(permanent.id));
    },
  );

  test(
    'reopening a dirty editor while another tab closes keeps its document',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);
      final permanent = await _controller.openFileTab(
        workspace: workspace,
        relativePath: 'lib/a.dart',
      );
      final extra = await _controller.openFileTab(
        workspace: workspace,
        relativePath: 'lib/extra.dart',
      );
      await _flush();
      final registry = _harness.container.read(editorSessionRegistryProvider);
      final document = registry.documentFor(permanent.id);
      document.loadedText = 'original a';
      document.currentText = 'dirty a';

      final upsertGate = Completer<void>();
      _harness.workbenchRepository.upsertWorkspaceTabGate = upsertGate;
      final reopen = _controller.openFileTab(
        workspace: workspace,
        relativePath: 'lib/a.dart',
        preview: true,
      );
      await _flush();
      final closeGate = Completer<void>();
      _harness.workbenchRepository.removeWorkspaceTabGate = closeGate;
      final closing = _controller.closeWorkspaceTab(
        workspace: workspace,
        tabId: extra.id,
      );
      await _flush();
      upsertGate.complete();
      final reopened = await reopen;
      closeGate.complete();
      await closing;
      await _flush();

      expect(reopened.id, permanent.id);
      expect(identical(registry.documentFor(permanent.id), document), isTrue);
      expect(document.currentText, 'dirty a');
    },
  );

  test(
    'opening a source control file replaces the explorer preview tab',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);

      final explorer = await _controller.openFileTab(
        workspace: workspace,
        relativePath: 'lib/a.dart',
        preview: true,
      );
      final git = await _controller.openGitDiffTab(
        workspace: workspace,
        relativePath: 'lib/b.dart',
        area: .unstaged,
        scope: .file,
        preview: true,
      );
      await _flush();

      expect(git.id, explorer.id);
      expect(git.kind, WorkspaceTabKind.gitDiff);
      expect(git.filePath, 'lib/b.dart');
      expect(git.isPreview, isTrue);
      expect(
        _controller.state.tabsFor(workspace.id).where(_isPreviewSlotTab),
        hasLength(1),
      );
    },
  );

  test(
    'opening another source control file replaces the git preview',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);

      final first = await _controller.openGitDiffTab(
        workspace: workspace,
        relativePath: 'lib/a.dart',
        area: .unstaged,
        scope: .file,
        preview: true,
      );
      final second = await _controller.openGitDiffTab(
        workspace: workspace,
        relativePath: 'lib/b.dart',
        area: .staged,
        scope: .file,
        preview: true,
      );
      await _flush();

      expect(second.id, first.id);
      expect(second.filePath, 'lib/b.dart');
      expect(second.gitDiffArea, GitChangeArea.staged);
      expect(second.isPreview, isTrue);
      expect(
        _controller.state
            .tabsFor(workspace.id)
            .where((tab) => tab.kind == WorkspaceTabKind.gitDiff),
        hasLength(1),
      );
    },
  );

  test('opening all changes does not replace a preview tab', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);

    final preview = await _controller.openFileTab(
      workspace: workspace,
      relativePath: 'lib/a.dart',
      preview: true,
    );
    final allChanges = await _controller.openGitDiffTab(
      workspace: workspace,
      scope: .all,
    );
    await _flush();

    expect(allChanges.id, isNot(preview.id));
    expect(allChanges.isPreview, isFalse);
    expect(preview.isPreview, isTrue);
    expect(
      _controller.state.tabsFor(workspace.id).map((tab) => tab.id),
      containsAll(<String>[preview.id, allChanges.id]),
    );
  });

  test('permanent source control open pins the git preview tab', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);

    final preview = await _controller.openGitDiffTab(
      workspace: workspace,
      relativePath: 'lib/a.dart',
      area: .unstaged,
      scope: .file,
      preview: true,
    );
    final pinned = await _controller.openGitDiffTab(
      workspace: workspace,
      relativePath: 'lib/a.dart',
      area: .unstaged,
      scope: .file,
    );
    await _flush();

    expect(pinned.id, preview.id);
    expect(pinned.isPreview, isFalse);
    expect(
      _controller.state
          .tabsFor(workspace.id)
          .singleWhere((tab) => tab.kind == WorkspaceTabKind.gitDiff)
          .isPreview,
      isFalse,
    );
  });
}
