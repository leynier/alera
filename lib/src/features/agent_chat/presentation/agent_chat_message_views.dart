import 'dart:math' as math;

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_shimmer_text.dart';
import 'package:alera/src/design_system/icons/alera_file_icon.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_disclosure.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_markdown.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_message_meta.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_partial_text.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_timeline_context.dart';
import 'package:alera/src/features/chat_tasks/presentation/chat_task_notice.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// What the person sent, on the trailing edge. Input another chat or the
/// runtime sent on the chat's behalf renders as a notice instead, so it is
/// never mistaken for the person's own words. A long message starts
/// collapsed behind Show Full Message; [expansion] keeps that choice when
/// the row scrolls away or the tab comes back.
class const AgentChatUserMessageView({
  super.key,
  required final String chatId,
  required final AgentChatItem item,
  required final String workspacePath,
  required final ValueChanged<String> onOpenFile,
  final AgentChatExpansion? expansion,
  final bool steering = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (item.isAutomatedInput) {
      return _AutomatedInputNotice(
        chatId: chatId,
        item: item,
        expansion: expansion,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) => AgentChatMessageMeta(
        alignment: CrossAxisAlignment.end,
        copyText: item.text,
        timestamp: item.createdAt,
        caption: _actorCaption(item.actor),
        builder: (context) => Padding(
          padding: EdgeInsets.only(
            left: agentChatUserMessageInset(constraints.maxWidth),
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
                      : _CollapsibleText(item: item, expansion: expansion),
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
      ),
    );
  }
}

/// The leading inset of a user message: the fixed inset on a wide pane, a
/// share of the width on a narrow one so the bubble keeps room for text.
double agentChatUserMessageInset(double width) {
  if (!width.isFinite) return AleraTokens.agentChatUserMessageLeftInset;
  return math.min(
    AleraTokens.agentChatUserMessageLeftInset,
    width * (1 - AleraTokens.agentChatUserMessageWidthFraction),
  );
}

/// A sent message's text, collapsed past
/// [agentChatMessageCollapseLines] lines or
/// [agentChatMessageCollapseCharacters] characters.
class const _CollapsibleText({
  required final AgentChatItem item,
  required final AgentChatExpansion? expansion,
}) extends StatefulWidget {
  @override
  State<_CollapsibleText> createState() => _CollapsibleTextState();
}

class _CollapsibleTextState extends State<_CollapsibleText> {
  bool? _localExpanded;

  String get _key => agentChatMessageFoldKey(widget.item.id);

  @override
  Widget build(BuildContext context) {
    final text = widget.item.text;
    if (!agentChatMessageCollapses(text)) return AgentChatMarkdown(data: text);
    final expansion = widget.expansion;
    final expanded =
        expansion?.isExpanded(_key, byDefault: false) ??
        (_localExpanded ?? false);
    void toggle() => setState(() {
      if (expansion == null) {
        _localExpanded = !expanded;
      } else {
        expansion.set(_key, expanded: !expanded);
      }
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        if (expanded)
          AgentChatMarkdown(data: text)
        else
          Text(
            text,
            maxLines: agentChatMessageCollapseLines,
            overflow: TextOverflow.fade,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        AgentChatDisclosure(
          key: ValueKey<String>('agent-chat-message-toggle-${widget.item.id}'),
          expanded: expanded,
          onToggle: toggle,
          child: Text(
            expanded ? agentChatShowLessLabel : agentChatShowFullMessageLabel,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: AleraTokens.foregroundMuted),
          ),
        ),
      ],
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
  required final AgentChatExpansion? expansion,
}) extends StatefulWidget {
  @override
  State<_AutomatedInputNotice> createState() => _AutomatedInputNoticeState();
}

/// Input from another chat or a wake. A delegated task brief starts open and
/// reads "Task"; other notices start folded. A wake is one response boundary
/// with the task outcomes inside it.
class _AutomatedInputNoticeState extends State<_AutomatedInputNotice> {
  bool? _localExpanded;

  String get _key => agentChatMessageFoldKey(widget.item.id);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;
    final origin = item.origin!;
    final text = item.isPartialContinuation ? item.text : item.text.trim();
    final byDefault = agentChatOriginStartsExpanded(origin);
    final expansion = widget.expansion;
    final expanded =
        expansion?.isExpanded(_key, byDefault: byDefault) ??
        (_localExpanded ?? byDefault);
    return Container(
      key: ValueKey<String>('agent-chat-automated-input-${item.id}'),
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
          AgentChatDisclosure(
            expanded: expanded,
            onToggle: text.isEmpty
                ? null
                : () => setState(() {
                    if (expansion == null) {
                      _localExpanded = !expanded;
                    } else {
                      expansion.set(_key, expanded: !expanded);
                    }
                  }),
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
                    agentChatOriginHeading(origin),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AleraTokens.foregroundMuted,
                    ),
                  ),
                ),
                if (text.isNotEmpty)
                  Icon(
                    expanded ? AleraIcons.chevronDown : AleraIcons.chevronRight,
                    size: AleraTokens.iconMd,
                    color: AleraTokens.foregroundFaint,
                  ),
              ],
            ),
          ),
          if (expanded && text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AleraTokens.space8),
              child: item.isPartialContinuation
                  ? AgentChatPartialText(text: text, muted: true)
                  : AgentChatMarkdown(data: text, muted: true),
            ),
          if (item.isPartialContinuation && !expanded)
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
    return AgentChatMessageMeta(
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

/// Shown while a message's attachments upload to the runtime, which happens
/// before the message itself goes out.
const String agentChatUploadingFilesLabel = 'Uploading files';

/// A message on its way to the runtime, or one it refused. [uploading] is
/// true while its attachments are still uploading.
class const AgentChatOutgoingMessageView({
  super.key,
  required final AgentChatOutgoingMessage message,
  required final VoidCallback onRetry,
  required final VoidCallback onEdit,
  final bool uploading = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final failed = message.status == AgentChatOutgoingStatus.failed;
    return LayoutBuilder(
      builder: (context, constraints) => Padding(
        key: ValueKey<String>('agent-chat-outgoing-${message.clientMessageId}'),
        padding: EdgeInsets.only(
          left: agentChatUserMessageInset(constraints.maxWidth),
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
                    border: failed
                        ? Border.all(color: AleraTokens.error)
                        : null,
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
                key: ValueKey<String>(
                  'agent-chat-outgoing-status-${message.clientMessageId}',
                ),
                text: uploading
                    ? agentChatUploadingFilesLabel
                    : message.status == AgentChatOutgoingStatus.sending
                    ? 'Sending'
                    : 'Sent',
                style: AleraTokens.labelMicroFaintStyle,
              ),
          ],
        ),
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
