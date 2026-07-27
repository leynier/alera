part of 'terminal_runtime.dart';

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
    return 'JetBrains Mono';
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
