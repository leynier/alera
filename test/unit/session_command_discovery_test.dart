import 'dart:io';

import 'package:alera/src/features/session/domain/commands/custom_command_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('CustomCommandRepository', () {
    test('discovers repo and user prompts and keeps repo over user', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'session-command-discovery',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final workspacePath = p.join(tempDir.path, 'workspace');
      final codeHomePath = p.join(tempDir.path, 'codex-home');
      await Directory(
        p.join(workspacePath, '.codex', 'prompts'),
      ).create(recursive: true);
      await Directory(p.join(codeHomePath, 'prompts')).create(recursive: true);

      await File(
        p.join(workspacePath, '.codex', 'prompts', 'repo-only.md'),
      ).writeAsString('''
---
description: Repo only
argument-hint: "<path>"
---
Review \$1
''');
      await File(
        p.join(workspacePath, '.codex', 'prompts', 'shared.md'),
      ).writeAsString('''
---
description: Repo shared
---
Repository wins
''');
      await File(p.join(codeHomePath, 'prompts', 'shared.md')).writeAsString('''
---
description: User shared
---
User loses
''');
      await File(
        p.join(codeHomePath, 'prompts', 'user-only.md'),
      ).writeAsString('User only body');

      final repository = CustomCommandRepository(codexHomePath: codeHomePath);
      final commands = await repository.discover(workspacePath: workspacePath);

      expect(commands.map((command) => command.name).toSet(), <String>{
        'repo-only',
        'shared',
        'user-only',
      });

      final shared = commands
          .where((command) => command.name == 'shared')
          .single;
      expect(shared.scope?.name, 'repo');
      expect(shared.content?.trim(), 'Repository wins');

      final repoOnly = commands
          .where((command) => command.name == 'repo-only')
          .single;
      expect(repoOnly.description, 'Repo only');
      expect(repoOnly.argumentHint, '<path>');

      final userOnly = commands
          .where((command) => command.name == 'user-only')
          .single;
      expect(userOnly.scope?.name, 'user');
      expect(userOnly.description, 'Run saved prompt');
    });

    test('built-in names hide colliding custom commands', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'session-command-builtins',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final workspacePath = p.join(tempDir.path, 'workspace');
      final codeHomePath = p.join(tempDir.path, 'codex-home');
      await Directory(
        p.join(workspacePath, '.codex', 'prompts'),
      ).create(recursive: true);
      await Directory(p.join(codeHomePath, 'prompts')).create(recursive: true);

      await File(
        p.join(workspacePath, '.codex', 'prompts', 'review.md'),
      ).writeAsString('Repository review');
      await File(
        p.join(codeHomePath, 'prompts', 'review.md'),
      ).writeAsString('User review');

      final commands = await CustomCommandRepository(
        codexHomePath: codeHomePath,
      ).discover(workspacePath: workspacePath);

      expect(commands.where((command) => command.name == 'review'), isEmpty);
    });
  });
}
