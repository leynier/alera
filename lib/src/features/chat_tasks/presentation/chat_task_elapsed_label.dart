import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';

/// How long a task has run, or ran. Only this label rebuilds while the task
/// is unsettled, once a second, and only while it is on screen.
class const ChatTaskElapsedLabel({
  super.key,
  required final AgentChatTask task,
  required final DateTime Function() now,
  final TextStyle? style,
}) extends StatefulWidget {
  @override
  State<ChatTaskElapsedLabel> createState() => _ChatTaskElapsedLabelState();
}

class _ChatTaskElapsedLabelState extends State<ChatTaskElapsedLabel> {
  // The label shows whole seconds, so a finer tick would only cost frames.
  static const Duration _tick = Duration(seconds: 1);

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(ChatTaskElapsedLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.task.status.settled) {
      _timer?.cancel();
      _timer = null;
    } else {
      _timer ??= Timer.periodic(_tick, (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(
    agentChatDurationLabel(agentChatTaskElapsed(widget.task, widget.now())),
    maxLines: 1,
    style: widget.style,
  );
}
