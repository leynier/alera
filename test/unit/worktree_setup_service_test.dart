import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/domain/project_config.dart';
import 'package:alera/src/features/workbench/application/worktree_setup_service.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_creation_result.dart';
import 'package:alera/src/shared/infra/process/command_environment_resolver.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('WorktreeSetupService', () {
    late Directory tempDir;
    late Directory repoDir;
    late Directory workspaceDir;
    late Project project;
    late Workspace workspace;
    late _FakeProcessRunner processRunner;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('alera-setup-test-');
      repoDir = Directory(p.join(tempDir.path, 'repo'))..createSync();
      workspaceDir = Directory(p.join(tempDir.path, 'workspace'))..createSync();
      project = Project(
        id: 'project-1',
        name: 'Project',
        repoPath: repoDir.path,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      workspace = Workspace(
        id: 'workspace-1',
        projectId: project.id,
        name: 'Feature',
        branch: 'feature/setup',
        path: workspaceDir.path,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        kind: WorkspaceKind.linked,
        status: WorkspaceStatus.active,
      );
      processRunner = _FakeProcessRunner();
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('copies files and runs setup commands in order', () async {
      await File(p.join(repoDir.path, '.env')).writeAsString('TOKEN=1\n');
      await Directory(p.join(repoDir.path, '.config')).create();
      await File(
        p.join(repoDir.path, '.config', 'tool.json'),
      ).writeAsString('{}');
      final service = WorktreeSetupService(
        processRunner: processRunner,
        operatingSystem: WorktreeSetupOperatingSystem.posix,
      );

      final report = await service.run(
        project: project,
        workspace: workspace,
        config: const ProjectConfig(
          worktree: WorktreeSetupConfig(
            copy: <WorktreeCopyRule>[
              WorktreeCopyRule(from: '.env'),
              WorktreeCopyRule(from: '.config', to: '.copied-config'),
            ],
            setup: <String>['pnpm install', 'make bootstrap'],
          ),
        ),
      );

      expect(report.hasFailures, isFalse);
      expect(
        await File(p.join(workspaceDir.path, '.env')).readAsString(),
        'TOKEN=1\n',
      );
      expect(
        await File(
          p.join(workspaceDir.path, '.copied-config', 'tool.json'),
        ).readAsString(),
        '{}',
      );
      expect(processRunner.calls.map((call) => call.arguments.last), <String>[
        'pnpm install',
        'make bootstrap',
      ]);
      expect(
        processRunner.calls.map((call) => call.workingDirectory).toSet(),
        <String>{workspaceDir.path},
      );
    });

    test('reports unsafe copy paths without running commands', () async {
      final service = WorktreeSetupService(processRunner: processRunner);

      final report = await service.run(
        project: project,
        workspace: workspace,
        config: const ProjectConfig(
          worktree: WorktreeSetupConfig(
            copy: <WorktreeCopyRule>[WorktreeCopyRule(from: '../secret')],
            setup: <String>['echo should-not-run'],
          ),
        ),
      );

      expect(report.hasFailures, isTrue);
      expect(report.steps.single.kind, WorktreeSetupStepKind.copy);
      expect(processRunner.calls, isEmpty);
    });

    test('rejects destination symlink ancestors', () async {
      await File(p.join(repoDir.path, '.env')).writeAsString('TOKEN=1\n');
      final outsideDir = Directory(p.join(tempDir.path, 'outside'))
        ..createSync();
      await Link(p.join(workspaceDir.path, 'linked')).create(outsideDir.path);
      final service = WorktreeSetupService(processRunner: processRunner);

      final report = await service.run(
        project: project,
        workspace: workspace,
        config: const ProjectConfig(
          worktree: WorktreeSetupConfig(
            copy: <WorktreeCopyRule>[
              WorktreeCopyRule(from: '.env', to: 'linked/.env'),
            ],
          ),
        ),
      );

      expect(report.hasFailures, isTrue);
      expect(report.steps.single.message, contains('symlink'));
      expect(File(p.join(outsideDir.path, '.env')).existsSync(), isFalse);
    }, skip: Platform.isWindows ? 'Windows symlink privileges vary.' : false);

    test('stops command execution after the first failure', () async {
      processRunner.exitCodeByCommand['make fail'] = 2;
      final service = WorktreeSetupService(
        processRunner: processRunner,
        operatingSystem: WorktreeSetupOperatingSystem.posix,
      );

      final report = await service.run(
        project: project,
        workspace: workspace,
        config: const ProjectConfig(
          worktree: WorktreeSetupConfig(
            setup: <String>['make fail', 'make after'],
          ),
        ),
      );

      expect(report.hasFailures, isTrue);
      expect(report.steps.single.exitCode, 2);
      expect(processRunner.calls.map((call) => call.arguments.last), <String>[
        'make fail',
      ]);
    });

    test('passes hydrated user environment to setup commands', () async {
      final environment = <String, String>{'PATH': '/custom/bin'};
      final service = WorktreeSetupService(
        processRunner: processRunner,
        commandEnvironmentResolver: _FakeCommandEnvironmentResolver(
          environment,
        ),
        operatingSystem: WorktreeSetupOperatingSystem.posix,
      );

      final report = await service.run(
        project: project,
        workspace: workspace,
        config: const ProjectConfig(
          worktree: WorktreeSetupConfig(setup: <String>['pnpm install']),
        ),
      );

      expect(report.hasFailures, isFalse);
      expect(processRunner.calls.single.environment, environment);
    });

    test('closes setup command stdin immediately', () async {
      final service = WorktreeSetupService(
        processRunner: processRunner,
        operatingSystem: WorktreeSetupOperatingSystem.posix,
      );

      final report = await service.run(
        project: project,
        workspace: workspace,
        config: const ProjectConfig(
          worktree: WorktreeSetupConfig(setup: <String>['cat']),
        ),
      );

      expect(report.hasFailures, isFalse);
      expect(processRunner.stdinClosedByCommand, contains('cat'));
    });

    test('keeps bounded output tails for verbose commands', () async {
      final stdout = 'stdout-head${List.filled(5000, 'o').join()}stdout-tail';
      final stderr = 'stderr-head${List.filled(5000, 'e').join()}stderr-tail';
      processRunner.exitCodeByCommand['make loud'] = 1;
      processRunner.stdoutByCommand['make loud'] = stdout;
      processRunner.stderrByCommand['make loud'] = stderr;
      final service = WorktreeSetupService(
        processRunner: processRunner,
        operatingSystem: WorktreeSetupOperatingSystem.posix,
      );

      final report = await service.run(
        project: project,
        workspace: workspace,
        config: const ProjectConfig(
          worktree: WorktreeSetupConfig(setup: <String>['make loud']),
        ),
      );

      final step = report.steps.single;
      expect(step.succeeded, isFalse);
      expect(step.stdoutTail, endsWith('stdout-tail'));
      expect(step.stdoutTail, isNot(contains('stdout-head')));
      expect(step.stdoutTail!.length, lessThanOrEqualTo(4000));
      expect(step.stderrTail, endsWith('stderr-tail'));
      expect(step.stderrTail, isNot(contains('stderr-head')));
      expect(step.stderrTail!.length, lessThanOrEqualTo(4000));
    });

    test('builds platform shell invocations', () {
      final posix = shellInvocationFor(
        command: 'echo hi',
        operatingSystem: WorktreeSetupOperatingSystem.posix,
      );
      expect(posix.executable, '/bin/sh');
      expect(posix.arguments, <String>['-c', 'echo hi']);

      final windows = shellInvocationFor(
        command: 'echo hi',
        operatingSystem: WorktreeSetupOperatingSystem.windows,
      );
      expect(windows.executable, 'cmd.exe');
      expect(windows.arguments, <String>['/d', '/s', '/c', 'echo hi']);
    });
  });
}

class _FakeProcessRunner implements ProcessRunner {
  final List<_ProcessCall> calls = <_ProcessCall>[];
  final Map<String, int> exitCodeByCommand = <String, int>{};
  final Map<String, String> stdoutByCommand = <String, String>{};
  final Map<String, String> stderrByCommand = <String, String>{};
  final Set<String> stdinClosedByCommand = <String>{};

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
        arguments: arguments,
        workingDirectory: workingDirectory,
        environment: environment,
      ),
    );
    final command = arguments.last;
    final exitCode = exitCodeByCommand[command] ?? 0;
    return ProcessRunOutput(
      exitCode: exitCode,
      stdout: exitCode == 0 ? 'ok' : '',
      stderr: exitCode == 0 ? '' : 'failed',
    );
  }

  @override
  Future<StartedProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
  }) async {
    calls.add(
      _ProcessCall(
        executable: executable,
        arguments: arguments,
        workingDirectory: workingDirectory,
        environment: environment,
      ),
    );
    final command = arguments.last;
    final exitCode = exitCodeByCommand[command] ?? 0;
    return StartedProcess(
      stdinWrite: (_) {},
      stdinClose: () => stdinClosedByCommand.add(command),
      stdout: _streamText(
        stdoutByCommand[command] ?? (exitCode == 0 ? 'ok' : ''),
      ),
      stderr: _streamText(
        stderrByCommand[command] ?? (exitCode == 0 ? '' : 'failed'),
      ),
      pid: calls.length,
      exitCode: Future<int>.value(exitCode),
      kill: ([signal]) => true,
    );
  }
}

class _FakeCommandEnvironmentResolver implements CommandEnvironmentResolver {
  const _FakeCommandEnvironmentResolver(this._environment);

  final Map<String, String> _environment;

  @override
  Future<Map<String, String>> environment() async => _environment;

  @override
  Future<Map<String, String>> environmentVariables(List<String> names) async =>
      const <String, String>{};
}

Stream<List<int>> _streamText(String value) {
  if (value.isEmpty) {
    return const Stream<List<int>>.empty();
  }
  final split = value.length ~/ 2;
  return Stream<List<int>>.fromIterable(<List<int>>[
    utf8.encode(value.substring(0, split)),
    utf8.encode(value.substring(split)),
  ]);
}

class _ProcessCall {
  const _ProcessCall({
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
    required this.environment,
  });

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
  final Map<String, String>? environment;
}
