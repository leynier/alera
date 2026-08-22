import 'dart:async';
import 'dart:io';

import 'package:alera/src/features/updater/infra/app_restart_launcher.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('alera-app-restart');
  });

  tearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });

  for (final testCase
      in <
        ({
          String platform,
          String executable,
          String scriptName,
          String scriptFragment,
        })
      >[
        (
          platform: 'linux',
          executable: '/bin/sh',
          scriptName: 'restart-alera.sh',
          scriptFragment: r'"$app_bin"',
        ),
        (
          platform: 'macos',
          executable: '/bin/sh',
          scriptName: 'restart-alera.sh',
          scriptFragment: '/usr/bin/open -b dev.leynier.alera',
        ),
        (
          platform: 'windows',
          executable: 'powershell.exe',
          scriptName: 'restart-alera.ps1',
          scriptFragment: r'Start-Process -FilePath $AleraPath',
        ),
      ]) {
    test('hands a ${testCase.platform} restart off before exiting', () async {
      final runner = _RecordingProcessRunner()..writeHandoffOnStart = true;
      var exits = 0;
      final launcher = AppRestartLauncher(
        processRunner: runner,
        platform: testCase.platform,
        resolvedExecutable: '/installed/alera',
        processId: 4242,
        exitApp: () => exits += 1,
        restartDirectory: () async => directory,
      );

      await launcher.restart();

      expect(exits, 1);
      expect(runner.starts, hasLength(1));
      final invocation = runner.starts.single;
      expect(invocation.executable, testCase.executable);
      expect(invocation.arguments, contains('4242'));
      expect(invocation.arguments, contains(testCase.platform));
      expect(invocation.arguments.last, '/installed/alera');
      final scriptPath = invocation.arguments.firstWhere(
        (argument) => argument.endsWith(testCase.scriptName),
      );
      expect(File(scriptPath).existsSync(), isTrue);
      expect(
        File(scriptPath).readAsStringSync(),
        contains(testCase.scriptFragment),
      );
    });
  }

  test('discards a stale handoff marker', () async {
    final runner = _RecordingProcessRunner();
    File(p.join(directory.path, 'restart.ready')).writeAsStringSync('ready');
    var exits = 0;
    final launcher = AppRestartLauncher(
      processRunner: runner,
      platform: 'linux',
      resolvedExecutable: '/installed/alera',
      processId: 4242,
      exitApp: () => exits += 1,
      restartDirectory: () async => directory,
      handoffTimeout: const Duration(milliseconds: 200),
    );

    await expectLater(launcher.restart(), throwsA(isA<TimeoutException>()));

    expect(exits, 0);
    expect(runner.killed, isTrue);
  });

  test('keeps Alera open when the helper exits before handoff', () async {
    final runner = _RecordingProcessRunner()..helperExitCode = 1;
    var exits = 0;
    final launcher = AppRestartLauncher(
      processRunner: runner,
      platform: 'linux',
      resolvedExecutable: '/installed/alera',
      processId: 4242,
      exitApp: () => exits += 1,
      restartDirectory: () async => directory,
    );

    await expectLater(launcher.restart(), throwsA(isA<StateError>()));

    expect(exits, 0);
  });
}

class _RecordingProcessRunner implements ProcessRunner {
  final List<_Invocation> starts = <_Invocation>[];
  bool writeHandoffOnStart = false;
  bool killed = false;
  int? helperExitCode;

  @override
  Future<ProcessRunOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    return const ProcessRunOutput(exitCode: 0, stdout: '', stderr: '');
  }

  @override
  Future<StartedProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
  }) async {
    starts.add(_Invocation(executable, arguments));
    if (writeHandoffOnStart) {
      final handoff = arguments.firstWhere(
        (argument) => argument.endsWith('restart.ready'),
      );
      await File(handoff).writeAsString('ready');
    }
    return StartedProcess(
      stdinWrite: (_) {},
      stdout: const Stream<List<int>>.empty(),
      stderr: const Stream<List<int>>.empty(),
      pid: 12,
      exitCode: helperExitCode == null
          ? Completer<int>().future
          : Future<int>.value(helperExitCode),
      kill: ([dynamic signal]) {
        killed = true;
        return true;
      },
    );
  }
}

class _Invocation {
  const _Invocation(this.executable, this.arguments);

  final String executable;
  final List<String> arguments;
}
