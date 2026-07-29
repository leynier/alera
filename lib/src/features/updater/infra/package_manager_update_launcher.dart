import 'dart:async';
import 'dart:io';

import 'package:alera/src/features/updater/domain/package_install_method.dart';
import 'package:alera/src/features/updater/domain/package_manager_upgrade_script.dart';
import 'package:alera/src/features/updater/infra/desktop_update_handoff.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

typedef PackageManagerUpgradeDirectory = Future<Directory> Function();

/// Runs the package manager's own upgrade and brings Alera back.
///
/// The shape mirrors [DesktopUpdateHandoff]: start the helper, wait until it
/// writes its handoff file, and only then close the app. Exiting before the
/// helper is ready would leave nothing running to perform the upgrade, and the
/// user would be left staring at a closed app that never came back.
class PackageManagerUpdateLauncher {
  PackageManagerUpdateLauncher({
    required this.processRunner,
    int? processId,
    AleraAppExit? exitApp,
    PackageManagerUpgradeDirectory? upgradeDirectory,
    this.handoffTimeout = const Duration(seconds: 30),
  }) : _processId = processId ?? pid,
       _exitApp = exitApp ?? _exitCurrentApp,
       _upgradeDirectory = upgradeDirectory ?? _defaultUpgradeDirectory;

  final ProcessRunner processRunner;
  final int _processId;
  final AleraAppExit _exitApp;
  final PackageManagerUpgradeDirectory _upgradeDirectory;
  final Duration handoffTimeout;

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
      await Future<void>.delayed(const Duration(milliseconds: 50));
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
