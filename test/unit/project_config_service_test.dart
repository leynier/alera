import 'package:alera/src/features/projects/application/project_config_service.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/domain/project_config.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_project_config.dart';

void main() {
  group('ProjectConfigService', () {
    late FakeProjectConfigRepository repository;
    late FakeProjectConfigFileStore fileStore;
    late ProjectConfigService service;
    late Project project;

    setUp(() {
      repository = FakeProjectConfigRepository();
      fileStore = FakeProjectConfigFileStore();
      service = ProjectConfigService(
        repository: repository,
        fileStore: fileStore,
        now: () => DateTime.utc(2026, 6, 27),
      );
      project = Project(
        id: 'project-1',
        name: 'Project',
        repoPath: '/repo/project',
        createdAt: .utc(2026),
        updatedAt: .utc(2026),
      );
    });

    tearDown(() => repository.dispose());

    test('uses UI override before repo file config', () async {
      fileStore.config = const ProjectConfig(
        worktree: WorktreeSetupConfig(setup: <String>['repo']),
      );
      await service.saveUiOverride(
        projectId: project.id,
        config: const ProjectConfig(
          worktree: WorktreeSetupConfig(setup: <String>['ui']),
        ),
      );

      final effective = await service.resolve(project);

      expect(effective.origin, ProjectConfigOrigin.uiOverride);
      expect(effective.config.worktree.setup, <String>['ui']);
    });

    test(
      'a remote-only project never reads a repo file on this device',
      () async {
        fileStore.config = const ProjectConfig(
          worktree: WorktreeSetupConfig(setup: <String>['local-lookalike']),
        );
        final remoteOnly = project.copyWith(primaryHostId: 'ssh-box');

        expect(await service.loadRepoFile(remoteOnly), isNull);
        final effective = await service.resolve(remoteOnly);
        expect(effective.origin, ProjectConfigOrigin.none);
        expect(effective.hasError, isFalse);

        // A broken file at the same local path is not this project's either.
        fileStore.error = ProjectConfigException('Invalid alera.toml');
        expect((await service.resolve(remoteOnly)).hasError, isFalse);

        await service.saveUiOverride(
          projectId: remoteOnly.id,
          config: const ProjectConfig(
            worktree: WorktreeSetupConfig(setup: <String>['ui']),
          ),
        );
        expect(
          (await service.resolve(remoteOnly)).origin,
          ProjectConfigOrigin.uiOverride,
        );
      },
    );

    test('falls back to repo file after removing UI override', () async {
      fileStore.config = const ProjectConfig(
        worktree: WorktreeSetupConfig(setup: <String>['repo']),
      );
      await service.saveUiOverride(
        projectId: project.id,
        config: const ProjectConfig(
          worktree: WorktreeSetupConfig(setup: <String>['ui']),
        ),
      );
      await service.removeUiOverride(project.id);

      final effective = await service.resolve(project);

      expect(effective.origin, ProjectConfigOrigin.repoFile);
      expect(effective.config.worktree.setup, <String>['repo']);
    });

    test('reports repo file errors without throwing', () async {
      fileStore.error = ProjectConfigException('Invalid Config');

      final effective = await service.resolve(project);

      expect(effective.origin, ProjectConfigOrigin.repoFile);
      expect(effective.config.isEmpty, isTrue);
      expect(effective.hasError, isTrue);
    });
  });
}
