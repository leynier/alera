import 'dart:io';

import 'package:alera/src/features/projects/application/project_config_service.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/infra/project_config_toml_file_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('Project Config TOML', () {
    test('parses worktree copy rules and setup commands', () {
      final config = parseProjectConfigToml('''
[worktree]
copy = [
  { from = ".env", to = ".env.local", overwrite = true },
  { from = ".claude/settings.local.json" }
]
setup = ["pnpm install", "make bootstrap"]
''');

      expect(config.worktree.copy, hasLength(2));
      expect(config.worktree.copy.first.from, '.env');
      expect(config.worktree.copy.first.to, '.env.local');
      expect(config.worktree.copy.first.overwrite, isTrue);
      expect(
        config.worktree.copy.last.destination,
        '.claude/settings.local.json',
      );
      expect(config.worktree.setup, <String>['pnpm install', 'make bootstrap']);
    });

    test('returns empty config when the worktree table is absent', () {
      final config = parseProjectConfigToml('title = "Alera"');

      expect(config.isEmpty, isTrue);
    });

    test('rejects invalid TOML and unsafe paths', () {
      expect(
        () => parseProjectConfigToml('[worktree'),
        throwsA(isA<ProjectConfigException>()),
      );
      expect(
        () => parseProjectConfigToml('''
[worktree]
copy = [{ from = "../.env" }]
'''),
        throwsA(isA<ProjectConfigException>()),
      );
      expect(
        () => parseProjectConfigToml('''
[worktree]
copy = [{ from = "/tmp/.env" }]
'''),
        throwsA(isA<ProjectConfigException>()),
      );
      expect(
        () => parseProjectConfigToml(r'''
[worktree]
copy = [{ from = " C:\tmp\.env " }]
'''),
        throwsA(isA<ProjectConfigException>()),
      );
    });

    test('loads repo-root alera.toml when present', () async {
      final tempDir = Directory.systemTemp.createTempSync('alera-config-test-');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      await File(
        p.join(tempDir.path, aleraProjectConfigFileName),
      ).writeAsString('''
[worktree]
setup = ["dart pub get"]
''');
      final store = const TomlProjectConfigFileStore();

      final config = await store.load(
        Project(
          id: 'project-1',
          name: 'Project',
          repoPath: tempDir.path,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      );

      expect(config?.worktree.setup, <String>['dart pub get']);
    });
  });
}
