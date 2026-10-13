import 'dart:math' as math;

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_question_card.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';

typedef _DraftKey = (String chatId, String requestId);

/// Pending questions docked above the composer, one request at a time. Each
/// request keeps its draft while the user pages between requests, and the
/// draft is dropped once its request is no longer pending.
class const AgentChatQuestionDock({
  super.key,
  required final String chatId,
  required final List<AgentChatRequest> requests,
  required final Set<String> respondingRequestIds,
  required final bool enabled,
  required final Future<void> Function(
    AgentChatRequest request,
    AgentChatResponse response,
  )
  onRespond,
}) extends StatefulWidget {
  @override
  State<AgentChatQuestionDock> createState() => _AgentChatQuestionDockState();
}

class _AgentChatQuestionDockState extends State<AgentChatQuestionDock> {
  final Map<_DraftKey, AgentChatQuestionDraft> _drafts =
      <_DraftKey, AgentChatQuestionDraft>{};
  // Observes whether focus is inside the card, so the card that replaces it
  // can keep the keyboard instead of handing it back to the composer.
  final FocusNode _cardArea = FocusNode(
    debugLabel: 'Agent chat question dock',
    canRequestFocus: false,
    skipTraversal: true,
  );
  String? _activeRequestId;
  bool _carryFocus = false;

  @override
  void initState() {
    super.initState();
    _activeRequestId = widget.requests.firstOrNull?.id;
  }

  @override
  void didUpdateWidget(covariant AgentChatQuestionDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previousKey = (oldWidget.chatId, _activeRequestId);
    if (oldWidget.chatId != widget.chatId) {
      _activeRequestId = widget.requests.firstOrNull?.id;
    } else if (_indexOf(_activeRequestId) < 0) {
      _activeRequestId = _nearestRemaining(oldWidget.requests);
    }
    if ((widget.chatId, _activeRequestId) != previousKey) {
      _carryFocus = _cardArea.hasFocus;
    }
    _dropSettledDrafts();
  }

  @override
  void dispose() {
    for (final draft in _drafts.values) {
      draft.dispose();
    }
    _cardArea.dispose();
    super.dispose();
  }

  _DraftKey _draftKey(AgentChatRequest request) => (widget.chatId, request.id);

  int _indexOf(String? requestId) =>
      widget.requests.indexWhere((request) => request.id == requestId);

  /// The request closest to where the active one sat in [previous], looking
  /// after it first, since that is the one that takes its place.
  String? _nearestRemaining(List<AgentChatRequest> previous) {
    final requests = widget.requests;
    if (requests.isEmpty) return null;
    final from = previous.indexWhere(
      (request) => request.id == _activeRequestId,
    );
    if (from < 0) return requests.first.id;
    final remaining = <String>{for (final request in requests) request.id};
    for (var distance = 1; distance < previous.length; distance += 1) {
      for (final index in <int>[from + distance, from - distance]) {
        if (index >= 0 &&
            index < previous.length &&
            remaining.contains(previous[index].id)) {
          return previous[index].id;
        }
      }
    }
    return requests[math.min(from, requests.length - 1)].id;
  }

  void _dropSettledDrafts() {
    final pending = <_DraftKey>{
      for (final request in widget.requests) _draftKey(request),
    };
    _drafts.removeWhere((key, draft) {
      if (pending.contains(key)) return false;
      draft.dispose();
      return true;
    });
  }

  void _select(int index) {
    final requests = widget.requests;
    if (index < 0 || index >= requests.length) return;
    setState(() {
      _carryFocus = _cardArea.hasFocus;
      _activeRequestId = requests[index].id;
    });
  }

  @override
  Widget build(BuildContext context) {
    final requests = widget.requests;
    if (requests.isEmpty) return const SizedBox.shrink();
    final index = math.max(0, _indexOf(_activeRequestId));
    final request = requests[index];
    final key = _draftKey(request);
    return Center(
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: AleraTokens.agentChatDockMaxWidth,
        ),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: <Widget>[
            if (requests.length > 1)
              _RequestPager(
                index: index,
                count: requests.length,
                onSelect: _select,
              ),
            Flexible(
              child: Focus(
                focusNode: _cardArea,
                child: AgentChatQuestionCard(
                  key: ValueKey<_DraftKey>(key),
                  request: request,
                  draft: _drafts.putIfAbsent(key, AgentChatQuestionDraft.new),
                  responding: widget.respondingRequestIds.contains(request.id),
                  enabled: widget.enabled,
                  takeFocus: _carryFocus,
                  onRespond: widget.onRespond,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class const _RequestPager({
  required final int index,
  required final int count,
  required final ValueChanged<int> onSelect,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AleraTokens.space4),
      child: Row(
        mainAxisAlignment: .end,
        children: <Widget>[
          Text(
            'Request ${index + 1} of $count',
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: AleraTokens.foregroundMuted),
          ),
          const SizedBox(width: AleraTokens.space4),
          AleraIconButton(
            tooltip: 'Previous Request',
            icon: AleraIcons.chevronLeft,
            minSize: AleraTokens.iconButtonSm,
            onPressed: index > 0 ? () => onSelect(index - 1) : null,
          ),
          AleraIconButton(
            tooltip: 'Next Request',
            icon: AleraIcons.chevronRight,
            minSize: AleraTokens.iconButtonSm,
            onPressed: index < count - 1 ? () => onSelect(index + 1) : null,
          ),
        ],
      ),
    );
  }
}
