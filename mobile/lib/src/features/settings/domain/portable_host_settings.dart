import 'package:alera_mobile/src/core/json_payload_fields.dart';
import 'package:alera_mobile/src/features/quotas/domain/quota_settings.dart';

const List<String> supportedAgentHooks = <String>[
  'codex',
  'claude',
  'copilot',
  'cursor',
  'agy',
  'opencode',
  'pi',
  'amp',
  'grok',
];

const Map<String, String> agentHookLabels = <String, String>{
  'codex': 'Codex',
  'claude': 'Claude Code',
  'copilot': 'GitHub Copilot',
  'cursor': 'Cursor',
  'agy': 'Antigravity',
  'opencode': 'OpenCode',
  'pi': 'Pi',
  'amp': 'Amp',
  'grok': 'Grok Build',
};

class PortableHostSettings {
  const PortableHostSettings({
    required this.workspaceDirectory,
    required this.confirmProjectRemoval,
    required this.confirmWorkspaceRemoval,
    required this.agentStatusHooks,
    required this.agentQuotas,
  });

  factory PortableHostSettings.fromJson(Map<String, Object?> json) {
    final hooks = json.mapValue('agentStatusHooks');
    return PortableHostSettings(
      workspaceDirectory: json['workspaceDirectory'] as String?,
      confirmProjectRemoval: json['confirmProjectRemoval'] != false,
      confirmWorkspaceRemoval: json['confirmWorkspaceRemoval'] != false,
      agentStatusHooks: <String, bool>{
        for (final agent in supportedAgentHooks) agent: hooks[agent] == true,
      },
      agentQuotas: QuotaSettings.fromJson(json.mapValue('agentQuotas')),
    );
  }

  final String? workspaceDirectory;
  final bool confirmProjectRemoval;
  final bool confirmWorkspaceRemoval;
  final Map<String, bool> agentStatusHooks;
  final QuotaSettings agentQuotas;

  PortableHostSettings copyWith({
    String? workspaceDirectory,
    bool clearWorkspaceDirectory = false,
    bool? confirmProjectRemoval,
    bool? confirmWorkspaceRemoval,
    Map<String, bool>? agentStatusHooks,
    QuotaSettings? agentQuotas,
  }) {
    return PortableHostSettings(
      workspaceDirectory: clearWorkspaceDirectory
          ? null
          : workspaceDirectory ?? this.workspaceDirectory,
      confirmProjectRemoval:
          confirmProjectRemoval ?? this.confirmProjectRemoval,
      confirmWorkspaceRemoval:
          confirmWorkspaceRemoval ?? this.confirmWorkspaceRemoval,
      agentStatusHooks: agentStatusHooks ?? this.agentStatusHooks,
      agentQuotas: agentQuotas ?? this.agentQuotas,
    );
  }
}

class CliRegistrationStatus {
  const CliRegistrationStatus({
    required this.state,
    required this.ready,
    required this.pathConfigured,
    required this.detail,
    this.commandPath,
  });

  factory CliRegistrationStatus.fromJson(Map<String, Object?> json) {
    return CliRegistrationStatus(
      state: json['state'] as String? ?? 'unsupported',
      ready: json['ready'] == true,
      pathConfigured: json['pathConfigured'] == true,
      detail: json['detail'] as String? ?? 'CLI status unavailable.',
      commandPath: json['commandPath'] as String?,
    );
  }

  final String state;
  final bool ready;
  final bool pathConfigured;
  final String detail;
  final String? commandPath;
}

class SkillInstallResult {
  const SkillInstallResult({required this.succeeded, required this.summary});

  factory SkillInstallResult.fromJson(Map<String, Object?> json) {
    return SkillInstallResult(
      succeeded: json['succeeded'] == true,
      summary: json['summary'] as String? ?? 'Skill install failed.',
    );
  }

  final bool succeeded;
  final String summary;
}
