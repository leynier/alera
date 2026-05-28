import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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
      environment.containsKey('ALERA_OPENCODE_CONFIG_DIR') ||
      environment.containsKey('ALERA_PI_CODING_AGENT_DIR');
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

String _zshEnvFile(String managedZdotdir) {
  final quotedManagedZdotdir = _quotePosixSingle(managedZdotdir);
  return '''
# Generated by Alera. Do not edit.
_alera_spawn_orig_zdotdir="\${ALERA_ORIG_ZDOTDIR:-}"
unset ZDOTDIR
__alera_source_user_zshenv() {
  local _alera_user_zdotdir="\${_alera_spawn_orig_zdotdir:-\${HOME:-}}"
  if [[ -n "\$_alera_user_zdotdir" && -f "\$_alera_user_zdotdir/.zshenv" ]]; then
    source "\$_alera_user_zdotdir/.zshenv"
  fi
}
__alera_source_user_zshenv
unfunction __alera_source_user_zshenv
export ALERA_ORIG_ZDOTDIR="\${ZDOTDIR:-\${_alera_spawn_orig_zdotdir:-\${HOME:-}}}"
unset _alera_spawn_orig_zdotdir
while [[ "\${ALERA_ORIG_ZDOTDIR}" == */ ]]; do
  ALERA_ORIG_ZDOTDIR="\${ALERA_ORIG_ZDOTDIR%/}"
done
case "\${ALERA_ORIG_ZDOTDIR}" in
  */terminal-shell-startup/zsh|*/shell-ready/zsh) export ALERA_ORIG_ZDOTDIR="\${HOME:-}" ;;
esac
export ZDOTDIR=$quotedManagedZdotdir
if [[ -n "\${ALERA_CODEX_HOME:-}" ]]; then
  export CODEX_HOME="\${ALERA_CODEX_HOME}"
fi
if [[ -n "\${ALERA_CLAUDE_CONFIG_DIR:-}" ]]; then
  export CLAUDE_CONFIG_DIR="\${ALERA_CLAUDE_CONFIG_DIR}"
fi
if [[ -n "\${ALERA_OPENCODE_CONFIG_DIR:-}" ]]; then
  export OPENCODE_CONFIG_DIR="\${ALERA_OPENCODE_CONFIG_DIR}"
fi
if [[ -n "\${ALERA_PI_CODING_AGENT_DIR:-}" ]]; then
  export PI_CODING_AGENT_DIR="\${ALERA_PI_CODING_AGENT_DIR}"
fi
''';
}

String _zshStartupFile(String fileName, String managedZdotdir) {
  final quotedManagedZdotdir = _quotePosixSingle(managedZdotdir);
  return '''
# Generated by Alera. Do not edit.
_alera_orig_zdotdir="\${ALERA_ORIG_ZDOTDIR:-\${HOME:-}}"
case "\${_alera_orig_zdotdir%/}" in
  */terminal-shell-startup/zsh|*/shell-ready/zsh) _alera_orig_zdotdir="\${HOME:-}" ;;
esac
if [[ -n "\$_alera_orig_zdotdir" && "\$_alera_orig_zdotdir" != "\${ZDOTDIR:-}" && -r "\$_alera_orig_zdotdir/$fileName" ]]; then
  source "\$_alera_orig_zdotdir/$fileName"
fi
if [[ -n "\${ALERA_CODEX_HOME:-}" ]]; then
  export CODEX_HOME="\${ALERA_CODEX_HOME}"
fi
if [[ -n "\${ALERA_CLAUDE_CONFIG_DIR:-}" ]]; then
  export CLAUDE_CONFIG_DIR="\${ALERA_CLAUDE_CONFIG_DIR}"
fi
if [[ -n "\${ALERA_OPENCODE_CONFIG_DIR:-}" ]]; then
  export OPENCODE_CONFIG_DIR="\${ALERA_OPENCODE_CONFIG_DIR}"
fi
if [[ -n "\${ALERA_PI_CODING_AGENT_DIR:-}" ]]; then
  export PI_CODING_AGENT_DIR="\${ALERA_PI_CODING_AGENT_DIR}"
fi
export ZDOTDIR=$quotedManagedZdotdir
unset _alera_orig_zdotdir
''';
}

String? _resolveOriginalZdotdir({
  required Map<String, String> environment,
  required String? home,
}) {
  return _normalizeOriginalZdotdirCandidate(environment['ZDOTDIR']) ??
      _normalizeOriginalZdotdirCandidate(environment['ALERA_ORIG_ZDOTDIR']) ??
      _normalizeOriginalZdotdirCandidate(home);
}

String? _normalizeOriginalZdotdirCandidate(String? candidate) {
  if (candidate == null || candidate.isEmpty) {
    return null;
  }
  var normalized = candidate;
  while (normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  if (normalized.isEmpty || _isGeneratedZshStartupPath(normalized)) {
    return null;
  }
  return normalized;
}

bool _isGeneratedZshStartupPath(String path) {
  final normalized = path.replaceAll(r'\', '/');
  return normalized.endsWith('/terminal-shell-startup/zsh') ||
      normalized.endsWith('/shell-ready/zsh');
}

String _quotePosixSingle(String value) {
  return "'${value.replaceAll("'", "'\"'\"'")}'";
}

const String _bashRcFile = '''
# Generated by Alera. Do not edit.
if [ -n "\${ALERA_ORIG_BASHRC:-}" ] && [ -r "\${ALERA_ORIG_BASHRC}" ]; then
  . "\${ALERA_ORIG_BASHRC}"
elif [ -n "\${HOME:-}" ] && [ -r "\${HOME}/.bashrc" ]; then
  . "\${HOME}/.bashrc"
fi
if [ -n "\${ALERA_CODEX_HOME:-}" ]; then
  export CODEX_HOME="\${ALERA_CODEX_HOME}"
fi
if [ -n "\${ALERA_CLAUDE_CONFIG_DIR:-}" ]; then
  export CLAUDE_CONFIG_DIR="\${ALERA_CLAUDE_CONFIG_DIR}"
fi
if [ -n "\${ALERA_OPENCODE_CONFIG_DIR:-}" ]; then
  export OPENCODE_CONFIG_DIR="\${ALERA_OPENCODE_CONFIG_DIR}"
fi
if [ -n "\${ALERA_PI_CODING_AGENT_DIR:-}" ]; then
  export PI_CODING_AGENT_DIR="\${ALERA_PI_CODING_AGENT_DIR}"
fi
''';

const String _fishRestoreManagedAgentEnvironment =
    'if set -q ALERA_CODEX_HOME; set -gx CODEX_HOME \$ALERA_CODEX_HOME; end\n'
    'if set -q ALERA_CLAUDE_CONFIG_DIR; set -gx CLAUDE_CONFIG_DIR \$ALERA_CLAUDE_CONFIG_DIR; end\n'
    'if set -q ALERA_OPENCODE_CONFIG_DIR; set -gx OPENCODE_CONFIG_DIR \$ALERA_OPENCODE_CONFIG_DIR; end\n'
    'if set -q ALERA_PI_CODING_AGENT_DIR; set -gx PI_CODING_AGENT_DIR \$ALERA_PI_CODING_AGENT_DIR; end\n';

const String _cmdRestoreManagedAgentEnvironment =
    'if defined ALERA_CODEX_HOME set "CODEX_HOME=%ALERA_CODEX_HOME%"\n'
    'if defined ALERA_CLAUDE_CONFIG_DIR set "CLAUDE_CONFIG_DIR=%ALERA_CLAUDE_CONFIG_DIR%"\n'
    'if defined ALERA_OPENCODE_CONFIG_DIR set "OPENCODE_CONFIG_DIR=%ALERA_OPENCODE_CONFIG_DIR%"\n'
    'if defined ALERA_PI_CODING_AGENT_DIR set "PI_CODING_AGENT_DIR=%ALERA_PI_CODING_AGENT_DIR%"\n';

const String _shRestoreManagedAgentEnvironment =
    'if [ -n "\${ALERA_CODEX_HOME:-}" ]; then export CODEX_HOME="\$ALERA_CODEX_HOME"; fi\n'
    'if [ -n "\${ALERA_CLAUDE_CONFIG_DIR:-}" ]; then export CLAUDE_CONFIG_DIR="\$ALERA_CLAUDE_CONFIG_DIR"; fi\n'
    'if [ -n "\${ALERA_OPENCODE_CONFIG_DIR:-}" ]; then export OPENCODE_CONFIG_DIR="\$ALERA_OPENCODE_CONFIG_DIR"; fi\n'
    'if [ -n "\${ALERA_PI_CODING_AGENT_DIR:-}" ]; then export PI_CODING_AGENT_DIR="\$ALERA_PI_CODING_AGENT_DIR"; fi\n';

const String _nushellRestoreManagedAgentEnvironment =
    r'if ("ALERA_CODEX_HOME" in $env) { $env.CODEX_HOME = $env.ALERA_CODEX_HOME }'
    '\n'
    r'if ("ALERA_CLAUDE_CONFIG_DIR" in $env) { $env.CLAUDE_CONFIG_DIR = $env.ALERA_CLAUDE_CONFIG_DIR }'
    '\n'
    r'if ("ALERA_OPENCODE_CONFIG_DIR" in $env) { $env.OPENCODE_CONFIG_DIR = $env.ALERA_OPENCODE_CONFIG_DIR }'
    '\n'
    r'if ("ALERA_PI_CODING_AGENT_DIR" in $env) { $env.PI_CODING_AGENT_DIR = $env.ALERA_PI_CODING_AGENT_DIR }'
    '\n';

const String _nushellConfigFile = r'''
# Generated by Alera. Do not edit.
let __alera_user_config = ($nu.default-config-dir | path join "config.nu")
if ($__alera_user_config | path exists) {
  source $__alera_user_config
}
if ("ALERA_CODEX_HOME" in $env) {
  $env.CODEX_HOME = $env.ALERA_CODEX_HOME
}
if ("ALERA_CLAUDE_CONFIG_DIR" in $env) {
  $env.CLAUDE_CONFIG_DIR = $env.ALERA_CLAUDE_CONFIG_DIR
}
if ("ALERA_OPENCODE_CONFIG_DIR" in $env) {
  $env.OPENCODE_CONFIG_DIR = $env.ALERA_OPENCODE_CONFIG_DIR
}
if ("ALERA_PI_CODING_AGENT_DIR" in $env) {
  $env.PI_CODING_AGENT_DIR = $env.ALERA_PI_CODING_AGENT_DIR
}
let __alera_restore_managed_agent_environment = { ||
  if ("ALERA_CODEX_HOME" in $env) {
    $env.CODEX_HOME = $env.ALERA_CODEX_HOME
  }
  if ("ALERA_CLAUDE_CONFIG_DIR" in $env) {
    $env.CLAUDE_CONFIG_DIR = $env.ALERA_CLAUDE_CONFIG_DIR
  }
  if ("ALERA_OPENCODE_CONFIG_DIR" in $env) {
    $env.OPENCODE_CONFIG_DIR = $env.ALERA_OPENCODE_CONFIG_DIR
  }
  if ("ALERA_PI_CODING_AGENT_DIR" in $env) {
    $env.PI_CODING_AGENT_DIR = $env.ALERA_PI_CODING_AGENT_DIR
  }
}
if not ("config" in $env) {
  $env.config = {}
}
let __alera_hooks = if ("hooks" in $env.config) { $env.config.hooks } else { {} }
let __alera_pre_prompt = if ("pre_prompt" in $__alera_hooks) { $__alera_hooks.pre_prompt } else { [] }
$env.config = ($env.config | upsert hooks ($__alera_hooks | upsert pre_prompt ($__alera_pre_prompt | append $__alera_restore_managed_agent_environment)))
''';

const String _powerShellRestoreManagedAgentEnvironment = r'''
if ($env:ALERA_CODEX_HOME) {
  $env:CODEX_HOME = $env:ALERA_CODEX_HOME
}
if ($env:ALERA_CLAUDE_CONFIG_DIR) {
  $env:CLAUDE_CONFIG_DIR = $env:ALERA_CLAUDE_CONFIG_DIR
}
if ($env:ALERA_OPENCODE_CONFIG_DIR) {
  $env:OPENCODE_CONFIG_DIR = $env:ALERA_OPENCODE_CONFIG_DIR
}
if ($env:ALERA_PI_CODING_AGENT_DIR) {
  $env:PI_CODING_AGENT_DIR = $env:ALERA_PI_CODING_AGENT_DIR
}
''';

String _encodePowerShellCommand(String script) {
  // PowerShell expects -EncodedCommand content as UTF-16LE before base64.
  final bytes = <int>[];
  for (final codeUnit in script.codeUnits) {
    bytes
      ..add(codeUnit & 0xff)
      ..add((codeUnit >> 8) & 0xff);
  }
  return base64.encode(bytes);
}

bool _hasBashCommandArgument(List<String> arguments) {
  return arguments.any(
    (argument) => argument == '-c' || argument == '--command',
  );
}

bool _hasBashRcOverride(List<String> arguments) {
  for (var i = 0; i < arguments.length; i += 1) {
    final argument = arguments[i];
    if (argument == '--rcfile' ||
        argument == '--init-file' ||
        argument.startsWith('--rcfile=') ||
        argument.startsWith('--init-file=')) {
      return true;
    }
  }
  return false;
}

bool _hasBashNoRc(List<String> arguments) {
  return arguments.any((argument) => argument == '--norc');
}

bool _hasFishCommandArgument(List<String> arguments) {
  return arguments.any((argument) {
    final lower = argument.toLowerCase();
    return lower == '-c' ||
        lower == '--command' ||
        lower.startsWith('--command=');
  });
}

bool _hasPowerShellCommandArgument(List<String> arguments) {
  for (var i = 0; i < arguments.length; i += 1) {
    final argument = arguments[i].toLowerCase();
    if (argument == '-command' ||
        argument == '-c' ||
        argument == '-encodedcommand' ||
        argument == '-enc' ||
        argument == '-file') {
      return true;
    }
  }
  return false;
}

bool _isPosixSetupFallbackShell(String executable) {
  return const <String>{
    'ash',
    'dash',
    'ksh',
    'mksh',
    'oksh',
    'sh',
  }.contains(executable);
}

bool _requiresNushellSetupFallback(List<String> arguments) {
  for (var i = 0; i < arguments.length; i += 1) {
    final argument = arguments[i].toLowerCase();
    if (argument == '-c' ||
        argument == '--commands' ||
        argument.startsWith('--commands=') ||
        argument == '--command' ||
        argument.startsWith('--command=') ||
        argument == '-e' ||
        argument == '--execute' ||
        argument.startsWith('--execute=')) {
      return true;
    }
    if (argument == '--config' ||
        argument.startsWith('--config=') ||
        argument == '--env-config' ||
        argument.startsWith('--env-config=') ||
        argument == '-n' ||
        argument == '--no-config-file') {
      return true;
    }
    if (!argument.startsWith('-')) {
      return true;
    }
  }
  return false;
}

bool _isPowerShellNoLogo(String argument) {
  return argument.toLowerCase() == '-nologo';
}

bool _isPowerShellNoExit(String argument) {
  return argument.toLowerCase() == '-noexit';
}

String _shellExecutableName(GhosttyTerminalShellLaunch launch) {
  final executable = launch.shell.replaceAll(r'\', '/').split('/').last;
  final lower = executable.toLowerCase();
  return lower.endsWith('.exe') ? lower.substring(0, lower.length - 4) : lower;
}
