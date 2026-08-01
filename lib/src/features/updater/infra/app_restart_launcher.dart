import 'dart:async';
import 'dart:io';

import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

typedef AppRestartDirectory = Future<Directory> Function();
typedef AleraAppExit = FutureOr<void> Function();

abstract interface class AleraAppRestarter {
  Future<void> restart();
}

/// Relaunches Alera after the current process has fully stopped.
///
/// A system-shell helper owns the handoff so Windows can release the running
/// executable before it is opened again and every platform avoids briefly
/// running two app instances against the same state.
class AppRestartLauncher implements AleraAppRestarter {
  AppRestartLauncher({
    required this.processRunner,
    String? platform,
    String? resolvedExecutable,
    int? processId,
    AleraAppExit? exitApp,
    AppRestartDirectory? restartDirectory,
    this.handoffTimeout = const Duration(seconds: 30),
  }) : _platform = platform ?? Platform.operatingSystem,
       _resolvedExecutable = resolvedExecutable ?? Platform.resolvedExecutable,
       _processId = processId ?? pid,
       _exitApp = exitApp ?? _exitCurrentApp,
       _restartDirectory = restartDirectory ?? _defaultRestartDirectory;

  final ProcessRunner processRunner;
  final String _platform;
  final String _resolvedExecutable;
  final int _processId;
  final AleraAppExit _exitApp;
  final AppRestartDirectory _restartDirectory;
  final Duration handoffTimeout;

  @override
  Future<void> restart() async {
    final script = _restartScriptFor(_platform);
    final directory = await _restartDirectory();
    await directory.create(recursive: true);
    final scriptFile = File(p.join(directory.path, script.fileName));
    await scriptFile.writeAsString(script.contents);
    final handoffFile = File(p.join(directory.path, 'restart.ready'));
    if (await handoffFile.exists()) {
      await handoffFile.delete();
    }
    final logPath = p.join(directory.path, 'app-restart.log');
    final child = await processRunner.start(script.executable, <String>[
      ...script.arguments,
      scriptFile.path,
      '$_processId',
      handoffFile.path,
      logPath,
      _platform,
      _resolvedExecutable,
    ], workingDirectory: directory.path);

    unawaited(child.stdout.drain<void>());
    unawaited(child.stderr.drain<void>());
    var helperExited = false;
    unawaited(
      child.exitCode.then(
        (_) => helperExited = true,
        onError: (Object _, StackTrace _) => helperExited = true,
      ),
    );

    final deadline = DateTime.now().add(handoffTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await handoffFile.exists()) {
        await _exitApp();
        return;
      }
      if (helperExited) {
        throw StateError('The app restart helper exited before it was ready.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    child.kill();
    throw TimeoutException(
      'The app restart helper did not start in time.',
      handoffTimeout,
    );
  }
}

class _AppRestartScript {
  const _AppRestartScript({
    required this.fileName,
    required this.contents,
    required this.executable,
    required this.arguments,
  });

  final String fileName;
  final String contents;
  final String executable;
  final List<String> arguments;
}

_AppRestartScript _restartScriptFor(String platform) {
  return switch (platform) {
    'linux' || 'macos' => const _AppRestartScript(
      fileName: 'restart-alera.sh',
      contents: _unixRestartScript,
      executable: '/bin/sh',
      arguments: <String>[],
    ),
    'windows' => const _AppRestartScript(
      fileName: 'restart-alera.ps1',
      contents: _windowsRestartScript,
      executable: 'powershell.exe',
      arguments: <String>[
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
      ],
    ),
    _ => throw UnsupportedError('App restart is not supported on $platform.'),
  };
}

const String _unixRestartScript = r'''#!/bin/sh
set -u

parent_pid="$1"
handoff_file="$2"
log_file="$3"
platform="$4"
app_bin="$5"

printf 'ready\n' >"$handoff_file"
while kill -0 "$parent_pid" 2>/dev/null; do
  sleep 1
done

if [ "$platform" = "macos" ]; then
  /usr/bin/open -b dev.leynier.alera >>"$log_file" 2>&1 ||
    /usr/bin/open -a Alera >>"$log_file" 2>&1
elif [ -x "$app_bin" ]; then
  "$app_bin" >>"$log_file" 2>&1 &
else
  printf 'Alera was not found at %s\n' "$app_bin" >"$log_file"
fi
''';

const String _windowsRestartScript = r'''param(
  [int]$ParentPid,
  [string]$HandoffFile,
  [string]$LogFile,
  [string]$Platform,
  [string]$AleraPath
)

Set-Content -LiteralPath $HandoffFile -Value 'ready'
while (Get-Process -Id $ParentPid -ErrorAction SilentlyContinue) {
  Start-Sleep -Milliseconds 250
}

if (Test-Path -LiteralPath $AleraPath -PathType Leaf) {
  Start-Process -FilePath $AleraPath
} else {
  Set-Content -LiteralPath $LogFile -Value "Alera was not found at $AleraPath"
}
''';

Future<Directory> _defaultRestartDirectory() async {
  final support = await getApplicationSupportDirectory();
  return Directory(p.join(support.path, 'app-restart'));
}

Never _exitCurrentApp() => exit(0);
