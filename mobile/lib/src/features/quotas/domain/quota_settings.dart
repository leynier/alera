import 'package:alera_mobile/src/core/json_payload_fields.dart';

const List<String> supportedQuotaProviders = <String>[
  'claude',
  'codex',
  'kimi',
  'grok',
  'cursor',
  'antigravity',
  'minimax',
  'zai',
  'opencode',
];

const Map<String, String> quotaProviderLabels = <String, String>{
  'claude': 'Claude Code',
  'codex': 'Codex',
  'kimi': 'Kimi',
  'grok': 'Grok Build',
  'cursor': 'Cursor',
  'antigravity': 'Antigravity',
  'minimax': 'MiniMax',
  'zai': 'Z.ai',
  'opencode': 'OpenCode',
};

class const QuotaSettings({
  required final List<String> enabledProviders,
  required final bool claudeDefaultEnabled,
  required final List<ClaudeQuotaProfile> claudeProfiles,
  required final QuotaEnvironment environment,
}) {
  factory fromJson(Map<String, Object?> json) {
    final providers = json.containsKey('enabledProviders')
        ? json.stringList('enabledProviders')
        : supportedQuotaProviders;
    return QuotaSettings(
      enabledProviders: providers
          .where(supportedQuotaProviders.contains)
          .toList(growable: false),
      claudeDefaultEnabled: json['claudeDefaultEnabled'] != false,
      claudeProfiles: <ClaudeQuotaProfile>[
        for (final item in json.objectList('claudeProfiles'))
          if (item is Map) ClaudeQuotaProfile.fromJson(asJsonMap(item)),
      ],
      environment: .fromJson(json.mapValue('environment')),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'enabledProviders': enabledProviders,
    'claudeDefaultEnabled': claudeDefaultEnabled,
    'claudeProfiles': <Map<String, String>>[
      for (final profile in claudeProfiles) profile.toJson(),
    ],
    'environment': environment.toJson(),
  };

  QuotaSettings copyWith({
    List<String>? enabledProviders,
    bool? claudeDefaultEnabled,
    List<ClaudeQuotaProfile>? claudeProfiles,
    QuotaEnvironment? environment,
  }) {
    return QuotaSettings(
      enabledProviders: enabledProviders ?? this.enabledProviders,
      claudeDefaultEnabled: claudeDefaultEnabled ?? this.claudeDefaultEnabled,
      claudeProfiles: claudeProfiles ?? this.claudeProfiles,
      environment: environment ?? this.environment,
    );
  }
}

class const ClaudeQuotaProfile({
  required final String alias,
  required final String profile,
}) {
  factory fromJson(Map<String, Object?> json) {
    return ClaudeQuotaProfile(
      alias: json['alias'] as String? ?? '',
      profile: json['profile'] as String? ?? '',
    );
  }

  Map<String, String> toJson() => <String, String>{
    'alias': alias,
    'profile': profile,
  };
}

class const QuotaEnvironment({
  final String kimiApiKey = 'KIMI_API_KEY',
  final String zaiApiKey = 'ZAI_API_KEY',
  final String zaiBaseUrl = 'ZAI_BASE_URL',
  final String minimaxApiKey = 'MINIMAX_API_KEY',
  final String minimaxApiHost = 'MINIMAX_API_HOST',
}) {
  factory fromJson(Map<String, Object?> json) {
    return QuotaEnvironment(
      kimiApiKey: json['kimiApiKey'] as String? ?? 'KIMI_API_KEY',
      zaiApiKey: json['zaiApiKey'] as String? ?? 'ZAI_API_KEY',
      zaiBaseUrl: json['zaiBaseUrl'] as String? ?? 'ZAI_BASE_URL',
      minimaxApiKey: json['minimaxApiKey'] as String? ?? 'MINIMAX_API_KEY',
      minimaxApiHost: json['minimaxApiHost'] as String? ?? 'MINIMAX_API_HOST',
    );
  }

  Map<String, String> toJson() => <String, String>{
    'kimiApiKey': kimiApiKey,
    'zaiApiKey': zaiApiKey,
    'zaiBaseUrl': zaiBaseUrl,
    'minimaxApiKey': minimaxApiKey,
    'minimaxApiHost': minimaxApiHost,
  };

  QuotaEnvironment copyWith({
    String? kimiApiKey,
    String? zaiApiKey,
    String? zaiBaseUrl,
    String? minimaxApiKey,
    String? minimaxApiHost,
  }) {
    return QuotaEnvironment(
      kimiApiKey: kimiApiKey ?? this.kimiApiKey,
      zaiApiKey: zaiApiKey ?? this.zaiApiKey,
      zaiBaseUrl: zaiBaseUrl ?? this.zaiBaseUrl,
      minimaxApiKey: minimaxApiKey ?? this.minimaxApiKey,
      minimaxApiHost: minimaxApiHost ?? this.minimaxApiHost,
    );
  }
}
