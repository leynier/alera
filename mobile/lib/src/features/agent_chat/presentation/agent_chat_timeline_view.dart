import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/buttons/alera_floating_pill_button.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_item_rows.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_message_view.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_request_card.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_turn_view.dart';
import 'package:flutter/material.dart';

/// The transcript, newest at the bottom.
///
/// The list is reversed so the bottom is its origin: a streaming answer grows
/// without moving what the reader is looking at, and older history loads at
/// the far end without a jump. A reader who scrolled up gets Jump To Latest.
class const AgentChatTimelineView({
  super.key,
  required final AgentChatTimelineProjection timeline,
  required final String emptyMessage,
  required final bool canLoadEarlier,
  required final bool loadingEarlier,
  required final bool canRespond,
  required final Set<String> respondingRequestIds,
  required final VoidCallback onLoadEarlier,
  required final AgentChatRespond onRespond,
  required final ValueChanged<String> onRetry,
  required final ValueChanged<String> onEdit,
}) extends StatefulWidget {
  @override
  State<AgentChatTimelineView> createState() => _AgentChatTimelineViewState();
}

class _AgentChatTimelineViewState extends State<AgentChatTimelineView> {
  final ScrollController _scroll = ScrollController();
  bool _awayFromLatest = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    final away = _scroll.hasClients && _scroll.offset > AleraTokens.space48;
    if (away != _awayFromLatest) setState(() => _awayFromLatest = away);
  }

  void _jumpToLatest() {
    if (!_scroll.hasClients) return;
    unawaited(
      _scroll.animateTo(
        0,
        duration: AleraTokens.durationSlow,
        curve: Curves.easeOut,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.timeline.entries;
    if (entries.isEmpty && !widget.canLoadEarlier) {
      return AleraEmptyState(
        icon: AleraIcons.agent,
        message: widget.emptyMessage,
      );
    }
    final count = entries.length + (widget.canLoadEarlier ? 1 : 0);
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: ListView.builder(
            controller: _scroll,
            reverse: true,
            padding: AleraTokens.contentPadding,
            itemCount: count,
            findChildIndexCallback: (key) {
              if (key is! ValueKey<String>) return null;
              final index = widget.timeline.indexOfKey(key.value);
              return index == null ? null : entries.length - 1 - index;
            },
            itemBuilder: (context, index) {
              if (index == entries.length) return _loadEarlier();
              final entry = entries[entries.length - 1 - index];
              return Center(
                key: ValueKey<String>(entry.key),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AleraTokens.conversationMaxWidth,
                  ),
                  child: _entry(entry),
                ),
              );
            },
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: AleraTokens.space12,
          child: Center(
            child: AnimatedSwitcher(
              duration: AleraTokens.durationMid,
              child: _awayFromLatest
                  ? AleraFloatingPillButton(
                      label: 'Jump To Latest',
                      icon: AleraIcons.chevronDown,
                      onPressed: _jumpToLatest,
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _loadEarlier() => Padding(
    padding: const EdgeInsets.only(bottom: AleraTokens.space12),
    child: Center(
      child: widget.loadingEarlier
          ? const SizedBox.square(
              dimension: AleraTokens.space24,
              child: CircularProgressIndicator(
                strokeWidth: AleraTokens.strokeSm,
              ),
            )
          : TextButton(
              onPressed: widget.onLoadEarlier,
              child: const Text('Load Earlier Messages'),
            ),
    ),
  );

  Widget _entry(AgentChatTimelineEntry entry) => switch (entry) {
    AgentChatTurnEntry(:final section) => AgentChatTurnView(section: section),
    AgentChatStandaloneEntry(:final item) => switch (item.type) {
      AgentChatItemType.userMessage => AgentChatUserMessage(item: item),
      AgentChatItemType.assistantMessage => AgentChatAssistantMessage(
        item: item,
      ),
      _ => AgentChatItemRowView(item: item),
    },
    AgentChatRequestEntry(:final request) => AgentChatRequestCard(
      request: request,
      enabled:
          widget.canRespond &&
          !widget.respondingRequestIds.contains(request.id),
      onRespond: widget.onRespond,
    ),
    AgentChatOutgoingEntry(:final message) => AgentChatOutgoingMessageView(
      message: message,
      onRetry: widget.canRespond
          ? () => widget.onRetry(message.clientMessageId)
          : null,
      onEdit: () => widget.onEdit(message.clientMessageId),
    ),
  };
}
