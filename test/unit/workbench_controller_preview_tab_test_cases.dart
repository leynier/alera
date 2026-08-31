part of 'workbench_controller_test.dart';

void _registerWorkbenchControllerPreviewTabTests() {
  test('opening another explorer file replaces the preview tab', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);

    final first = await _controller.openFileTab(
      workspace: workspace,
      relativePath: 'lib/a.dart',
      preview: true,
    );
    final second = await _controller.openFileTab(
      workspace: workspace,
      relativePath: 'lib/b.dart',
      preview: true,
    );
    await _flush();

    expect(second.id, first.id);
    expect(second.filePath, 'lib/b.dart');
    expect(second.isPreview, isTrue);
    expect(
      _controller.state.tabsFor(workspace.id).where(_isFileTab),
      hasLength(1),
    );
    expect(_controller.state.activeWorkspaceTab?.id, first.id);
  });

  test(
    'keeping a preview tab then opening another file creates a second tab',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);

      final first = await _controller.openFileTab(
        workspace: workspace,
        relativePath: 'lib/a.dart',
        preview: true,
      );
      await _controller.keepPreviewTab(first.id);
      final second = await _controller.openFileTab(
        workspace: workspace,
        relativePath: 'lib/b.dart',
        preview: true,
      );
      await _flush();

      final kept = _controller.state
          .tabsFor(workspace.id)
          .firstWhere((tab) => tab.id == first.id);
      expect(kept.isPreview, isFalse);
      expect(second.id, isNot(first.id));
      expect(second.isPreview, isTrue);
      expect(
        _controller.state.tabsFor(workspace.id).where(_isFileTab),
        hasLength(2),
      );
    },
  );

  test('reopening the same preview path reuses the existing tab', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);

    final first = await _controller.openFileTab(
      workspace: workspace,
      relativePath: './lib/a.dart',
      preview: true,
    );
    final second = await _controller.openFileTab(
      workspace: workspace,
      relativePath: 'lib/a.dart',
      preview: true,
    );
    await _flush();

    expect(second.id, first.id);
    expect(second.isPreview, isTrue);
    expect(
      _controller.state.tabsFor(workspace.id).where(_isFileTab),
      hasLength(1),
    );
  });

  test('permanent open of a preview path pins that tab', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);

    final preview = await _controller.openFileTab(
      workspace: workspace,
      relativePath: 'lib/a.dart',
      preview: true,
    );
    final pinned = await _controller.openFileTab(
      workspace: workspace,
      relativePath: 'lib/a.dart',
    );
    await _flush();

    expect(pinned.id, preview.id);
    expect(pinned.isPreview, isFalse);
    expect(
      _controller.state.tabsFor(workspace.id).singleWhere(_isFileTab).isPreview,
      isFalse,
    );
  });

  test('split groups keep independent preview slots', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);

    final previewA = await _controller.openFileTab(
      workspace: workspace,
      relativePath: 'lib/a.dart',
      preview: true,
    );
    await _flush();
    final originalGroupId = _controller.state
        .layoutFor(workspace.id)!
        .groupIdForTab(previewA.id)!;
    final splitTerminal = await _controller.splitWorkbenchGroupWithTerminal(
      workspace: workspace,
      groupId: originalGroupId,
      zone: .right,
    );
    await _flush();
    final newGroupId = _controller.state
        .layoutFor(workspace.id)!
        .groupIdForTab(splitTerminal.id)!;

    final previewB = await _controller.openFileTab(
      workspace: workspace,
      relativePath: 'lib/b.dart',
      preview: true,
      targetGroupId: newGroupId,
    );
    final previewC = await _controller.openFileTab(
      workspace: workspace,
      relativePath: 'lib/c.dart',
      preview: true,
      targetGroupId: originalGroupId,
    );
    await _flush();

    expect(previewB.id, isNot(previewA.id));
    expect(previewC.id, previewA.id);
    expect(previewC.filePath, 'lib/c.dart');
    expect(
      _controller.state.tabsFor(workspace.id).map((tab) => tab.id),
      containsAll(<String>[previewB.id, previewC.id]),
    );
    expect(
      _controller.state.layoutFor(workspace.id)!.groupIdForTab(previewB.id),
      newGroupId,
    );
    expect(
      _controller.state.layoutFor(workspace.id)!.groupIdForTab(previewC.id),
      originalGroupId,
    );
  });

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

bool _isFileTab(WorkspaceTabRecord tab) {
  return tab.kind == WorkspaceTabKind.editor ||
      tab.kind == WorkspaceTabKind.markdownViewer ||
      tab.kind == WorkspaceTabKind.pdf;
}

bool _isPreviewSlotTab(WorkspaceTabRecord tab) => tab.isFilePreviewSlot;
