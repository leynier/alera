import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/keyboard/domain/keyboard_shortcut_settings.dart';
import 'package:alera/src/features/settings/domain/terminal_theme_catalog.dart';

enum TerminalCursorShape { block, bar, underline }

TerminalCursorShape _terminalCursorShapeFromWire(Object? value) {
  if (value is String) {
    for (final option in TerminalCursorShape.values) {
      if (option.name == value) {
        return option;
      }
    }
  }
  return TerminalSettings.defaults.cursorShape;
}

String _terminalThemeNameFromWire(Object? value, Object? legacyPreset) {
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  return terminalThemeNameFromLegacyPreset(legacyPreset) ??
      TerminalSettings.defaults.themeName;
}

double _doubleFromWire(Object? value, double fallback, double min, double max) {
  final number = switch (value) {
    final num raw => raw.toDouble(),
    final String raw => double.tryParse(raw),
    _ => null,
  };
  if (number == null || !number.isFinite) {
    return fallback;
  }
  return number.clamp(min, max).toDouble();
}

int _intFromWire(Object? value, int fallback, int min, int max) {
  final number = switch (value) {
    final int raw => raw,
    final num raw => raw.round(),
    final String raw => int.tryParse(raw),
    _ => null,
  };
  if (number == null) {
    return fallback;
  }
  return number.clamp(min, max).toInt();
}

String _stringFromWire(Object? value, String fallback) {
  if (value is! String || value.trim().isEmpty) {
    return fallback;
  }
  return value.trim();
}

String? _wordSeparatorsFromWire(Object? value) {
  if (value is! String || value.isEmpty) {
    return null;
  }
  return value;
}

final _hexColorPattern = RegExp(r'^#?[0-9a-fA-F]{6}$');

String? normalizeTerminalHexColor(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  if (trimmed.isEmpty || !_hexColorPattern.hasMatch(trimmed)) {
    return null;
  }
  final hex = trimmed.startsWith('#') ? trimmed.substring(1) : trimmed;
  return '#${hex.toLowerCase()}';
}

class TerminalColorOverrides {
  const TerminalColorOverrides({
    this.foreground,
    this.background,
    this.cursor,
    this.selection,
  });

  final String? foreground;
  final String? background;
  final String? cursor;
  final String? selection;

  bool get isEmpty =>
      foreground == null &&
      background == null &&
      cursor == null &&
      selection == null;

  TerminalColorOverrides copyWith({
    Object? foreground = _unset,
    Object? background = _unset,
    Object? cursor = _unset,
    Object? selection = _unset,
  }) {
    return TerminalColorOverrides(
      foreground: identical(foreground, _unset)
          ? this.foreground
          : foreground as String?,
      background: identical(background, _unset)
          ? this.background
          : background as String?,
      cursor: identical(cursor, _unset) ? this.cursor : cursor as String?,
      selection: identical(selection, _unset)
          ? this.selection
          : selection as String?,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (foreground != null) 'foreground': foreground,
      if (background != null) 'background': background,
      if (cursor != null) 'cursor': cursor,
      if (selection != null) 'selection': selection,
    };
  }

  factory TerminalColorOverrides.fromJson(Map<String, Object?> json) {
    return TerminalColorOverrides(
      foreground: normalizeTerminalHexColor(json['foreground']),
      background: normalizeTerminalHexColor(json['background']),
      cursor: normalizeTerminalHexColor(json['cursor']),
      selection: normalizeTerminalHexColor(json['selection']),
    );
  }
}

class TerminalSettings {
  const TerminalSettings({
    required this.fontFamily,
    required this.fontSize,
    this.fontWeight = 400,
    required this.lineHeight,
    double? padding,
    double? paddingX,
    double? paddingY,
    required this.cursorShape,
    this.cursorBlink = false,
    this.cursorOpacity = 1,
    this.themeName = TerminalThemeNames.aleraDark,
    this.backgroundOpacity = 1,
    this.wordSeparators,
    this.colorOverrides = const TerminalColorOverrides(),
    required this.scrollbackLines,
  }) : paddingX = paddingX ?? padding ?? AleraTokens.space12,
       paddingY = paddingY ?? padding ?? AleraTokens.space12;

  final String fontFamily;
  final double fontSize;
  final int fontWeight;
  final double lineHeight;
  final double paddingX;
  final double paddingY;
  final TerminalCursorShape cursorShape;
  final bool cursorBlink;
  final double cursorOpacity;
  final String themeName;
  final double backgroundOpacity;
  final String? wordSeparators;
  final TerminalColorOverrides colorOverrides;
  final int scrollbackLines;

  double get padding =>
      paddingX == paddingY ? paddingX : (paddingX + paddingY) / 2;

  static const TerminalSettings defaults = TerminalSettings(
    fontFamily: 'JetBrains Mono',
    fontSize: 13,
    fontWeight: 400,
    lineHeight: 1.3,
    padding: AleraTokens.space12,
    cursorShape: TerminalCursorShape.block,
    cursorBlink: false,
    cursorOpacity: 1,
    themeName: TerminalThemeNames.aleraDark,
    backgroundOpacity: 1,
    scrollbackLines: 10000,
  );

  TerminalSettings copyWith({
    String? fontFamily,
    double? fontSize,
    int? fontWeight,
    double? lineHeight,
    double? padding,
    double? paddingX,
    double? paddingY,
    TerminalCursorShape? cursorShape,
    bool? cursorBlink,
    double? cursorOpacity,
    String? themeName,
    double? backgroundOpacity,
    Object? wordSeparators = _unset,
    TerminalColorOverrides? colorOverrides,
    int? scrollbackLines,
  }) {
    return TerminalSettings(
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      fontWeight: fontWeight ?? this.fontWeight,
      lineHeight: lineHeight ?? this.lineHeight,
      paddingX: paddingX ?? padding ?? this.paddingX,
      paddingY: paddingY ?? padding ?? this.paddingY,
      cursorShape: cursorShape ?? this.cursorShape,
      cursorBlink: cursorBlink ?? this.cursorBlink,
      cursorOpacity: cursorOpacity ?? this.cursorOpacity,
      themeName: themeName ?? this.themeName,
      backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
      wordSeparators: identical(wordSeparators, _unset)
          ? this.wordSeparators
          : wordSeparators as String?,
      colorOverrides: colorOverrides ?? this.colorOverrides,
      scrollbackLines: scrollbackLines ?? this.scrollbackLines,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'fontFamily': fontFamily,
      'fontSize': fontSize,
      'fontWeight': fontWeight,
      'lineHeight': lineHeight,
      'padding': padding,
      'paddingX': paddingX,
      'paddingY': paddingY,
      'cursorShape': cursorShape.name,
      'cursorBlink': cursorBlink,
      'cursorOpacity': cursorOpacity,
      'themeName': themeName,
      'backgroundOpacity': backgroundOpacity,
      if (wordSeparators != null) 'wordSeparators': wordSeparators,
      if (!colorOverrides.isEmpty) 'colorOverrides': colorOverrides.toJson(),
      'scrollbackLines': scrollbackLines,
    };
  }

  factory TerminalSettings.fromJson(Map<String, Object?> json) {
    const defaults = TerminalSettings.defaults;
    final legacyPadding = _doubleFromWire(
      json['padding'],
      defaults.padding,
      0,
      64,
    );
    final colorOverridesJson = json['colorOverrides'];
    return TerminalSettings(
      fontFamily: _stringFromWire(json['fontFamily'], defaults.fontFamily),
      fontSize: _doubleFromWire(json['fontSize'], defaults.fontSize, 8, 32),
      fontWeight: _intFromWire(
        json['fontWeight'],
        defaults.fontWeight,
        100,
        900,
      ),
      lineHeight: _doubleFromWire(
        json['lineHeight'],
        defaults.lineHeight,
        0.8,
        2.4,
      ),
      paddingX: _doubleFromWire(json['paddingX'], legacyPadding, 0, 64),
      paddingY: _doubleFromWire(json['paddingY'], legacyPadding, 0, 64),
      cursorShape: _terminalCursorShapeFromWire(json['cursorShape']),
      cursorBlink: json['cursorBlink'] == true,
      cursorOpacity: _doubleFromWire(
        json['cursorOpacity'],
        defaults.cursorOpacity,
        0,
        1,
      ),
      themeName: _terminalThemeNameFromWire(
        json['themeName'],
        json['themePreset'],
      ),
      backgroundOpacity: _doubleFromWire(
        json['backgroundOpacity'],
        defaults.backgroundOpacity,
        0,
        1,
      ),
      wordSeparators: _wordSeparatorsFromWire(json['wordSeparators']),
      colorOverrides: colorOverridesJson is Map
          ? TerminalColorOverrides.fromJson(
              Map<String, Object?>.from(colorOverridesJson),
            )
          : defaults.colorOverrides,
      scrollbackLines: _intFromWire(
        json['scrollbackLines'],
        defaults.scrollbackLines,
        100,
        200000,
      ),
    );
  }
}

class GeneralSettings {
  const GeneralSettings({this.workspaceDirectory, this.starClicked = false});

  /// User-configured root directory where new linked workspaces are created.
  /// `null` falls back to the platform default (`~/.alera/workspaces`).
  final String? workspaceDirectory;

  /// Local flag set after the user has interacted with the GitHub star flow.
  /// Used to mute the in-app nag; the Settings row state is still driven by
  /// the live `gh` check.
  final bool starClicked;

  static const GeneralSettings defaults = GeneralSettings();

  GeneralSettings copyWith({
    Object? workspaceDirectory = _unset,
    bool? starClicked,
  }) {
    return GeneralSettings(
      workspaceDirectory: identical(workspaceDirectory, _unset)
          ? this.workspaceDirectory
          : workspaceDirectory as String?,
      starClicked: starClicked ?? this.starClicked,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (workspaceDirectory != null) 'workspaceDirectory': workspaceDirectory,
      'starClicked': starClicked,
    };
  }

  factory GeneralSettings.fromJson(Map<String, Object?> json) {
    final raw = json['workspaceDirectory'];
    final dir = raw is String && raw.trim().isNotEmpty ? raw.trim() : null;
    final starClicked = json['starClicked'] == true;
    return GeneralSettings(workspaceDirectory: dir, starClicked: starClicked);
  }
}

const Object _unset = Object();

class AleraSettings {
  const AleraSettings({
    required this.general,
    required this.terminal,
    required this.keyboard,
  });

  final GeneralSettings general;
  final TerminalSettings terminal;
  final KeyboardShortcutSettings keyboard;

  static const AleraSettings defaults = AleraSettings(
    general: GeneralSettings.defaults,
    terminal: TerminalSettings.defaults,
    keyboard: KeyboardShortcutSettings.defaults,
  );

  AleraSettings copyWith({
    GeneralSettings? general,
    TerminalSettings? terminal,
    KeyboardShortcutSettings? keyboard,
  }) {
    return AleraSettings(
      general: general ?? this.general,
      terminal: terminal ?? this.terminal,
      keyboard: keyboard ?? this.keyboard,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'general': general.toJson(),
      'terminal': terminal.toJson(),
      'keyboard': keyboard.toJson(),
    };
  }

  factory AleraSettings.fromJson(Map<String, Object?> json) {
    final generalJson = json['general'];
    final terminalJson = json['terminal'];
    final keyboardJson = json['keyboard'];
    return AleraSettings(
      general: generalJson is Map
          ? GeneralSettings.fromJson(Map<String, Object?>.from(generalJson))
          : GeneralSettings.defaults,
      terminal: terminalJson is Map
          ? TerminalSettings.fromJson(Map<String, Object?>.from(terminalJson))
          : TerminalSettings.defaults,
      keyboard: keyboardJson is Map
          ? KeyboardShortcutSettings.fromJson(
              Map<String, Object?>.from(keyboardJson),
            )
          : KeyboardShortcutSettings.defaults,
    );
  }
}
