import 'dart:async';
import 'dart:io';

import 'package:alera/src/features/updater/domain/alera_update.dart';
import 'package:alera/src/features/updater/infra/desktop_update_handoff.dart';
import 'package:alera/src/features/updater/infra/desktop_update_stager.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('desktopUpdateInstallLayout', () {
    test('resolves Linux and Windows bundle roots', () {
      expect(
        desktopUpdateInstallLayout(
          platform: 'linux',
          resolvedExecutable: '/opt/alera/alera',
        ).installRoot,
        '/opt/alera',
      );
      final windows = desktopUpdateInstallLayout(
        platform: 'windows',
        resolvedExecutable: r'C:\Program Files\Alera\Alera.exe',
      );
      expect(windows.installRoot, r'C:\Program Files\Alera');
      expect(windows.relativeExecutable, 'Alera.exe');
    });

    test('resolves the complete macOS app bundle', () {
      final layout = desktopUpdateInstallLayout(
        platform: 'macos',
        resolvedExecutable: '/Applications/Alera.app/Contents/MacOS/Alera',
      );

      expect(layout.installRoot, '/Applications/Alera.app');
      expect(layout.relativeExecutable, 'Contents/MacOS/Alera');
    });

    test('rejects macOS executables outside an app bundle', () {
      expect(
        () => desktopUpdateInstallLayout(
          platform: 'macos',
          resolvedExecutable: '/tmp/Alera',
        ),
        throwsStateError,
      );
    });
  });

  group('DesktopUpdateHandoff', () {
    for (final installerKind in <String>['deb', 'rpm']) {
      test(
        'rejects Linux $installerKind packages without changing the install',
        () async {
          final runner = _RecordingProcessRunner();
          var exitCalls = 0;
          final staged = await _packageStage(installerKind);
          addTearDown(staged.delete);
          final handoff = DesktopUpdateHandoff(
            processRunner: runner,
            platform: 'linux',
            resolvedExecutable: '/opt/alera/alera',
            exitApp: () => exitCalls += 1,
          );

          await expectLater(
            handoff.applyAndRestart(staged),
            throwsA(
              isA<StateError>().having(
                (error) => error.message,
                'message',
                contains('apt, dnf'),
              ),
            ),
          );

          expect(runner.runs, isEmpty);
          expect(runner.starts, isEmpty);
          expect(exitCalls, 0);
          expect(await staged.directory.exists(), isTrue);
        },
      );
    }

    for (final fixture
        in <
          ({
            String platform,
            String resolvedExecutable,
            String command,
            String scriptName,
          })
        >[
          (
            platform: 'macos',
            resolvedExecutable: '/Applications/Alera.app/Contents/MacOS/Alera',
            command: '/bin/sh',
            scriptName: 'apply-update.sh',
          ),
          (
            platform: 'windows',
            resolvedExecutable: r'C:\Program Files\Alera\Alera.exe',
            command: 'powershell.exe',
            scriptName: 'apply-update.ps1',
          ),
        ]) {
      test(
        'prepares ${fixture.platform} replacement helper before exit',
        () async {
          final runner = _RecordingProcessRunner()
            ..createHandoffMarkerOnStart = true;
          var exitCalls = 0;
          final staged = await _tarballStage(fixture.platform);
          addTearDown(staged.delete);
          final handoff = DesktopUpdateHandoff(
            processRunner: runner,
            platform: fixture.platform,
            resolvedExecutable: fixture.resolvedExecutable,
            processId: 4321,
            exitApp: () => exitCalls += 1,
            installRootExists: (_) async => true,
            handoffTimeout: const Duration(seconds: 1),
          );

          await handoff.applyAndRestart(staged);

          expect(runner.starts.single.executable, fixture.command);
          expect(runner.starts.single.arguments, contains('4321'));
          expect(exitCalls, 1);
          final script = File(
            p.join(staged.directory.path, fixture.scriptName),
          );
          expect(await script.exists(), isTrue);
          final source = await script.readAsString();
          expect(source.toLowerCase(), contains('backup'));
          expect(source.toLowerCase(), contains('handoff'));
        },
      );
    }

    test('rejects Linux tarballs without replacing the installation', () async {
      final runner = _RecordingProcessRunner();
      var exitCalls = 0;
      final staged = await _tarballStage('linux');
      addTearDown(staged.delete);
      final handoff = DesktopUpdateHandoff(
        processRunner: runner,
        platform: 'linux',
        resolvedExecutable: '/opt/alera/alera',
        exitApp: () => exitCalls += 1,
        installRootExists: (_) async => true,
      );

      await expectLater(
        handoff.applyAndRestart(staged),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('apt, dnf'),
          ),
        ),
      );

      expect(runner.runs, isEmpty);
      expect(runner.starts, isEmpty);
      expect(exitCalls, 0);
    });

    test('does not exit when the replacement helper rejects handoff', () async {
      final runner = _RecordingProcessRunner()..helperExitCode = 3;
      var exitCalls = 0;
      final staged = await _tarballStage('macos');
      addTearDown(staged.delete);
      final handoff = DesktopUpdateHandoff(
        processRunner: runner,
        platform: 'macos',
        resolvedExecutable: '/Applications/Alera.app/Contents/MacOS/Alera',
        exitApp: () => exitCalls += 1,
        installRootExists: (_) async => true,
        handoffTimeout: const Duration(seconds: 1),
      );

      await expectLater(
        handoff.applyAndRestart(staged),
        throwsA(isA<ProcessException>()),
      );

      expect(exitCalls, 0);
    });
  });
}

Future<StagedDesktopUpdate> _packageStage(String installerKind) async {
  final directory = await Directory.systemTemp.createTemp('handoff-test-');
  final artifact = File(p.join(directory.path, 'alera.$installerKind'));
  await artifact.writeAsString('package');
  return StagedDesktopUpdate(
    update: _update('linux', installerKind),
    directory: directory,
    artifactPath: artifact.path,
    payloadPath: null,
  );
}

Future<StagedDesktopUpdate> _tarballStage(String platform) async {
  final directory = await Directory.systemTemp.createTemp('handoff-test-');
  final payload = Directory(p.join(directory.path, 'payload'));
  await payload.create();
  final artifact = File(p.join(directory.path, 'alera.tar.gz'));
  await artifact.writeAsString('archive');
  return StagedDesktopUpdate(
    update: _update(platform, 'tar.gz'),
    directory: directory,
    artifactPath: artifact.path,
    payloadPath: payload.path,
  );
}

AleraUpdateInfo _update(String platform, String installerKind) {
  return AleraUpdateInfo(
    version: '1.2.3',
    shortVersion: 2,
    date: '2026-07-27',
    mandatory: false,
    url: Uri.parse('https://example.com/alera.$installerKind'),
    platform: platform,
    changes: const <String>['Update Alera'],
    installerKind: installerKind,
    sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    size: 7,
  );
}

class _RecordingProcessRunner implements ProcessRunner {
  final List<_Invocation> runs = <_Invocation>[];
  final List<_Invocation> starts = <_Invocation>[];
  bool createHandoffMarkerOnStart = false;
  int? helperExitCode;

  @override
  Future<ProcessRunOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    runs.add(_Invocation(executable, arguments));
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
    if (createHandoffMarkerOnStart) {
      final handoffPath = arguments[arguments.length - 2];
      await File(handoffPath).writeAsString('ready');
    }
    final exitCode = helperExitCode == null
        ? Completer<int>().future
        : Future<int>.value(helperExitCode);
    return StartedProcess(
      stdinWrite: (_) {},
      stdout: const Stream<List<int>>.empty(),
      stderr: const Stream<List<int>>.empty(),
      pid: 12,
      exitCode: exitCode,
      kill: ([dynamic signal]) => true,
    );
  }
}

class _Invocation {
  const _Invocation(this.executable, this.arguments);

  final String executable;
  final List<String> arguments;
}
