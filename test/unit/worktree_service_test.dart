import 'dart:async';
import 'dart:io';

import 'package:alera/src/features/projects/application/project_repository.dart';
import 'package:alera/src/features/projects/application/worktree_service.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/domain/worktree.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('WorktreeService', () {
    late Directory tempDir;
    late _FakeProjectRepository repository;
    late _FakeProcessRunner processRunner;
    late WorktreeService service;
    late Project project;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('alera-worktree-test-');
      repository = _FakeProjectRepository();
      processRunner = _FakeProcessRunner();
      service = WorktreeService(
        projectRepository: repository,
        processRunner: processRunner,
        worktreeRoot: WorktreeRoot(override: p.join(tempDir.path, 'worktrees')),
        now: () => DateTime.utc(2026, 5, 1, 12),
      );
      project = Project(
        id: 'project-1',
        name: 'Alera',
        repoPath: p.join(tempDir.path, 'repo'),
        createdAt: DateTime.utc(2026, 5, 1),
        updatedAt: DateTime.utc(2026, 5, 1),
      );
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('creates an isolated git worktree and stores it as active', () async {
      final worktree = await service.create(
        project: project,
        name: 'Smoke Branch',
      );

      expect(worktree.projectId, project.id);
      expect(worktree.name, 'smoke-branch');
      expect(worktree.branch, 'alera/smoke-branch');
      expect(worktree.status, WorktreeStatus.active);
      expect(
        worktree.path,
        service.resolveWorktreePath(project, 'smoke-branch'),
      );
      expect(repository.worktrees.single, worktree);
      expect(processRunner.calls.single.executable, 'git');
      expect(processRunner.calls.single.arguments, <String>[
        'worktree',
        'add',
        '-b',
        'alera/smoke-branch',
        worktree.path,
      ]);
      expect(processRunner.calls.single.workingDirectory, project.repoPath);
    });

    test('removes the worktree and optionally deletes its branch', () async {
      final worktree = await service.create(project: project, name: 'cleanup');
      processRunner.calls.clear();

      await service.remove(
        project: project,
        worktree: worktree,
        deleteBranch: true,
      );

      expect(processRunner.calls.map((call) => call.arguments), <List<String>>[
        <String>['worktree', 'remove', '--force', worktree.path],
        <String>['branch', '-D', worktree.branch],
      ]);
      expect(repository.worktrees.single.status, WorktreeStatus.removed);
    });

    test('reconcile marks missing active worktrees as removed', () async {
      final stale = await service.create(project: project, name: 'stale');
      final live = await service.create(project: project, name: 'live');
      processRunner.calls.clear();
      processRunner.worktreeListStdout =
          'worktree ${project.repoPath}\n'
          'branch refs/heads/main\n'
          '\n'
          'worktree ${live.path}\n'
          'branch refs/heads/${live.branch}\n';

      final reconciled = await service.reconcile(project);

      expect(
        reconciled.singleWhere((w) => w.id == stale.id).status,
        WorktreeStatus.removed,
      );
      expect(
        reconciled.singleWhere((w) => w.id == live.id).status,
        WorktreeStatus.active,
      );
      expect(repository.findStored(stale.id)?.status, WorktreeStatus.removed);
    });
  });
}

class _FakeProjectRepository implements ProjectRepository {
  final List<Worktree> worktrees = <Worktree>[];

  @override
  Future<Project> add(Project project) async => project;

  @override
  Future<Worktree> addWorktree(Worktree worktree) async {
    worktrees.add(worktree);
    return worktree;
  }

  @override
  Future<Worktree?> findWorktreeById(String worktreeId) async =>
      findStored(worktreeId);

  Worktree? findStored(String worktreeId) {
    for (final worktree in worktrees) {
      if (worktree.id == worktreeId) {
        return worktree;
      }
    }
    return null;
  }

  @override
  Future<List<Project>> listAll() async => const <Project>[];

  @override
  Future<List<Worktree>> listWorktrees(String projectId) async =>
      worktrees.where((w) => w.projectId == projectId).toList(growable: false);

  @override
  Future<void> remove(String projectId) async {}

  @override
  Future<Project> update(Project project) async => project;

  @override
  Future<Worktree> updateWorktree(Worktree worktree) async {
    final index = worktrees.indexWhere((w) => w.id == worktree.id);
    if (index == -1) {
      worktrees.add(worktree);
    } else {
      worktrees[index] = worktree;
    }
    return worktree;
  }

  @override
  Stream<List<Project>> watchAll() => const Stream<List<Project>>.empty();

  @override
  Stream<List<Worktree>> watchWorktrees(String projectId) =>
      const Stream<List<Worktree>>.empty();
}

class _FakeProcessRunner implements ProcessRunner {
  final List<_ProcessCall> calls = <_ProcessCall>[];
  String worktreeListStdout = '';

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
    if (arguments.length >= 3 &&
        arguments[0] == 'worktree' &&
        arguments[1] == 'list') {
      return ProcessRunOutput(
        exitCode: 0,
        stdout: worktreeListStdout,
        stderr: '',
      );
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
