import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/design_system/forms/alera_checkbox.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/design_system/layout/alera_dialog_header.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/chat_tasks/application/chat_task_providers.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Send To Chat: a person's message into another chat, in any project or
/// host. With Expect A Reply the reply is tracked as a task, owned by
/// [parentChatId] when the runtime lets a person name one, else by the
/// person. Returns what the runtime answered; nothing opens.
class const SendToChatDialog({
  super.key,
  required final String fromChatId,
  final String? parentChatId,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<SendToChatDialog> createState() => _SendToChatDialogState();
}

class _SendToChatDialogState extends ConsumerState<SendToChatDialog> {
  late final AgentChatRequestIds _requestIds = AgentChatRequestIds(
    ref.read(agentChatIdGeneratorProvider),
  );
  final TextEditingController _message = TextEditingController();
  String? _chatId;
  bool _expectReply = true;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final chatId = _chatId;
    final message = _message.text.trim();
    if (chatId == null || message.isEmpty) {
      setState(
        () => _error = chatId == null ? 'Choose a chat.' : 'Write a message.',
      );
      return;
    }
    final parent = _expectReply ? widget.parentChatId : null;
    final fingerprint = <Object?>[
      chatId,
      message,
      _expectReply,
      parent,
    ].join('\u0000');
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(chatTaskRepositoryProvider)
          .send(
            AgentChatTaskMessageInput(
              requestId: _requestIds.idFor(fingerprint),
              chatId: chatId,
              message: message,
              parentChatId: parent,
              expectReply: _expectReply,
            ),
          );
      _requestIds.reset();
      if (mounted) Navigator.of(context).pop(result);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = agentChatOrchestrationErrorMessage(error));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chats = ref.watch(chatTaskDirectoryProvider);
    final rows = <AgentChatDirectoryEntry>[
      for (final chat in chats.value ?? const <AgentChatDirectoryEntry>[])
        if (chat.chatId != widget.fromChatId && !chat.chat.archived) chat,
    ]..sort((a, b) => (a.projectName ?? '').compareTo(b.projectName ?? ''));
    final replyNote = widget.parentChatId == null
        ? 'The reply is tracked as a task in Activity.'
        : 'The reply is tracked as a task in this chat.';
    return AleraDialog(
      maxWidth: 560,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: <Widget>[
            AleraDialogHeader(
              title: 'Send To Chat',
              onClose: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: AleraTokens.space4),
            Text(
              'The chat receives your message as its next turn. Nothing opens until you choose to.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
            const SizedBox(height: AleraTokens.space12),
            if (chats.value == null)
              Text(
                chats.error == null
                    ? 'Loading chats…'
                    : agentChatOrchestrationErrorMessage(chats.error!),
                style: theme.textTheme.bodySmall,
              )
            else
              AleraDropdownField<String>(
                key: const ValueKey<String>('sendToChatTarget'),
                value: _chatId,
                labelText: 'Chat',
                hintText: rows.isEmpty ? 'No Other Chats' : 'Choose a Chat',
                enabled: !_sending && rows.isNotEmpty,
                filterable: rows.length > 6,
                filterHintText: 'Search Chats',
                entries: <AleraDropdownFieldEntry<String>>[
                  for (final chat in rows)
                    AleraDropdownFieldEntry<String>(
                      value: chat.chatId,
                      label: chat.title,
                      detail: <String>[
                        ?chat.projectName,
                        ?chat.workspaceName,
                      ].join(' / '),
                      group: chat.projectName,
                    ),
                ],
                onChanged: (id) => setState(() {
                  _chatId = id;
                  _error = null;
                }),
              ),
            const SizedBox(height: AleraTokens.space8),
            AleraTextField(
              key: const ValueKey<String>('sendToChatMessage'),
              controller: _message,
              labelText: 'Message',
              autofocus: true,
              minLines: 3,
              maxLines: 8,
              enabled: !_sending,
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: AleraTokens.space8),
            AleraCheckbox(
              key: const ValueKey<String>('sendToChatExpectReply'),
              value: _expectReply,
              label: 'Expect A Reply',
              enabled: !_sending,
              onChanged: (value) => setState(() => _expectReply = value),
            ),
            if (_expectReply)
              Text(
                replyNote,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AleraTokens.foregroundMuted,
                ),
              ),
            if (_error case final message?) ...<Widget>[
              const SizedBox(height: AleraTokens.space12),
              AleraInlineNotice(message: message, tone: .error),
            ],
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
                  key: const ValueKey<String>('sendToChatSubmit'),
                  onPressed: _sending ? null : _send,
                  child: Text(_sending ? 'Sending…' : 'Send'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
