import 'dart:async';
import 'dart:io';

import 'package:alera/src/features/projects/application/project_service.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/workbench_repository.dart';
import 'package:alera/src/features/workbench/application/workspace_service.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
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
        workspaceRoot: WorkspaceRoot(
          override: p.join(tempDir.path, 'workspaces'),
        ),
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

    test('workspace root throws when no home directory is available', () {
      expect(
        () => WorkspaceRoot(environment: const <String, String>{}).resolve(),
        throwsA(isA<WorkspaceException>()),
      );
    });

    test(
      'ensureMainWorkspace stores the main checkout as an active workspace',
      () async {
        processRunner.currentBranch = 'main';

        final workspace = await service.ensureMainWorkspace(project);

        expect(workspace.projectId, project.id);
        expect(workspace.name, 'Main');
        expect(workspace.branch, 'main');
        expect(workspace.path, project.repoPath);
        expect(workspace.kind, WorkspaceKind.main);
        expect(workspace.status, WorkspaceStatus.active);
        expect(repository.workspaces.single, workspace);
      },
    );

    test('ensureMainWorkspace stores a folder project without Git', () async {
      final folderProject = project.copyWith(kind: ProjectKind.folder);

      final workspace = await service.ensureMainWorkspace(folderProject);

      expect(workspace.projectId, folderProject.id);
      expect(workspace.name, 'Main');
      expect(workspace.branch, isNull);
      expect(workspace.path, folderProject.repoPath);
      expect(workspace.kind, WorkspaceKind.main);
      expect(workspace.status, WorkspaceStatus.active);
      expect(processRunner.calls, isEmpty);
    });

    test(
      'ensureMainWorkspace preserves a custom main workspace name',
      () async {
        final existing = Workspace(
          id: 'workspace-1',
          projectId: project.id,
          name: 'Production checkout',
          branch: 'old-main',
          path: '/old/path',
          createdAt: DateTime.utc(2026, 5, 19),
          updatedAt: DateTime.utc(2026, 5, 19),
          kind: WorkspaceKind.main,
          status: WorkspaceStatus.active,
        );
        await repository.upsertWorkspace(existing);
        processRunner.currentBranch = 'main';

        final workspace = await service.ensureMainWorkspace(project);

        expect(workspace.name, 'Production checkout');
        expect(workspace.branch, 'main');
        expect(workspace.path, project.repoPath);
      },
    );

    test(
      'ensureMainWorkspace falls back to HEAD when git cannot resolve a branch',
      () async {
        processRunner.currentBranch = '';
        processRunner.currentBranchExitCode = 1;

        final workspace = await service.ensureMainWorkspace(project);

        expect(workspace.branch, 'HEAD');
      },
    );

    test('renames a workspace with a trimmed non-empty name', () async {
      final workspace = Workspace(
        id: 'workspace-1',
        projectId: project.id,
        name: 'Old name',
        branch: 'main',
        path: project.repoPath,
        createdAt: DateTime.utc(2026, 5, 19),
        updatedAt: DateTime.utc(2026, 5, 19),
        kind: WorkspaceKind.main,
        status: WorkspaceStatus.active,
      );
      await repository.upsertWorkspace(workspace);

      final renamed = await service.renameWorkspace(
        workspaceId: workspace.id,
        name: '  New name  ',
      );

      expect(renamed.name, 'New name');
      expect(renamed.updatedAt, DateTime.utc(2026, 5, 20, 12));
      expect(repository.workspaces.single.name, 'New name');
    });

    test('rejects a blank workspace name when renaming', () async {
      await expectLater(
        service.renameWorkspace(workspaceId: 'workspace-1', name: '   '),
        throwsA(isA<WorkspaceException>()),
      );
    });

    test('rejects renaming a workspace that does not exist', () async {
      await expectLater(
        service.renameWorkspace(workspaceId: 'missing-workspace', name: 'Main'),
        throwsA(isA<WorkspaceException>()),
      );
    });

    test('listSourceBranches skips folder projects', () async {
      final branches = await service.listSourceBranches(
        project.copyWith(kind: ProjectKind.folder),
      );

      expect(branches, isEmpty);
      expect(processRunner.calls, isEmpty);
    });

    test(
      'createLinkedWorkspace creates a new worktree from the requested source branch',
      () async {
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
      },
    );

    test('createLinkedWorkspace rejects a blank source branch', () async {
      await expectLater(
        service.createLinkedWorkspace(
          project: project,
          sourceBranch: '   ',
          newBranchName: 'feature/blank-source',
        ),
        throwsA(isA<WorkspaceException>()),
      );

      expect(processRunner.calls, isEmpty);
    });

    test('createLinkedWorkspace rejects a blank new branch name', () async {
      await expectLater(
        service.createLinkedWorkspace(
          project: project,
          sourceBranch: 'main',
          newBranchName: '   ',
        ),
        throwsA(isA<WorkspaceException>()),
      );

      expect(processRunner.calls, isEmpty);
    });

    test('createLinkedWorkspace rejects invalid git branch names', () async {
      processRunner.invalidBranchNames.add('bad branch');

      await expectLater(
        service.createLinkedWorkspace(
          project: project,
          sourceBranch: 'main',
          newBranchName: 'bad branch',
        ),
        throwsA(isA<WorkspaceException>()),
      );
    });

    test(
      'createLinkedWorkspace rejects missing sources and existing target branches',
      () async {
        processRunner.sourceBranches = <String>['develop'];

        await expectLater(
          service.createLinkedWorkspace(
            project: project,
            sourceBranch: 'main',
            newBranchName: 'feature/missing-source',
          ),
          throwsA(isA<WorkspaceException>()),
        );

        processRunner.sourceBranches = <String>['main', 'feature/existing'];

        await expectLater(
          service.createLinkedWorkspace(
            project: project,
            sourceBranch: 'main',
            newBranchName: 'feature/existing',
          ),
          throwsA(isA<WorkspaceException>()),
        );
      },
    );

    test('createLinkedWorkspace surfaces git worktree add failures', () async {
      processRunner.sourceBranches = <String>['main'];
      processRunner.failingWorktreeAddBranches.add('feature/add-failure');

      await expectLater(
        service.createLinkedWorkspace(
          project: project,
          sourceBranch: 'main',
          newBranchName: 'feature/add-failure',
        ),
        throwsA(isA<WorkspaceException>()),
      );
    });

    test(
      'createLinkedWorkspace rejects duplicate branches, paths, and invalid slugs',
      () async {
        processRunner.sourceBranches = <String>['main'];
        await repository.upsertWorkspace(
          Workspace(
            id: 'workspace-existing-branch',
            projectId: project.id,
            name: 'Existing branch',
            branch: 'feature/duplicate',
            path: p.join(tempDir.path, 'duplicate-branch'),
            createdAt: DateTime.utc(2026, 5, 19),
            updatedAt: DateTime.utc(2026, 5, 19),
            kind: WorkspaceKind.linked,
            status: WorkspaceStatus.active,
          ),
        );

        await expectLater(
          service.createLinkedWorkspace(
            project: project,
            sourceBranch: 'main',
            newBranchName: 'feature/duplicate',
          ),
          throwsA(isA<WorkspaceException>()),
        );

        await repository.upsertWorkspace(
          Workspace(
            id: 'workspace-existing-path',
            projectId: project.id,
            name: 'Existing path',
            branch: 'feature/other',
            path: p.join(
              tempDir.path,
              'workspaces',
              'repo-project-1',
              'feature-path-dup',
            ),
            createdAt: DateTime.utc(2026, 5, 19),
            updatedAt: DateTime.utc(2026, 5, 19),
            kind: WorkspaceKind.linked,
            status: WorkspaceStatus.active,
          ),
        );

        await expectLater(
          service.createLinkedWorkspace(
            project: project,
            sourceBranch: 'main',
            newBranchName: 'feature/path-dup',
          ),
          throwsA(isA<WorkspaceException>()),
        );

        await expectLater(
          service.createLinkedWorkspace(
            project: project,
            sourceBranch: 'main',
            newBranchName: 'feature/slug',
            name: '!!!',
          ),
          throwsA(isA<WorkspaceException>()),
        );
      },
    );

    test(
      'reconcile keeps the main workspace and removes missing linked ones',
      () async {
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
          workspaces
              .singleWhere((workspace) => workspace.id == mainWorkspace.id)
              .status,
          WorkspaceStatus.active,
        );
        expect(
          repository.workspaces.any(
            (workspace) => workspace.id == linkedWorkspace.id,
          ),
          isFalse,
        );
      },
    );

    test(
      'reconcile keeps linked workspaces when git worktree list fails',
      () async {
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
      },
    );

    test(
      'reconcile updates linked workspace metadata from live worktrees',
      () async {
        processRunner.currentBranch = 'main';
        processRunner.sourceBranches = <String>['main'];
        await service.ensureMainWorkspace(project);
        final linkedWorkspace = await service.createLinkedWorkspace(
          project: project,
          sourceBranch: 'main',
          newBranchName: 'feature/live-rename',
        );
        processRunner.liveBranchByPath = <String, String>{
          project.repoPath: 'main',
          linkedWorkspace.path: 'feature/live-updated',
        };

        final workspaces = await service.reconcile(project);

        expect(
          workspaces
              .singleWhere((workspace) => workspace.id == linkedWorkspace.id)
              .branch,
          'feature/live-updated',
        );
      },
    );

    test(
      'reconcile skips pruning when the live list does not include the main workspace',
      () async {
        processRunner.currentBranch = 'main';
        processRunner.sourceBranches = <String>['main'];
        await service.ensureMainWorkspace(project);
        final linkedWorkspace = await service.createLinkedWorkspace(
          project: project,
          sourceBranch: 'main',
          newBranchName: 'feature/cannot-prune',
        );
        processRunner.liveBranchByPath = <String, String>{
          linkedWorkspace.path: 'feature/cannot-prune',
        };

        final workspaces = await service.reconcile(project);

        expect(
          workspaces.map((workspace) => workspace.id),
          contains(linkedWorkspace.id),
        );
      },
    );

    test(
      'reconcile keeps only the primary workspace for folder projects',
      () async {
        final folderProject = project.copyWith(kind: ProjectKind.folder);
        final linkedWorkspace = Workspace(
          id: 'linked-folder-workspace',
          projectId: folderProject.id,
          name: 'Linked',
          branch: 'feature/remove-me',
          path: p.join(tempDir.path, 'linked-folder-workspace'),
          createdAt: DateTime.utc(2026, 5, 20),
          updatedAt: DateTime.utc(2026, 5, 20),
          kind: WorkspaceKind.linked,
          status: WorkspaceStatus.active,
        );
        await repository.upsertWorkspace(linkedWorkspace);

        final workspaces = await service.reconcile(folderProject);

        expect(workspaces, hasLength(1));
        expect(workspaces.single.isMain, isTrue);
        expect(workspaces.single.branch, isNull);
        expect(
          repository.workspaces.any(
            (workspace) => workspace.id == linkedWorkspace.id,
          ),
          isFalse,
        );
        expect(processRunner.calls, isEmpty);
      },
    );

    test(
      'createLinkedWorkspace rejects folder projects before Git calls',
      () async {
        final folderProject = project.copyWith(kind: ProjectKind.folder);

        await expectLater(
          service.createLinkedWorkspace(
            project: folderProject,
            sourceBranch: 'main',
            newBranchName: 'feature/not-allowed',
          ),
          throwsA(isA<WorkspaceException>()),
        );

        expect(processRunner.calls, isEmpty);
      },
    );

    test(
      'removeWorkspace deletes the workspace and cascades its workspace tabs',
      () async {
        processRunner.sourceBranches = <String>['main'];
        final linkedWorkspace = await service.createLinkedWorkspace(
          project: project,
          sourceBranch: 'main',
          newBranchName: 'feature/with-tabs',
        );
        await repository.upsertWorkspaceTab(
          WorkspaceTabRecord(
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
          repository.workspaces.any(
            (workspace) => workspace.id == linkedWorkspace.id,
          ),
          isFalse,
        );
        expect(await repository.listWorkspaceTabs(linkedWorkspace.id), isEmpty);
      },
    );

    test('removeWorkspace rejects removing the main workspace', () async {
      final mainWorkspace = await service.ensureMainWorkspace(project);

      await expectLater(
        service.removeWorkspace(
          project: project,
          workspace: mainWorkspace,
          deleteBranch: true,
        ),
        throwsA(isA<WorkspaceException>()),
      );
    });

    test(
      'removeWorkspace keeps the branch when deleteBranch is false',
      () async {
        processRunner.sourceBranches = <String>['main'];
        final linkedWorkspace = await service.createLinkedWorkspace(
          project: project,
          sourceBranch: 'main',
          newBranchName: 'feature/keep-branch',
        );

        await service.removeWorkspace(
          project: project,
          workspace: linkedWorkspace,
          deleteBranch: false,
        );

        expect(
          processRunner.calls.any(
            (call) =>
                call.arguments.length >= 3 &&
                call.arguments[0] == 'branch' &&
                call.arguments[1] == '-D' &&
                call.arguments[2] == 'feature/keep-branch',
          ),
          isFalse,
        );
        expect(
          repository.workspaces.any(
            (workspace) => workspace.id == linkedWorkspace.id,
          ),
          isFalse,
        );
      },
    );

    test('removeWorkspace surfaces git worktree removal failures', () async {
      processRunner.sourceBranches = <String>['main'];
      final linkedWorkspace = await service.createLinkedWorkspace(
        project: project,
        sourceBranch: 'main',
        newBranchName: 'feature/remove-failure',
      );
      processRunner.failingWorktreeRemovePaths.add(linkedWorkspace.path);

      await expectLater(
        service.removeWorkspace(
          project: project,
          workspace: linkedWorkspace,
          deleteBranch: true,
        ),
        throwsA(isA<WorkspaceException>()),
      );
    });

    test('removeWorkspace surfaces git branch deletion failures', () async {
      processRunner.sourceBranches = <String>['main'];
      final linkedWorkspace = await service.createLinkedWorkspace(
        project: project,
        sourceBranch: 'main',
        newBranchName: 'feature/branch-failure',
      );
      processRunner.failingBranchDeletes.add('feature/branch-failure');

      await expectLater(
        service.removeWorkspace(
          project: project,
          workspace: linkedWorkspace,
          deleteBranch: true,
        ),
        throwsA(isA<WorkspaceException>()),
      );
    });

    test('removeWorkspace requires a branch when deleting it', () async {
      final branchlessWorkspace = Workspace(
        id: 'workspace-branchless',
        projectId: project.id,
        name: 'Detached',
        branch: '',
        path: p.join(tempDir.path, 'detached'),
        createdAt: DateTime.utc(2026, 5, 20),
        updatedAt: DateTime.utc(2026, 5, 20),
        kind: WorkspaceKind.linked,
        status: WorkspaceStatus.active,
      );

      await expectLater(
        service.removeWorkspace(
          project: project,
          workspace: branchlessWorkspace,
          deleteBranch: true,
        ),
        throwsA(isA<WorkspaceException>()),
      );
    });

    test('WorkspaceException includes stderr only when present', () {
      expect(WorkspaceException('Could not open').toString(), 'Could not open');
      expect(
        WorkspaceException(
          'Could not open',
          stderr: 'fatal error\n',
        ).toString(),
        'Could not open: fatal error',
      );
    });

    test('WorkspaceRoot resolves the default HOME-based path', () {
      final resolved = WorkspaceRoot().resolve();

      expect(resolved, endsWith('.alera/workspaces'));
      expect(resolved, contains(Platform.environment['HOME']!));
    });

    test('WorkspaceService defaults timestamps to current utc time', () async {
      final defaultService = WorkspaceService(
        repository: repository,
        projectService: ProjectService(processRunner),
        processRunner: processRunner,
      );
      final before = DateTime.now().toUtc().subtract(
        const Duration(seconds: 1),
      );

      final workspace = await defaultService.ensureMainWorkspace(project);

      final after = DateTime.now().toUtc().add(const Duration(seconds: 1));
      expect(workspace.updatedAt.isUtc, isTrue);
      expect(workspace.updatedAt.isAfter(before), isTrue);
      expect(workspace.updatedAt.isBefore(after), isTrue);
    });
  });
}

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
