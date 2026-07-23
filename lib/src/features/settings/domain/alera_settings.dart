import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/ai_text_generation/domain/ai_text_generation_settings.dart';
import 'package:alera/src/features/keyboard/domain/keyboard_shortcut_settings.dart';
import 'package:alera/src/features/settings/domain/editor_syntax_theme_catalog.dart';
import 'package:alera/src/features/settings/domain/terminal_theme_catalog.dart';
import 'package:dart_mappable/dart_mappable.dart';
import 'package:flutter/foundation.dart';

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
    this.tuiScrollSensitivity = 1,
    this.clipboardOnSelect = false,
    this.allowOsc52Clipboard = false,
    this.hostEmptyShutdownDelaySeconds = 30,
    this.hostDetachedSessionShutdownDelaySeconds = 60 * 60,
    this.hostScrollbackBytes = 10 * 1000 * 1000,
    this.stopRuntimeOnAppQuit = false,
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
  final int hostEmptyShutdownDelaySeconds;
  final int hostDetachedSessionShutdownDelaySeconds;
  final int hostScrollbackBytes;
  final bool stopRuntimeOnAppQuit;

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
    hostEmptyShutdownDelaySeconds: 30,
    hostDetachedSessionShutdownDelaySeconds: 60 * 60,
    hostScrollbackBytes: 10 * 1000 * 1000,
    stopRuntimeOnAppQuit: false,
  );

  factory TerminalSettings.fromJson(Map<String, Object?> json) =>
      TerminalSettingsMapper.fromMap(Map<String, dynamic>.from(json));
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
    this.pi = false,
    this.amp = false,
    this.grok = false,
  });

  final bool codex;
  final bool claude;
  final bool copilot;
  final bool cursor;
  final bool agy;
  final bool opencode;
  final bool pi;
  final bool amp;
  final bool grok;

  bool get anyEnabled =>
      codex ||
      claude ||
      copilot ||
      cursor ||
      agy ||
      opencode ||
      pi ||
      amp ||
      grok;

  static const AgentStatusHookSettings defaults = AgentStatusHookSettings();

  factory AgentStatusHookSettings.fromJson(Map<String, Object?> json) =>
      AgentStatusHookSettingsMapper.fromMap(Map<String, dynamic>.from(json));
}

@MappableClass()
class EditorSettings with EditorSettingsMappable {
  const EditorSettings({
    this.tabSize = 4,
    this.themeName = EditorSyntaxThemeNames.alera,
  });

  /// Number of spaces inserted when the editor handles a Tab key press.
  final int tabSize;

  /// Syntax highlighting theme used by editor tabs.
  final String themeName;

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

  static const GeneralSettings defaults = GeneralSettings();

  factory GeneralSettings.fromJson(Map<String, Object?> json) =>
      GeneralSettingsMapper.fromMap(Map<String, dynamic>.from(json));
}

@MappableClass()
class AgentSettings with AgentSettingsMappable {
  const AgentSettings({
    this.agentStatusHooks = AgentStatusHookSettings.defaults,
    this.agentStatusNotificationsEnabled = false,
    this.keepComputerAwakeWhileAgentsWork = false,
    this.quotas = AgentQuotaSettings.defaults,
  });

  /// Install managed agent hooks for terminal status. Each agent is
  /// default-off because enabling it writes into that agent's user config area.
  final AgentStatusHookSettings agentStatusHooks;

  /// Show native desktop notifications for local agent status events.
  final bool agentStatusNotificationsEnabled;

  /// Keep the local computer awake while local hook-reported agents are working.
  final bool keepComputerAwakeWhileAgentsWork;

  /// Per-host quota providers, Claude CCS profiles, and environment names.
  final AgentQuotaSettings quotas;

  static const AgentSettings defaults = AgentSettings();

  factory AgentSettings.fromJson(Map<String, Object?> json) =>
      AgentSettingsMapper.fromMap(Map<String, dynamic>.from(json));
}

@MappableEnum()
enum AgentQuotaProviderId {
  claude,
  codex,
  kimi,
  grok,
  cursor,
  antigravity,
  minimax,
  zai,
}

extension AgentQuotaProviderIdLabel on AgentQuotaProviderId {
  String get label => switch (this) {
    AgentQuotaProviderId.claude => 'Claude Code',
    AgentQuotaProviderId.codex => 'Codex',
    AgentQuotaProviderId.kimi => 'Kimi',
    AgentQuotaProviderId.grok => 'Grok Build',
    AgentQuotaProviderId.cursor => 'Cursor',
    AgentQuotaProviderId.antigravity => 'Antigravity',
    AgentQuotaProviderId.minimax => 'MiniMax',
    AgentQuotaProviderId.zai => 'Z.ai',
  };
}

@MappableClass()
class ClaudeQuotaProfileSettings with ClaudeQuotaProfileSettingsMappable {
  const ClaudeQuotaProfileSettings({
    required this.alias,
    required this.profile,
  });

  final String alias;
  final String profile;

  factory ClaudeQuotaProfileSettings.fromJson(Map<String, Object?> json) =>
      ClaudeQuotaProfileSettingsMapper.fromMap(Map<String, dynamic>.from(json));
}

@MappableClass()
class AgentQuotaEnvironmentSettings with AgentQuotaEnvironmentSettingsMappable {
  const AgentQuotaEnvironmentSettings({
    this.kimiApiKey = 'KIMI_API_KEY',
    this.zaiApiKey = 'ZAI_API_KEY',
    this.zaiBaseUrl = 'ZAI_BASE_URL',
    this.minimaxApiKey = 'MINIMAX_API_KEY',
    this.minimaxApiHost = 'MINIMAX_API_HOST',
  });

  final String kimiApiKey;
  final String zaiApiKey;
  final String zaiBaseUrl;
  final String minimaxApiKey;
  final String minimaxApiHost;

  static const AgentQuotaEnvironmentSettings defaults =
      AgentQuotaEnvironmentSettings();

  factory AgentQuotaEnvironmentSettings.fromJson(Map<String, Object?> json) =>
      AgentQuotaEnvironmentSettingsMapper.fromMap(
        Map<String, dynamic>.from(json),
      );
}

@MappableClass()
class AgentQuotaHostSettings with AgentQuotaHostSettingsMappable {
  const AgentQuotaHostSettings({
    this.enabledProviders = AgentQuotaProviderId.values,
    this.claudeDefaultEnabled = true,
    this.claudeProfiles = const <ClaudeQuotaProfileSettings>[],
    this.selectedClaudeProfile = 'default',
    this.environment = AgentQuotaEnvironmentSettings.defaults,
  });

  final List<AgentQuotaProviderId> enabledProviders;
  final bool claudeDefaultEnabled;
  final List<ClaudeQuotaProfileSettings> claudeProfiles;
  final String selectedClaudeProfile;
  final AgentQuotaEnvironmentSettings environment;

  static const AgentQuotaHostSettings defaults = AgentQuotaHostSettings();

  factory AgentQuotaHostSettings.fromJson(Map<String, Object?> json) =>
      AgentQuotaHostSettingsMapper.fromMap(Map<String, dynamic>.from(json));
}

@MappableClass()
class AgentQuotaSettings with AgentQuotaSettingsMappable {
  const AgentQuotaSettings({
    this.hosts = const <String, AgentQuotaHostSettings>{},
  });

  final Map<String, AgentQuotaHostSettings> hosts;

  static const AgentQuotaSettings defaults = AgentQuotaSettings();

  AgentQuotaHostSettings forHost(String hostId) =>
      hosts[hostId] ?? AgentQuotaHostSettings.defaults;

  AgentQuotaSettings withHost(String hostId, AgentQuotaHostSettings settings) {
    return copyWith(
      hosts: <String, AgentQuotaHostSettings>{...hosts, hostId: settings},
    );
  }

  factory AgentQuotaSettings.fromJson(Map<String, Object?> json) =>
      AgentQuotaSettingsMapper.fromMap(Map<String, dynamic>.from(json));
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

@MappableClass(hook: _LegacyAgentSettingsHook())
class AleraSettings with AleraSettingsMappable {
  const AleraSettings({
    required this.general,
    this.agents = AgentSettings.defaults,
    this.aiTextGeneration = AiTextGenerationSettings.defaults,
    this.editor = EditorSettings.defaults,
    required this.terminal,
    required this.keyboard,
  });

  final GeneralSettings general;
  final AgentSettings agents;
  final AiTextGenerationSettings aiTextGeneration;
  final EditorSettings editor;
  final TerminalSettings terminal;
  final KeyboardShortcutSettings keyboard;

  static const AleraSettings defaults = AleraSettings(
    general: GeneralSettings.defaults,
    agents: AgentSettings.defaults,
    aiTextGeneration: AiTextGenerationSettings.defaults,
    editor: EditorSettings.defaults,
    terminal: TerminalSettings.defaults,
    keyboard: KeyboardShortcutSettings.defaults,
  );

  factory AleraSettings.fromJson(Map<String, Object?> json) =>
      AleraSettingsMapper.fromMap(Map<String, dynamic>.from(json));
}
