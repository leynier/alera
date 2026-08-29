import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/ai_assist/domain/ai_assist_settings.dart';
import 'package:alera/src/features/ai_dictation/domain/ai_dictation_settings.dart';
import 'package:alera/src/features/keyboard/domain/keyboard_shortcut_settings.dart';
import 'package:alera/src/features/settings/domain/editor_syntax_theme_catalog.dart';
import 'package:alera/src/features/settings/domain/terminal_theme_catalog.dart';
import 'package:alera/src/features/text_actions/domain/text_actions_settings.dart';
import 'package:dart_mappable/dart_mappable.dart';
import 'package:flutter/foundation.dart';

part 'agent_quota_settings.dart';
part 'codex_chat_settings.dart';
part 'alera_settings.mapper.dart';

@MappableEnum()
enum TerminalCursorShape { block, bar, underline }

@MappableEnum()
enum TerminalToolbarCorner {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight;

  String get label => switch (this) {
    topLeft => 'Top Left',
    topRight => 'Top Right',
    bottomLeft => 'Bottom Left',
    bottomRight => 'Bottom Right',
  };
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

@MappableClass(hook: _LegacyKeepRuntimeOpenHook())
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
    this.tuiScrollSensitivity = 1,
    this.clipboardOnSelect = false,
    this.allowOsc52Clipboard = false,
    this.showComposerByDefault = false,
    this.toolbarCorner = TerminalToolbarCorner.topRight,
    this.hostEmptyShutdownDelaySeconds = 30,
    this.hostDetachedSessionShutdownDelaySeconds = 60 * 60,
    this.hostScrollbackBytes = 10 * 1000 * 1000,
    this.bufferBudgetMegabytes = 256,
    this.keepRuntimeOpenOnAppQuit = false,
    this.loginShell,
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
  final int tuiScrollSensitivity;
  final bool clipboardOnSelect;
  final bool allowOsc52Clipboard;

  /// Whether new terminal sessions open the prompt composer immediately.
  final bool showComposerByDefault;

  /// Where the terminal action-button cluster sits inside the tab.
  final TerminalToolbarCorner toolbarCorner;
  final int hostEmptyShutdownDelaySeconds;
  final int hostDetachedSessionShutdownDelaySeconds;
  final int hostScrollbackBytes;

  /// Terminal buffer ceiling; 0 is unbounded. See `TerminalBufferBudget`.
  final int bufferBudgetMegabytes;
  final bool keepRuntimeOpenOnAppQuit;

  /// `null` keeps the platform default resolved by [resolvedLoginShell].
  final bool? loginShell;

  /// Whether terminals start the user shell as a login shell.
  ///
  /// macOS GUI apps inherit a minimal `launchd` PATH and never read
  /// `~/.zprofile`, where Homebrew and similar prefixes are set up, so login
  /// shells are the default there. Other platforms keep the plain interactive
  /// shell their terminal emulators use.
  bool get resolvedLoginShell => loginShell ?? defaultLoginShell;

  static bool get defaultLoginShell =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

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
    tuiScrollSensitivity: 1,
    clipboardOnSelect: false,
    allowOsc52Clipboard: false,
    showComposerByDefault: false,
    toolbarCorner: TerminalToolbarCorner.topRight,
    hostEmptyShutdownDelaySeconds: 30,
    hostDetachedSessionShutdownDelaySeconds: 60 * 60,
    hostScrollbackBytes: 10 * 1000 * 1000,
    keepRuntimeOpenOnAppQuit: false,
  );

  factory TerminalSettings.fromJson(Map<String, Object?> json) =>
      TerminalSettingsMapper.fromMap(Map<String, dynamic>.from(json));
}

/// Maps the inverted legacy `stopRuntimeOnAppQuit` flag to
/// `keepRuntimeOpenOnAppQuit` so older settings blobs keep their intent.
///
/// Blobs that never stored either flag used the old implicit default (leave
/// the runtime open on quit), so they migrate to `keepRuntimeOpenOnAppQuit:
/// true`. Fresh installs use [TerminalSettings.defaults] without decoding.
class _LegacyKeepRuntimeOpenHook extends MappingHook {
  const _LegacyKeepRuntimeOpenHook();

  @override
  Object? beforeDecode(Object? value) {
    if (value is! Map) {
      return value;
    }
    if (value.containsKey('keepRuntimeOpenOnAppQuit')) {
      return value;
    }
    if (value.containsKey('stopRuntimeOnAppQuit')) {
      return <String, dynamic>{
        for (final entry in value.entries)
          if (entry.key.toString() != 'stopRuntimeOnAppQuit')
            entry.key.toString(): entry.value,
        'keepRuntimeOpenOnAppQuit': value['stopRuntimeOnAppQuit'] != true,
      };
    }
    return <String, dynamic>{
      for (final entry in value.entries) entry.key.toString(): entry.value,
      'keepRuntimeOpenOnAppQuit': true,
    };
  }
}

@MappableClass()
class AgentStatusHookSettings with AgentStatusHookSettingsMappable {
  const AgentStatusHookSettings({
    this.codex = false,
    this.claude = false,
    this.copilot = false,
    this.cursor = false,
    this.agy = false,
    this.opencode = false,
    this.opencode2 = false,
    this.pi = false,
    this.amp = false,
    this.grok = false,
    this.fx = false,
  });

  final bool codex;
  final bool claude;
  final bool copilot;
  final bool cursor;
  final bool agy;
  final bool opencode;
  final bool opencode2;
  final bool pi;
  final bool amp;
  final bool grok;
  final bool fx;

  bool get anyEnabled =>
      codex ||
      claude ||
      copilot ||
      cursor ||
      agy ||
      opencode ||
      opencode2 ||
      pi ||
      amp ||
      grok ||
      fx;

  static const AgentStatusHookSettings defaults = AgentStatusHookSettings();

  factory AgentStatusHookSettings.fromJson(Map<String, Object?> json) =>
      AgentStatusHookSettingsMapper.fromMap(Map<String, dynamic>.from(json));
}

@MappableClass()
class EditorSettings with EditorSettingsMappable {
  const EditorSettings({
    this.tabSize = 4,
    this.themeName = EditorSyntaxThemeNames.alera,
    this.autosaveEnabled = false,
    this.autosaveDelaySeconds = defaultAutosaveDelaySeconds,
  });

  static const int minAutosaveDelaySeconds = 1;
  static const int maxAutosaveDelaySeconds = 60;
  static const int defaultAutosaveDelaySeconds = 1;

  /// Number of spaces inserted when the editor handles a Tab key press.
  final int tabSize;

  /// Syntax highlighting theme used by editor tabs.
  final String themeName;

  /// Save dirty editor tabs after they have been idle for the configured delay.
  final bool autosaveEnabled;

  /// Number of idle seconds before an automatic editor save.
  final int autosaveDelaySeconds;

  /// Clamps persisted values before they are used to construct a timer.
  int get effectiveAutosaveDelaySeconds => autosaveDelaySeconds
      .clamp(minAutosaveDelaySeconds, maxAutosaveDelaySeconds)
      .toInt();

  Duration get autosaveDebounce =>
      Duration(seconds: effectiveAutosaveDelaySeconds);

  static const EditorSettings defaults = EditorSettings();

  factory EditorSettings.fromJson(Map<String, Object?> json) =>
      EditorSettingsMapper.fromMap(Map<String, dynamic>.from(json));
}

@MappableClass()
class GeneralSettings with GeneralSettingsMappable {
  const GeneralSettings({
    this.workspaceDirectory,
    this.starClicked = false,
    this.confirmProjectRemoval = true,
    this.confirmWorkspaceRemoval = true,
    this.keepAliveEnabled = false,
    this.showTrayIcon = true,
    this.showDockBadge = true,
    this.showTrayBadge = true,
  });

  /// User-configured root directory where new linked workspaces are created.
  /// `null` falls back to the platform default (`~/.alera/workspaces`).
  final String? workspaceDirectory;

  /// Local flag after the GitHub star flow; Settings still uses the live `gh` check.
  final bool starClicked;

  /// Ask before unregistering a project and deleting its workspace metadata.
  final bool confirmProjectRemoval;

  /// Ask before removing a linked workspace and its Git worktree.
  final bool confirmWorkspaceRemoval;

  /// Prevent idle and display sleep while Alera is running.
  final bool keepAliveEnabled;

  /// Tray icon. Close hides; Quit still exits.
  final bool showTrayIcon;

  /// Pending-review Dock / taskbar badge.
  final bool showDockBadge;

  /// Pending-review count drawn onto the tray icon itself.
  final bool showTrayBadge;
  static const GeneralSettings defaults = GeneralSettings();

  factory GeneralSettings.fromJson(Map<String, Object?> json) =>
      GeneralSettingsMapper.fromMap(Map<String, dynamic>.from(json));
}

@MappableClass()
class AgentSettings with AgentSettingsMappable {
  const AgentSettings({
    this.agentStatusHooks = AgentStatusHookSettings.defaults,
    this.agentStatusNotificationsEnabled = false,
    this.agentStatusFinishedNotificationsEnabled = false,
    this.keepComputerAwakeWhileAgentsWork = false,
    this.defaultAgentProfileId,
    this.quotas = AgentQuotaSettings.defaults,
  });

  /// Install managed agent hooks for terminal status. Each agent is
  /// default-off because enabling it writes into that agent's user config area.
  final AgentStatusHookSettings agentStatusHooks;

  /// Show native desktop notifications when an agent needs attention.
  final bool agentStatusNotificationsEnabled;

  /// Also notify when an agent reports it finished.
  ///
  /// Default-off: every supported agent reports the end of a turn rather than
  /// the end of a task, so a normal back-and-forth notifies on every reply.
  final bool agentStatusFinishedNotificationsEnabled;

  /// Keep the local computer awake while local hook-reported agents are working.
  final bool keepComputerAwakeWhileAgentsWork;

  /// Runtime profile selected for flows that need an initial agent choice.
  final String? defaultAgentProfileId;

  /// Per-host quota providers, Claude CCS profiles, and environment names.
  final AgentQuotaSettings quotas;

  static const AgentSettings defaults = AgentSettings();

  factory AgentSettings.fromJson(Map<String, Object?> json) =>
      AgentSettingsMapper.fromMap(Map<String, dynamic>.from(json));
}

/// Lifts the agent-related keys that historically lived under `general` into
/// the `agents` sub-map so settings blobs written before the `AgentSettings`
/// extraction keep decoding with their values intact.
class _LegacyAgentSettingsHook extends MappingHook {
  const _LegacyAgentSettingsHook();

  static const List<String> _legacyKeys = <String>[
    'agentStatusHooks',
    'agentStatusNotificationsEnabled',
    'keepComputerAwakeWhileAgentsWork',
  ];

  @override
  Object? beforeDecode(Object? value) {
    if (value is! Map) {
      return value;
    }
    if (value.containsKey('agents')) {
      return value;
    }
    final general = value['general'];
    if (general is! Map) {
      return value;
    }
    final agents = <String, dynamic>{
      for (final key in _legacyKeys)
        if (general.containsKey(key)) key: general[key],
    };
    if (agents.isEmpty) {
      return value;
    }
    return <String, dynamic>{
      for (final entry in value.entries) entry.key.toString(): entry.value,
      'agents': agents,
    };
  }
}

/// Log levels offered in Settings, kept as a closed set so the stored value
/// cannot drift into something `package:logging` will not accept.
@MappableEnum()
enum DiagnosticsLogLevel { error, warning, info, debug }

@MappableClass()
class DiagnosticsSettings with DiagnosticsSettingsMappable {
  const DiagnosticsSettings({
    this.logLevel = DiagnosticsLogLevel.info,
    this.crashReportingEnabled = false,
  });

  /// Detail written to the app and runtime log files.
  final DiagnosticsLogLevel logLevel;

  /// Send crashes to Sentry. Default-off because it leaves the machine; the
  /// local log file is what makes diagnosis possible without it.
  final bool crashReportingEnabled;

  static const DiagnosticsSettings defaults = DiagnosticsSettings();

  factory DiagnosticsSettings.fromJson(Map<String, Object?> json) =>
      DiagnosticsSettingsMapper.fromMap(Map<String, dynamic>.from(json));
}

@MappableClass(hook: _LegacyAgentSettingsHook())
class AleraSettings with AleraSettingsMappable {
  const AleraSettings({
    required this.general,
    this.agents = AgentSettings.defaults,
    this.aiAssist = AiAssistSettings.defaults,
    this.aiDictation = AiDictationSettings.defaults,
    this.textActions = TextActionsSettings.defaults,
    this.editor = EditorSettings.defaults,
    this.diagnostics = DiagnosticsSettings.defaults,
    this.codexChat = CodexChatSettings.defaults,
    required this.terminal,
    required this.keyboard,
  });

  final GeneralSettings general;
  final AgentSettings agents;
  // Wire and persisted key stays `aiTextGeneration` so older hosts and settings keep working.
  @MappableField(key: 'aiTextGeneration')
  final AiAssistSettings aiAssist;
  final AiDictationSettings aiDictation;
  final TextActionsSettings textActions;
  final EditorSettings editor;
  final DiagnosticsSettings diagnostics;
  final CodexChatSettings codexChat;
  final TerminalSettings terminal;
  final KeyboardShortcutSettings keyboard;

  static const AleraSettings defaults = AleraSettings(
    general: GeneralSettings.defaults,
    agents: AgentSettings.defaults,
    aiAssist: AiAssistSettings.defaults,
    aiDictation: AiDictationSettings.defaults,
    editor: EditorSettings.defaults,
    diagnostics: DiagnosticsSettings.defaults,
    codexChat: CodexChatSettings.defaults,
    terminal: TerminalSettings.defaults,
    keyboard: KeyboardShortcutSettings.defaults,
  );

  factory AleraSettings.fromJson(Map<String, Object?> json) =>
      AleraSettingsMapper.fromMap(Map<String, dynamic>.from(json));
}
