import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/design_system/layout/alera_dialog_header.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';

/// Asks what the agent should do instead of the request being declined.
/// Returns the feedback, or null when dismissed.
Future<String?> showAgentChatDeclineFeedbackDialog(BuildContext context) =>
    showDialog<String>(
      context: context,
      builder: (_) => const _DeclineFeedbackDialog(),
    );

class const _DeclineFeedbackDialog() extends StatefulWidget {
  @override
  State<_DeclineFeedbackDialog> createState() => _DeclineFeedbackDialogState();
}

class _DeclineFeedbackDialogState extends State<_DeclineFeedbackDialog> {
  final TextEditingController _feedback = TextEditingController();

  @override
  void dispose() {
    _feedback.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _feedback.text.trim();
    if (text.isNotEmpty) Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) => AleraDialog(
    maxWidth: 520,
    child: Padding(
      padding: const EdgeInsets.all(AleraTokens.space20),
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        children: <Widget>[
          AleraDialogHeader(
            title: agentChatDeclineWithFeedbackLabel,
            onClose: () => Navigator.of(context).pop(),
          ),
          const SizedBox(height: AleraTokens.space12),
          Text(
            'The agent that asked gets this message instead of a plain '
            'refusal, so it can try another way.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: AleraTokens.foregroundMuted),
          ),
          const SizedBox(height: AleraTokens.space12),
          AleraTextField(
            key: const ValueKey<String>('agentChatDeclineFeedback'),
            controller: _feedback,
            labelText: 'Feedback',
            autofocus: true,
            minLines: 3,
            maxLines: 8,
            onChanged: (_) => setState(() {}),
            onCommandEnter: _submit,
          ),
          const SizedBox(height: AleraTokens.space16),
          Row(
            mainAxisAlignment: .end,
            children: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: AleraTokens.space8),
              FilledButton(
                key: const ValueKey<String>('agentChatDeclineFeedbackSend'),
                onPressed: _feedback.text.trim().isEmpty ? null : _submit,
                child: const Text('Decline'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
