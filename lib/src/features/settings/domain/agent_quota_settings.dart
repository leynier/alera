part of 'alera_settings.dart';

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
  opencode,
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
    AgentQuotaProviderId.opencode => 'OpenCode',
  };
}

@MappableClass()
class const ClaudeQuotaProfileSettings({
  required this.alias,
  required this.profile,
  this.showInUsage = true,
  this.usageDisplayName,
}) with ClaudeQuotaProfileSettingsMappable {
  final String alias;
  final String profile;
  final bool showInUsage;
  final String? usageDisplayName;

  String get usageLabel {
    final configured = usageDisplayName?.trim();
    return configured == null || configured.isEmpty ? alias : configured;
  }

  factory fromJson(Map<String, Object?> json) =>
      ClaudeQuotaProfileSettingsMapper.fromMap(Map<String, dynamic>.from(json));
}

@MappableClass()
class const AgentQuotaEnvironmentSettings({
  this.kimiApiKey = 'KIMI_API_KEY',
  this.zaiApiKey = 'ZAI_API_KEY',
  this.zaiBaseUrl = 'ZAI_BASE_URL',
  this.minimaxApiKey = 'MINIMAX_API_KEY',
  this.minimaxApiHost = 'MINIMAX_API_HOST',
}) with AgentQuotaEnvironmentSettingsMappable {
  final String kimiApiKey;
  final String zaiApiKey;
  final String zaiBaseUrl;
  final String minimaxApiKey;
  final String minimaxApiHost;

  static const AgentQuotaEnvironmentSettings defaults =
      AgentQuotaEnvironmentSettings();

  factory fromJson(Map<String, Object?> json) =>
      AgentQuotaEnvironmentSettingsMapper.fromMap(
        Map<String, dynamic>.from(json),
      );
}

@MappableClass()
class const AgentQuotaHostSettings({
  this.enabledProviders = AgentQuotaProviderId.values,
  this.claudeDefaultEnabled = true,
  this.claudeDefaultShowInUsage = true,
  this.claudeProfiles = const <ClaudeQuotaProfileSettings>[],
  this.selectedClaudeProfile = 'default',
  this.environment = AgentQuotaEnvironmentSettings.defaults,
  this.unpinnedQuotaKeys = const <String>[],
}) with AgentQuotaHostSettingsMappable {
  final List<AgentQuotaProviderId> enabledProviders;
  final bool claudeDefaultEnabled;
  final bool claudeDefaultShowInUsage;
  final List<ClaudeQuotaProfileSettings> claudeProfiles;
  final String selectedClaudeProfile;
  final AgentQuotaEnvironmentSettings environment;

  /// Quotas hidden from the status bar (still visible in the overview panel).
  /// Absence means pinned, so older settings blobs keep today's behavior.
  final List<String> unpinnedQuotaKeys;

  static const AgentQuotaHostSettings defaults = AgentQuotaHostSettings();

  /// Stable pin key: provider name for single-account providers, and
  /// `provider:<accountId>` for providers with multiple accounts.
  static String quotaPinKey(
    AgentQuotaProviderId provider, {
    String claudeAccountId = 'default',
  }) {
    if (provider == AgentQuotaProviderId.claude ||
        provider == AgentQuotaProviderId.opencode) {
      return '${provider.name}:$claudeAccountId';
    }
    return provider.name;
  }

  bool isQuotaPinned(
    AgentQuotaProviderId provider, {
    String claudeAccountId = 'default',
  }) {
    return !unpinnedQuotaKeys.contains(
      quotaPinKey(provider, claudeAccountId: claudeAccountId),
    );
  }

  factory fromJson(Map<String, Object?> json) =>
      AgentQuotaHostSettingsMapper.fromMap(Map<String, dynamic>.from(json));
}

@MappableClass()
class const AgentQuotaSettings({
  this.hosts = const <String, AgentQuotaHostSettings>{},
}) with AgentQuotaSettingsMappable {
  final Map<String, AgentQuotaHostSettings> hosts;

  static const AgentQuotaSettings defaults = AgentQuotaSettings();

  AgentQuotaHostSettings forHost(String hostId) =>
      hosts[hostId] ?? AgentQuotaHostSettings.defaults;

  AgentQuotaSettings withHost(String hostId, AgentQuotaHostSettings settings) {
    return copyWith(
      hosts: <String, AgentQuotaHostSettings>{...hosts, hostId: settings},
    );
  }

  factory fromJson(Map<String, Object?> json) =>
      AgentQuotaSettingsMapper.fromMap(Map<String, dynamic>.from(json));
}
