import 'package:alera/src/features/projects/domain/project_config.dart';
import 'package:alera/src/features/projects/infra/drift_project_config_repository.dart';
import 'package:alera/src/shared/infra/storage/drift_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DriftProjectConfigRepository', () {
    test(
      'saves, loads, watches, and removes project config overrides',
      () async {
        final db = AleraDatabase(executor: NativeDatabase.memory());
        addTearDown(db.close);
        final repository = DriftProjectConfigRepository(db);
        final config = ProjectConfig(
          worktree: WorktreeSetupConfig(
            copy: const <WorktreeCopyRule>[
              WorktreeCopyRule(from: '.env', overwrite: true),
            ],
            setup: const <String>['pnpm install'],
          ),
        );

        await repository.save(
          projectId: 'project-1',
          config: config,
          updatedAt: DateTime.utc(2026, 6, 27),
        );

        expect(await repository.findByProjectId('project-1'), config);
        expect(await repository.loadAll(), <String, ProjectConfig>{
          'project-1': config,
        });
        expect(await repository.watchAll().first, <String, ProjectConfig>{
          'project-1': config,
        });

        await repository.remove('project-1');

        expect(await repository.findByProjectId('project-1'), isNull);
      },
    );
  });
}
