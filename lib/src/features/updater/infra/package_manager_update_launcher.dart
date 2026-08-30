import 'dart:async';
import 'dart:io';

import 'package:alera/src/features/updater/domain/package_install_method.dart';
import 'package:alera/src/features/updater/domain/package_manager_upgrade_script.dart';
import 'package:alera/src/features/updater/infra/app_restart_launcher.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

typedef PackageManagerUpgradeDirectory = Future<Directory> Function();

/// Runs the package manager's own upgrade and brings Alera back.
///
/// Starts the helper, waits until it writes its handoff file, and only then
/// closes the app. Exiting before the helper is ready would leave nothing
/// running to perform the upgrade.
class PackageManagerUpdateLauncher({
  required final ProcessRunner processRunner,
  int? processId,
  AleraAppExit? exitApp,
  PackageManagerUpgradeDirectory? upgradeDirectory,
  final Duration handoffTimeout = const Duration(seconds: 30),
}) {
  this
    : _processId = processId ?? pid,
      _exitApp = exitApp ?? _exitCurrentApp,
      _upgradeDirectory = upgradeDirectory ?? _defaultUpgradeDirectory;

  final int _processId;
  final AleraAppExit _exitApp;
  final PackageManagerUpgradeDirectory _upgradeDirectory;

  /// The log the helper writes, so a failed upgrade is readable on next launch
  /// instead of vanishing with the process that produced it.
  static const String logFileName = 'package-upgrade.log';

  Future<void> upgradeAndRestart(PackageManagerInstall install) async {
    final script = packageManagerUpgradeScript(install);
    if (script == null) {
      throw StateError(
        'Alera cannot run the upgrade for this installation. Run the '
        'package manager command shown in Settings instead.',
      );
    }

    final directory = await _upgradeDirectory();
    await directory.create(recursive: true);
    final scriptFile = File(p.join(directory.path, script.fileName));
    await scriptFile.writeAsString(script.contents);
    final handoffFile = File(p.join(directory.path, 'upgrade.ready'));
    if (await handoffFile.exists()) {
      await handoffFile.delete();
    }
    final logPath = p.join(directory.path, logFileName);

    final arguments = <String>[
      ...script.arguments,
      scriptFile.path,
      '$_processId',
      handoffFile.path,
      logPath,
      install.managerExecutable!,
      if (install.method == PackageInstallMethod.scoop)
        install.relaunchExecutable!,
    ];

    final child = await processRunner.start(
      script.executable,
      arguments,
      workingDirectory: directory.path,
    );

    var helperExited = false;
    unawaited(
      child.exitCode.then(
        (_) => helperExited = true,
        onError: (Object error, StackTrace stackTrace) => helperExited = true,
      ),
    );

    final deadline = DateTime.now().add(handoffTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await handoffFile.exists()) {
        await _exitApp();
        return;
      }
      if (helperExited) {
        throw StateError(
          await _readLog(logPath) ??
              'The upgrade helper exited before it was ready.',
        );
      }
      await Future.pause(const Duration(milliseconds: 50));
    }
    child.kill();
    throw TimeoutException(
      'The upgrade helper did not start in time.',
      handoffTimeout,
    );
  }
}

Future<String?> _readLog(String path) async {
  final file = File(path);
  if (!await file.exists()) {
    return null;
  }
  final trimmed = (await file.readAsString()).trim();
  return trimmed.isEmpty ? null : trimmed;
}

Future<Directory> _defaultUpgradeDirectory() async {
  final support = await getApplicationSupportDirectory();
  return Directory(p.join(support.path, 'package-upgrade'));
}

Never _exitCurrentApp() => exit(0);
