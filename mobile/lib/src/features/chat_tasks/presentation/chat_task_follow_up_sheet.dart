import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/forms/alera_text_field.dart';
import 'package:flutter/material.dart';

/// Asks for a follow-up to a finished task's chat. The reply is tracked as a
/// new task; the sheet returns the message, or null when dismissed.
Future<String?> showChatTaskFollowUpSheet(BuildContext context) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _ChatTaskFollowUpSheet(),
    );

class const _ChatTaskFollowUpSheet() extends StatefulWidget {
  @override
  State<_ChatTaskFollowUpSheet> createState() => _ChatTaskFollowUpSheetState();
}

class _ChatTaskFollowUpSheetState extends State<_ChatTaskFollowUpSheet> {
  final TextEditingController _message = TextEditingController();

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: AleraTokens.spaceLg,
        right: AleraTokens.spaceLg,
        top: AleraTokens.spaceLg,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AleraTokens.spaceLg,
      ),
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        children: <Widget>[
          Text('Send Follow-Up', style: theme.textTheme.titleMedium),
          const SizedBox(height: AleraTokens.spaceXs),
          Text(
            'The chat answers in a new turn, tracked as a new task.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          ),
          const SizedBox(height: AleraTokens.spaceMd),
          AleraTextField(
            key: const ValueKey<String>('chatTaskFollowUpMessage'),
            controller: _message,
            labelText: 'Message',
            autofocus: true,
            minLines: 3,
            maxLines: 8,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AleraTokens.spaceMd),
          FilledButton(
            key: const ValueKey<String>('chatTaskFollowUpSend'),
            onPressed: _message.text.trim().isEmpty
                ? null
                : () => Navigator.of(context).pop(_message.text.trim()),
            child: const Text('Send Follow-Up'),
          ),
        ],
      ),
    );
  }
}
