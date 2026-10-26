import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_provider_identity.dart';
import 'package:alera_mobile/src/features/workbench/presentation/agent_identity_icon.dart';
import 'package:flutter/material.dart';

/// What a sub-agent screen shows instead of the composer, as on the
/// desktop: the sub-agent's model and effort, its status and running time,
/// that it runs on its own, and the way back to whatever started it.
class const AgentChatSubagentBar({
  super.key,
  required final String provider,
  required final AgentChatItem call,
  required final String modelLabel,
  final String? effortLabel,
  final VoidCallback? onOpenParent,
}) extends StatefulWidget {
  @override
  State<AgentChatSubagentBar> createState() => _AgentChatSubagentBarState();
}

class _AgentChatSubagentBarState extends State<AgentChatSubagentBar> {
  Timer? _ticker;

  bool get _live =>
      widget.call.subagentStatus == AgentChatSubagentStatus.running;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(AgentChatSubagentBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  // Only the status label changes each second, and only while it runs.
  void _syncTicker() {
    if (_live && _ticker == null) {
      _ticker = Timer.periodic(
        const Duration(seconds: 1),
        (_) => setState(() {}),
      );
    } else if (!_live) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: AleraTokens.foregroundMuted,
    );
    final status = agentChatSubagentStatusLabel(widget.call, DateTime.now());
    final model = widget.effortLabel == null
        ? widget.modelLabel
        : '${widget.modelLabel}, ${widget.effortLabel}';
    return SafeArea(
      top: false,
      child: Container(
        key: const ValueKey<String>('agent-chat-subagent-bar'),
        margin: const EdgeInsets.all(AleraTokens.space12),
        padding: const EdgeInsets.symmetric(
          horizontal: AleraTokens.space12,
          vertical: AleraTokens.space8,
        ),
        decoration: BoxDecoration(
          color: AleraTokens.surface,
          border: Border.all(color: AleraTokens.borderSubtle),
          borderRadius: BorderRadius.circular(AleraTokens.radiusXl),
        ),
        child: Semantics(
          container: true,
          label: '$model sub-agent: $status',
          child: Row(
            children: <Widget>[
              AgentIdentityIcon(
                agentType: agentChatAgentType(widget.provider),
                size: AleraTokens.space16,
                showTooltip: false,
              ),
              const SizedBox(width: AleraTokens.space8),
              Expanded(
                child: ExcludeSemantics(
                  child: Column(
                    crossAxisAlignment: .start,
                    mainAxisSize: .min,
                    children: <Widget>[
                      Text(
                        model,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AleraTokens.foreground,
                          fontWeight: .w600,
                        ),
                        maxLines: 1,
                        overflow: .ellipsis,
                      ),
                      Text(
                        '$status · Runs on its own',
                        key: const ValueKey<String>(
                          'agent-chat-subagent-status',
                        ),
                        style: muted,
                        maxLines: 1,
                        overflow: .ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
              if (widget.onOpenParent case final onOpenParent?)
                TextButton.icon(
                  key: const ValueKey<String>('agent-chat-subagent-parent'),
                  onPressed: onOpenParent,
                  icon: const Icon(AleraIcons.openParent),
                  label: const Text('Open Parent'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
