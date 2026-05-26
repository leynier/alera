import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/keyboard/domain/keyboard_shortcut_settings.dart';
import 'package:alera/src/features/settings/domain/terminal_theme_catalog.dart';
import 'package:dart_mappable/dart_mappable.dart';

part 'alera_settings.mapper.dart';

@MappableEnum()
enum TerminalCursorShape { block, bar, underline }

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

@MappableClass()
class TerminalColorOverrides with TerminalColorOverridesMappable {
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

  factory TerminalColorOverrides.fromJson(Map<String, Object?> json) =>
      TerminalColorOverridesMapper.fromMap(Map<String, dynamic>.from(json));
}

@MappableClass()
class TerminalSettings with TerminalSettingsMappable {
  const TerminalSettings({
    required this.fontFamily,
    required this.fontSize,
    this.fontWeight = 400,
    required this.lineHeight,
    this.paddingX = AleraTokens.space12,
    this.paddingY = AleraTokens.space12,
    required this.cursorShape,
    this.cursorBlink = false,
    this.cursorOpacity = 1,
    this.themeName = TerminalThemeNames.aleraDark,
    this.backgroundOpacity = 1,
    this.wordSeparators,
    this.colorOverrides = const TerminalColorOverrides(),
    required this.scrollbackLines,
    this.hostEmptyShutdownDelaySeconds = 30,
    this.hostDetachedSessionShutdownDelaySeconds = 60 * 60,
    this.hostScrollbackBytes = 10 * 1000 * 1000,
  });

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
  final int hostEmptyShutdownDelaySeconds;
  final int hostDetachedSessionShutdownDelaySeconds;
  final int hostScrollbackBytes;

  double get padding =>
      paddingX == paddingY ? paddingX : (paddingX + paddingY) / 2;

  static const TerminalSettings defaults = TerminalSettings(
    fontFamily: 'JetBrains Mono',
    fontSize: 13,
    fontWeight: 400,
    lineHeight: 1.3,
    paddingX: AleraTokens.space12,
    paddingY: AleraTokens.space12,
    cursorShape: TerminalCursorShape.block,
    cursorBlink: false,
    cursorOpacity: 1,
    themeName: TerminalThemeNames.aleraDark,
    backgroundOpacity: 1,
    scrollbackLines: 10000,
    hostEmptyShutdownDelaySeconds: 30,
    hostDetachedSessionShutdownDelaySeconds: 60 * 60,
    hostScrollbackBytes: 10 * 1000 * 1000,
  );

  factory TerminalSettings.fromJson(Map<String, Object?> json) =>
      TerminalSettingsMapper.fromMap(Map<String, dynamic>.from(json));
}

@MappableClass()
class GeneralSettings with GeneralSettingsMappable {
  const GeneralSettings({
    this.workspaceDirectory,
    this.starClicked = false,
    this.confirmProjectRemoval = true,
    this.confirmWorkspaceRemoval = true,
    this.agentStatusHooksEnabled = false,
  });

  /// User-configured root directory where new linked workspaces are created.
  /// `null` falls back to the platform default (`~/.alera/workspaces`).
  final String? workspaceDirectory;

  /// Local flag set after the user has interacted with the GitHub star flow.
  /// Used to mute the in-app nag; the Settings row state is still driven by
  /// the live `gh` check.
  final bool starClicked;

  /// Ask before unregistering a project and deleting its workspace metadata.
  final bool confirmProjectRemoval;

  /// Ask before removing a linked workspace and its Git worktree.
  final bool confirmWorkspaceRemoval;

  /// Install managed Codex and Claude Code hooks for local Alera terminal
  /// status. Default-off because enabling it edits user agent config files.
  final bool agentStatusHooksEnabled;

  static const GeneralSettings defaults = GeneralSettings();

  factory GeneralSettings.fromJson(Map<String, Object?> json) =>
      GeneralSettingsMapper.fromMap(Map<String, dynamic>.from(json));
}

@MappableClass()
class AleraSettings with AleraSettingsMappable {
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

  factory AleraSettings.fromJson(Map<String, Object?> json) =>
      AleraSettingsMapper.fromMap(Map<String, dynamic>.from(json));
}
