part of 'terminal_runtime.dart';

/// Flags that make a shell read its login profile (`~/.zprofile`, `~/.profile`).
///
/// GUI-launched apps inherit a minimal environment on macOS, where the login
/// profile is where Homebrew and similar prefixes are added to PATH, so without
/// this the shell starts without the tools the user's rc files expect.
const Map<String, String> _loginShellArguments = <String, String>{
  'zsh': '-l',
  'bash': '-l',
  'sh': '-l',
  'dash': '-l',
  'ksh': '-l',
  'ksh93': '-l',
  'mksh': '-l',
  'tcsh': '-l',
  'csh': '-l',
  'fish': '--login',
  'nu': '--login',
  'nushell': '--login',
  'elvish': '--login',
  'xonsh': '--login',
};

const Set<String> _rcSkippingShellArguments = <String>{
  '-f',
  '--noprofile',
  '--norc',
  '--no-rcs',
  '--no-config',
};

GhosttyTerminalShellLaunch _launchAsLoginShell(
  GhosttyTerminalShellLaunch launch,
) {
  final loginArgument = _loginShellArguments[_shellExecutableName(launch)];
  if (loginArgument == null) {
    return launch;
  }
  final arguments = launch.arguments;
  if (arguments.contains(loginArgument) || arguments.contains('-li')) {
    return launch;
  }
  // Profiles that deliberately skip startup files must stay pristine.
  if (arguments.any(_rcSkippingShellArguments.contains)) {
    return launch;
  }
  return GhosttyTerminalShellLaunch(
    label: launch.label,
    shell: launch.shell,
    arguments: <String>[loginArgument, ...arguments],
    environment: launch.environment,
    setupCommand: launch.setupCommand,
  );
}

@visibleForTesting
GhosttyTerminalShellLaunch launchAsLoginShellForTesting(
  GhosttyTerminalShellLaunch launch,
) {
  return _launchAsLoginShell(launch);
}
