part of 'workbench_controller_test.dart';

void _registerWorkbenchControllerWorkspaceGraphTests() {
  test(
    'createWorkspace links the new workspace to the selected parent',
    () async {
      final parent = Workspace(
        id: 'parent-1',
        projectId: _harness.project.id,
        name: 'Parent',
        branch: 'main',
        path: _harness.project.repoPath,
        createdAt: DateTime.utc(2026, 5, 22),
        updatedAt: DateTime.utc(2026, 5, 22),
        kind: WorkspaceKind.main,
        status: WorkspaceStatus.active,
      );
      await _harness.workbenchRepository.upsertWorkspace(parent);

      final result = await _controller.createWorkspace(
        project: _harness.project,
        sourceBranch: 'main',
        newBranchName: 'feature/ui-tags',
        parentWorkspaceId: parent.id,
      );

      expect(_harness.workspaceGraphRepository.linkedWorkspaces.single, (
        parentWorkspaceId: parent.id,
        childWorkspaceId: result.workspace.id,
      ));
      expect(_controller.state.activeWorkspaceId, result.workspace.id);
    },
  );

  test(
    'createWorkspace reports a parent link failure without failing creation',
    () async {
      _harness.workspaceGraphRepository.linkErrorsByParent['parent-1'] =
          StateError('Parent workspace not found');

      final result = await _controller.createWorkspace(
        project: _harness.project,
        sourceBranch: 'main',
        newBranchName: 'feature/orphan-link',
        parentWorkspaceId: 'parent-1',
      );

      expect(result.hasParentLinkError, isTrue);
      expect(_harness.workspaceGraphRepository.linkedWorkspaces, isEmpty);
      expect(_controller.state.activeWorkspaceId, result.workspace.id);
      expect(_controller.state.error, isNull);
    },
  );

  test('updateWorkspaceTags applies only tag assignment diffs', () async {
    final workspace = Workspace(
      id: 'workspace-1',
      projectId: _harness.project.id,
      name: 'Feature',
      path: '/tmp/workspace-1',
      createdAt: DateTime.utc(2026, 5, 22),
      updatedAt: DateTime.utc(2026, 5, 22),
      kind: WorkspaceKind.linked,
      status: WorkspaceStatus.active,
      tagIds: const <String>['tag-old', 'tag-keep'],
    );

    await _controller.updateWorkspaceTags(
      workspace: workspace,
      tagIds: <String>{'tag-keep', 'tag-new'},
    );

    expect(_harness.workspaceGraphRepository.unassignedTags, <Object>[
      (workspaceId: workspace.id, tagId: 'tag-old'),
    ]);
    expect(_harness.workspaceGraphRepository.assignedTags, <Object>[
      (workspaceId: workspace.id, tagId: 'tag-new'),
    ]);
  });

  test('updateWorkspaceTags diffs against the freshest state', () async {
    // Bootstrap so the controller watches the repository and mirrors upserts.
    await _controller.bootstrap();
    await _flushUntil(
      () => _controller.state.workspacesFor(_harness.project.id).isNotEmpty,
    );
    final workspace = Workspace(
      id: 'workspace-1',
      projectId: _harness.project.id,
      name: 'Feature',
      path: '/tmp/workspace-1',
      createdAt: DateTime.utc(2026, 5, 22),
      updatedAt: DateTime.utc(2026, 5, 22),
      kind: WorkspaceKind.linked,
      status: WorkspaceStatus.active,
      tagIds: const <String>['tag-stale'],
    );
    await _harness.workbenchRepository.upsertWorkspace(
      workspace.copyWith(tagIds: const <String>['tag-current']),
    );
    await _flushUntil(
      () => _controller.state
          .workspacesFor(_harness.project.id)
          .any((candidate) => candidate.id == workspace.id),
    );

    await _controller.updateWorkspaceTags(
      workspace: workspace,
      tagIds: <String>{'tag-new'},
    );

    expect(_harness.workspaceGraphRepository.unassignedTags, <Object>[
      (workspaceId: workspace.id, tagId: 'tag-current'),
    ]);
    expect(_harness.workspaceGraphRepository.assignedTags, <Object>[
      (workspaceId: workspace.id, tagId: 'tag-new'),
    ]);
  });

  test('deleteWorkspaceTag removes the tag through the repository', () async {
    final tag = WorkspaceTag.create(name: 'review');
    await _harness.workspaceGraphRepository.upsertTag(tag);

    await _controller.deleteWorkspaceTag(tag.id);

    expect(_harness.workspaceGraphRepository.tags, isEmpty);
    expect(_controller.state.error, isNull);
  });

  test('setWorkspaceParent rejects a descendant as new parent', () async {
    final workspace = Workspace(
      id: 'workspace-1',
      projectId: _harness.project.id,
      name: 'Feature',
      path: '/tmp/workspace-1',
      createdAt: DateTime.utc(2026, 5, 22),
      updatedAt: DateTime.utc(2026, 5, 22),
      kind: WorkspaceKind.linked,
      status: WorkspaceStatus.active,
    );
    await _harness.workspaceGraphRepository.linkWorkspaces(
      parentWorkspaceId: workspace.id,
      childWorkspaceId: 'child-1',
    );
    await _harness.workspaceGraphRepository.linkWorkspaces(
      parentWorkspaceId: 'child-1',
      childWorkspaceId: 'grandchild-1',
    );
    _harness.workspaceGraphRepository.linkedWorkspaces.clear();

    await expectLater(
      _controller.setWorkspaceParent(
        workspace: workspace,
        parentWorkspaceId: 'grandchild-1',
      ),
      throwsA(isA<WorkspaceException>()),
    );

    expect(_harness.workspaceGraphRepository.unlinkedWorkspaces, isEmpty);
    expect(_harness.workspaceGraphRepository.linkedWorkspaces, isEmpty);
  });

  test('setWorkspaceParent replaces and clears parent relationships', () async {
    final workspace = Workspace(
      id: 'workspace-1',
      projectId: _harness.project.id,
      name: 'Feature',
      path: '/tmp/workspace-1',
      createdAt: DateTime.utc(2026, 5, 22),
      updatedAt: DateTime.utc(2026, 5, 22),
      kind: WorkspaceKind.linked,
      status: WorkspaceStatus.active,
      parentWorkspaceId: 'parent-old',
    );

    await _controller.setWorkspaceParent(
      workspace: workspace,
      parentWorkspaceId: 'parent-new',
    );
    await _controller.setWorkspaceParent(
      workspace: workspace.copyWith(parentWorkspaceId: 'parent-new'),
    );

    expect(_harness.workspaceGraphRepository.unlinkedWorkspaces, <Object>[
      (parentWorkspaceId: 'parent-old', childWorkspaceId: workspace.id),
      (parentWorkspaceId: 'parent-new', childWorkspaceId: workspace.id),
    ]);
    expect(_harness.workspaceGraphRepository.linkedWorkspaces, <Object>[
      (parentWorkspaceId: 'parent-new', childWorkspaceId: workspace.id),
    ]);
  });

  test(
    'setWorkspaceParent restores the previous parent when relink fails',
    () async {
      final workspace = Workspace(
        id: 'workspace-1',
        projectId: _harness.project.id,
        name: 'Feature',
        path: '/tmp/workspace-1',
        createdAt: DateTime.utc(2026, 5, 22),
        updatedAt: DateTime.utc(2026, 5, 22),
        kind: WorkspaceKind.linked,
        status: WorkspaceStatus.active,
        parentWorkspaceId: 'parent-old',
      );
      _harness.workspaceGraphRepository.linkErrorsByParent['parent-new'] =
          StateError('Parent workspace not found');

      await expectLater(
        _controller.setWorkspaceParent(
          workspace: workspace,
          parentWorkspaceId: 'parent-new',
        ),
        throwsA(isA<StateError>()),
      );

      expect(_harness.workspaceGraphRepository.unlinkedWorkspaces, <Object>[
        (parentWorkspaceId: 'parent-old', childWorkspaceId: workspace.id),
      ]);
      expect(_harness.workspaceGraphRepository.linkedWorkspaces, <Object>[
        (parentWorkspaceId: 'parent-old', childWorkspaceId: workspace.id),
      ]);
    },
  );
}
