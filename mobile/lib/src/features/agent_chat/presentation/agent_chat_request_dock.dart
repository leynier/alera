import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_question_card.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_request_card.dart';
import 'package:flutter/material.dart';

/// When the person last typed into this chat, so a request that arrives
/// mid-sentence does not pull the dock to another page under their thumb.
class AgentChatTypingClock {
  DateTime? _lastKeystroke;
  bool _settled = true;

  void keystroke() {
    _lastKeystroke = DateTime.now();
    _settled = false;
  }

  /// A send or the field losing focus ends the typing burst at once.
  void settle() => _settled = true;

  bool mayTakeFocus() => agentChatRequestMayTakeFocus(
    now: DateTime.now(),
    lastKeystroke: _lastKeystroke,
    sentOrBlurred: _settled,
  );

  /// How long until [mayTakeFocus] can turn true.
  Duration get remaining {
    final last = _lastKeystroke;
    if (_settled || last == null) return Duration.zero;
    final left = agentChatTypingIdle - DateTime.now().difference(last);
    return left.isNegative ? Duration.zero : left;
  }
}

/// Every request the agent is blocked on, one at a time above the composer:
/// approvals first, then forms, then questions, oldest first within each.
/// "Request X of N" pages through them; the composer underneath keeps its
/// draft. Nothing here accepts on its own.
class const AgentChatRequestDock({
  super.key,
  required final List<AgentChatRequest> requests,
  required final bool enabled,
  required final Set<String> respondingRequestIds,
  required final AgentChatRespond onRespond,
  required final AgentChatTypingClock typing,
}) extends StatefulWidget {
  @override
  State<AgentChatRequestDock> createState() => _AgentChatRequestDockState();
}

class _AgentChatRequestDockState extends State<AgentChatRequestDock> {
  String? _shownId;
  final Set<String> _seen = <String>{};
  Timer? _recheck;

  @override
  void initState() {
    super.initState();
    _shownId = widget.requests.firstOrNull?.id;
    _seen.addAll(widget.requests.map((request) => request.id));
  }

  @override
  void didUpdateWidget(covariant AgentChatRequestDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    _follow();
  }

  @override
  void dispose() {
    _recheck?.cancel();
    super.dispose();
  }

  /// Keeps the page the person is on. A new request that outranks it takes
  /// over only once typing has paused; until then it waits its turn.
  void _follow() {
    final requests = widget.requests;
    final ids = <String>[for (final request in requests) request.id];
    final shown = _shownId;
    final arrived = <String>[
      for (final id in ids)
        if (!_seen.contains(id)) id,
    ];
    if (shown == null || !ids.contains(shown)) {
      _shownId = ids.firstOrNull;
    } else if (arrived.isNotEmpty) {
      final outranking = ids.indexOf(arrived.first) < ids.indexOf(shown);
      if (outranking) {
        if (widget.typing.mayTakeFocus()) {
          _shownId = arrived.first;
        } else {
          _recheck?.cancel();
          _recheck = Timer(widget.typing.remaining, () {
            if (!mounted ||
                !widget.requests.any((r) => r.id == arrived.first)) {
              return;
            }
            setState(() => _shownId = arrived.first);
          });
        }
      }
    }
    _seen
      ..retainAll(ids)
      ..addAll(ids);
  }

  void _page(int delta) {
    final requests = widget.requests;
    final index = requests.indexWhere((request) => request.id == _shownId);
    final next = (index + delta).clamp(0, requests.length - 1);
    setState(() => _shownId = requests[next].id);
  }

  @override
  Widget build(BuildContext context) {
    final requests = widget.requests;
    if (requests.isEmpty) return const SizedBox.shrink();
    final index = requests
        .indexWhere((request) => request.id == _shownId)
        .clamp(0, requests.length - 1);
    final request = requests[index];
    final enabled =
        widget.enabled && !widget.respondingRequestIds.contains(request.id);
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Request ${index + 1} of ${requests.length}',
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        children: <Widget>[
          if (requests.length > 1)
            _Pager(
              index: index,
              count: requests.length,
              onPrevious: index > 0 ? () => _page(-1) : null,
              onNext: index < requests.length - 1 ? () => _page(1) : null,
            ),
          if (request.isQuestion)
            AgentChatQuestionCard(
              key: ValueKey<String>('question-${request.id}'),
              request: request,
              enabled: enabled,
              onRespond: widget.onRespond,
            )
          else
            AgentChatRequestCard(
              key: ValueKey<String>('request-${request.id}'),
              request: request,
              enabled: enabled,
              onRespond: widget.onRespond,
            ),
        ],
      ),
    );
  }
}

class const _Pager({
  required final int index,
  required final int count,
  required final VoidCallback? onPrevious,
  required final VoidCallback? onNext,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Expanded(
        child: Text(
          'Request ${index + 1} of $count',
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: AleraTokens.foregroundMuted),
        ),
      ),
      IconButton(
        tooltip: 'Previous Request',
        onPressed: onPrevious,
        icon: const Icon(AleraIcons.chevronUp),
      ),
      IconButton(
        tooltip: 'Next Request',
        onPressed: onNext,
        icon: const Icon(AleraIcons.chevronDown),
      ),
    ],
  );
}
