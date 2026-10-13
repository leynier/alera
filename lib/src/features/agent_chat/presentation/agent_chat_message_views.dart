import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/feedback/alera_shimmer_text.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/icons/alera_file_icon.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_markdown.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_partial_text.dart';
import 'package:alera/src/features/chat_tasks/presentation/chat_task_notice.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// What the person sent, on the trailing edge. Input another chat or the
/// runtime sent on the chat's behalf renders as a notice instead, so it is
/// never mistaken for the person's own words.
class const AgentChatUserMessageView({
  super.key,
  required final String chatId,
  required final AgentChatItem item,
  required final String workspacePath,
  required final ValueChanged<String> onOpenFile,
  final bool steering = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (item.isAutomatedInput) {
      return _AutomatedInputNotice(chatId: chatId, item: item);
    }
    return _HoverActions(
      alignment: CrossAxisAlignment.end,
      copyText: item.text,
      timestamp: item.createdAt,
      caption: _actorCaption(item.actor),
      builder: (context) => Padding(
        padding: const EdgeInsets.only(
          left: AleraTokens.agentChatUserMessageLeftInset,
          top: AleraTokens.space6,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            if (item.attachments.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: AleraTokens.space6),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: AleraTokens.space6,
                  runSpacing: AleraTokens.space6,
                  children: <Widget>[
                    for (final attachment in item.attachments)
                      AgentChatAttachmentChip(
                        attachment: attachment,
                        onOpen: attachment.path == null
                            ? null
                            : () => onOpenFile(
                                _resolve(attachment.path!, workspacePath),
                              ),
                      ),
                  ],
                ),
              ),
            if (item.text.trim().isNotEmpty || item.isPartialContinuation)
              Container(
                key: ValueKey<String>('agent-chat-user-message-${item.id}'),
                padding: const EdgeInsets.all(AleraTokens.space12),
                decoration: BoxDecoration(
                  color: AleraTokens.accentSubtle,
                  borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
                  border: steering
                      ? Border.all(color: AleraTokens.border)
                      : null,
                ),
                child: item.isPartialContinuation
                    ? AgentChatPartialText(text: item.text)
                    : AgentChatMarkdown(data: item.text),
              ),
            if (steering)
              Padding(
                padding: const EdgeInsets.only(top: AleraTokens.space4),
                child: Text(
                  'Sent during the turn',
                  style: AleraTokens.labelMicroFaintStyle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _resolve(String path, String workspacePath) =>
    p.isAbsolute(path) || workspacePath.isEmpty
    ? path
    : p.join(workspacePath, path);

String? _actorCaption(String? actor) {
  if (actor == null) return null;
  if (actor.startsWith('mobile:')) return 'From Phone';
  if (actor == 'cli') return 'From CLI';
  if (actor.startsWith('mcp:')) return 'From MCP';
  return null;
}

class const _AutomatedInputNotice({
  required final String chatId,
  required final AgentChatItem item,
}) extends StatefulWidget {
  @override
  State<_AutomatedInputNotice> createState() => _AutomatedInputNoticeState();
}

class _AutomatedInputNoticeState extends State<_AutomatedInputNotice> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final origin = widget.item.origin!;
    final count = origin.taskIds.length;
    final label = switch (origin.kind) {
      AgentChatItemOriginKind.orchestrationWake =>
        count == 0
            ? 'Resumed after delegated work finished'
            : 'Resumed after $count delegated '
                  '${count == 1 ? 'task' : 'tasks'} finished',
      _ => 'Message from another chat',
    };
    final item = widget.item;
    final text = item.isPartialContinuation ? item.text : item.text.trim();
    return Container(
      key: ValueKey<String>('agent-chat-automated-input-${widget.item.id}'),
      margin: const EdgeInsets.only(
        top: AleraTokens.space6,
        bottom: AleraTokens.space4,
      ),
      padding: const EdgeInsets.all(AleraTokens.space8),
      decoration: BoxDecoration(
        color: AleraTokens.surface,
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        border: Border.all(color: AleraTokens.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          InkWell(
            onTap: text.isEmpty
                ? null
                : () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
            child: Row(
              children: <Widget>[
                const Icon(
                  AleraIcons.agent,
                  size: AleraTokens.iconMd,
                  color: AleraTokens.foregroundMuted,
                ),
                const SizedBox(width: AleraTokens.space8),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AleraTokens.foregroundMuted,
                    ),
                  ),
                ),
                if (text.isNotEmpty)
                  Icon(
                    _expanded
                        ? AleraIcons.chevronDown
                        : AleraIcons.chevronRight,
                    size: AleraTokens.iconMd,
                    color: AleraTokens.foregroundFaint,
                  ),
              ],
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.only(top: AleraTokens.space8),
              child: item.isPartialContinuation
                  ? AgentChatPartialText(text: text, muted: true)
                  : AgentChatMarkdown(data: text, muted: true),
            ),
          if (item.isPartialContinuation && !_expanded)
            const AgentChatPartialMessageNote(),
          ChatTaskOriginNotice(origin: origin, chatId: widget.chatId),
        ],
      ),
    );
  }
}

/// What the agent said. While it streams the text grows in place and a
/// shimmer marks it as unfinished.
class const AgentChatAssistantMessageView({
  super.key,
  required final AgentChatItem item,
  required final ValueChanged<String> onOpenLink,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final text = item.text;
    if (text.trim().isEmpty && !item.isPartialContinuation) {
      return item.isInProgress
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: AleraTokens.space6),
              child: AleraShimmerText(
                text: 'Writing',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: AleraTokens.foregroundMuted),
              ),
            )
          : const SizedBox.shrink();
    }
    return _HoverActions(
      alignment: CrossAxisAlignment.start,
      copyText: text,
      timestamp: item.isInProgress ? null : item.updatedAt,
      builder: (context) => Padding(
        padding: const EdgeInsets.only(top: AleraTokens.space6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (item.isPartialContinuation)
              AgentChatPartialText(text: text)
            else
              AgentChatMarkdown(data: text, onOpenLink: onOpenLink),
            if (item.isInProgress)
              const Padding(
                padding: EdgeInsets.only(top: AleraTokens.space6),
                child: AleraShimmerText(
                  text: 'Writing',
                  style: AleraTokens.labelMicroFaintStyle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A message on its way to the runtime, or one it refused.
class const AgentChatOutgoingMessageView({
  super.key,
  required final AgentChatOutgoingMessage message,
  required final VoidCallback onRetry,
  required final VoidCallback onEdit,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final failed = message.status == AgentChatOutgoingStatus.failed;
    return Padding(
      key: ValueKey<String>('agent-chat-outgoing-${message.clientMessageId}'),
      padding: const EdgeInsets.only(
        left: AleraTokens.agentChatUserMessageLeftInset,
        top: AleraTokens.space6,
        bottom: AleraTokens.space12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          if (message.attachments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AleraTokens.space6),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: AleraTokens.space6,
                children: <Widget>[
                  for (final attachment in message.attachments)
                    AgentChatAttachmentChip(attachment: attachment),
                ],
              ),
            ),
          if (message.text.isNotEmpty)
            Opacity(
              opacity: failed ? 1 : AleraTokens.agentChatPendingOpacity,
              child: Container(
                padding: const EdgeInsets.all(AleraTokens.space12),
                decoration: BoxDecoration(
                  color: AleraTokens.accentSubtle,
                  borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
                  border: failed ? Border.all(color: AleraTokens.error) : null,
                ),
                child: Text(message.text, style: theme.textTheme.bodyMedium),
              ),
            ),
          const SizedBox(height: AleraTokens.space4),
          if (failed) ...<Widget>[
            Text(
              message.error ?? 'The message was not sent.',
              textAlign: TextAlign.end,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AleraTokens.error,
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                TextButton(onPressed: onEdit, child: const Text('Edit')),
                const SizedBox(width: AleraTokens.space4),
                FilledButton(onPressed: onRetry, child: const Text('Retry')),
              ],
            ),
          ] else
            AleraShimmerText(
              text: message.status == AgentChatOutgoingStatus.sending
                  ? 'Sending'
                  : 'Sent',
              style: AleraTokens.labelMicroFaintStyle,
            ),
        ],
      ),
    );
  }
}

class const AgentChatAttachmentChip({
  super.key,
  required final AgentChatAttachment attachment,
  final VoidCallback? onOpen,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final name = attachment.displayName;
    return InkWell(
      onTap: onOpen,
      mouseCursor: onOpen == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
      child: Container(
        constraints: const BoxConstraints(
          maxWidth: AleraTokens.contextMenuWidth,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AleraTokens.space8,
          vertical: AleraTokens.space6,
        ),
        decoration: BoxDecoration(
          color: AleraTokens.surface,
          borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
          border: Border.all(color: AleraTokens.borderSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (attachment.type.isImage)
              const Icon(
                AleraIcons.viewImage,
                size: AleraTokens.iconMd,
                color: AleraTokens.foregroundMuted,
              )
            else
              AleraFileIcon(
                pathOrName: attachment.path ?? name,
                kind: AleraFileIconKind.file,
                size: AleraTokens.iconMd,
              ),
            const SizedBox(width: AleraTokens.space6),
            Flexible(
              child: Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Copy and time controls under a message, revealed on hover.
class const _HoverActions({
  required final CrossAxisAlignment alignment,
  required final String copyText,
  required final DateTime? timestamp,
  required final WidgetBuilder builder,
  final String? caption,
}) extends StatefulWidget {
  @override
  State<_HoverActions> createState() => _HoverActionsState();
}

class _HoverActionsState extends State<_HoverActions> {
  bool _hovered = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.copyText));
    AleraToast.publish(message: 'Copied to clipboard.');
  }

  @override
  Widget build(BuildContext context) {
    final timestamp = widget.timestamp;
    final localizations = MaterialLocalizations.of(context);
    final time = timestamp == null
        ? null
        : localizations.formatTimeOfDay(
            TimeOfDay.fromDateTime(timestamp.toLocal()),
          );
    final details = <String>[?widget.caption, ?time].join(' · ');
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Column(
        crossAxisAlignment: widget.alignment,
        children: <Widget>[
          widget.builder(context),
          AnimatedOpacity(
            opacity: _hovered ? 1 : 0,
            duration: AleraTokens.durationFast,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (details.isNotEmpty)
                  Text(details, style: AleraTokens.labelMicroFaintStyle),
                AleraIconButton(
                  tooltip: 'Copy Message',
                  icon: AleraIcons.copy,
                  iconSize: AleraTokens.iconSm,
                  minSize: AleraTokens.iconButtonSm,
                  onPressed: widget.copyText.isEmpty
                      ? null
                      : () => unawaited(_copy()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
