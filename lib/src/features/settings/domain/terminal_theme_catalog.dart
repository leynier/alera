import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';
import 'package:xterm2/xterm.dart' as xterm;
part 'terminal_theme_base_palette.dart';
part 'terminal_theme_extended_palette.dart';

abstract final class TerminalThemeNames {
  static const String aleraDark = 'Alera Dark';
  static const String ghosttyDark = 'Ghostty Default Style Dark';
  static const String builtinTangoLight = 'Builtin Tango Light';
  static const String dracula = 'Dracula';
  static const String catppuccinMocha = 'Catppuccin Mocha';
  static const String ayuDark = 'Ayu Dark';
}

class const TerminalThemeEntry({
  required final String name,
  required final xterm.TerminalTheme theme,
});

final List<TerminalThemeEntry> terminalThemeCatalog =
    List<TerminalThemeEntry>.unmodifiableOf(<TerminalThemeEntry>[
      ...terminalThemeBasePalette,
      ...terminalThemeExtendedPalette,
    ]);

final List<String> terminalThemeNames = List<String>.unmodifiableOf(
  terminalThemeCatalog.map((entry) => entry.name),
);

TerminalThemeEntry? terminalThemeEntryForName(String name) {
  final normalized = name.trim().toLowerCase();
  for (final entry in terminalThemeCatalog) {
    if (entry.name.toLowerCase() == normalized) {
      return entry;
    }
  }
  return null;
}

xterm.TerminalTheme terminalThemeForName(String name) {
  return terminalThemeEntryForName(name)?.theme ?? _aleraTheme.theme;
}

String? terminalThemeNameFromLegacyPreset(Object? value) {
  return switch (value) {
    'aleraDark' => TerminalThemeNames.aleraDark,
    'ghosttyDark' => TerminalThemeNames.ghosttyDark,
    'dracula' => TerminalThemeNames.dracula,
    'catppuccinMocha' => TerminalThemeNames.catppuccinMocha,
    'ayuDark' => TerminalThemeNames.ayuDark,
    _ => null,
  };
}

class const _AnsiColor(final int normal, [int? bright]) {
  this : bright = bright ?? normal;

  final int bright;
}

class const _AnsiPalette({
  required final _AnsiColor black,
  required final _AnsiColor red,
  required final _AnsiColor green,
  required final _AnsiColor yellow,
  required final _AnsiColor blue,
  required final _AnsiColor magenta,
  required final _AnsiColor cyan,
  required final _AnsiColor white,
});

const _AnsiPalette _solarizedAnsiPalette = _AnsiPalette(
  black: _AnsiColor(0x073642, 0x002B36),
  red: _AnsiColor(0xDC322F, 0xCB4B16),
  green: _AnsiColor(0x859900, 0x586E75),
  yellow: _AnsiColor(0xB58900, 0x657B83),
  blue: _AnsiColor(0x268BD2, 0x839496),
  magenta: _AnsiColor(0xD33682, 0x6C71C4),
  cyan: _AnsiColor(0x2AA198, 0x93A1A1),
  white: _AnsiColor(0xEEE8D5, 0xFDF6E3),
);

const _AnsiPalette _tangoAnsiPalette = _AnsiPalette(
  black: _AnsiColor(0x2E3436, 0x555753),
  red: _AnsiColor(0xCC0000, 0xEF2929),
  green: _AnsiColor(0x4E9A06, 0x8AE234),
  yellow: _AnsiColor(0xC4A000, 0xFCE94F),
  blue: _AnsiColor(0x3465A4, 0x729FCF),
  magenta: _AnsiColor(0x75507B, 0xAD7FA8),
  cyan: _AnsiColor(0x06989A, 0x34E2E2),
  white: _AnsiColor(0xD3D7CF, 0xEEEEEC),
);

TerminalThemeEntry _hexTheme(
  String name, {
  required int background,
  required int foreground,
  int? cursor,
  required int selection,
  required _AnsiPalette ansi,
}) {
  return TerminalThemeEntry(
    name: name,
    theme: xterm.TerminalTheme(
      background: _hex(background),
      foreground: _hex(foreground),
      cursor: _hex(cursor ?? foreground),
      selection: _hex(selection),
      black: _hex(ansi.black.normal),
      red: _hex(ansi.red.normal),
      green: _hex(ansi.green.normal),
      yellow: _hex(ansi.yellow.normal),
      blue: _hex(ansi.blue.normal),
      magenta: _hex(ansi.magenta.normal),
      cyan: _hex(ansi.cyan.normal),
      white: _hex(ansi.white.normal),
      brightBlack: _hex(ansi.black.bright),
      brightRed: _hex(ansi.red.bright),
      brightGreen: _hex(ansi.green.bright),
      brightYellow: _hex(ansi.yellow.bright),
      brightBlue: _hex(ansi.blue.bright),
      brightMagenta: _hex(ansi.magenta.bright),
      brightCyan: _hex(ansi.cyan.bright),
      brightWhite: _hex(ansi.white.bright),
      searchHitBackground: _hex(selection),
      searchHitBackgroundCurrent: _hex(ansi.black.bright),
      searchHitForeground: _hex(foreground),
    ),
  );
}

Color _hex(int value) => Color(0xFF000000 | value);

const TerminalThemeEntry _aleraTheme = TerminalThemeEntry(
  name: TerminalThemeNames.aleraDark,
  theme: xterm.TerminalTheme(
    cursor: AleraTokens.accent,
    selection: AleraTokens.accentSubtle,
    foreground: AleraTokens.foreground,
    background: AleraTokens.bg,
    black: AleraTokens.foregroundFaint,
    red: AleraTokens.error,
    green: AleraTokens.success,
    yellow: AleraTokens.warning,
    blue: AleraTokens.info,
    magenta: AleraTokens.accent,
    cyan: AleraTokens.info,
    white: AleraTokens.foreground,
    brightBlack: AleraTokens.foregroundMuted,
    brightRed: AleraTokens.error,
    brightGreen: AleraTokens.success,
    brightYellow: AleraTokens.warning,
    brightBlue: AleraTokens.info,
    brightMagenta: AleraTokens.accent,
    brightCyan: AleraTokens.info,
    brightWhite: AleraTokens.foreground,
    searchHitBackground: AleraTokens.surfaceElevated,
    searchHitBackgroundCurrent: AleraTokens.accentSubtle,
    searchHitForeground: AleraTokens.foreground,
  ),
);
