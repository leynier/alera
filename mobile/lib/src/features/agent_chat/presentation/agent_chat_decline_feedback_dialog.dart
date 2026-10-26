import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/forms/alera_text_field.dart';
import 'package:alera_mobile/src/design_system/layout/alera_dialog.dart';
import 'package:flutter/material.dart';

/// Asks what the agent should do instead of the declined request and pops
/// with the trimmed text, or `null` when cancelled.
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
  final TextEditingController _controller = TextEditingController();

  bool get _canSubmit => _controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AleraDialog(
      maxWidth: 480,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .start,
          children: <Widget>[
            Text(
              agentChatDeclineWithFeedbackLabel,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AleraTokens.space4),
            Text(
              'The agent that asked gets this message instead of a plain '
              'refusal, so it can try another way.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
            const SizedBox(height: AleraTokens.space12),
            AleraTextField(
              key: const ValueKey<String>('agentChatDeclineFeedback'),
              controller: _controller,
              autofocus: true,
              hintText: 'What should the agent do instead?',
              keyboardType: .multiline,
              minLines: 3,
              maxLines: 8,
            ),
            const SizedBox(height: AleraTokens.space20),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: AleraTokens.space8),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey<String>('agentChatDeclineFeedbackSend'),
                    onPressed: _canSubmit ? _submit : null,
                    child: const Text('Decline'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
