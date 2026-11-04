import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';

/// Loading, Update Required or unavailable, for a Chat Tasks read with
/// nothing to show yet. A runtime without `chatOrchestrationV1` gets Update
/// Required, never a fallback.
class const ChatTaskReadState({
  super.key,
  final Object? error,
  required final VoidCallback onRefresh,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final incompatible = error is AgentChatOrchestrationUpdateRequired;
    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space16),
      child: Column(
        crossAxisAlignment: .start,
        children: <Widget>[
          Text(
            error == null
                ? 'Loading'
                : incompatible
                ? 'Update Required'
                : 'Chat Tasks Unavailable',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: AleraTokens.space8),
          Text(
            error == null
                ? 'Waiting for the runtime.'
                : agentChatOrchestrationErrorMessage(error!),
          ),
          if (error != null && !incompatible) ...<Widget>[
            const SizedBox(height: AleraTokens.space12),
            OutlinedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(AleraIcons.refresh, size: AleraTokens.iconMd),
              label: const Text('Refresh'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Shown above a list kept from before the connection dropped.
class const ChatTaskStaleNotice({
  super.key,
  required final VoidCallback onRefresh,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AleraTokens.space8),
    child: AleraInlineNotice(
      message: 'This list may be out of date until the runtime reconnects.',
      tone: .warning,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton(onPressed: onRefresh, child: const Text('Refresh')),
      ),
    ),
  );
}
