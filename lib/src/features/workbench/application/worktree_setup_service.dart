import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/domain/project_config.dart';
import 'package:alera/src/features/projects/domain/project_config_paths.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_creation_result.dart';
import 'package:alera/src/shared/infra/process/command_environment_resolver.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:path/path.dart' as p;

enum WorktreeSetupOperatingSystem { posix, windows }

abstract interface class WorktreeSetupRunner {
  Future<WorktreeSetupReport> run({
    required Project project,
    required Workspace workspace,
    required ProjectConfig config,
  });
}

class NoopWorktreeSetupRunner implements WorktreeSetupRunner {
  const NoopWorktreeSetupRunner();

  @override
  Future<WorktreeSetupReport> run({
    required Project project,
    required Workspace workspace,
    required ProjectConfig config,
  }) async {
    return WorktreeSetupReport.empty;
  }
}

class WorktreeSetupService implements WorktreeSetupRunner {
  WorktreeSetupService({
    required ProcessRunner processRunner,
    CommandEnvironmentResolver? commandEnvironmentResolver,
    WorktreeSetupOperatingSystem? operatingSystem,
  }) : this._(
         processRunner,
         commandEnvironmentResolver ?? UserCommandEnvironmentResolver(),
         operatingSystem ??
             (Platform.isWindows
                 ? WorktreeSetupOperatingSystem.windows
                 : WorktreeSetupOperatingSystem.posix),
       );

  WorktreeSetupService._(
    this._processRunner,
    this._commandEnvironmentResolver,
    this._operatingSystem,
  );

  final ProcessRunner _processRunner;
  final CommandEnvironmentResolver _commandEnvironmentResolver;
  final WorktreeSetupOperatingSystem _operatingSystem;

  @override
  Future<WorktreeSetupReport> run({
    required Project project,
    required Workspace workspace,
    required ProjectConfig config,
  }) async {
    final steps = <WorktreeSetupStepReport>[];

    for (final rule in config.worktree.copy) {
      final report = await _copyRule(
        project: project,
        workspace: workspace,
        rule: rule,
      );
      steps.add(report);
      if (!report.succeeded) {
        return WorktreeSetupReport(steps: List.unmodifiable(steps));
      }
    }

    for (final command in config.worktree.setup) {
      final report = await _runCommand(
        workspacePath: workspace.path,
        command: command,
      );
      steps.add(report);
      if (!report.succeeded) {
        return WorktreeSetupReport(steps: List.unmodifiable(steps));
      }
    }

    return WorktreeSetupReport(steps: List.unmodifiable(steps));
  }

  Future<WorktreeSetupStepReport> _copyRule({
    required Project project,
    required Workspace workspace,
    required WorktreeCopyRule rule,
  }) async {
    final label = '${rule.from} -> ${rule.destination}';
    try {
      final projectRoot = Directory(
        project.repoPath,
      ).resolveSymbolicLinksSync();
      final workspaceRoot = Directory(
        workspace.path,
      ).resolveSymbolicLinksSync();
      final sourcePath = _joinConfigPath(
        projectRoot,
        normalizeProjectConfigPath(rule.from, 'copy source'),
      );
      final targetPath = _joinConfigPath(
        workspaceRoot,
        normalizeProjectConfigPath(rule.destination, 'copy destination'),
      );

      if (_isSymlink(sourcePath)) {
        throw WorktreeSetupException('Source is a symlink');
      }
      final sourceType = FileSystemEntity.typeSync(
        sourcePath,
        followLinks: false,
      );
      if (sourceType == FileSystemEntityType.notFound) {
        throw WorktreeSetupException('Source does not exist');
      }
      final sourceCanonical = FileSystemEntity.isDirectorySync(sourcePath)
          ? Directory(sourcePath).resolveSymbolicLinksSync()
          : File(sourcePath).resolveSymbolicLinksSync();
      if (!_isWithinOrEqual(projectRoot, sourceCanonical)) {
        throw WorktreeSetupException('Source escapes the project root');
      }

      await _prepareTarget(
        targetPath,
        workspaceRoot,
        overwrite: rule.overwrite,
      );
      if (sourceType == FileSystemEntityType.directory) {
        await _copyDirectory(sourcePath, targetPath, workspaceRoot);
      } else if (sourceType == FileSystemEntityType.file) {
        await File(sourcePath).copy(targetPath);
      } else {
        throw WorktreeSetupException('Unsupported source type');
      }

      return WorktreeSetupStepReport(
        kind: WorktreeSetupStepKind.copy,
        label: label,
        succeeded: true,
      );
    } catch (error) {
      return WorktreeSetupStepReport(
        kind: WorktreeSetupStepKind.copy,
        label: label,
        succeeded: false,
        message: error.toString(),
      );
    }
  }

  Future<void> _prepareTarget(
    String targetPath,
    String workspaceRoot, {
    required bool overwrite,
  }) async {
    _validateDestinationParent(targetPath, workspaceRoot);
    final parent = Directory(p.dirname(targetPath));
    if (!parent.existsSync()) {
      await parent.create(recursive: true);
    }
    _validateDestinationParent(targetPath, workspaceRoot);

    final exists =
        FileSystemEntity.typeSync(targetPath, followLinks: false) !=
        FileSystemEntityType.notFound;
    if (!exists) {
      return;
    }
    if (!overwrite) {
      throw WorktreeSetupException('Destination already exists');
    }
    final targetType = FileSystemEntity.typeSync(
      targetPath,
      followLinks: false,
    );
    if (targetType == FileSystemEntityType.directory) {
      await Directory(targetPath).delete(recursive: true);
    } else {
      await File(targetPath).delete();
    }
  }

  Future<void> _copyDirectory(
    String sourcePath,
    String targetPath,
    String workspaceRoot,
  ) async {
    await Directory(targetPath).create(recursive: true);
    final targetCanonical = Directory(targetPath).resolveSymbolicLinksSync();
    if (!_isWithinOrEqual(workspaceRoot, targetCanonical)) {
      throw WorktreeSetupException('Destination escapes the workspace root');
    }
    await for (final entity in Directory(sourcePath).list(followLinks: false)) {
      if (_isSymlink(entity.path)) {
        throw WorktreeSetupException('Directory contains a symlink');
      }
      final childTarget = p.join(targetPath, p.basename(entity.path));
      final type = FileSystemEntity.typeSync(entity.path, followLinks: false);
      if (type == FileSystemEntityType.directory) {
        await _copyDirectory(entity.path, childTarget, workspaceRoot);
      } else if (type == FileSystemEntityType.file) {
        await File(entity.path).copy(childTarget);
      } else {
        throw WorktreeSetupException('Directory contains an unsupported entry');
      }
    }
  }

  Future<WorktreeSetupStepReport> _runCommand({
    required String workspacePath,
    required String command,
  }) async {
    final invocation = shellInvocationFor(
      command: command,
      operatingSystem: _operatingSystem,
    );
    try {
      final process = await _processRunner.start(
        invocation.executable,
        invocation.arguments,
        workingDirectory: workspacePath,
        environment: await _commandEnvironmentResolver.environment(),
      );
      process.stdinClose();
      final stdoutTail = _BoundedTextTail();
      final stderrTail = _BoundedTextTail();
      final stdoutDone = process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(stdoutTail.add)
          .asFuture<void>();
      final stderrDone = process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(stderrTail.add)
          .asFuture<void>();
      final exitCode = await process.exitCode;
      await Future.wait<void>(<Future<void>>[stdoutDone, stderrDone]);
      return WorktreeSetupStepReport(
        kind: WorktreeSetupStepKind.command,
        label: command,
        succeeded: exitCode == 0,
        exitCode: exitCode,
        stdoutTail: stdoutTail.value,
        stderrTail: stderrTail.value,
        message: exitCode == 0 ? null : 'Command exited with code $exitCode',
      );
    } catch (error) {
      return WorktreeSetupStepReport(
        kind: WorktreeSetupStepKind.command,
        label: command,
        succeeded: false,
        message: error.toString(),
      );
    }
  }
}

class _BoundedTextTail {
  void add(String chunk) {
    if (chunk.isEmpty) {
      return;
    }
    _buffer.write(chunk);
    final current = _buffer.toString();
    if (current.length <= _maxLength) {
      return;
    }
    _buffer
      ..clear()
      ..write(current.substring(current.length - _maxLength));
  }

  String? get value => _tail(_buffer.toString());

  static const int _maxLength = 4000;
  final StringBuffer _buffer = StringBuffer();
}

class WorktreeSetupException implements Exception {
  WorktreeSetupException(this.message);

  final String message;

  @override
  String toString() => message;
}

({String executable, List<String> arguments}) shellInvocationFor({
  required String command,
  required WorktreeSetupOperatingSystem operatingSystem,
}) {
  return switch (operatingSystem) {
    WorktreeSetupOperatingSystem.windows => (
      executable: 'cmd.exe',
      arguments: <String>['/d', '/s', '/c', command],
    ),
    WorktreeSetupOperatingSystem.posix => (
      executable: '/bin/sh',
      arguments: <String>['-c', command],
    ),
  };
}

String _joinConfigPath(String root, String relativePath) {
  return p.joinAll(<String>[root, ...p.posix.split(relativePath)]);
}

bool _isSymlink(String path) {
  return FileSystemEntity.typeSync(path, followLinks: false) ==
      FileSystemEntityType.link;
}

bool _isWithinOrEqual(String parent, String child) {
  return p.equals(parent, child) || p.isWithin(parent, child);
}

void _validateDestinationParent(String targetPath, String workspaceRoot) {
  final root = p.normalize(workspaceRoot);
  final parentPath = p.normalize(p.dirname(targetPath));
  if (!_isWithinOrEqual(root, parentPath)) {
    throw WorktreeSetupException('Destination escapes the workspace root');
  }

  var currentPath = parentPath;
  while (true) {
    final type = FileSystemEntity.typeSync(currentPath, followLinks: false);
    if (type != FileSystemEntityType.notFound) {
      if (type == FileSystemEntityType.link) {
        throw WorktreeSetupException('Destination contains a symlink');
      }
      if (type != FileSystemEntityType.directory) {
        throw WorktreeSetupException('Destination parent is not a directory');
      }
      final canonical = Directory(currentPath).resolveSymbolicLinksSync();
      if (!_isWithinOrEqual(root, canonical)) {
        throw WorktreeSetupException('Destination escapes the workspace root');
      }
    }

    if (p.equals(currentPath, root)) {
      return;
    }
    final nextPath = p.dirname(currentPath);
    if (p.equals(nextPath, currentPath)) {
      throw WorktreeSetupException('Destination escapes the workspace root');
    }
    currentPath = nextPath;
  }
}

String? _tail(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  const maxLength = 4000;
  if (trimmed.length <= maxLength) {
    return trimmed;
  }
  return trimmed.substring(trimmed.length - maxLength);
}
