import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';

/// A native rewind the runtime has not finished or could not confirm. It
/// names the operation, repeats the runtime's sentence, and offers exactly
/// the recovery actions the runtime allows; each asks first and none runs on
/// its own. While [busy] (a choice is on its way) every action is disabled,
/// so a choice is never sent twice.
class const AgentChatNativeOperationNotice({
  super.key,
  required final AgentChatNativeOperation operation,
  required final bool enabled,
  required final bool busy,
  required final ValueChanged<AgentChatNativeHistoryAction> onAction,
}) extends StatelessWidget {
  Future<void> _choose(
    BuildContext context,
    AgentChatNativeHistoryAction action,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AleraConfirmDialog(
        title: '${agentChatNativeOperationActionLabel(action)}?',
        message: agentChatNativeOperationActionDescription(action),
        confirmLabel: agentChatNativeOperationActionLabel(action),
        destructive:
            action == AgentChatNativeHistoryAction.restartFromTranscript,
      ),
    );
    if (confirmed ?? false) onAction(action);
  }

  @override
  Widget build(BuildContext context) {
    final actions = agentChatNativeOperationActions(operation);
    final decide = operation.recovery?.needsReconciliation ?? false;
    final ready = enabled && !busy;
    return AleraInlineNotice(
      key: ValueKey<String>(
        'agent-chat-native-operation-${operation.operationId}',
      ),
      tone: decide ? AleraInlineNoticeTone.warning : AleraInlineNoticeTone.info,
      message:
          '${agentChatNativeOperationTitle(operation)}. '
          '${agentChatNativeOperationMessage(operation)}',
      maxLines: 4,
      child: actions.isEmpty && !busy
          ? null
          : Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AleraTokens.space8,
              runSpacing: AleraTokens.space4,
              children: <Widget>[
                if (busy)
                  const SizedBox.square(
                    dimension: AleraTokens.iconMd,
                    child: CircularProgressIndicator(
                      strokeWidth: AleraTokens.strokeSm,
                    ),
                  ),
                for (final (index, action) in actions.indexed)
                  if (index == 0)
                    FilledButton(
                      key: ValueKey<String>(
                        'agent-chat-native-action-${action.wire}',
                      ),
                      onPressed: ready
                          ? () => unawaited(_choose(context, action))
                          : null,
                      child: Text(agentChatNativeOperationActionLabel(action)),
                    )
                  else
                    TextButton(
                      key: ValueKey<String>(
                        'agent-chat-native-action-${action.wire}',
                      ),
                      onPressed: ready
                          ? () => unawaited(_choose(context, action))
                          : null,
                      child: Text(agentChatNativeOperationActionLabel(action)),
                    ),
              ],
            ),
    );
  }
}
