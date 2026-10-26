import 'package:alera_mobile/src/core/json_payload_fields.dart';
import 'package:alera_mobile/src/features/quotas/domain/quota_settings.dart';
import 'package:alera_mobile/src/features/voice/domain/mobile_voice_settings.dart';

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
  'fx',
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
  'fx': 'fx',
};

class const PortableHostSettings({
  required final String? workspaceDirectory,
  required final bool confirmProjectRemoval,
  required final bool confirmWorkspaceRemoval,

  /// Null when the host predates the setting and would reject an update.
  final bool? deleteAgentSessionsOnWorkspaceRemoval,
  required final Map<String, bool> agentStatusHooks,
  required final QuotaSettings agentQuotas,
  required final MobileVoiceSettings voice,
}) {
  factory fromJson(Map<String, Object?> json) {
    final hooks = json.mapValue('agentStatusHooks');
    return PortableHostSettings(
      workspaceDirectory: json['workspaceDirectory'] as String?,
      confirmProjectRemoval: json['confirmProjectRemoval'] != false,
      confirmWorkspaceRemoval: json['confirmWorkspaceRemoval'] != false,
      deleteAgentSessionsOnWorkspaceRemoval:
          json['deleteAgentSessionsOnWorkspaceRemoval'] as bool?,
      agentStatusHooks: <String, bool>{
        for (final agent in supportedAgentHooks)
          agent:
              hooks[agent] == true ||
              // OpenCode v1 and OpenCode 2 share one toggle now; a runtime
              // may still report the retired `opencode2` one.
              (agent == 'opencode' && hooks['opencode2'] == true),
      },
      agentQuotas: .fromJson(json.mapValue('agentQuotas')),
      voice: MobileVoiceSettings.fromJson(json.mapValue('voice')),
    );
  }

  PortableHostSettings copyWith({
    String? workspaceDirectory,
    bool clearWorkspaceDirectory = false,
    bool? confirmProjectRemoval,
    bool? confirmWorkspaceRemoval,
    bool? deleteAgentSessionsOnWorkspaceRemoval,
    Map<String, bool>? agentStatusHooks,
    QuotaSettings? agentQuotas,
    MobileVoiceSettings? voice,
  }) {
    return PortableHostSettings(
      workspaceDirectory: clearWorkspaceDirectory
          ? null
          : workspaceDirectory ?? this.workspaceDirectory,
      confirmProjectRemoval:
          confirmProjectRemoval ?? this.confirmProjectRemoval,
      confirmWorkspaceRemoval:
          confirmWorkspaceRemoval ?? this.confirmWorkspaceRemoval,
      deleteAgentSessionsOnWorkspaceRemoval:
          deleteAgentSessionsOnWorkspaceRemoval ??
          this.deleteAgentSessionsOnWorkspaceRemoval,
      agentStatusHooks: agentStatusHooks ?? this.agentStatusHooks,
      agentQuotas: agentQuotas ?? this.agentQuotas,
      voice: voice ?? this.voice,
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
