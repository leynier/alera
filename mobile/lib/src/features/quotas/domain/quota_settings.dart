import 'package:alera_mobile/src/core/json_payload_fields.dart';

const List<String> supportedQuotaProviders = <String>[
  'claude',
  'codex',
  'kimi',
  'grok',
  'antigravity',
  'minimax',
  'zai',
];

const Map<String, String> quotaProviderLabels = <String, String>{
  'claude': 'Claude Code',
  'codex': 'Codex',
  'kimi': 'Kimi',
  'grok': 'Grok Build',
  'antigravity': 'Antigravity',
  'minimax': 'MiniMax',
  'zai': 'Z.ai',
};

class QuotaSettings {
  const QuotaSettings({
    required this.enabledProviders,
    required this.claudeDefaultEnabled,
    required this.claudeProfiles,
    required this.environment,
  });

  factory QuotaSettings.fromJson(Map<String, Object?> json) {
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
      environment: QuotaEnvironment.fromJson(json.mapValue('environment')),
    );
  }

  final List<String> enabledProviders;
  final bool claudeDefaultEnabled;
  final List<ClaudeQuotaProfile> claudeProfiles;
  final QuotaEnvironment environment;

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

class ClaudeQuotaProfile {
  const ClaudeQuotaProfile({required this.alias, required this.profile});

  factory ClaudeQuotaProfile.fromJson(Map<String, Object?> json) {
    return ClaudeQuotaProfile(
      alias: json['alias'] as String? ?? '',
      profile: json['profile'] as String? ?? '',
    );
  }

  final String alias;
  final String profile;

  Map<String, String> toJson() => <String, String>{
    'alias': alias,
    'profile': profile,
  };
}

class QuotaEnvironment {
  const QuotaEnvironment({
    this.kimiApiKey = 'KIMI_API_KEY',
    this.zaiApiKey = 'ZAI_API_KEY',
    this.zaiBaseUrl = 'ZAI_BASE_URL',
    this.minimaxApiKey = 'MINIMAX_API_KEY',
    this.minimaxApiHost = 'MINIMAX_API_HOST',
  });

  factory QuotaEnvironment.fromJson(Map<String, Object?> json) {
    return QuotaEnvironment(
      kimiApiKey: json['kimiApiKey'] as String? ?? 'KIMI_API_KEY',
      zaiApiKey: json['zaiApiKey'] as String? ?? 'ZAI_API_KEY',
      zaiBaseUrl: json['zaiBaseUrl'] as String? ?? 'ZAI_BASE_URL',
      minimaxApiKey: json['minimaxApiKey'] as String? ?? 'MINIMAX_API_KEY',
      minimaxApiHost: json['minimaxApiHost'] as String? ?? 'MINIMAX_API_HOST',
    );
  }

  final String kimiApiKey;
  final String zaiApiKey;
  final String zaiBaseUrl;
  final String minimaxApiKey;
  final String minimaxApiHost;

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
