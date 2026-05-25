import 'dart:async';
import 'dart:io';

import 'package:alera/src/features/projects/application/project_repository.dart';
import 'package:alera/src/features/projects/application/project_service.dart';
import 'package:alera/src/features/projects/application/projects_service.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('ProjectsService', () {
    late Directory tempDir;
    late _FakeProjectRepository repository;
    late _FakeProcessRunner processRunner;
    late ProjectsService service;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('alera-projects-test-');
      repository = _FakeProjectRepository();
      processRunner = _FakeProcessRunner();
      service = ProjectsService(
        projectService: ProjectService(processRunner),
        projectRepository: repository,
        now: () => DateTime.utc(2026, 5, 25, 12),
      );
    });

    tearDown(() async {
      await repository.dispose();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('adds a non-Git local folder as a folder project', () async {
      final folder = Directory(p.join(tempDir.path, 'notes'))
        ..createSync(recursive: true);

      final project = await service.addLocalProject(path: folder.path);

      expect(project.kind, ProjectKind.folder);
      expect(project.repoPath, folder.path);
      expect(project.name, 'notes');
      expect(repository.projects.single, project);
    });

    test('adds a Git local folder as a Git repository project', () async {
      final repo = Directory(p.join(tempDir.path, 'repo'))
        ..createSync(recursive: true);
      Directory(p.join(repo.path, '.git')).createSync();

      final project = await service.addLocalProject(path: repo.path);

      expect(project.kind, ProjectKind.gitRepository);
      expect(processRunner.calls, isEmpty);
    });

    test('rejects blank local project paths', () async {
      await expectLater(
        service.addLocalProject(path: '   '),
        throwsStateError,
      );
    });

    test('surfaces invalid local project path messages', () async {
      await expectLater(
        service.addLocalProject(path: p.join(tempDir.path, 'missing-folder')),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('does not exist'),
          ),
        ),
      );
    });

    test('returns an already-registered local project for the same path', () async {
      final repo = Directory(p.join(tempDir.path, 'repo'))
        ..createSync(recursive: true);
      Directory(p.join(repo.path, '.git')).createSync();
      final existing = Project(
        id: 'project-1',
        name: 'Existing',
        repoPath: repo.path,
        createdAt: DateTime.utc(2026, 5, 24),
        updatedAt: DateTime.utc(2026, 5, 24),
      );
      await repository.add(existing);

      final project = await service.addLocalProject(path: repo.path);

      expect(project, same(existing));
      expect(repository.projects, hasLength(1));
    });

    test('clones and registers a Git repository project', () async {
      final destination = p.join(tempDir.path, 'cloned-repo');

      final project = await service.cloneProject(
        gitUrl: 'https://example.com/acme/cloned-repo.git',
        destinationPath: destination,
      );

      expect(project.kind, ProjectKind.gitRepository);
      expect(project.repoPath, destination);
      expect(project.name, 'cloned-repo');
      expect(processRunner.calls.single.arguments, <String>[
        'clone',
        '--progress',
        '--',
        'https://example.com/acme/cloned-repo.git',
        destination,
      ]);
    });

    test('does not persist a project when clone fails', () async {
      processRunner.cloneFails = true;

      await expectLater(
        service.cloneProject(
          gitUrl: 'https://example.com/acme/repo.git',
          destinationPath: p.join(tempDir.path, 'repo'),
        ),
        throwsStateError,
      );

      expect(repository.projects, isEmpty);
    });

    test('rejects blank clone destinations', () async {
      await expectLater(
        service.cloneProject(
          gitUrl: 'https://example.com/acme/repo.git',
          destinationPath: '   ',
        ),
        throwsStateError,
      );
    });

    test('rejects clone destinations that are already registered', () async {
      final existing = Project(
        id: 'project-1',
        name: 'Existing',
        repoPath: p.join(tempDir.path, 'repo'),
        createdAt: DateTime.utc(2026, 5, 24),
        updatedAt: DateTime.utc(2026, 5, 24),
      );
      await repository.add(existing);

      await expectLater(
        service.cloneProject(
          gitUrl: 'https://example.com/acme/repo.git',
          destinationPath: existing.repoPath,
        ),
        throwsStateError,
      );
    });

    test('renames a project with a trimmed non-empty name', () async {
      final project = Project(
        id: 'project-1',
        name: 'Old name',
        repoPath: tempDir.path,
        createdAt: DateTime.utc(2026, 5, 24),
        updatedAt: DateTime.utc(2026, 5, 24),
      );
      await repository.add(project);

      final renamed = await service.renameProject(
        projectId: project.id,
        name: '  New name  ',
      );

      expect(renamed.name, 'New name');
      expect(renamed.updatedAt, DateTime.utc(2026, 5, 25, 12));
      expect(repository.projects.single.name, 'New name');
    });

    test('rejects a blank project name when renaming', () async {
      await expectLater(
        service.renameProject(projectId: 'project-1', name: '   '),
        throwsStateError,
      );
    });

    test('addProject delegates to addLocalProject', () async {
      final repo = Directory(p.join(tempDir.path, 'repo-wrapper'))
        ..createSync(recursive: true);
      Directory(p.join(repo.path, '.git')).createSync();

      final project = await service.addProject(repoPath: repo.path, name: 'Wrapper');

      expect(project.repoPath, repo.path);
      expect(project.name, 'Wrapper');
    });

    test('renameProject rejects missing ids', () async {
      await expectLater(
        service.renameProject(projectId: 'missing-project', name: 'Renamed'),
        throwsStateError,
      );
    });

    test('removeProject delegates to the repository', () async {
      final project = Project(
        id: 'project-1',
        name: 'Existing',
        repoPath: p.join(tempDir.path, 'repo'),
        createdAt: DateTime.utc(2026, 5, 24),
        updatedAt: DateTime.utc(2026, 5, 24),
      );
      await repository.add(project);

      await service.removeProject(project.id);

      expect(repository.projects, isEmpty);
    });

    test('legacy project JSON without kind remains Git-backed', () {
      final now = DateTime.utc(2026, 5, 25);

      final project = Project.fromJson(<String, Object?>{
        'id': 'project-1',
        'name': 'Legacy',
        'repoPath': '/repo/legacy',
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      });

      expect(project.kind, ProjectKind.gitRepository);
      expect(project.supportsLinkedWorkspaces, isTrue);
    });
  });
}

class _FakeProjectRepository implements ProjectRepository {
  final List<Project> projects = <Project>[];
  final StreamController<List<Project>> _controller =
      StreamController<List<Project>>.broadcast();

  @override
  Future<Project> add(Project project) async {
    projects.add(project);
    _controller.add(List<Project>.from(projects));
    return project;
  }

  @override
  Future<List<Project>> listAll() async => List<Project>.from(projects);

  @override
  Future<void> remove(String projectId) async {
    projects.removeWhere((project) => project.id == projectId);
    _controller.add(List<Project>.from(projects));
  }

  @override
  Future<Project> update(Project project) async {
    final index = projects.indexWhere((entry) => entry.id == project.id);
    if (index < 0) {
      projects.add(project);
    } else {
      projects[index] = project;
    }
    _controller.add(List<Project>.from(projects));
    return project;
  }

  @override
  Stream<List<Project>> watchAll() => _controller.stream;

  Future<void> dispose() {
    return _controller.close();
  }
}

class _FakeProcessRunner implements ProcessRunner {
  final List<_ProcessCall> calls = <_ProcessCall>[];
  bool cloneFails = false;

  @override
  Future<ProcessRunOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    if (arguments.isNotEmpty && arguments.first == 'clone') {
      calls.add(_ProcessCall(arguments: List<String>.from(arguments)));
      if (cloneFails) {
        return const ProcessRunOutput(
          exitCode: 128,
          stdout: '',
          stderr: 'fatal: could not clone',
        );
      }
      final destination = arguments.last;
      Directory(p.join(destination, '.git')).createSync(recursive: true);
      return const ProcessRunOutput(exitCode: 0, stdout: '', stderr: '');
    }

    if (arguments.contains('rev-parse')) {
      return const ProcessRunOutput(
        exitCode: 128,
        stdout: '',
        stderr: 'fatal: not a git repository',
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
  const _ProcessCall({required this.arguments});

  final List<String> arguments;
}
