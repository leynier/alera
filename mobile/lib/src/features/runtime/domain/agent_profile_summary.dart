import 'package:alera_mobile/src/core/json_payload_fields.dart';

class AgentProfileSummary {
  const AgentProfileSummary({
    required this.id,
    required this.name,
    required this.agentType,
  });

  final String id;
  final String name;
  final String agentType;

  factory AgentProfileSummary.fromJson(Map<String, Object?> json) {
    return AgentProfileSummary(
      id: json.requiredString('id'),
      name: json.requiredString('name'),
      agentType: json.requiredString('agentType'),
    );
  }
}

class GeneratedWorkspaceIdentity {
  const GeneratedWorkspaceIdentity({
    required this.workspaceName,
    required this.branchName,
  });

  final String workspaceName;
  final String branchName;
}

class AgentProfileLaunchResult {
  const AgentProfileLaunchResult({
    required this.tabId,
    required this.agentType,
  });

  final String tabId;
  final String agentType;
}
