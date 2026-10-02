import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/updater/infra/updater_process_adapter.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart'
    as app_process;
import 'package:crypto/crypto.dart' as crypto;
import 'package:desktop_updater/desktop_updater.dart' as updater;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'cancels DMG ditto, reaps it, and force-detaches without masking cancel',
    () async {
      final artifactBytes = utf8.encode('test-dmg-payload');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final sibling = await Directory.systemTemp.createTemp(
        'alera-dmg-stage-sibling_',
      );
      final runner = _DmgProcessRunner();
      final token = updater.UpdateCancellationToken();
      final processAdapter = UpdaterProcessAdapter(
        processRunner: runner,
        timeout: const Duration(seconds: 1),
      );
      final cleanupAdapter = UpdaterProcessAdapter(
        processRunner: runner,
        timeout: const Duration(seconds: 1),
      );
      server.listen((request) async {
        request.response.statusCode = HttpStatus.ok;
        request.response.contentLength = artifactBytes.length;
        request.response.add(artifactBytes);
        await request.response.close();
      });

      final descriptor = updater.ReleaseDescriptor.fromJson({
        'schemaVersion': 3,
        'packageId': 'com.example.app',
        'appName': 'Example',
        'version': '2.0.0',
        'buildNumber': 2,
        'platform': 'macos',
        'channel': 'stable',
        'artifact': {
          'kind': 'dmg',
          'url': 'http://127.0.0.1:${server.port}/artifact.dmg',
          'sha256': crypto.sha256.convert(artifactBytes).toString(),
          'length': artifactBytes.length,
        },
        'install': {
          'strategy': 'wholeBundleReplace',
          'macosDmg': {
            'appBundleName': 'Example.app',
            'verifyPrimarySignature': false,
          },
        },
        'minimumUpdaterVersion': '2.0.0',
        'generatedAt': '2026-06-11T00:00:00Z',
      });
      final download = updater.DesktopUpdater().downloadZipFirstUpdate(
        appArchiveUrl: Uri.parse('http://127.0.0.1:${server.port}/index.json'),
        currentVersion: updater.DesktopVersionInfo.fromParts(
          versionName: '1.0.0',
          buildNumber: '1',
        ),
        descriptor: descriptor,
        runProcess: (executable, arguments) =>
            processAdapter.run(executable, arguments, cancellationToken: token),
        runCleanupProcess: cleanupAdapter.run,
        cancellationToken: token,
      );
      var settled = false;
      final observed = download.then<void>(
        (_) => settled = true,
        onError: (Object _, StackTrace _) {
          settled = true;
        },
      );

      try {
        if (!Platform.isMacOS) {
          markTestSkipped(
            'The public updater selects Platform.operatingSystem; DMG staging '
            'requires macOS.',
          );
          return;
        }

        await runner.dittoStarted.future.timeout(const Duration(seconds: 2));
        final ditto = runner.dittoProcess!;
        final stagingRoot = runner.stagingRoot!;
        token.cancel();

        await ditto.killed.future.timeout(const Duration(seconds: 1));
        await Future<void>.delayed(Duration.zero);
        expect(settled, isFalse);

        ditto.completeExit(143);
        await expectLater(
          download.timeout(const Duration(seconds: 2)),
          throwsA(isA<updater.UpdateCancelledException>()),
        );
        await observed;

        expect(ditto.killCalls, 1);
        expect(runner.detachCommands, <List<String>>[
          <String>['/usr/bin/hdiutil', 'detach', runner.mountPoint],
          <String>['/usr/bin/hdiutil', 'detach', '-force', runner.mountPoint],
        ]);
        expect(Directory(stagingRoot).existsSync(), isFalse);
        expect(sibling.existsSync(), isTrue);
      } finally {
        token.cancel();
        _dittoCleanup(runner.dittoProcess);
        await observed;
        await server.close(force: true);
        if (sibling.existsSync()) {
          await sibling.delete(recursive: true);
        }
        final stagingRoot = runner.stagingRoot;
        if (stagingRoot != null && Directory(stagingRoot).existsSync()) {
          await Directory(stagingRoot).delete(recursive: true);
        }
      }
    },
    skip: !Platform.isMacOS,
  );
}

void _dittoCleanup(_ControlledStartedProcess? process) {
  if (process == null) {
    return;
  }
  process.completeExit(143);
  unawaited(process.dispose());
}

class _DmgProcessRunner implements app_process.ProcessRunner {
  final Completer<void> dittoStarted = Completer<void>();
  final List<List<String>> detachCommands = <List<String>>[];
  _ControlledStartedProcess? dittoProcess;
  String? stagingRoot;
  late String mountPoint;

  @override
  Future<app_process.ProcessRunOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<app_process.StartedProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
  }) async {
    if (executable == '/usr/bin/hdiutil' && arguments.first == 'attach') {
      final mountIndex = arguments.indexOf('-mountpoint') + 1;
      mountPoint = arguments[mountIndex];
      return _immediateProcess(stdout: '/dev/disk4\tApple_HFS\t$mountPoint\n');
    }
    if (executable == '/usr/bin/ditto') {
      stagingRoot = p.dirname(arguments.last);
      final process = _ControlledStartedProcess();
      dittoProcess = process;
      if (!dittoStarted.isCompleted) {
        dittoStarted.complete();
      }
      return process.startedProcess;
    }
    if (executable == '/usr/bin/hdiutil' && arguments.first == 'detach') {
      detachCommands.add(<String>[executable, ...arguments]);
      return _immediateProcess(
        exitCode: arguments.contains('-force') ? 0 : 1,
        stderr: arguments.contains('-force') ? '' : 'busy',
      );
    }
    throw StateError('Unexpected updater command: $executable $arguments');
  }

  app_process.StartedProcess _immediateProcess({
    int exitCode = 0,
    String stdout = '',
    String stderr = '',
  }) {
    return app_process.StartedProcess(
      stdinWrite: (_) {},
      stdout: Stream<List<int>>.value(utf8.encode(stdout)),
      stderr: Stream<List<int>>.value(utf8.encode(stderr)),
      pid: 1,
      exitCode: Future<int>.value(exitCode),
      kill: ([dynamic signal]) => false,
    );
  }
}

class _ControlledStartedProcess {
  final StreamController<List<int>> _stdout = StreamController<List<int>>();
  final StreamController<List<int>> _stderr = StreamController<List<int>>();
  final Completer<int> _exitCode = Completer<int>();
  final Completer<void> killed = Completer<void>();
  int killCalls = 0;

  app_process.StartedProcess get startedProcess => app_process.StartedProcess(
    stdinWrite: (_) {},
    stdout: _stdout.stream,
    stderr: _stderr.stream,
    pid: 2,
    exitCode: _exitCode.future,
    kill: ([dynamic signal]) {
      killCalls += 1;
      if (!killed.isCompleted) {
        killed.complete();
      }
      return true;
    },
  );

  void completeExit(int code) {
    if (!_exitCode.isCompleted) {
      _exitCode.complete(code);
    }
  }

  Future<void> dispose() async {
    if (!_stdout.isClosed) {
      await _stdout.close();
    }
    if (!_stderr.isClosed) {
      await _stderr.close();
    }
  }
}
