import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_shimmer.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_turn_view.dart';
import 'package:flutter/material.dart';

/// "Compacting for 12s" while a compaction owns a turn's live row, ticking
/// once a second while the app is in front.
class const AgentChatCompactingText({
  super.key,
  required final DateTime? since,
  final TextStyle? style,
}) extends StatefulWidget {
  @override
  State<AgentChatCompactingText> createState() =>
      _AgentChatCompactingTextState();
}

class _AgentChatCompactingTextState extends State<AgentChatCompactingText> {
  Timer? _timer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant AgentChatCompactingText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.since != widget.since) _sync();
  }

  void _sync() {
    _timer?.cancel();
    final ticking =
        widget.since != null && TickerMode.valuesOf(context).enabled;
    _timer = ticking
        ? Timer.periodic(AleraTokens.elapsedTimeTick, (_) {
            if (mounted) setState(() {});
          })
        : null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AgentChatShimmerText(
    text: agentChatCompactingLabel(
      widget.since,
      now: AgentChatElapsedClock.read(context),
    ),
    style: widget.style,
  );
}
