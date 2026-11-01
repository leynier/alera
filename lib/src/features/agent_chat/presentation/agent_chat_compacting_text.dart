import 'dart:async';

import 'package:alera/src/design_system/feedback/alera_shimmer_text.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// "Compacting for 12s" while a compaction owns a turn's live row. It ticks
/// once a second, only while it knows when the compaction started.
class const AgentChatCompactingText({
  super.key,
  required final DateTime? since,
  final TextStyle? style,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<AgentChatCompactingText> createState() =>
      _AgentChatCompactingTextState();
}

class _AgentChatCompactingTextState
    extends ConsumerState<AgentChatCompactingText> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant AgentChatCompactingText oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _syncTicker() {
    if (widget.since != null && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (widget.since == null) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  Widget build(BuildContext context) => AleraShimmerText(
    text: agentChatCompactingLabel(
      widget.since,
      now: ref.read(agentChatClockProvider)(),
    ),
    style: widget.style,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  );
}
