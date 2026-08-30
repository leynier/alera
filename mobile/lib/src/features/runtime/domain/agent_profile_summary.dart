import 'package:alera_mobile/src/core/json_payload_fields.dart';

class const AgentProfileSummary({
  required final String id,
  required final String name,
  required final String agentType,
}) {
  factory fromJson(Map<String, Object?> json) {
    return AgentProfileSummary(
      id: json.requiredString('id'),
      name: json.requiredString('name'),
      agentType: json.requiredString('agentType'),
    );
  }
}

class const GeneratedWorkspaceIdentity({
  required final String workspaceName,
  required final String branchName,
});

class const AgentProfileLaunchResult({
  required final String tabId,
  required final String agentType,
});
