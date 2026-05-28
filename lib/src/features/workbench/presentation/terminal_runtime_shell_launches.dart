part of 'terminal_runtime.dart';

Map<String, String> _terminalPlatformEnvironment() {
  final environment = <String, String>{...ghosttyTerminalPlatformEnvironment()};
  environment.remove('NO_COLOR');
  return environment;
}

List<GhosttyTerminalShellLaunch> _terminalShellLaunches() {
  final platformEnvironment = _terminalPlatformEnvironment();
  final launches = <GhosttyTerminalShellLaunch>[
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
  final seen = <String>{};
  return launches
      .where((launch) {
        final key = '${launch.shell}\u0000${launch.arguments.join('\u0000')}';
        return seen.add(key);
      })
      .toList(growable: false);
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

String _shellExecutableName(GhosttyTerminalShellLaunch launch) {
  final executable = launch.shell.replaceAll(r'\', '/').split('/').last;
  final lower = executable.toLowerCase();
  return lower.endsWith('.exe') ? lower.substring(0, lower.length - 4) : lower;
}

String _cmdQuote(String value) {
  return '"${value.replaceAll('"', '""')}"';
}

@visibleForTesting
String cmdQuoteForTesting(String value) {
  return _cmdQuote(value);
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
