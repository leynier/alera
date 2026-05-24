import 'dart:async';
import 'dart:io';

import 'package:alera/src/features/projects/application/project_service.dart';
import 'package:alera/src/features/projects/application/worktree_service.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/workbench_repository.dart';
import 'package:alera/src/features/workbench/application/workspace_service.dart';
import 'package:alera/src/features/workbench/domain/terminal_tab_record.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('WorkspaceService', () {
    late Directory tempDir;
    late _FakeWorkbenchRepository repository;
    late _FakeProcessRunner processRunner;
    late WorkspaceService service;
    late Project project;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('alera-workspace-test-');
      repository = _FakeWorkbenchRepository();
      processRunner = _FakeProcessRunner();
      service = WorkspaceService(
        repository: repository,
        projectService: ProjectService(processRunner),
        processRunner: processRunner,
        worktreeRoot: WorktreeRoot(override: p.join(tempDir.path, 'workspaces')),
        now: () => DateTime.utc(2026, 5, 20, 12),
      );
      project = Project(
        id: 'project-1',
        name: 'Alera',
        repoPath: p.join(tempDir.path, 'repo'),
        createdAt: DateTime.utc(2026, 5, 20),
        updatedAt: DateTime.utc(2026, 5, 20),
      );
      Directory(project.repoPath).createSync(recursive: true);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('ensureMainWorkspace stores the main checkout as an active workspace', () async {
      processRunner.currentBranch = 'main';

      final workspace = await service.ensureMainWorkspace(project);

      expect(workspace.projectId, project.id);
      expect(workspace.name, 'Main');
      expect(workspace.branch, 'main');
      expect(workspace.path, project.repoPath);
      expect(workspace.kind, WorkspaceKind.main);
      expect(workspace.status, WorkspaceStatus.active);
      expect(repository.workspaces.single, workspace);
    });

    test('createLinkedWorkspace creates a new worktree from the requested source branch', () async {
      processRunner.sourceBranches = <String>['main', 'origin/main'];

      final workspace = await service.createLinkedWorkspace(
        project: project,
        sourceBranch: 'origin/main',
        newBranchName: 'feature/terminal-tabs',
      );

      expect(workspace.kind, WorkspaceKind.linked);
      expect(workspace.sourceBranch, 'origin/main');
      expect(workspace.branch, 'feature/terminal-tabs');
      expect(workspace.name, 'feature/terminal-tabs');
      expect(workspace.path, contains('project-1'));
      expect(processRunner.calls.last.arguments, <String>[
        'worktree',
        'add',
        '-b',
        'feature/terminal-tabs',
        workspace.path,
        'origin/main',
      ]);
    });

    test('reconcile keeps the main workspace and removes missing linked ones', () async {
      processRunner.currentBranch = 'main';
      processRunner.sourceBranches = <String>['main'];
      final mainWorkspace = await service.ensureMainWorkspace(project);
      final linkedWorkspace = await service.createLinkedWorkspace(
        project: project,
        sourceBranch: 'main',
        newBranchName: 'feature/remove-me',
      );
      processRunner.liveBranchByPath = <String, String>{
        project.repoPath: 'main',
      };

      final workspaces = await service.reconcile(project);

      expect(workspaces.map((workspace) => workspace.id), <String>[
        mainWorkspace.id,
      ]);
      expect(
        workspaces.singleWhere((workspace) => workspace.id == mainWorkspace.id).status,
        WorkspaceStatus.active,
      );
      expect(
        repository.workspaces.any((workspace) => workspace.id == linkedWorkspace.id),
        isFalse,
      );
    });

    test('reconcile keeps linked workspaces when git worktree list fails', () async {
      processRunner.currentBranch = 'main';
      processRunner.sourceBranches = <String>['main'];
      final mainWorkspace = await service.ensureMainWorkspace(project);
      final linkedWorkspace = await service.createLinkedWorkspace(
        project: project,
        sourceBranch: 'main',
        newBranchName: 'feature/keep-me',
      );
      processRunner.worktreeListFails = true;

      final workspaces = await service.reconcile(project);

      expect(
        workspaces.map((workspace) => workspace.id),
        containsAll(<String>[mainWorkspace.id, linkedWorkspace.id]),
      );
    });

    test('removeWorkspace deletes the workspace and cascades its terminal tabs', () async {
      processRunner.sourceBranches = <String>['main'];
      final linkedWorkspace = await service.createLinkedWorkspace(
        project: project,
        sourceBranch: 'main',
        newBranchName: 'feature/with-tabs',
      );
      await repository.upsertTerminalTab(
        TerminalTabRecord(
          id: 'tab-1',
          workspaceId: linkedWorkspace.id,
          title: 'Terminal 1',
          createdAt: DateTime.utc(2026, 5, 20),
          updatedAt: DateTime.utc(2026, 5, 20),
        ),
      );

      await service.removeWorkspace(
        project: project,
        workspace: linkedWorkspace,
        deleteBranch: true,
      );

      expect(
        repository.workspaces.any((workspace) => workspace.id == linkedWorkspace.id),
        isFalse,
      );
      expect(await repository.listTerminalTabs(linkedWorkspace.id), isEmpty);
    });
  });
}

class _FakeWorkbenchRepository implements WorkbenchRepository {
  final List<Workspace> workspaces = <Workspace>[];
  final List<TerminalTabRecord> tabs = <TerminalTabRecord>[];

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
  Future<TerminalTabRecord?> findTerminalTabById(String tabId) async {
    for (final tab in tabs) {
      if (tab.id == tabId) {
        return tab;
      }
    }
    return null;
  }

  @override
  Future<List<TerminalTabRecord>> listTerminalTabs(String workspaceId) async =>
      tabs
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
  Future<void> removeTerminalTab(String tabId) async {
    tabs.removeWhere((tab) => tab.id == tabId);
  }

  @override
  Future<void> removeTerminalTabsForWorkspace(String workspaceId) async {
    tabs.removeWhere((tab) => tab.workspaceId == workspaceId);
  }

  @override
  Future<void> removeWorkspace(String workspaceId, {bool cascadeTabs = true}) async {
    workspaces.removeWhere((workspace) => workspace.id == workspaceId);
    if (cascadeTabs) {
      await removeTerminalTabsForWorkspace(workspaceId);
    }
  }

  @override
  Future<void> removeWorkspacesForProject(String projectId) async {
    workspaces.removeWhere((workspace) => workspace.projectId == projectId);
  }

  @override
  Future<TerminalTabRecord> upsertTerminalTab(TerminalTabRecord tab) async {
    final index = tabs.indexWhere((entry) => entry.id == tab.id);
    if (index == -1) {
      tabs.add(tab);
    } else {
      tabs[index] = tab;
    }
    return tab;
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
  Stream<List<TerminalTabRecord>> watchTerminalTabs(String workspaceId) =>
      const Stream<List<TerminalTabRecord>>.empty();

  @override
  Stream<List<Workspace>> watchWorkspaces(String projectId) =>
      const Stream<List<Workspace>>.empty();
}

class _FakeProcessRunner implements ProcessRunner {
  final List<_ProcessCall> calls = <_ProcessCall>[];
  String currentBranch = 'main';
  List<String> sourceBranches = <String>['main'];
  Map<String, String> liveBranchByPath = <String, String>{};
  bool worktreeListFails = false;

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
      return ProcessRunOutput(exitCode: 0, stdout: '$currentBranch\n', stderr: '');
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
      return ProcessRunOutput(exitCode: 0, stdout: buffer.toString(), stderr: '');
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
