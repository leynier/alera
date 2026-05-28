import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'terminal_shell_zsh_startup.dart';
part 'terminal_shell_startup_templates.dart';
part 'terminal_shell_argument_predicates.dart';

typedef TerminalShellStartupDirectoryResolver = Future<Directory> Function();

abstract interface class TerminalShellStartupPreparer {
  FutureOr<GhosttyTerminalShellLaunch> prepare(
    GhosttyTerminalShellLaunch launch,
  );
}

final class AleraTerminalShellStartupPreparer
    implements TerminalShellStartupPreparer {
  AleraTerminalShellStartupPreparer({
    TerminalShellStartupDirectoryResolver? applicationSupportDirectory,
  }) : _applicationSupportDirectory =
           applicationSupportDirectory ?? getApplicationSupportDirectory;

  final TerminalShellStartupDirectoryResolver _applicationSupportDirectory;

  @override
  Future<GhosttyTerminalShellLaunch> prepare(
    GhosttyTerminalShellLaunch launch,
  ) async {
    final environment = launch.environment;
    if (environment == null ||
        !_hasManagedAgentRuntimeEnvironment(environment)) {
      return launch;
    }

    return switch (_shellExecutableName(launch)) {
      'zsh' => _prepareZshLaunch(launch, environment),
      'bash' => _prepareBashLaunch(launch, environment),
      'fish' => _prepareFishLaunch(launch),
      'nu' || 'nushell' => _prepareNushellLaunch(launch),
      'powershell' || 'pwsh' => _preparePowerShellLaunch(launch),
      'cmd' => _launchWithPrependedSetupCommand(
        launch,
        _cmdRestoreManagedAgentEnvironment,
      ),
      final executable when _isPosixSetupFallbackShell(executable) =>
        _launchWithPrependedSetupCommand(
          launch,
          _shRestoreManagedAgentEnvironment,
        ),
      _ => launch,
    };
  }

  Future<GhosttyTerminalShellLaunch> _prepareZshLaunch(
    GhosttyTerminalShellLaunch launch,
    Map<String, String> environment,
  ) async {
    final zdotdir = await _startupDirectory('zsh');
    final managedZdotdir = zdotdir.path;
    await Future.wait(<Future<void>>[
      _writeIfChanged(
        File(p.join(zdotdir.path, '.zshenv')),
        _zshEnvFile(managedZdotdir),
      ),
      _writeIfChanged(
        File(p.join(zdotdir.path, '.zprofile')),
        _zshStartupFile('.zprofile', managedZdotdir),
      ),
      _writeIfChanged(
        File(p.join(zdotdir.path, '.zshrc')),
        _zshStartupFile('.zshrc', managedZdotdir),
      ),
      _writeIfChanged(
        File(p.join(zdotdir.path, '.zlogin')),
        _zshStartupFile('.zlogin', managedZdotdir),
      ),
    ]);

    final home = environment['HOME'] ?? Platform.environment['HOME'];
    final originalZdotdir = _resolveOriginalZdotdir(
      environment: environment,
      home: home,
    );
    final preparedEnvironment = <String, String>{...environment}
      ..['ZDOTDIR'] = managedZdotdir;
    if (originalZdotdir != null) {
      preparedEnvironment['ALERA_ORIG_ZDOTDIR'] = originalZdotdir;
    } else {
      preparedEnvironment.remove('ALERA_ORIG_ZDOTDIR');
    }

    return GhosttyTerminalShellLaunch(
      label: launch.label,
      shell: launch.shell,
      arguments: launch.arguments,
      environment: preparedEnvironment,
      setupCommand: launch.setupCommand,
    );
  }

  Future<GhosttyTerminalShellLaunch> _prepareBashLaunch(
    GhosttyTerminalShellLaunch launch,
    Map<String, String> environment,
  ) async {
    if (_hasBashCommandArgument(launch.arguments) ||
        _hasBashRcOverride(launch.arguments) ||
        _hasBashNoRc(launch.arguments)) {
      return launch;
    }

    final bashDir = await _startupDirectory('bash');
    final rcFile = File(p.join(bashDir.path, 'rcfile'));
    await _writeIfChanged(rcFile, _bashRcFile);

    final home = environment['HOME'] ?? Platform.environment['HOME'];
    final preparedEnvironment = <String, String>{...environment};
    if (home != null && home.isNotEmpty) {
      preparedEnvironment['ALERA_ORIG_BASHRC'] = p.join(home, '.bashrc');
    }

    return GhosttyTerminalShellLaunch(
      label: launch.label,
      shell: launch.shell,
      arguments: <String>['--rcfile', rcFile.path, ...launch.arguments],
      environment: preparedEnvironment,
      setupCommand: launch.setupCommand,
    );
  }

  GhosttyTerminalShellLaunch _prepareFishLaunch(
    GhosttyTerminalShellLaunch launch,
  ) {
    if (_hasFishCommandArgument(launch.arguments)) {
      return _launchWithPrependedSetupCommand(
        launch,
        _fishRestoreManagedAgentEnvironment,
      );
    }

    return GhosttyTerminalShellLaunch(
      label: launch.label,
      shell: launch.shell,
      arguments: <String>[
        ...launch.arguments,
        '-C',
        _fishRestoreManagedAgentEnvironment.trimRight(),
      ],
      environment: launch.environment,
      setupCommand: launch.setupCommand,
    );
  }

  Future<GhosttyTerminalShellLaunch> _prepareNushellLaunch(
    GhosttyTerminalShellLaunch launch,
  ) async {
    if (_requiresNushellSetupFallback(launch.arguments)) {
      return _launchWithPrependedSetupCommand(
        launch,
        _nushellRestoreManagedAgentEnvironment,
      );
    }

    final nushellDir = await _startupDirectory('nushell');
    final configFile = File(p.join(nushellDir.path, 'config.nu'));
    await _writeIfChanged(configFile, _nushellConfigFile);

    return GhosttyTerminalShellLaunch(
      label: launch.label,
      shell: launch.shell,
      arguments: <String>['--config', configFile.path, ...launch.arguments],
      environment: launch.environment,
      setupCommand: launch.setupCommand,
    );
  }

  GhosttyTerminalShellLaunch _preparePowerShellLaunch(
    GhosttyTerminalShellLaunch launch,
  ) {
    if (_hasPowerShellCommandArgument(launch.arguments)) {
      return launch;
    }

    final filteredArguments = launch.arguments
        .where(
          (argument) =>
              !_isPowerShellNoLogo(argument) && !_isPowerShellNoExit(argument),
        )
        .toList(growable: false);
    return GhosttyTerminalShellLaunch(
      label: launch.label,
      shell: launch.shell,
      arguments: <String>[
        ...filteredArguments,
        '-NoLogo',
        '-NoExit',
        '-EncodedCommand',
        _encodePowerShellCommand(_powerShellRestoreManagedAgentEnvironment),
      ],
      environment: launch.environment,
      setupCommand: launch.setupCommand,
    );
  }

  Future<Directory> _startupDirectory(String shellName) async {
    final support = await _applicationSupportDirectory();
    final directory = Directory(
      p.join(support.path, 'terminal-shell-startup', shellName),
    );
    await directory.create(recursive: true);
    return directory;
  }
}

GhosttyTerminalShellLaunch _launchWithPrependedSetupCommand(
  GhosttyTerminalShellLaunch launch,
  String setupCommand,
) {
  final existing = launch.setupCommand;
  return GhosttyTerminalShellLaunch(
    label: launch.label,
    shell: launch.shell,
    arguments: launch.arguments,
    environment: launch.environment,
    setupCommand: existing == null || existing.isEmpty
        ? setupCommand
        : '$setupCommand$existing',
  );
}

bool _hasManagedAgentRuntimeEnvironment(Map<String, String> environment) {
  return environment.containsKey('ALERA_CODEX_HOME') ||
      environment.containsKey('ALERA_CLAUDE_CONFIG_DIR') ||
      environment.containsKey('ALERA_COPILOT_HOME') ||
      environment.containsKey('ALERA_OPENCODE_CONFIG_DIR') ||
      environment.containsKey('ALERA_PI_CODING_AGENT_DIR') ||
      environment.containsKey('ALERA_AGENT_WRAPPER_PATH');
}

Future<void> _writeIfChanged(File file, String contents) async {
  await file.parent.create(recursive: true);
  if (await file.exists()) {
    final current = await file.readAsString();
    if (current == contents) {
      return;
    }
  }
  await file.writeAsString(contents);
}
