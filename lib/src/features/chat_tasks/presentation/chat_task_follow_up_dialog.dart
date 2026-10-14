import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/design_system/layout/alera_dialog_header.dart';
import 'package:flutter/material.dart';

/// Asks for a follow-up to a finished task's chat. The reply is tracked as a
/// new task; the dialog returns the message, or null when dismissed.
Future<String?> showChatTaskFollowUpDialog(BuildContext context) =>
    showDialog<String>(
      context: context,
      builder: (_) => const _ChatTaskFollowUpDialog(),
    );

class const _ChatTaskFollowUpDialog() extends StatefulWidget {
  @override
  State<_ChatTaskFollowUpDialog> createState() =>
      _ChatTaskFollowUpDialogState();
}

class _ChatTaskFollowUpDialogState extends State<_ChatTaskFollowUpDialog> {
  final TextEditingController _message = TextEditingController();

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _message.text.trim();
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
            title: 'Send Follow-Up',
            onClose: () => Navigator.of(context).pop(),
          ),
          const SizedBox(height: AleraTokens.space12),
          Text(
            'The chat answers in a new turn, tracked as a new task.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: AleraTokens.foregroundMuted),
          ),
          const SizedBox(height: AleraTokens.space12),
          AleraTextField(
            key: const ValueKey<String>('chatTaskFollowUpMessage'),
            controller: _message,
            labelText: 'Message',
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
                key: const ValueKey<String>('chatTaskFollowUpSend'),
                onPressed: _message.text.trim().isEmpty ? null : _submit,
                child: const Text('Send Follow-Up'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
