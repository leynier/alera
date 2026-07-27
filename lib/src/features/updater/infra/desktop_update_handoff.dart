import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/updater/infra/desktop_update_stager.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:path/path.dart' as p;

typedef AleraAppExit = FutureOr<void> Function();
typedef DesktopUpdateInstallRootExists = Future<bool> Function(String path);

abstract interface class AleraDesktopUpdateHandoff {
  Future<void> applyAndRestart(StagedDesktopUpdate stagedUpdate);
}

class DesktopUpdateHandoff implements AleraDesktopUpdateHandoff {
  DesktopUpdateHandoff({
    required this.processRunner,
    required this.platform,
    String? resolvedExecutable,
    int? processId,
    AleraAppExit? exitApp,
    DesktopUpdateInstallRootExists? installRootExists,
    this.handoffTimeout = const Duration(minutes: 2),
  }) : _resolvedExecutable = resolvedExecutable ?? Platform.resolvedExecutable,
       _processId = processId ?? pid,
       _exitApp = exitApp ?? _exitCurrentApp,
       _installRootExists = installRootExists ?? _defaultInstallRootExists;

  final ProcessRunner processRunner;
  final String platform;
  final String _resolvedExecutable;
  final int _processId;
  final AleraAppExit _exitApp;
  final DesktopUpdateInstallRootExists _installRootExists;
  final Duration handoffTimeout;

  @override
  Future<void> applyAndRestart(StagedDesktopUpdate stagedUpdate) async {
    if (platform == 'linux' &&
        (stagedUpdate.update.installerKind == 'deb' ||
            stagedUpdate.update.installerKind == 'rpm')) {
      await _installLinuxPackage(stagedUpdate);
      return;
    }
    await _launchReplacementHelper(stagedUpdate);
  }

  Future<void> _installLinuxPackage(StagedDesktopUpdate stagedUpdate) async {
    final arguments = switch (stagedUpdate.update.installerKind) {
      'deb' => <String>['dpkg', '--install', stagedUpdate.artifactPath],
      'rpm' => <String>[
        'rpm',
        '--upgrade',
        '--replacepkgs',
        stagedUpdate.artifactPath,
      ],
      _ => throw StateError('Unsupported Linux package type.'),
    };
    final result = await processRunner.run('pkexec', arguments);
    if (result.exitCode != 0) {
      final details = result.stderr.trim();
      throw ProcessException(
        'pkexec',
        arguments,
        details.isEmpty
            ? 'The package installer exited with code ${result.exitCode}.'
            : details,
        result.exitCode,
      );
    }

    await processRunner.start(
      _resolvedExecutable,
      const <String>[],
      workingDirectory: p.dirname(_resolvedExecutable),
    );
    await stagedUpdate.delete();
    await _exitApp();
  }

  Future<void> _launchReplacementHelper(
    StagedDesktopUpdate stagedUpdate,
  ) async {
    final payloadPath = stagedUpdate.payloadPath;
    if (payloadPath == null) {
      throw StateError('The update payload has not been prepared.');
    }
    final layout = desktopUpdateInstallLayout(
      platform: platform,
      resolvedExecutable: _resolvedExecutable,
    );
    if (!await _installRootExists(layout.installRoot)) {
      throw StateError('The current Alera installation cannot be located.');
    }

    final token = p.basename(stagedUpdate.directory.path);
    final pathContext = _pathContext(platform);
    final installParent = pathContext.dirname(layout.installRoot);
    final installName = pathContext.basename(layout.installRoot);
    final readyPath = pathContext.join(
      installParent,
      '.$installName.alera-update-ready-$token',
    );
    final backupPath = pathContext.join(
      installParent,
      '.$installName.alera-update-backup-$token',
    );
    final handoffPath = p.join(stagedUpdate.directory.path, 'handoff.ready');
    final failurePath = p.join(stagedUpdate.directory.path, 'handoff.error');
    final command = await _writeHelper(
      stagedUpdate.directory,
      layout: layout,
      payloadPath: payloadPath,
      readyPath: readyPath,
      backupPath: backupPath,
      handoffPath: handoffPath,
      failurePath: failurePath,
    );
    final child = await processRunner.start(
      command.executable,
      command.arguments,
      workingDirectory: stagedUpdate.directory.path,
    );

    final exitCode = Completer<int>();
    unawaited(
      child.exitCode.then(
        (value) {
          if (!exitCode.isCompleted) {
            exitCode.complete(value);
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!exitCode.isCompleted) {
            exitCode.completeError(error, stackTrace);
          }
        },
      ),
    );
    final deadline = DateTime.now().add(handoffTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await File(handoffPath).exists()) {
        await _exitApp();
        return;
      }
      if (exitCode.isCompleted) {
        final code = await exitCode.future;
        final details = await _readFailure(failurePath);
        throw ProcessException(
          command.executable,
          command.arguments,
          details ?? 'The update helper exited before accepting the handoff.',
          code,
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    child.kill();
    throw TimeoutException(
      'The update helper did not accept the handoff.',
      handoffTimeout,
    );
  }

  Future<DesktopUpdateHandoffCommand> _writeHelper(
    Directory directory, {
    required DesktopUpdateInstallLayout layout,
    required String payloadPath,
    required String readyPath,
    required String backupPath,
    required String handoffPath,
    required String failurePath,
  }) async {
    if (platform == 'windows') {
      final script = File(p.join(directory.path, 'apply-update.ps1'));
      await script.writeAsString(_windowsUpdateScript);
      return DesktopUpdateHandoffCommand(
        executable: 'powershell.exe',
        arguments: <String>[
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          script.path,
          '$_processId',
          layout.installRoot,
          payloadPath,
          readyPath,
          backupPath,
          layout.relativeExecutable,
          directory.path,
          handoffPath,
          failurePath,
        ],
      );
    }

    final script = File(p.join(directory.path, 'apply-update.sh'));
    await script.writeAsString(_unixUpdateScript);
    return DesktopUpdateHandoffCommand(
      executable: '/bin/sh',
      arguments: <String>[
        script.path,
        '$_processId',
        layout.installRoot,
        payloadPath,
        readyPath,
        backupPath,
        layout.relativeExecutable,
        directory.path,
        handoffPath,
        failurePath,
      ],
    );
  }
}

class DesktopUpdateHandoffCommand {
  const DesktopUpdateHandoffCommand({
    required this.executable,
    required this.arguments,
  });

  final String executable;
  final List<String> arguments;
}

class DesktopUpdateInstallLayout {
  const DesktopUpdateInstallLayout({
    required this.installRoot,
    required this.relativeExecutable,
  });

  final String installRoot;
  final String relativeExecutable;
}

DesktopUpdateInstallLayout desktopUpdateInstallLayout({
  required String platform,
  required String resolvedExecutable,
}) {
  final context = _pathContext(platform);
  final executable = context.normalize(resolvedExecutable);
  if (platform != 'macos') {
    return DesktopUpdateInstallLayout(
      installRoot: context.dirname(executable),
      relativeExecutable: context.basename(executable),
    );
  }

  var current = context.dirname(executable);
  while (current != context.dirname(current)) {
    if (context.extension(current).toLowerCase() == '.app') {
      return DesktopUpdateInstallLayout(
        installRoot: current,
        relativeExecutable: context.relative(executable, from: current),
      );
    }
    current = context.dirname(current);
  }
  throw StateError('The current macOS Alera app bundle cannot be located.');
}

p.Context _pathContext(String platform) {
  return p.Context(
    style: platform == 'windows' ? p.Style.windows : p.Style.posix,
  );
}

Future<String?> _readFailure(String path) async {
  final file = File(path);
  if (!await file.exists()) {
    return null;
  }
  final contents = await file.readAsString(encoding: utf8);
  final trimmed = contents.trim();
  return trimmed.isEmpty ? null : trimmed;
}

Never _exitCurrentApp() => exit(0);

Future<bool> _defaultInstallRootExists(String path) {
  return Directory(path).exists();
}

const String _unixUpdateScript = r'''#!/bin/sh
set -eu

parent_pid="$1"
install_root="$2"
payload="$3"
ready="$4"
backup="$5"
relative_executable="$6"
stage_root="$7"
handoff_file="$8"
failure_file="$9"

fail_before_handoff() {
  printf '%s\n' "$1" >"$failure_file"
  exit 1
}

[ -d "$install_root" ] || fail_before_handoff "The current Alera installation is missing."
[ -d "$payload" ] || fail_before_handoff "The staged Alera update is missing."
[ ! -e "$ready" ] || fail_before_handoff "A prepared update directory already exists."
[ ! -e "$backup" ] || fail_before_handoff "An update backup directory already exists."

if command -v ditto >/dev/null 2>&1; then
  ditto "$payload" "$ready" || fail_before_handoff "The update could not be prepared beside Alera."
else
  mkdir "$ready" || fail_before_handoff "The update directory could not be created."
  cp -a "$payload"/. "$ready"/ || fail_before_handoff "The update could not be prepared beside Alera."
fi
[ -x "$ready/$relative_executable" ] || fail_before_handoff "The prepared Alera executable is invalid."
printf 'ready\n' >"$handoff_file"

while kill -0 "$parent_pid" 2>/dev/null; do
  sleep 1
done

swapped=0
rollback() {
  message="$1"
  if [ "$swapped" -eq 1 ]; then
    rm -rf "$install_root"
    if [ -e "$backup" ]; then
      mv "$backup" "$install_root"
    fi
  fi
  if [ -x "$install_root/$relative_executable" ]; then
    (
      cd "$install_root"
      "./$relative_executable" >/dev/null 2>&1 &
    )
  fi
  printf '%s\n' "$message" >"$failure_file"
  exit 1
}

mv "$install_root" "$backup" || rollback "The existing Alera installation could not be backed up."
swapped=1
mv "$ready" "$install_root" || rollback "The prepared Alera update could not be installed."
(
  cd "$install_root"
  "./$relative_executable" >/dev/null 2>&1 &
) || rollback "The updated Alera app could not be launched."
swapped=0
rm -rf "$backup"
rm -rf "$stage_root"
exit 0
''';

const String _windowsUpdateScript = r'''param(
  [int]$ParentPid,
  [string]$InstallRoot,
  [string]$Payload,
  [string]$Ready,
  [string]$Backup,
  [string]$RelativeExecutable,
  [string]$StageRoot,
  [string]$HandoffFile,
  [string]$FailureFile
)

$ErrorActionPreference = 'Stop'

function Fail-BeforeHandoff([string]$Message) {
  Set-Content -LiteralPath $FailureFile -Value $Message
  exit 1
}

try {
  if (-not (Test-Path -LiteralPath $InstallRoot -PathType Container)) {
    Fail-BeforeHandoff 'The current Alera installation is missing.'
  }
  if (-not (Test-Path -LiteralPath $Payload -PathType Container)) {
    Fail-BeforeHandoff 'The staged Alera update is missing.'
  }
  if ((Test-Path -LiteralPath $Ready) -or (Test-Path -LiteralPath $Backup)) {
    Fail-BeforeHandoff 'An update preparation directory already exists.'
  }
  New-Item -ItemType Directory -Path $Ready | Out-Null
  Get-ChildItem -LiteralPath $Payload -Force |
    Copy-Item -Destination $Ready -Recurse -Force
  $PreparedExecutable = Join-Path $Ready $RelativeExecutable
  if (-not (Test-Path -LiteralPath $PreparedExecutable -PathType Leaf)) {
    Fail-BeforeHandoff 'The prepared Alera executable is invalid.'
  }
  Set-Content -LiteralPath $HandoffFile -Value 'ready'
} catch {
  Fail-BeforeHandoff $_.Exception.Message
}

while (Get-Process -Id $ParentPid -ErrorAction SilentlyContinue) {
  Start-Sleep -Milliseconds 250
}

$Swapped = $false
try {
  Move-Item -LiteralPath $InstallRoot -Destination $Backup
  $Swapped = $true
  Move-Item -LiteralPath $Ready -Destination $InstallRoot
  $UpdatedExecutable = Join-Path $InstallRoot $RelativeExecutable
  Start-Process -FilePath $UpdatedExecutable -WorkingDirectory $InstallRoot
  $Swapped = $false
  Remove-Item -LiteralPath $Backup -Recurse -Force
  Remove-Item -LiteralPath $StageRoot -Recurse -Force -ErrorAction SilentlyContinue
  exit 0
} catch {
  $Message = $_.Exception.Message
  if ($Swapped) {
    Remove-Item -LiteralPath $InstallRoot -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $Backup) {
      Move-Item -LiteralPath $Backup -Destination $InstallRoot
    }
  }
  $PreviousExecutable = Join-Path $InstallRoot $RelativeExecutable
  if (Test-Path -LiteralPath $PreviousExecutable -PathType Leaf) {
    Start-Process -FilePath $PreviousExecutable -WorkingDirectory $InstallRoot
  }
  Set-Content -LiteralPath $FailureFile -Value $Message
  exit 1
}
''';
