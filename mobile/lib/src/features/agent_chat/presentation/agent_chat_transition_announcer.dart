import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/features/agent_chat/domain/agent_chat_view_state.dart';
import 'package:flutter/material.dart';

/// Says the moments that matter out loud for a screen reader, once each: a
/// request needing an answer, a turn finishing, a turn failing.
class const AgentChatTransitionAnnouncer({
  super.key,
  required final AgentChatViewState view,
}) extends StatefulWidget {
  @override
  State<AgentChatTransitionAnnouncer> createState() =>
      _AgentChatTransitionAnnouncerState();
}

class _AgentChatTransitionAnnouncerState
    extends State<AgentChatTransitionAnnouncer> {
  String _label = '';

  @override
  void didUpdateWidget(covariant AgentChatTransitionAnnouncer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final before = oldWidget.view;
    final after = widget.view;
    final next =
        after.timeline.requests.length > before.timeline.requests.length
        ? 'The agent needs your response.'
        : before.turnActive && !after.turnActive
        ? (_lastTurnFailed(after) ? 'The turn failed.' : 'The turn finished.')
        : null;
    if (next != null) _label = next;
  }

  bool _lastTurnFailed(AgentChatViewState view) =>
      switch (view.thread.turns.lastOrNull?.status) {
        AgentChatTurnStatus.failed => true,
        _ => false,
      };

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: _label,
    child: const SizedBox.shrink(),
  );
}
