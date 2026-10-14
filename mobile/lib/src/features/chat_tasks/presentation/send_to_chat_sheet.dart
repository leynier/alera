import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera_mobile/src/design_system/forms/alera_text_field.dart';
import 'package:alera_mobile/src/features/chat_tasks/application/mobile_chat_task_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Send To Chat on the phone: a person's message into another chat. With
/// Expect A Reply the reply is tracked as a task owned by [parentChatId]
/// when the runtime lets a person name one. Returns what the runtime
/// answered; nothing opens.
class const SendToChatSheet({
  super.key,
  required final String hostId,
  required final String fromChatId,
  final String? parentChatId,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<SendToChatSheet> createState() => _SendToChatSheetState();
}

class _SendToChatSheetState extends ConsumerState<SendToChatSheet> {
  late final AgentChatRequestIds _requestIds = AgentChatRequestIds(
    ref.read(mobileChatTaskIdGeneratorProvider),
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
    final navigator = Navigator.of(context);
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
      final repository = await ref.read(
        mobileChatTaskRepositoryProvider(widget.hostId).future,
      );
      final result = await repository.send(
        AgentChatTaskMessageInput(
          requestId: _requestIds.idFor(fingerprint),
          chatId: chatId,
          message: message,
          parentChatId: parent,
          expectReply: _expectReply,
        ),
      );
      _requestIds.reset();
      navigator.pop(result);
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
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: AleraTokens.foregroundMuted,
    );
    final chats = ref.watch(mobileChatTaskDirectoryProvider(widget.hostId));
    final rows = <AgentChatDirectoryEntry>[
      for (final chat in chats.value ?? const <AgentChatDirectoryEntry>[])
        if (chat.chatId != widget.fromChatId && !chat.chat.archived) chat,
    ];
    // The route's safe area leaves the bottom out, so this one keeps Send off
    // the home indicator, and the scroll view keeps the form reachable over
    // the keyboard on a short phone or at large text sizes.
    return SafeArea(
      child: SingleChildScrollView(
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
            Text('Send To Chat', style: theme.textTheme.titleMedium),
            const SizedBox(height: AleraTokens.spaceXs),
            Text(
              'The chat receives your message as its next turn. Nothing opens until you choose to.',
              style: muted,
            ),
            const SizedBox(height: AleraTokens.spaceMd),
            if (chats.value == null)
              Text(
                chats.error == null
                    ? 'Loading chats…'
                    : agentChatOrchestrationErrorMessage(chats.error!),
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
                      label: <String>[
                        chat.title,
                        ?chat.workspaceName,
                      ].join(' · '),
                    ),
                ],
                onChanged: (id) => setState(() {
                  _chatId = id;
                  _error = null;
                }),
              ),
            const SizedBox(height: AleraTokens.spaceSm),
            AleraTextField(
              key: const ValueKey<String>('sendToChatMessage'),
              controller: _message,
              labelText: 'Message',
              minLines: 3,
              maxLines: 8,
              enabled: !_sending,
              onChanged: (_) => setState(() => _error = null),
            ),
            SwitchListTile(
              key: const ValueKey<String>('sendToChatExpectReply'),
              contentPadding: EdgeInsets.zero,
              value: _expectReply,
              title: const Text('Expect A Reply'),
              subtitle: Text(
                widget.parentChatId == null
                    ? 'The reply is tracked as a task in Activity.'
                    : 'The reply is tracked as a task in this chat.',
              ),
              onChanged: _sending
                  ? null
                  : (value) => setState(() => _expectReply = value),
            ),
            if (_error case final message?)
              Text(
                message,
                key: const ValueKey<String>('sendToChatError'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AleraTokens.error,
                ),
              ),
            const SizedBox(height: AleraTokens.spaceMd),
            FilledButton(
              key: const ValueKey<String>('sendToChatSubmit'),
              onPressed: _sending ? null : _send,
              child: Text(_sending ? 'Sending…' : 'Send'),
            ),
          ],
        ),
      ),
    );
  }
}
