part of 'workspace_service_test.dart';

class _FakeWorkbenchRepository implements WorkbenchRepository {
  final List<Workspace> workspaces = <Workspace>[];
  final List<WorkspaceTabRecord> tabs = <WorkspaceTabRecord>[];
  final Map<String, WorkbenchLayout> layouts = <String, WorkbenchLayout>{};

  @override
  Future<Workspace?> findWorkspaceById(String workspaceId) async {
    for (final workspace in workspaces) {
      if (workspace.id == workspaceId) {
        return workspace;
      }
    }
    return null;
  }

  @override
  Future<WorkspaceTabRecord?> findWorkspaceTabById(String tabId) async {
    for (final tab in tabs) {
      if (tab.id == tabId) {
        return tab;
      }
    }
    return null;
  }

  @override
  Future<WorkbenchLayout?> findWorkbenchLayout(String workspaceId) async {
    return layouts[workspaceId];
  }

  @override
  Future<List<WorkspaceTabRecord>> listWorkspaceTabs(
    String workspaceId,
  ) async => tabs
      .where((tab) => tab.workspaceId == workspaceId)
      .toList(growable: false);

  @override
  Future<List<Workspace>> listWorkspaces(String projectId) async {
    final matches = workspaces
        .where((workspace) => workspace.projectId == projectId)
        .toList(growable: false);
    matches.sort((left, right) {
      if (left.isMain != right.isMain) {
        return left.isMain ? -1 : 1;
      }
      return left.createdAt.compareTo(right.createdAt);
    });
    return matches;
  }

  @override
  Future<void> removeWorkspaceTab(String tabId) async {
    tabs.removeWhere((tab) => tab.id == tabId);
  }

  @override
  Future<void> removeWorkspaceTabsForWorkspace(String workspaceId) async {
    tabs.removeWhere((tab) => tab.workspaceId == workspaceId);
  }

  @override
  Future<void> removeWorkspace(
    String workspaceId, {
    bool cascadeTabs = true,
  }) async {
    workspaces.removeWhere((workspace) => workspace.id == workspaceId);
    if (cascadeTabs) {
      await removeWorkspaceTabsForWorkspace(workspaceId);
    }
    await removeWorkbenchLayout(workspaceId);
  }

  @override
  Future<void> removeWorkspacesForProject(String projectId) async {
    final removed = workspaces
        .where((workspace) => workspace.projectId == projectId)
        .toList(growable: false);
    workspaces.removeWhere((workspace) => workspace.projectId == projectId);
    for (final workspace in removed) {
      await removeWorkbenchLayout(workspace.id);
    }
  }

  @override
  Future<void> removeWorkbenchLayout(String workspaceId) async {
    layouts.remove(workspaceId);
  }

  @override
  Future<WorkspaceTabRecord> upsertWorkspaceTab(WorkspaceTabRecord tab) async {
    final index = tabs.indexWhere((entry) => entry.id == tab.id);
    if (index == -1) {
      tabs.add(tab);
    } else {
      tabs[index] = tab;
    }
    return tab;
  }

  @override
  Future<WorkbenchLayout> upsertWorkbenchLayout(WorkbenchLayout layout) async {
    layouts[layout.workspaceId] = layout;
    return layout;
  }

  @override
  Future<Workspace> upsertWorkspace(Workspace workspace) async {
    final index = workspaces.indexWhere((entry) => entry.id == workspace.id);
    if (index == -1) {
      workspaces.add(workspace);
    } else {
      workspaces[index] = workspace;
    }
    return workspace;
  }

  @override
  Stream<List<WorkspaceTabRecord>> watchWorkspaceTabs(String workspaceId) =>
      const Stream<List<WorkspaceTabRecord>>.empty();

  @override
  Stream<List<Workspace>> watchWorkspaces(String projectId) =>
      const Stream<List<Workspace>>.empty();
}

class _FakeProcessRunner implements ProcessRunner {
  final List<_ProcessCall> calls = <_ProcessCall>[];
  String currentBranch = 'main';
  int currentBranchExitCode = 0;
  List<String> sourceBranches = <String>['main'];
  Map<String, String> liveBranchByPath = <String, String>{};
  bool worktreeListFails = false;
  final Set<String> invalidBranchNames = <String>{};
  final Set<String> failingWorktreeAddBranches = <String>{};
  final Set<String> failingWorktreeRemovePaths = <String>{};
  final Set<String> failingBranchDeletes = <String>{};

  @override
  Future<ProcessRunOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    calls.add(
      _ProcessCall(
        executable: executable,
        arguments: List<String>.from(arguments),
        workingDirectory: workingDirectory,
      ),
    );

    if (arguments.length >= 2 &&
        arguments[0] == 'branch' &&
        arguments[1] == '--show-current') {
      return ProcessRunOutput(
        exitCode: currentBranchExitCode,
        stdout: '$currentBranch\n',
        stderr: '',
      );
    }

    if (arguments.contains('for-each-ref')) {
      return ProcessRunOutput(
        exitCode: 0,
        stdout: '${sourceBranches.join('\n')}\n',
        stderr: '',
      );
    }

    if (arguments.length >= 3 &&
        arguments[0] == 'check-ref-format' &&
        arguments[1] == '--branch') {
      final branchName = arguments[2];
      if (invalidBranchNames.contains(branchName)) {
        return const ProcessRunOutput(
          exitCode: 1,
          stdout: '',
          stderr: 'invalid branch',
        );
      }
      return const ProcessRunOutput(exitCode: 0, stdout: '', stderr: '');
    }

    if (arguments.length >= 4 &&
        arguments[0] == 'rev-parse' &&
        arguments[1] == '--verify') {
      final branch = arguments.last;
      final exists = sourceBranches.contains(branch);
      return ProcessRunOutput(
        exitCode: exists ? 0 : 1,
        stdout: exists ? '$branch\n' : '',
        stderr: '',
      );
    }

    if (arguments.length >= 3 &&
        arguments[0] == 'worktree' &&
        arguments[1] == 'list') {
      if (worktreeListFails) {
        return const ProcessRunOutput(
          exitCode: 128,
          stdout: '',
          stderr: 'fatal: not a git repository',
        );
      }
      final buffer = StringBuffer();
      for (final entry in liveBranchByPath.entries) {
        buffer
          ..writeln('worktree ${entry.key}')
          ..writeln('branch refs/heads/${entry.value}')
          ..writeln();
      }
      return ProcessRunOutput(
        exitCode: 0,
        stdout: buffer.toString(),
        stderr: '',
      );
    }

    if (arguments.length >= 4 &&
        arguments[0] == 'worktree' &&
        arguments[1] == 'add') {
      final branchName = arguments[3];
      if (failingWorktreeAddBranches.contains(branchName)) {
        return const ProcessRunOutput(
          exitCode: 1,
          stdout: '',
          stderr: 'add failed',
        );
      }
      return const ProcessRunOutput(exitCode: 0, stdout: '', stderr: '');
    }

    if (arguments.length >= 4 &&
        arguments[0] == 'worktree' &&
        arguments[1] == 'remove') {
      final workspacePath = arguments.last;
      if (failingWorktreeRemovePaths.contains(workspacePath)) {
        return const ProcessRunOutput(
          exitCode: 1,
          stdout: '',
          stderr: 'remove failed',
        );
      }
      return const ProcessRunOutput(exitCode: 0, stdout: '', stderr: '');
    }

    if (arguments.length >= 3 &&
        arguments[0] == 'branch' &&
        arguments[1] == '-D') {
      final branchName = arguments[2];
      if (failingBranchDeletes.contains(branchName)) {
        return const ProcessRunOutput(
          exitCode: 1,
          stdout: '',
          stderr: 'delete failed',
        );
      }
      return const ProcessRunOutput(exitCode: 0, stdout: '', stderr: '');
    }

    return const ProcessRunOutput(exitCode: 0, stdout: '', stderr: '');
  }

  @override
  Future<StartedProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) {
    throw UnimplementedError();
  }
}

class _ProcessCall {
  const _ProcessCall({
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
  });

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
}
