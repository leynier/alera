import 'package:alera/src/features/updater/domain/package_install_method.dart';

/// The detached helper that upgrades Alera through its package manager.
///
/// The upgrade cannot run while Alera is open: on Windows the install directory
/// is held by the running executable and by the terminal-host sidecar, and the
/// sidecar cannot drive it either because it is one of the files being
/// replaced. So the helper is the *system* shell, which lives outside the
/// install directory, waits for Alera's pid to disappear, runs the manager's
/// own upgrade, and starts Alera again.
class const PackageManagerUpgradeScript({
  required final String fileName,
  required final String contents,
  required final String executable,
  required this.arguments,
}) {
  /// Arguments up to, but not including, the runtime paths the launcher fills
  /// in: the script path, the parent pid, the handoff file, and the log file.
  final List<String> arguments;
}

/// Builds the helper for [install], or null when Alera must not run the upgrade
/// itself.
///
/// Chocolatey returns null by design: `choco upgrade` needs elevation, and a
/// UAC prompt raised after Alera has closed gives the user nothing to connect
/// it to. Those installations keep the copy-the-command path instead.
PackageManagerUpgradeScript? packageManagerUpgradeScript(
  PackageManagerInstall install,
) {
  if (!install.canRunUpgrade) {
    return null;
  }
  return switch (install.method) {
    PackageInstallMethod.homebrewCask => PackageManagerUpgradeScript(
      fileName: 'upgrade-alera.sh',
      contents: homebrewUpgradeScript,
      executable: '/bin/sh',
      arguments: <String>[],
    ),
    PackageInstallMethod.scoop => PackageManagerUpgradeScript(
      fileName: 'upgrade-alera.ps1',
      contents: scoopUpgradeScript,
      executable: 'powershell.exe',
      arguments: const <String>[
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
      ],
    ),
    // Chocolatey and the Linux packages both need elevation, so neither can be
    // handed to a detached shell: the prompt would appear with no window left
    // to explain it. Linux answers it in Alera's command terminal instead.
    PackageInstallMethod.chocolatey ||
    PackageInstallMethod.linuxSystemPackage ||
    PackageInstallMethod.unmanaged => null,
  };
}

/// `$1` script-owned pid, `$2` handoff file, `$3` log file, `$4` brew path.
///
/// `brew` is addressed by absolute path rather than through `PATH`: a macOS GUI
/// app inherits a minimal `launchd` environment that never sourced the shell
/// profile where Homebrew's prefix is added, so a bare `brew` would not resolve.
///
/// The relaunch goes through the bundle identifier because the Caskroom path
/// carries the version and stops existing the moment the upgrade lands.
const String homebrewUpgradeScript = r'''#!/bin/sh
set -u

parent_pid="$1"
handoff_file="$2"
log_file="$3"
brew_bin="$4"

if [ ! -x "$brew_bin" ]; then
  printf 'Homebrew was not found at %s\n' "$brew_bin" >"$log_file"
  exit 1
fi
printf 'ready\n' >"$handoff_file"

while kill -0 "$parent_pid" 2>/dev/null; do
  sleep 1
done

"$brew_bin" upgrade --cask alera >>"$log_file" 2>&1
status=$?
if [ "$status" -ne 0 ]; then
  printf 'brew upgrade --cask alera exited with %s\n' "$status" >>"$log_file"
fi

/usr/bin/open -b dev.leynier.alera >>"$log_file" 2>&1 ||
  /usr/bin/open -a Alera >>"$log_file" 2>&1
exit "$status"
''';

/// `-ParentPid`, `-HandoffFile`, `-LogFile`, `-ScoopExecutable`, `-AleraPath`.
///
/// Scoop is user scoped, so this never needs elevation. The relaunch uses the
/// `current` junction, which Scoop repoints on every upgrade.
const String scoopUpgradeScript = r'''param(
  [int]$ParentPid,
  [string]$HandoffFile,
  [string]$LogFile,
  [string]$ScoopExecutable,
  [string]$AleraPath
)

if (-not (Test-Path -LiteralPath $ScoopExecutable -PathType Leaf)) {
  Set-Content -LiteralPath $LogFile -Value "Scoop was not found at $ScoopExecutable"
  exit 1
}
Set-Content -LiteralPath $HandoffFile -Value 'ready'

while (Get-Process -Id $ParentPid -ErrorAction SilentlyContinue) {
  Start-Sleep -Milliseconds 250
}

& $ScoopExecutable update alera *>&1 | Out-File -LiteralPath $LogFile -Append
$status = $LASTEXITCODE
if ($status -ne 0) {
  Add-Content -LiteralPath $LogFile -Value "scoop update alera exited with $status"
}

if (Test-Path -LiteralPath $AleraPath -PathType Leaf) {
  Start-Process -FilePath $AleraPath
} else {
  Add-Content -LiteralPath $LogFile -Value "Alera was not found at $AleraPath"
}
exit $status
''';
