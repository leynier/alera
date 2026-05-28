import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart' as xterm;
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

class TerminalThemeEntry {
  const TerminalThemeEntry({required this.name, required this.theme});

  final String name;
  final xterm.TerminalTheme theme;
}

final List<TerminalThemeEntry> terminalThemeCatalog =
    List<TerminalThemeEntry>.unmodifiable(<TerminalThemeEntry>[
      ...terminalThemeBasePalette,
      ...terminalThemeExtendedPalette,
    ]);

final List<String> terminalThemeNames = List<String>.unmodifiable(
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

TerminalThemeEntry _hexTheme(
  String name, {
  required int background,
  required int foreground,
  required int cursor,
  required int selection,
  required int black,
  required int red,
  required int green,
  required int yellow,
  required int blue,
  required int magenta,
  required int cyan,
  required int white,
  required int brightBlack,
  required int brightRed,
  required int brightGreen,
  required int brightYellow,
  required int brightBlue,
  required int brightMagenta,
  required int brightCyan,
  required int brightWhite,
}) {
  return TerminalThemeEntry(
    name: name,
    theme: xterm.TerminalTheme(
      background: _hex(background),
      foreground: _hex(foreground),
      cursor: _hex(cursor),
      selection: _hex(selection),
      black: _hex(black),
      red: _hex(red),
      green: _hex(green),
      yellow: _hex(yellow),
      blue: _hex(blue),
      magenta: _hex(magenta),
      cyan: _hex(cyan),
      white: _hex(white),
      brightBlack: _hex(brightBlack),
      brightRed: _hex(brightRed),
      brightGreen: _hex(brightGreen),
      brightYellow: _hex(brightYellow),
      brightBlue: _hex(brightBlue),
      brightMagenta: _hex(brightMagenta),
      brightCyan: _hex(brightCyan),
      brightWhite: _hex(brightWhite),
      searchHitBackground: _hex(selection),
      searchHitBackgroundCurrent: _hex(brightBlack),
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
