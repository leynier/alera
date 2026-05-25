import 'dart:io';

import 'package:alera/src/features/projects/application/project_service.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('ProjectService', () {
    late _FakeProcessRunner processRunner;
    late ProjectService service;

    setUp(() {
      processRunner = _FakeProcessRunner();
      service = ProjectService(processRunner);
    });

    test(
      'validateGitRepository reports missing paths and sandbox denials',
      () async {
        final missing = await service.validateGitRepository('/missing/path');
        expect(missing.isValidGitRepository, isFalse);
        expect(missing.message, contains('path does not exist'));

        final dir = Directory.systemTemp.createTempSync(
          'alera-project-service-',
        );
        addTearDown(() {
          if (dir.existsSync()) {
            dir.deleteSync(recursive: true);
          }
        });
        processRunner.revParseResult = const ProcessRunOutput(
          exitCode: 1,
          stdout: '',
          stderr: 'Operation not permitted',
        );

        final denied = await service.validateGitRepository(dir.path);

        expect(denied.isValidGitRepository, isFalse);
        expect(denied.message, contains('access denied by macOS sandbox'));
        expect(await service.isGitRepository(dir.path), isFalse);
      },
    );

    test('validateGitRepository returns stderr and generic failures', () async {
      final dir = Directory.systemTemp.createTempSync('alera-project-service-');
      addTearDown(() {
        if (dir.existsSync()) {
          dir.deleteSync(recursive: true);
        }
      });

      processRunner.revParseResult = const ProcessRunOutput(
        exitCode: 1,
        stdout: '',
        stderr: 'not a git repository',
      );
      final stderrFailure = await service.validateGitRepository(dir.path);
      expect(stderrFailure.message, 'not a git repository');

      processRunner.revParseResult = const ProcessRunOutput(
        exitCode: 1,
        stdout: '',
        stderr: '',
      );
      final genericFailure = await service.validateGitRepository(dir.path);
      expect(
        genericFailure.message,
        'path is not a git repository: ${dir.path}',
      );
    });

    test(
      'inspectLocalProjectPath distinguishes missing, git, and folder paths',
      () async {
        final missing = await service.inspectLocalProjectPath('/missing/path');
        expect(missing.isValid, isFalse);
        expect(missing.message, contains('path does not exist'));

        final gitDir = Directory.systemTemp.createTempSync(
          'alera-project-git-',
        );
        Directory(p.join(gitDir.path, '.git')).createSync();
        addTearDown(() {
          if (gitDir.existsSync()) {
            gitDir.deleteSync(recursive: true);
          }
        });

        final gitProject = await service.inspectLocalProjectPath(gitDir.path);
        expect(gitProject.kind, ProjectKind.gitRepository);

        final folderDir = Directory.systemTemp.createTempSync(
          'alera-project-folder-',
        );
        addTearDown(() {
          if (folderDir.existsSync()) {
            folderDir.deleteSync(recursive: true);
          }
        });
        processRunner.revParseResult = const ProcessRunOutput(
          exitCode: 1,
          stdout: '',
          stderr: '',
        );

        final folderProject = await service.inspectLocalProjectPath(
          folderDir.path,
        );
        expect(folderProject.kind, ProjectKind.folder);
      },
    );

    test(
      'validateGitRepository accepts git work trees without a .git entry',
      () async {
        final dir = Directory.systemTemp.createTempSync(
          'alera-project-service-',
        );
        addTearDown(() {
          if (dir.existsSync()) {
            dir.deleteSync(recursive: true);
          }
        });

        processRunner.revParseResult = const ProcessRunOutput(
          exitCode: 0,
          stdout: 'true\n',
          stderr: '',
        );

        final result = await service.validateGitRepository(dir.path);

        expect(result.isValidGitRepository, isTrue);
        expect(result.message, isNull);
      },
    );

    test('cloneGitRepository validates inputs and destination state', () async {
      await expectLater(
        service.cloneGitRepository(url: '   ', destinationPath: '/tmp/repo'),
        throwsStateError,
      );
      await expectLater(
        service.cloneGitRepository(
          url: 'https://example.com/repo.git',
          destinationPath: '   ',
        ),
        throwsStateError,
      );

      final destination = Directory.systemTemp.createTempSync(
        'alera-project-clone-dest-',
      );
      File(p.join(destination.path, 'existing.txt')).writeAsStringSync('busy');
      addTearDown(() {
        if (destination.existsSync()) {
          destination.deleteSync(recursive: true);
        }
      });

      await expectLater(
        service.cloneGitRepository(
          url: 'https://example.com/repo.git',
          destinationPath: destination.path,
        ),
        throwsStateError,
      );
    });

    test(
      'cloneGitRepository surfaces clone failures and invalid clones',
      () async {
        final tempRoot = Directory.systemTemp.createTempSync(
          'alera-project-clone-root-',
        );
        addTearDown(() {
          if (tempRoot.existsSync()) {
            tempRoot.deleteSync(recursive: true);
          }
        });
        final failingDestination = p.join(
          tempRoot.path,
          'nested',
          'failing-clone',
        );
        processRunner.cloneResult = const ProcessRunOutput(
          exitCode: 1,
          stdout: '',
          stderr: 'fatal: boom',
        );

        await expectLater(
          service.cloneGitRepository(
            url: 'https://example.com/repo.git',
            destinationPath: failingDestination,
          ),
          throwsStateError,
        );
        expect(Directory(p.dirname(failingDestination)).existsSync(), isTrue);

        final invalidDestination = p.join(
          tempRoot.path,
          'nested',
          'invalid-clone',
        );
        processRunner.cloneResult = const ProcessRunOutput(
          exitCode: 0,
          stdout: '',
          stderr: '',
        );
        processRunner.createDestinationOnClone = true;
        processRunner.revParseResult = const ProcessRunOutput(
          exitCode: 1,
          stdout: '',
          stderr: 'not a git repository',
        );

        await expectLater(
          service.cloneGitRepository(
            url: 'https://example.com/repo.git',
            destinationPath: invalidDestination,
          ),
          throwsStateError,
        );
      },
    );

    test(
      'cloneGitRepository uses a generic error when git emits no stderr',
      () async {
        final destination = Directory.systemTemp.createTempSync(
          'alera-project-clone-empty-stderr-',
        );
        addTearDown(() {
          if (destination.existsSync()) {
            destination.deleteSync(recursive: true);
          }
        });
        processRunner.cloneResult = const ProcessRunOutput(
          exitCode: 128,
          stdout: '',
          stderr: '',
        );

        await expectLater(
          service.cloneGitRepository(
            url: 'https://example.com/repo.git',
            destinationPath: destination.path,
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'git clone failed (exit 128)',
            ),
          ),
        );
      },
    );

    test(
      'listGitBranches sorts unique refs and ignores HEAD aliases',
      () async {
        processRunner.branchesResult = const ProcessRunOutput(
          exitCode: 0,
          stdout: 'origin/main\nmain\norigin/HEAD\nfeature/a\nmain\n',
          stderr: '',
        );

        expect(await service.listGitBranches('/tmp/repo'), <String>[
          'feature/a',
          'main',
          'origin/main',
        ]);

        processRunner.branchesResult = const ProcessRunOutput(
          exitCode: 1,
          stdout: '',
          stderr: 'boom',
        );
        expect(await service.listGitBranches('/tmp/repo'), isEmpty);
      },
    );
  });
}

class _FakeProcessRunner implements ProcessRunner {
  ProcessRunOutput revParseResult = const ProcessRunOutput(
    exitCode: 0,
    stdout: 'true\n',
    stderr: '',
  );
  ProcessRunOutput cloneResult = const ProcessRunOutput(
    exitCode: 0,
    stdout: '',
    stderr: '',
  );
  ProcessRunOutput branchesResult = const ProcessRunOutput(
    exitCode: 0,
    stdout: '',
    stderr: '',
  );
  bool createDestinationOnClone = false;

  @override
  Future<ProcessRunOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    if (arguments.contains('rev-parse')) {
      return revParseResult;
    }
    if (arguments.contains('for-each-ref')) {
      return branchesResult;
    }
    if (arguments.isNotEmpty && arguments.first == 'clone') {
      if (createDestinationOnClone && arguments.length >= 4) {
        Directory(arguments.last).createSync(recursive: true);
      }
      return cloneResult;
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
