import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_provider_icon.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';

/// What a sub-agent view shows instead of the composer: a provider-native
/// sub-agent takes no messages, so the bar names its model and effort, keeps
/// its status and running time current, and leads back to the chat.
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
    return Container(
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final narrow =
                constraints.maxWidth < AleraTokens.dialogCompactWidth;
            final identity = Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                AgentChatProviderIcon(
                  provider: widget.provider,
                  size: AleraTokens.iconLg,
                ),
                const SizedBox(width: AleraTokens.space8),
                Flexible(
                  child: Text(
                    widget.modelLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AleraTokens.foreground,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (widget.effortLabel case final effort?) ...<Widget>[
                  const SizedBox(width: AleraTokens.space6),
                  Text(effort, style: muted),
                ],
              ],
            );
            final statusText = ExcludeSemantics(
              child: Text(
                status,
                key: const ValueKey<String>('agent-chat-subagent-status'),
                style: muted?.copyWith(
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            );
            return Row(
              children: <Widget>[
                Expanded(
                  child: narrow
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[identity, statusText],
                        )
                      : Row(
                          children: <Widget>[
                            Flexible(child: identity),
                            const SizedBox(width: AleraTokens.space12),
                            Flexible(child: statusText),
                          ],
                        ),
                ),
                if (!narrow) ...<Widget>[
                  const SizedBox(width: AleraTokens.space12),
                  Text('Runs on its own', style: muted),
                ],
                if (widget.onOpenParent case final onOpenParent?) ...<Widget>[
                  const SizedBox(width: AleraTokens.space8),
                  TextButton.icon(
                    key: const ValueKey<String>('agent-chat-subagent-parent'),
                    onPressed: onOpenParent,
                    icon: const Icon(AleraIcons.back, size: AleraTokens.iconMd),
                    label: const Text('Open Parent'),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
