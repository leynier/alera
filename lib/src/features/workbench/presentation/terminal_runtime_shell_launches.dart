part of 'terminal_runtime.dart';

Map<String, String> _terminalPlatformEnvironment() {
  final environment = <String, String>{...ghosttyTerminalPlatformEnvironment()};
  environment.remove('NO_COLOR');
  return environment;
}

List<GhosttyTerminalShellLaunch> _terminalShellLaunches() {
  final platformEnvironment = _terminalPlatformEnvironment();
  final ghosttyLaunches = <GhosttyTerminalShellLaunch>[
    ...ghosttyTerminalShellLaunches(
      profile: GhosttyTerminalShellProfile.userShell,
      platformEnvironment: platformEnvironment,
    ),
    ...ghosttyTerminalShellLaunches(
      profile: GhosttyTerminalShellProfile.cleanZsh,
      platformEnvironment: platformEnvironment,
    ),
    ...ghosttyTerminalShellLaunches(
      profile: GhosttyTerminalShellProfile.auto,
      platformEnvironment: platformEnvironment,
    ),
  ];
  final launches = <GhosttyTerminalShellLaunch>[
    if (_isWindowsDesktopTerminalTarget)
      ..._windowsTerminalShellLaunches(platformEnvironment),
    ...ghosttyLaunches,
    if (!_isWindowsDesktopTerminalTarget && ghosttyLaunches.isEmpty)
      ..._posixDesktopFallbackShellLaunches(platformEnvironment),
  ];
  final seen = <String>{};
  return launches
      .where((launch) {
        final key = '${launch.shell}\u0000${launch.arguments.join('\u0000')}';
        return seen.add(key);
      })
      .toList(growable: false);
}

List<GhosttyTerminalShellLaunch> _posixDesktopFallbackShellLaunches(
  Map<String, String> platformEnvironment,
) {
  return switch (defaultTargetPlatform) {
    TargetPlatform.linux ||
    TargetPlatform.macOS => <GhosttyTerminalShellLaunch>[
      GhosttyTerminalShellLaunch(
        label: 'sh',
        shell: '/bin/sh',
        arguments: const <String>['-i'],
        environment: ghosttyTerminalShellEnvironment(
          platformEnvironment: platformEnvironment,
          overrides: const <String, String>{'TERM': 'xterm-256color'},
        ),
      ),
    ],
    _ => const <GhosttyTerminalShellLaunch>[],
  };
}

List<GhosttyTerminalShellLaunch> _windowsTerminalShellLaunches(
  Map<String, String> platformEnvironment, {
  bool Function(String path) fileExists = _fileExists,
}) {
  final shellEnvironment = ghosttyTerminalShellEnvironment(
    platformEnvironment: platformEnvironment,
    overrides: const <String, String>{'TERM': 'xterm-256color'},
  );
  final launches = <GhosttyTerminalShellLaunch>[];
  final pwsh = _resolveWindowsPowerShell7(
    platformEnvironment,
    fileExists: fileExists,
  );
  if (pwsh != null) {
    launches.add(
      GhosttyTerminalShellLaunch(
        label: 'PowerShell 7',
        shell: pwsh,
        environment: shellEnvironment,
      ),
    );
  }
  final powershell = _resolveWindowsPowerShell(platformEnvironment);
  if (powershell != null) {
    launches.add(
      GhosttyTerminalShellLaunch(
        label: 'Windows PowerShell',
        shell: powershell,
        environment: shellEnvironment,
      ),
    );
  }
  launches.add(
    GhosttyTerminalShellLaunch(
      label: 'cmd.exe',
      shell: _resolveWindowsCommandPrompt(platformEnvironment),
      environment: shellEnvironment,
    ),
  );
  return launches;
}

String? _resolveWindowsPowerShell7(
  Map<String, String> environment, {
  required bool Function(String path) fileExists,
}) {
  return _resolveFirstExistingWindowsPath(<String>[
        if (_windowsEnvironmentValue(environment, 'ProgramFiles')
            case final dir?)
          _joinWindowsPath(dir, 'PowerShell', '7', 'pwsh.exe'),
        if (_windowsEnvironmentValue(environment, 'ProgramW6432')
            case final dir?)
          _joinWindowsPath(dir, 'PowerShell', '7', 'pwsh.exe'),
      ], fileExists: fileExists) ??
      'pwsh.exe';
}

String? _resolveWindowsPowerShell(Map<String, String> environment) {
  if (_windowsSystemRoot(environment) case final root?) {
    return _joinWindowsPath(
      root,
      'System32',
      'WindowsPowerShell',
      'v1.0',
      'powershell.exe',
    );
  }
  return 'powershell.exe';
}

String _resolveWindowsCommandPrompt(Map<String, String> environment) {
  final comspec = _windowsEnvironmentValue(environment, 'ComSpec');
  if (comspec != null && comspec.isNotEmpty) {
    return comspec;
  }
  if (_windowsSystemRoot(environment) case final root?) {
    return _joinWindowsPath(root, 'System32', 'cmd.exe');
  }
  return 'cmd.exe';
}

String? _resolveFirstExistingWindowsPath(
  Iterable<String> candidates, {
  required bool Function(String path) fileExists,
}) {
  for (final candidate in _uniqueWindowsPaths(candidates)) {
    if (candidate.isNotEmpty && fileExists(candidate)) {
      return candidate;
    }
  }
  return null;
}

String? _windowsSystemRoot(Map<String, String> environment) {
  return _windowsEnvironmentValue(environment, 'SystemRoot') ??
      _windowsEnvironmentValue(environment, 'windir');
}

String? _windowsEnvironmentValue(Map<String, String> environment, String key) {
  final exact = environment[key];
  if (exact != null && exact.isNotEmpty) {
    return exact;
  }
  final lowerKey = key.toLowerCase();
  for (final entry in environment.entries) {
    if (entry.key.toLowerCase() == lowerKey && entry.value.isNotEmpty) {
      return entry.value;
    }
  }
  return null;
}

List<String> _uniqueWindowsPaths(Iterable<String> paths) {
  final seen = <String>{};
  final unique = <String>[];
  for (final path in paths) {
    final key = path.toLowerCase();
    if (seen.add(key)) {
      unique.add(path);
    }
  }
  return unique;
}

String _joinWindowsPath(
  String first,
  String second, [
  String? third,
  String? fourth,
  String? fifth,
]) {
  final parts = <String>[first, second, ?third, ?fourth, ?fifth];
  final buffer = StringBuffer();
  for (final part in parts) {
    if (part.isEmpty) {
      continue;
    }
    if (buffer.isNotEmpty && !buffer.toString().endsWith(r'\')) {
      buffer.write(r'\');
    }
    buffer.write(part.replaceAll('/', r'\').replaceAll(RegExp(r'\\+$'), ''));
  }
  return buffer.toString();
}

bool _fileExists(String path) => File(path).existsSync();

bool get _isWindowsDesktopTerminalTarget {
  return !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
}

GhosttyTerminalShellLaunch _launchWithSanitizedAgentHookEnvironment(
  GhosttyTerminalShellLaunch launch,
  Map<String, String>? agentHookEnvironment,
) {
  final environment = <String, String>{...?launch.environment};
  _restoreOrStripManagedOverlayEnvironment(
    environment,
    primary: 'OPENCODE_CONFIG_DIR',
    overlay: 'ALERA_OPENCODE_CONFIG_DIR',
    source: 'ALERA_OPENCODE_SOURCE_CONFIG_DIR',
  );
  _restoreOrStripManagedOverlayEnvironment(
    environment,
    primary: 'PI_CODING_AGENT_DIR',
    overlay: 'ALERA_PI_CODING_AGENT_DIR',
    source: 'ALERA_PI_SOURCE_AGENT_DIR',
  );
  _restoreOrStripManagedOverlayEnvironment(
    environment,
    primary: 'COPILOT_HOME',
    overlay: 'ALERA_COPILOT_HOME',
    source: 'ALERA_COPILOT_SOURCE_HOME',
  );
  _stripManagedWrapperPath(environment);
  environment.removeWhere(_isAleraAgentHookEnvironmentKey);
  if (agentHookEnvironment != null) {
    environment.addAll(agentHookEnvironment);
  }
  _applyManagedWrapperPath(environment);
  return GhosttyTerminalShellLaunch(
    label: launch.label,
    shell: launch.shell,
    arguments: launch.arguments,
    environment: environment.isEmpty ? null : environment,
    setupCommand: launch.setupCommand,
  );
}

void _restoreOrStripManagedOverlayEnvironment(
  Map<String, String> environment, {
  required String primary,
  required String overlay,
  required String source,
}) {
  final sourceValue = environment[source];
  final overlayValue = environment[overlay];
  if (sourceValue != null && sourceValue.isNotEmpty) {
    environment[primary] = sourceValue;
  } else if (overlayValue != null && environment[primary] == overlayValue) {
    environment.remove(primary);
  }
  environment.remove(overlay);
  environment.remove(source);
}

void _stripManagedWrapperPath(Map<String, String> environment) {
  final wrapperPath = environment['ALERA_AGENT_WRAPPER_PATH'];
  if (wrapperPath == null || wrapperPath.isEmpty) {
    return;
  }
  _removePathEntries(environment, _splitPathList(wrapperPath));
  environment.remove('ALERA_AGENT_WRAPPER_PATH');
}

void _applyManagedWrapperPath(Map<String, String> environment) {
  final wrapperPath = environment['ALERA_AGENT_WRAPPER_PATH'];
  if (wrapperPath == null || wrapperPath.isEmpty) {
    return;
  }
  final wrappers = _splitPathList(wrapperPath);
  if (wrappers.isEmpty) {
    return;
  }
  _removePathEntries(environment, wrappers);
  final current = _splitPathList(environment['PATH'] ?? '');
  environment['PATH'] = <String>[
    ...wrappers,
    ...current,
  ].join(_pathListSeparator);
}

void _removePathEntries(
  Map<String, String> environment,
  Iterable<String> entriesToRemove,
) {
  final remove = entriesToRemove.where((entry) => entry.isNotEmpty).toSet();
  if (remove.isEmpty) {
    return;
  }
  final path = environment['PATH'];
  if (path == null || path.isEmpty) {
    return;
  }
  final entries = _splitPathList(
    path,
  ).where((entry) => !remove.contains(entry)).toList(growable: false);
  if (entries.isEmpty) {
    environment.remove('PATH');
  } else {
    environment['PATH'] = entries.join(_pathListSeparator);
  }
}

List<String> _splitPathList(String value) {
  if (value.isEmpty) {
    return const <String>[];
  }
  return value
      .split(_pathListSeparator)
      .where((entry) => entry.isNotEmpty)
      .toList(growable: false);
}

String get _pathListSeparator => Platform.isWindows ? ';' : ':';

GhosttyTerminalShellLaunch _launchInWorkingDirectory(
  GhosttyTerminalShellLaunch launch,
  String workingDirectory,
) {
  if (workingDirectory.trim().isEmpty) {
    return launch;
  }
  if (_isWindowsCommandPromptLaunch(launch)) {
    return GhosttyTerminalShellLaunch(
      label: launch.label,
      shell: launch.shell,
      arguments: <String>[
        ...launch.arguments,
        '/d',
        '/s',
        '/k',
        'cd /d ${_cmdQuote(workingDirectory)}',
      ],
      environment: launch.environment,
      setupCommand: launch.setupCommand,
    );
  }
  if (_isWindowsPowerShellLaunch(launch)) {
    return GhosttyTerminalShellLaunch(
      label: launch.label,
      shell: launch.shell,
      arguments: launch.arguments,
      environment: launch.environment,
      setupCommand: _prependSetupCommand(
        launch.setupCommand,
        "Set-Location -LiteralPath ${_powerShellQuote(workingDirectory)}\r\n",
      ),
    );
  }
  final execCommand = StringBuffer(
    'cd ${_shQuote(workingDirectory)} || true; exec ',
  )..write(_shQuote(launch.shell));
  for (final argument in launch.arguments) {
    execCommand
      ..write(' ')
      ..write(_shQuote(argument));
  }
  return GhosttyTerminalShellLaunch(
    label: launch.label,
    shell: '/bin/sh',
    arguments: <String>['-c', execCommand.toString()],
    environment: launch.environment,
    setupCommand: launch.setupCommand,
  );
}

@visibleForTesting
GhosttyTerminalShellLaunch launchInWorkingDirectoryForTesting(
  GhosttyTerminalShellLaunch launch,
  String workingDirectory,
) {
  return _launchInWorkingDirectory(launch, workingDirectory);
}

@visibleForTesting
Map<String, String> terminalPlatformEnvironmentForTesting() {
  return _terminalPlatformEnvironment();
}

@visibleForTesting
List<GhosttyTerminalShellLaunch> terminalShellLaunchesForTesting() {
  return _terminalShellLaunches();
}

@visibleForTesting
List<GhosttyTerminalShellLaunch> windowsTerminalShellLaunchesForTesting(
  Map<String, String> platformEnvironment, {
  required bool Function(String path) fileExists,
}) {
  return _windowsTerminalShellLaunches(
    platformEnvironment,
    fileExists: fileExists,
  );
}

@visibleForTesting
GhosttyTerminalShellLaunch launchWithSanitizedAgentHookEnvironmentForTesting(
  GhosttyTerminalShellLaunch launch,
  Map<String, String>? agentHookEnvironment,
) {
  return _launchWithSanitizedAgentHookEnvironment(launch, agentHookEnvironment);
}

bool _isAleraAgentHookEnvironmentKey(String key, String _) {
  return key.startsWith('ALERA_AGENT_HOOK_') ||
      key == 'ALERA_TERMINAL_SESSION_ID' ||
      key == 'ALERA_WORKSPACE_ID' ||
      key == 'ALERA_TAB_ID' ||
      key == 'ALERA_CODEX_HOME' ||
      key == 'ALERA_CLAUDE_CONFIG_DIR' ||
      key == 'ALERA_COPILOT_HOME' ||
      key == 'ALERA_COPILOT_SOURCE_HOME' ||
      key == 'ALERA_OPENCODE_CONFIG_DIR' ||
      key == 'ALERA_OPENCODE_SOURCE_CONFIG_DIR' ||
      key == 'ALERA_PI_CODING_AGENT_DIR' ||
      key == 'ALERA_PI_SOURCE_AGENT_DIR' ||
      key == 'ALERA_CURSOR_PLUGIN_DIR' ||
      key == 'ALERA_AMP_CONFIG_DIR' ||
      key == 'ALERA_AMP_SOURCE_CONFIG_DIR' ||
      key == 'ALERA_AGENT_WRAPPER_PATH';
}

bool _isWindowsCommandPromptLaunch(GhosttyTerminalShellLaunch launch) {
  return _shellExecutableName(launch) == 'cmd';
}

bool _isWindowsPowerShellLaunch(GhosttyTerminalShellLaunch launch) {
  return switch (_shellExecutableName(launch)) {
    'pwsh' || 'powershell' => true,
    _ => false,
  };
}

String _shellExecutableName(GhosttyTerminalShellLaunch launch) {
  final executable = launch.shell.replaceAll(r'\', '/').split('/').last;
  final lower = executable.toLowerCase();
  return lower.endsWith('.exe') ? lower.substring(0, lower.length - 4) : lower;
}

String _cmdQuote(String value) {
  return '"${value.replaceAll('"', '""')}"';
}

String _powerShellQuote(String value) {
  return "'${value.replaceAll("'", "''")}'";
}

String _prependSetupCommand(String? existing, String setupCommand) {
  if (existing == null || existing.isEmpty) {
    return setupCommand;
  }
  return '$setupCommand$existing';
}

@visibleForTesting
String cmdQuoteForTesting(String value) {
  return _cmdQuote(value);
}

@visibleForTesting
String powerShellQuoteForTesting(String value) {
  return _powerShellQuote(value);
}

String _shQuote(String value) {
  if (value.isEmpty) {
    return "''";
  }
  return "'${value.replaceAll("'", "'\"'\"'")}'";
}

@visibleForTesting
String shQuoteForTesting(String value) {
  return _shQuote(value);
}

bool get _isSupportedNativeDesktopTerminalPlatform {
  return _isSupportedNativeDesktopTerminalPlatformFor(
    defaultTargetPlatform,
    isWeb: kIsWeb,
  );
}

bool get _terminalHardwareKeyboardOnly {
  return _terminalHardwareKeyboardOnlyFor(defaultTargetPlatform, isWeb: kIsWeb);
}

final xterm.TerminalTargetPlatform _xtermTargetPlatform =
    _xtermTargetPlatformFor(defaultTargetPlatform);

@visibleForTesting
xterm.TerminalTargetPlatform defaultXtermTargetPlatformForTesting() {
  return _xtermTargetPlatform;
}

bool _isSupportedNativeDesktopTerminalPlatformFor(
  TargetPlatform platform, {
  required bool isWeb,
}) {
  if (isWeb) {
    return false;
  }
  return switch (platform) {
    TargetPlatform.linux ||
    TargetPlatform.macOS ||
    TargetPlatform.windows => true,
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.fuchsia => false,
  };
}

bool _terminalHardwareKeyboardOnlyFor(
  TargetPlatform platform, {
  required bool isWeb,
}) {
  return false;
}

String _noTerminalShellCandidatesMessage() {
  return switch (defaultTargetPlatform) {
    TargetPlatform.windows =>
      'No Windows terminal shell executable could be resolved.',
    _ => 'No desktop PTY shell candidates are available.',
  };
}

@visibleForTesting
bool terminalHardwareKeyboardOnlyForTesting(
  TargetPlatform platform, {
  bool isWeb = false,
}) {
  return _terminalHardwareKeyboardOnlyFor(platform, isWeb: isWeb);
}

xterm.TerminalTargetPlatform _xtermTargetPlatformFor(TargetPlatform platform) {
  return switch (platform) {
    TargetPlatform.android => xterm.TerminalTargetPlatform.android,
    TargetPlatform.iOS => xterm.TerminalTargetPlatform.ios,
    TargetPlatform.fuchsia => xterm.TerminalTargetPlatform.fuchsia,
    TargetPlatform.linux => xterm.TerminalTargetPlatform.linux,
    TargetPlatform.macOS => xterm.TerminalTargetPlatform.macos,
    TargetPlatform.windows => xterm.TerminalTargetPlatform.windows,
  };
}

String _resolveTerminalFontFamily(String fontFamily) {
  if (fontFamily.trim().toLowerCase() == 'jetbrains mono') {
    return GoogleFonts.jetBrainsMono().fontFamily ?? fontFamily;
  }
  return fontFamily.trim().isEmpty ? 'monospace' : fontFamily.trim();
}

Set<int>? _wordSeparatorsFromSettings(String? value) {
  final separators = value?.trim();
  if (separators == null || separators.isEmpty) {
    return null;
  }
  return separators.runes.toSet();
}

extension on TerminalCursorShape {
  xterm.TerminalCursorType toXtermCursorType() {
    return switch (this) {
      TerminalCursorShape.block => xterm.TerminalCursorType.block,
      TerminalCursorShape.bar => xterm.TerminalCursorType.verticalBar,
      TerminalCursorShape.underline => xterm.TerminalCursorType.underline,
    };
  }
}

const List<String> _terminalFontFallback = <String>[
  'SF Mono',
  'Menlo',
  'Monaco',
  'Cascadia Mono',
  'Consolas',
  'DejaVu Sans Mono',
  'Liberation Mono',
  'Symbols Nerd Font Mono',
  'MesloLGS Nerd Font',
  'JetBrainsMono Nerd Font',
  'Hack Nerd Font',
  'Apple Symbols',
  'Noto Color Emoji',
  'Noto Sans Symbols',
  'monospace',
];

@visibleForTesting
List<String> terminalFontFallbackForTesting() {
  return _terminalFontFallback;
}

Color? _colorFromHex(String? value) {
  final normalized = normalizeTerminalHexColor(value);
  if (normalized == null) {
    return null;
  }
  return Color(0xFF000000 | int.parse(normalized.substring(1), radix: 16));
}

xterm.TerminalTheme _resolveXtermTheme(TerminalSettings settings) {
  final base = terminalThemeForName(settings.themeName);
  final overrides = settings.colorOverrides;
  final cursor = (_colorFromHex(overrides.cursor) ?? base.cursor).withValues(
    alpha: settings.cursorOpacity,
  );
  return xterm.TerminalTheme(
    cursor: cursor,
    selection: _colorFromHex(overrides.selection) ?? base.selection,
    foreground: _colorFromHex(overrides.foreground) ?? base.foreground,
    background: _colorFromHex(overrides.background) ?? base.background,
    black: base.black,
    red: base.red,
    green: base.green,
    yellow: base.yellow,
    blue: base.blue,
    magenta: base.magenta,
    cyan: base.cyan,
    white: base.white,
    brightBlack: base.brightBlack,
    brightRed: base.brightRed,
    brightGreen: base.brightGreen,
    brightYellow: base.brightYellow,
    brightBlue: base.brightBlue,
    brightMagenta: base.brightMagenta,
    brightCyan: base.brightCyan,
    brightWhite: base.brightWhite,
    searchHitBackground: base.searchHitBackground,
    searchHitBackgroundCurrent: base.searchHitBackgroundCurrent,
    searchHitForeground: base.searchHitForeground,
  );
}
