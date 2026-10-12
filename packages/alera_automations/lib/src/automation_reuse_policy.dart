import 'package:alera_automations/src/automation_models.dart';

/// Runtime capability that gates `reusePolicy`, `boundTarget` and
/// `automation.unbind`. A runtime without it ignores the policy, so clients
/// hide the control rather than send it.
const String automationReuseCapability = 'automationReuseV1';

/// Where runs after the first one are delivered. An absent wire value means
/// [newEachRun].
enum AutomationReusePolicy(
  final String wireValue,
  final String label,
  final String description,
) {
  newEachRun(
    'newEachRun',
    'New Each Run',
    'Every run starts in a new destination.',
  ),
  reuseWorkspace(
    'reuseWorkspace',
    'Reuse Workspace',
    'Later runs open a new agent tab in the workspace the first run created.',
  ),
  reuseConversation(
    'reuseConversation',
    'Reuse Conversation',
    'Later runs continue the same agent conversation while it is available.',
  );

  bool get reuses => this != newEachRun;

  static AutomationReusePolicy parse(Object? value) {
    for (final policy in values) {
      if (policy.wireValue == value) return policy;
    }
    return newEachRun;
  }
}

/// Label shown instead of a choice when the target already decides the
/// policy: a conversation target always continues that conversation.
const String automationContinuesConversationLabel = 'Continues Conversation';

/// The policies that make sense for [type]. The runtime rejects Reuse
/// Workspace for an existing tab; a fresh tab has no workspace of its own to
/// return to, so only the conversation can be reused.
List<AutomationReusePolicy> applicableReusePolicies(
  AutomationTargetType? type,
) => switch (type) {
  null ||
  AutomationTargetType.worktree ||
  AutomationTargetType.projectCheckout => AutomationReusePolicy.values,
  AutomationTargetType.freshTab => const <AutomationReusePolicy>[
    .newEachRun,
    .reuseConversation,
  ],
  AutomationTargetType.existingTab => const <AutomationReusePolicy>[
    .reuseConversation,
  ],
};

/// Whether [type] fixes the policy so the user has nothing to choose.
bool automationReusePolicyIsFixed(AutomationTargetType? type) =>
    applicableReusePolicies(type).length == 1;
