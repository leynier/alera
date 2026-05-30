import 'dart:io';

import 'package:alera/src/features/projects/application/project_service.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/shared/infra/git/git_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'fake_git_backend.dart';

void main() {
  group('ProjectService', () {
    late FakeGitBackend gitBackend;
    late ProjectService service;

    setUp(() {
      gitBackend = FakeGitBackend();
      service = ProjectService(gitBackend);
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
        gitBackend.isRepositoryError = const AccessDeniedException(
          'operation not permitted',
        );

        final denied = await service.validateGitRepository(dir.path);

        expect(denied.isValidGitRepository, isFalse);
        expect(denied.message, contains('access denied by macOS sandbox'));
        expect(await service.isGitRepository(dir.path), isFalse);
      },
    );

    test('validateGitRepository reports non-repository folders', () async {
      final dir = Directory.systemTemp.createTempSync('alera-project-service-');
      addTearDown(() {
        if (dir.existsSync()) {
          dir.deleteSync(recursive: true);
        }
      });

      gitBackend.isRepository = false;

      final result = await service.validateGitRepository(dir.path);
      expect(result.isValidGitRepository, isFalse);
      expect(result.message, 'path is not a git repository: ${dir.path}');
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
        gitBackend.isRepository = false;

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

        gitBackend.isRepository = true;

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
        gitBackend.cloneFails = true;
        gitBackend.cloneError = const CloneFailedException('fatal: boom');

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
        // Clone succeeds but produces a folder that is not a git repository.
        gitBackend.cloneFails = false;
        gitBackend.isRepository = false;
        gitBackend.onClone = (_, destination) =>
            Directory(destination).createSync(recursive: true);

        await expectLater(
          service.cloneGitRepository(
            url: 'https://example.com/repo.git',
            destinationPath: invalidDestination,
          ),
          throwsStateError,
        );
      },
    );

    test('cloneGitRepository wraps clone failures as state errors', () async {
      final destination = Directory.systemTemp.createTempSync(
        'alera-project-clone-failure-',
      );
      addTearDown(() {
        if (destination.existsSync()) {
          destination.deleteSync(recursive: true);
        }
      });
      gitBackend.cloneFails = true;
      gitBackend.cloneError = const CloneFailedException('exit 128');

      await expectLater(
        service.cloneGitRepository(
          url: 'https://example.com/repo.git',
          destinationPath: destination.path,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('git clone failed'),
          ),
        ),
      );
    });

    test(
      'listGitBranches sorts unique refs and returns empty on failure',
      () async {
        gitBackend.sourceBranches = <String>[
          'origin/main',
          'main',
          'feature/a',
          'main',
        ];

        expect(await service.listGitBranches('/tmp/repo'), <String>[
          'feature/a',
          'main',
          'origin/main',
        ]);

        gitBackend.listBranchesFails = true;
        expect(await service.listGitBranches('/tmp/repo'), isEmpty);
      },
    );
  });
}
