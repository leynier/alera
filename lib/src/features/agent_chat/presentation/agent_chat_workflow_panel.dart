import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_workflow_dialogs.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_workflow_phases.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_workflow_scope.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';

/// Opens a member of the workflow [callId] started, or `null` outside a
/// chat's workflow scope.
ValueChanged<AgentChatWorkflowMember>? agentChatWorkflowMemberOpener(
  BuildContext context,
  String callId,
) {
  final scope = AgentChatWorkflowScope.maybeOf(context);
  if (scope == null) return null;
  return (member) => showAgentChatWorkflowMember(
    context,
    chatId: scope.chatId,
    workspaceId: scope.workspaceId,
    callId: callId,
    member: member,
    readable: scope.readable,
  );
}

/// A workflow opened on its own: how its run is going, its usage, its
/// script and its phases, whose members open on a press.
class const AgentChatWorkflowPanel({
  super.key,
  required final String callId,
  required final AgentChatWorkflowGroup group,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scope = AgentChatWorkflowScope.maybeOf(context);
    final usage = group.usage;
    final failed =
        group.status == AgentChatSubagentStatus.failed ||
        group.summary.endsWith('failed');
    return Container(
      key: ValueKey<String>('agent-chat-workflow-panel-$callId'),
      margin: const EdgeInsets.only(bottom: AleraTokens.space12),
      padding: const EdgeInsets.all(AleraTokens.space8),
      decoration: BoxDecoration(
        color: AleraTokens.surface,
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(AleraIcons.workflow, size: AleraTokens.iconMd),
              const SizedBox(width: AleraTokens.space6),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      TextSpan(text: group.lead),
                      TextSpan(
                        text: ' · ${group.summary}',
                        style: TextStyle(
                          color: failed
                              ? AleraTokens.error
                              : AleraTokens.foregroundMuted,
                        ),
                      ),
                    ],
                  ),
                  style: theme.textTheme.bodySmall,
                ),
              ),
              if (scope != null &&
                  scope.readable &&
                  group.workflow.scriptPath != null)
                TextButton.icon(
                  key: const ValueKey<String>(
                    'agent-chat-workflow-view-script',
                  ),
                  onPressed: () => showAgentChatWorkflowScript(
                    context,
                    chatId: scope.chatId,
                    workspaceId: scope.workspaceId,
                    callId: callId,
                  ),
                  icon: const Icon(AleraIcons.code, size: AleraTokens.iconMd),
                  label: const Text('View Script'),
                ),
            ],
          ),
          if (usage != null)
            Padding(
              padding: const EdgeInsets.only(
                left: AleraTokens.space20,
                bottom: AleraTokens.space4,
              ),
              child: Text(
                usage,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AleraTokens.foregroundFaint,
                ),
              ),
            ),
          AgentChatWorkflowPhases(
            group: group,
            onOpenMember: agentChatWorkflowMemberOpener(context, callId),
          ),
        ],
      ),
    );
  }
}
