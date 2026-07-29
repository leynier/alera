import 'dart:async';
import 'dart:io';

import 'package:alera/src/features/updater/domain/package_install_method.dart';
import 'package:alera/src/features/updater/infra/package_manager_update_launcher.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const PackageManagerInstall _homebrew = PackageManagerInstall(
  method: PackageInstallMethod.homebrewCask,
  managerExecutable: '/opt/homebrew/bin/brew',
  relaunchExecutable: '/usr/bin/open',
);

const PackageManagerInstall _scoop = PackageManagerInstall(
  method: PackageInstallMethod.scoop,
  managerExecutable: r'C:\scoop\shims\scoop.cmd',
  relaunchExecutable: r'C:\scoop\apps\alera\current\Alera.exe',
);

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('alera-package-upgrade');
  });

  tearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });

  PackageManagerUpdateLauncher launcher(
    _RecordingProcessRunner runner, {
    required void Function() onExit,
    Duration handoffTimeout = const Duration(seconds: 2),
  }) {
    return PackageManagerUpdateLauncher(
      processRunner: runner,
      processId: 4242,
      exitApp: onExit,
      upgradeDirectory: () async => directory,
      handoffTimeout: handoffTimeout,
    );
  }

  group('package manager update launcher', () {
    test('starts the Homebrew helper and only then closes Alera', () async {
      final runner = _RecordingProcessRunner()..writeHandoffOnStart = true;
      var exits = 0;

      await launcher(
        runner,
        onExit: () => exits += 1,
      ).upgradeAndRestart(_homebrew);

      expect(exits, 1);
      expect(runner.starts, hasLength(1));
      final invocation = runner.starts.single;
      expect(invocation.executable, '/bin/sh');
      expect(invocation.arguments.first, endsWith('upgrade-alera.sh'));
      expect(invocation.arguments[1], '4242');
      expect(invocation.arguments.last, '/opt/homebrew/bin/brew');
      expect(
        File(p.join(directory.path, 'upgrade-alera.sh')).existsSync(),
        isTrue,
      );
    });

    // Scoop needs the relaunch path too, because the app is started again from
    // the junction rather than through a bundle identifier.
    test('passes Scoop both the shim and the app path', () async {
      final runner = _RecordingProcessRunner()..writeHandoffOnStart = true;

      await launcher(runner, onExit: () {}).upgradeAndRestart(_scoop);

      final arguments = runner.starts.single.arguments;
      expect(runner.starts.single.executable, 'powershell.exe');
      expect(arguments, contains('-NoProfile'));
      expect(arguments[arguments.indexOf('-File') + 1], endsWith('.ps1'));
      expect(arguments[arguments.length - 2], r'C:\scoop\shims\scoop.cmd');
      expect(arguments.last, r'C:\scoop\apps\alera\current\Alera.exe');
    });

    test('refuses an installation it must not upgrade itself', () async {
      final runner = _RecordingProcessRunner();

      await expectLater(
        launcher(runner, onExit: () {}).upgradeAndRestart(
          const PackageManagerInstall(method: PackageInstallMethod.chocolatey),
        ),
        throwsA(isA<StateError>()),
      );
      expect(runner.starts, isEmpty);
    });

    // Exiting before the helper is ready would leave nothing running to perform
    // the upgrade, and Alera would never come back.
    test('keeps Alera open when the helper dies before it is ready', () async {
      final runner = _RecordingProcessRunner()..helperExitCode = 1;
      File(
        p.join(directory.path, PackageManagerUpdateLauncher.logFileName),
      ).writeAsStringSync('Homebrew was not found at /opt/homebrew/bin/brew');
      var exits = 0;

      await expectLater(
        launcher(runner, onExit: () => exits += 1).upgradeAndRestart(_homebrew),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Homebrew was not found'),
          ),
        ),
      );
      expect(exits, 0);
    });

    test('keeps Alera open when the helper never reports ready', () async {
      final runner = _RecordingProcessRunner();
      var exits = 0;

      await expectLater(
        launcher(
          runner,
          onExit: () => exits += 1,
          handoffTimeout: const Duration(milliseconds: 200),
        ).upgradeAndRestart(_homebrew),
        throwsA(isA<TimeoutException>()),
      );
      expect(exits, 0);
      expect(runner.killed, isTrue);
    });

    // A marker left by an earlier attempt would make the app exit immediately,
    // before this run's helper had done anything.
    test('discards a stale handoff marker', () async {
      final runner = _RecordingProcessRunner();
      File(p.join(directory.path, 'upgrade.ready')).writeAsStringSync('ready');
      var exits = 0;

      await expectLater(
        launcher(
          runner,
          onExit: () => exits += 1,
          handoffTimeout: const Duration(milliseconds: 200),
        ).upgradeAndRestart(_homebrew),
        throwsA(isA<TimeoutException>()),
      );
      expect(exits, 0);
    });
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
  }) async {
    starts.add(_Invocation(executable, arguments));
    if (writeHandoffOnStart) {
      // The helper's own job: the launcher must not exit before it appears.
      final handoff = arguments.firstWhere(
        (argument) => argument.endsWith('upgrade.ready'),
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
