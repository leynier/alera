import 'package:alera_automations/src/automation_json_fields.dart';

/// The workspace, and for conversation reuse the tab, a reusing automation
/// returns to. The runtime writes it after a dispatch; clients only read it
/// and clear it through `automation.unbind`.
class const AutomationBoundTarget({
  required final String workspaceId,
  required final String boundRunId,
  required final DateTime? boundAt,
  final String? tabId,
  final String? conversationId,
  final String? agentProfileId,
  final String? lastRunId,
  final DateTime? lastVerifiedAt,
}) {
  static AutomationBoundTarget? tryParse(Object? value) {
    if (value is! Map) return null;
    final map = automationJsonMap(value);
    final workspaceId = automationJsonOptionalString(map['workspaceId']);
    if (workspaceId == null) return null;
    return AutomationBoundTarget(
      workspaceId: workspaceId,
      boundRunId: automationJsonString(map['boundRunId']),
      boundAt: automationJsonDate(map['boundAt']),
      tabId: automationJsonOptionalString(map['tabId']),
      conversationId: automationJsonOptionalString(map['conversationId']),
      agentProfileId: automationJsonOptionalString(map['agentProfileId']),
      lastRunId: automationJsonOptionalString(map['lastRunId']),
      lastVerifiedAt: automationJsonDate(map['lastVerifiedAt']),
    );
  }

  bool get hasTab => tabId != null;
}

/// How one run reached its target under a reuse policy. Absent on runs that
/// did not reuse anything.
enum AutomationRunReuse(final String wireValue, final String label) {
  bound('bound', 'Bound The Automation'),
  conversation('conversation', 'Continued Conversation'),
  resumedConversation('resumedConversation', 'Resumed Conversation'),
  workspace('workspace', 'Reused Workspace');

  static AutomationRunReuse? tryParse(Object? value) {
    for (final reuse in values) {
      if (reuse.wireValue == value) return reuse;
    }
    return null;
  }
}
