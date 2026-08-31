import 'package:alera_mobile/src/core/json_payload_fields.dart';
import 'package:alera_mobile/src/features/quotas/domain/quota_settings.dart';

const List<String> supportedAgentHooks = <String>[
  'codex',
  'claude',
  'copilot',
  'cursor',
  'agy',
  'opencode',
  'opencode2',
  'pi',
  'amp',
  'grok',
  'fx',
];

const Map<String, String> agentHookLabels = <String, String>{
  'codex': 'Codex',
  'claude': 'Claude Code',
  'copilot': 'GitHub Copilot',
  'cursor': 'Cursor',
  'agy': 'Antigravity',
  'opencode': 'OpenCode',
  'opencode2': 'OpenCode 2',
  'pi': 'Pi',
  'amp': 'Amp',
  'grok': 'Grok Build',
  'fx': 'fx',
};

class const PortableHostSettings({
  required final String? workspaceDirectory,
  required final bool confirmProjectRemoval,
  required final bool confirmWorkspaceRemoval,
  required final Map<String, bool> agentStatusHooks,
  required final QuotaSettings agentQuotas,
}) {
  factory fromJson(Map<String, Object?> json) {
    final hooks = json.mapValue('agentStatusHooks');
    return PortableHostSettings(
      workspaceDirectory: json['workspaceDirectory'] as String?,
      confirmProjectRemoval: json['confirmProjectRemoval'] != false,
      confirmWorkspaceRemoval: json['confirmWorkspaceRemoval'] != false,
      agentStatusHooks: <String, bool>{
        for (final agent in supportedAgentHooks) agent: hooks[agent] == true,
      },
      agentQuotas: .fromJson(json.mapValue('agentQuotas')),
    );
  }

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

class const CliRegistrationStatus({
  required final String state,
  required final bool ready,
  required final bool pathConfigured,
  required final String detail,
  final String? commandPath,
}) {
  factory fromJson(Map<String, Object?> json) {
    return CliRegistrationStatus(
      state: json['state'] as String? ?? 'unsupported',
      ready: json['ready'] == true,
      pathConfigured: json['pathConfigured'] == true,
      detail: json['detail'] as String? ?? 'CLI status unavailable.',
      commandPath: json['commandPath'] as String?,
    );
  }
}

class const SkillInstallResult({
  required final bool succeeded,
  required final String summary,
}) {
  factory fromJson(Map<String, Object?> json) {
    return SkillInstallResult(
      succeeded: json['succeeded'] == true,
      summary: json['summary'] as String? ?? 'Skill install failed.',
    );
  }
}
