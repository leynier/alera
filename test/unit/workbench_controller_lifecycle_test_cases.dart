part of 'workbench_controller_test.dart';

void _registerWorkbenchControllerLifecycleTests() {
  test('bootstrap prepares the main workspace without selecting it', () async {
    await _controller.bootstrap();
    await _flushUntil(
      () => _controller.state.workspacesFor(_harness.project.id).isNotEmpty,
    );

    expect(_controller.state.activeProjectId, _harness.project.id);
    expect(_controller.state.activeWorkspace, isNull);
    final workspaces = _controller.state.workspacesFor(_harness.project.id);
    expect(workspaces.single.isMain, isTrue);
    expect(_controller.state.tabsFor(workspaces.single.id), isEmpty);
    expect(_controller.state.activeWorkspaceTab, isNull);
  });

  test(
    'selecting a workspace with no tabs seeds the first terminal tab',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);

      expect(_controller.state.activeWorkspaceId, workspace.id);
      expect(
        _controller.state.tabsFor(workspace.id).map((tab) => tab.title),
        <String>['Terminal 1'],
      );
      expect(_controller.state.activeWorkspaceTab?.title, 'Terminal 1');
    },
  );

  test('createWorkspace returns injected worktree setup warnings', () async {
    await _controller.bootstrap();
    const report = WorktreeSetupReport(
      steps: <WorktreeSetupStepReport>[
        WorktreeSetupStepReport(
          kind: .command,
          label: 'make bootstrap',
          succeeded: false,
          message: 'failed',
        ),
      ],
    );
    _harness.worktreeSetupRunner.report = report;

    final result = await _controller.createWorkspace(
      project: _harness.project,
      sourceBranch: 'main',
      newBranchName: 'feature/setup-report',
    );
    await _flush();

    expect(result.setupReport, same(report));
    expect(result.hasSetupWarnings, isTrue);
    expect(_harness.worktreeSetupRunner.calls, hasLength(1));
    expect(
      _harness.worktreeSetupRunner.calls.single.workspace.id,
      result.workspace.id,
    );
    expect(_controller.state.activeWorkspaceId, result.workspace.id);
  });

  test(
    'openFileTab upgrades a legacy PDF editor tab without duplicating it',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);

      final legacyTab = await _controller.openEditorTab(
        workspace: workspace,
        relativePath: 'docs/guide.pdf',
      );
      await _flush();

      expect(legacyTab.kind, WorkspaceTabKind.editor);

      final openedTab = await _controller.openFileTab(
        workspace: workspace,
        relativePath: './docs/guide.pdf',
      );
      await _flush();

      final tabs = _controller.state.tabsFor(workspace.id);
      final pdfTabs = tabs
          .where((tab) => tab.filePath == 'docs/guide.pdf')
          .toList(growable: false);
      expect(openedTab.id, legacyTab.id);
      expect(openedTab.kind, WorkspaceTabKind.pdf);
      expect(pdfTabs, hasLength(1));
      expect(pdfTabs.single.id, legacyTab.id);
      expect(pdfTabs.single.kind, WorkspaceTabKind.pdf);
      expect(_controller.state.activeWorkspaceTab?.id, legacyTab.id);
      expect(_controller.state.activeWorkspaceTab?.kind, WorkspaceTabKind.pdf);
    },
  );

  test('closing the last active tab deselects the workspace', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);

    final firstTab = _controller.state.activeWorkspaceTab!;
    final secondTab = await _controller.createTerminalTab(workspace);

    expect(_controller.state.activeWorkspaceTab?.id, secondTab.id);

    await _controller.closeWorkspaceTab(
      workspace: workspace,
      tabId: secondTab.id,
    );
    await _flush();

    expect(_controller.state.activeWorkspaceTab?.id, firstTab.id);

    await _controller.closeWorkspaceTab(
      workspace: workspace,
      tabId: firstTab.id,
    );
    await _flush();

    final tabs = _controller.state.tabsFor(workspace.id);
    expect(tabs, isEmpty);
    expect(_controller.state.activeWorkspace, isNull);
    expect(_controller.state.activeWorkspaceTab, isNull);
    expect(_controller.state.activeTabIdByWorkspace[workspace.id], isNull);
    expect(_controller.state.layoutFor(workspace.id)?.activeTabId, isNull);
  });

  test(
    'closing the last tab of an inactive workspace keeps the active workspace',
    () async {
      await _controller.bootstrap();
      final mainWorkspace = await _selectMainWorkspace(_controller, _harness);

      final linked = (await _controller.createWorkspace(
        project: _harness.project,
        sourceBranch: 'main',
        newBranchName: 'feature/inactive-close',
      )).workspace;
      await _flush();
      final linkedTab = _controller.state.activeWorkspaceTab!;

      await _controller.selectWorkspace(
        project: _harness.project,
        workspace: mainWorkspace,
      );
      await _flush();
      expect(_controller.state.activeWorkspaceId, mainWorkspace.id);

      await _controller.closeWorkspaceTab(
        workspace: linked,
        tabId: linkedTab.id,
      );
      await _flush();

      expect(_controller.state.tabsFor(linked.id), isEmpty);
      expect(_controller.state.activeWorkspaceId, mainWorkspace.id);
    },
  );

  test('closing several tabs keeps the remaining tab active', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);
    final firstTab = _controller.state.activeWorkspaceTab!;
    final secondTab = await _controller.createTerminalTab(workspace);
    final thirdTab = await _controller.createTerminalTab(workspace);
    await _flush();

    await _controller.closeWorkspaceTabs(
      workspace: workspace,
      tabIds: <String>[secondTab.id, thirdTab.id],
    );
    await _flush();

    expect(
      _controller.state.tabsFor(workspace.id).map((tab) => tab.id),
      <String>[firstTab.id],
    );
    expect(_controller.state.activeWorkspaceId, workspace.id);
    expect(_controller.state.activeWorkspaceTab?.id, firstTab.id);
    expect(_controller.state.layoutFor(workspace.id)?.activeTabId, firstTab.id);
  });

  test('closing a Codex tab purges its saved composer draft', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);
    final tab = await _controller.createCodexTab(workspace);
    final drafts = _harness.container.read(codexComposerDraftStoreProvider);
    drafts.write(
      tab.id,
      const CodexComposerDraft(value: TextEditingValue(text: 'Unsent draft')),
    );

    await _controller.closeWorkspaceTab(workspace: workspace, tabId: tab.id);
    await _flush();

    expect(drafts.read(tab.id).isEmpty, isTrue);
  });

  test('watched Codex tab removal purges its saved composer draft', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);
    final tab = await _controller.createCodexTab(workspace);
    final drafts = _harness.container.read(codexComposerDraftStoreProvider);
    drafts.write(
      tab.id,
      const CodexComposerDraft(
        value: TextEditingValue(text: 'Draft from another client'),
      ),
    );

    await _harness.workbenchRepository.removeWorkspaceTab(tab.id);
    await _flush();

    expect(drafts.read(tab.id).isEmpty, isTrue);
  });

  test('hosted review refs follow their persisted pull request tab', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);
    final first = await _controller.openGitPullRequestDiffTab(
      workspace: workspace,
      gitDiffRoot: 'packages/app',
      pullRequestNumber: 385,
      commitOid: 'head-385',
      parentOid: 'base-385',
      retentionId: 'retention-1',
    );
    final reused = await _controller.openGitPullRequestDiffTab(
      workspace: workspace,
      gitDiffRoot: 'packages/app',
      pullRequestNumber: 385,
      commitOid: 'head-385',
      parentOid: 'base-385',
      retentionId: 'retention-2',
    );

    expect(reused.id, first.id);
    expect(
      _harness.gitBackend.calls.any(
        (call) =>
            call.method == 'persistHostedReviewRange' &&
            call.args['retentionId'] == 'retention-1' &&
            call.args['path'] == p.join(workspace.path, 'packages', 'app'),
      ),
      isTrue,
    );
    expect(
      _harness.gitBackend.calls.where(
        (call) =>
            call.method == 'releaseHostedReviewRange' &&
            call.args['retentionId'] == 'retention-2',
      ),
      isNotEmpty,
    );

    await _harness.workbenchRepository.removeWorkspaceTab(first.id);
    await _flushUntil(
      () => _harness.gitBackend.calls.any(
        (call) =>
            call.method == 'releaseHostedReviewRange' &&
            call.args['retentionId'] == 'retention-1',
      ),
    );

    final release = _harness.gitBackend.calls.lastWhere(
      (call) =>
          call.method == 'releaseHostedReviewRange' &&
          call.args['retentionId'] == 'retention-1',
    );
    expect(release.args['path'], p.join(workspace.path, 'packages', 'app'));
  });

  test('failed project removal keeps hosted review refs retained', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);
    await _controller.openGitPullRequestDiffTab(
      workspace: workspace,
      pullRequestNumber: 385,
      commitOid: 'head-385',
      parentOid: 'base-385',
      retentionId: 'retention-failed-removal',
    );
    _harness.projectRepository.removeError = StateError('cannot remove');

    await expectLater(
      _controller.removeProject(_harness.project.id),
      throwsStateError,
    );

    expect(
      _harness.gitBackend.calls.where(
        (call) =>
            call.method == 'releaseHostedReviewRange' &&
            call.args['retentionId'] == 'retention-failed-removal',
      ),
      isEmpty,
    );
  });

  test('opens markdown viewer tabs in the active group', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);
    final layout = _controller.state.layoutFor(workspace.id)!;

    final tab = await _controller.openMarkdownViewerTab(
      workspace: workspace,
      relativePath: 'docs/readme.md',
      targetGroupId: layout.activeGroupId,
    );
    await _flush();

    expect(tab.kind, WorkspaceTabKind.markdownViewer);
    expect(tab.filePath, 'docs/readme.md');
    expect(_controller.state.activeWorkspaceTab?.id, tab.id);
    expect(
      _controller.state.layoutFor(workspace.id)?.groupIdForTab(tab.id),
      layout.activeGroupId,
    );
  });

  test('does not spawn runtime-owned terminals while syncing tabs', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);
    await _flushUntil(
      () => _harness.workbenchRepository.hasTabWatcher(workspace.id),
    );
    final tab = WorkspaceTabRecord(
      id: 'spawn-tab',
      workspaceId: workspace.id,
      title: 'Worker',
      createdAt: .utc(2026, 5, 22, 2),
      updatedAt: .utc(2026, 5, 22, 2),
      payload: const <String, Object?>{
        workspaceTabTerminalSessionIdPayloadKey: 'spawn-session',
        workspaceTabInitialCommandPayloadKey: 'claude',
        workspaceTabSpawnOnCreatePayloadKey: true,
      },
    );
    final session = _harness.terminalRuntime.sessionFor(
      workspace: workspace,
      tab: tab,
    ) as _FakeTerminalSessionHandle;

    await _harness.workbenchRepository.upsertWorkspaceTab(tab);
    await _flushUntil(
      () => _controller.state
          .tabsFor(workspace.id)
          .any((candidate) => candidate.id == tab.id),
    );

    expect(session.ensureStartedCalls, 0);
    expect(session.isRunning, isFalse);
  });

  test('path sync closes markdown viewer tabs renamed away from md', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);

    final editorTab = await _controller.openEditorTab(
      workspace: workspace,
      relativePath: 'docs/readme.md',
    );
    final previewTab = await _controller.openMarkdownViewerTab(
      workspace: workspace,
      relativePath: 'docs/readme.md',
    );
    await _flush();

    expect(_controller.state.activeWorkspaceTab?.id, previewTab.id);

    await _controller.syncFileTabsAfterPathMove(
      workspace: workspace,
      oldRelativePath: 'docs/readme.md',
      newRelativePath: 'docs/readme.txt',
    );
    await _flush();

    final tabs = _controller.state.tabsFor(workspace.id);
    expect(tabs.map((tab) => tab.id), isNot(contains(previewTab.id)));
    expect(
      tabs.singleWhere((tab) => tab.id == editorTab.id).filePath,
      'docs/readme.txt',
    );
    expect(
      _controller.state.layoutFor(workspace.id)?.groupIdForTab(previewTab.id),
      isNull,
    );
    expect(_controller.state.activeWorkspaceTab?.id, isNot(previewTab.id));
    final persistedTabs = await _harness.workbenchRepository.listWorkspaceTabs(
      workspace.id,
    );
    expect(persistedTabs.map((tab) => tab.id), isNot(contains(previewTab.id)));
  });

  test('renames project, workspace, and terminal tab in state', () async {
    await _controller.bootstrap();
    await _flushUntil(
      () => _controller.state.workspacesFor(_harness.project.id).isNotEmpty,
    );

    await _controller.renameProject(
      projectId: _harness.project.id,
      name: '  Renamed project  ',
    );
    await _flush();
    expect(_controller.state.projects.single.name, 'Renamed project');

    final workspace = await _selectMainWorkspace(_controller, _harness);
    await _controller.renameWorkspace(
      workspaceId: workspace.id,
      name: '  Primary workspace  ',
    );
    await _flush();
    expect(
      _controller.state.workspacesFor(_harness.project.id).single.name,
      'Primary workspace',
    );

    final tab = _controller.state.activeWorkspaceTab!;
    await _controller.renameWorkspaceTab(
      tabId: tab.id,
      title: '  API server  ',
    );
    await _flush();
    expect(_controller.state.activeWorkspaceTab?.title, 'API server');
    expect(_controller.state.activeWorkspaceTab?.hasManualTitle, isTrue);
  });

  test('opens merman preview as a separate tab from the editor', () async {
    await _controller.bootstrap();
    final workspace = await _selectMainWorkspace(_controller, _harness);

    final editor = await _controller.openEditorTab(
      workspace: workspace,
      relativePath: 'docs/diagram.mmd',
    );
    final preview = await _controller.openMermanPreviewTab(
      workspace: workspace,
      relativePath: 'docs/diagram.mmd',
    );
    await _flush();

    expect(editor.id, isNot(preview.id));
    expect(editor.isMermanPreview, isFalse);
    expect(preview.isMermanPreview, isTrue);
    expect(preview.title, 'diagram.mmd preview');
    expect(
      _controller.state.tabsFor(workspace.id).map((tab) => tab.id),
      containsAll(<String>[editor.id, preview.id]),
    );
    expect(_controller.state.activeWorkspaceTab?.id, preview.id);

    final reopenedEditor = await _controller.openEditorTab(
      workspace: workspace,
      relativePath: 'docs/diagram.mmd',
    );
    await _flush();

    expect(reopenedEditor.id, editor.id);
    expect(_controller.state.activeWorkspaceTab?.id, editor.id);
    expect(_controller.state.tabsFor(workspace.id), hasLength(3));
  });

  test(
    'opening editor from preview recreates the editor tab if needed',
    () async {
      await _controller.bootstrap();
      final workspace = await _selectMainWorkspace(_controller, _harness);

      final editor = await _controller.openEditorTab(
        workspace: workspace,
        relativePath: 'docs/diagram.mmd',
      );
      final preview = await _controller.openMermanPreviewTab(
        workspace: workspace,
        relativePath: 'docs/diagram.mmd',
      );
      await _controller.closeWorkspaceTab(
        workspace: workspace,
        tabId: editor.id,
      );
      await _flush();

      final recreated = await _controller.openEditorTab(
        workspace: workspace,
        relativePath: 'docs/diagram.mmd',
      );
      await _flush();

      expect(recreated.id, isNot(editor.id));
      expect(recreated.isMermanPreview, isFalse);
      expect(_controller.state.activeWorkspaceTab?.id, recreated.id);
      expect(
        _controller.state.tabsFor(workspace.id).map((tab) => tab.id),
        containsAll(<String>[preview.id, recreated.id]),
      );
    },
  );

  _registerWorkbenchControllerSelectionTests();
}
