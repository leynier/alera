import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/layout/alera_key_value_row.dart';
import 'package:flutter/material.dart';

/// How full the context window is, as a ring next to the model. Hidden when
/// the provider reports neither the window nor any usage limit.
class const AgentChatUsageButton({
  super.key,
  required final AgentChatUsage usage,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final fraction = usage.contextFraction;
    if (fraction == null && usage.windows.isEmpty) {
      return const SizedBox.shrink();
    }
    return IconButton(
      tooltip: 'Context Window',
      visualDensity: .compact,
      onPressed: () => unawaited(showAgentChatUsageSheet(context, usage)),
      icon: SizedBox.square(
        dimension: AleraTokens.space16,
        child: CircularProgressIndicator(
          value: fraction ?? 0,
          strokeWidth: AleraTokens.strokeSm,
          color: (fraction ?? 0) > 0.9
              ? AleraTokens.warning
              : AleraTokens.foregroundMuted,
          backgroundColor: AleraTokens.borderSubtle,
        ),
      ),
    );
  }
}

/// The context window and usage limits of a chat, as a bottom sheet. The
/// usage ring and the composer's `/usage` open it.
Future<void> showAgentChatUsageSheet(
  BuildContext context,
  AgentChatUsage usage,
) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) {
    final localizations = MaterialLocalizations.of(context);
    final used = usage.contextTokens;
    final window = usage.contextWindow;
    final fraction = usage.contextFraction;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: AleraTokens.pagePadding,
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .stretch,
            spacing: AleraTokens.space8,
            children: <Widget>[
              if (fraction != null &&
                  used != null &&
                  window != null) ...<Widget>[
                AleraKeyValueRow(
                  label: 'Context Window',
                  value:
                      '${(fraction * 100).round()}% used, '
                      '${localizations.formatDecimal(used)} of '
                      '${localizations.formatDecimal(window)} tokens',
                ),
                _ContextBar(
                  fraction: fraction,
                  tick: usage.autoCompactFraction,
                ),
                if ((usage.autoCompactFraction, usage.autoCompactTokens) case (
                  _?,
                  final tokens?,
                ))
                  Text(
                    agentChatAutoCompactNote(
                      localizations.formatDecimal(tokens),
                    ),
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: AleraTokens.foregroundMuted),
                  ),
              ],
              for (final limit in usage.windows)
                AleraKeyValueRow(
                  label: limit.label,
                  value: limit.resetsAt == null
                      ? '${limit.usedPercent.round()}% used'
                      : '${limit.usedPercent.round()}% used, resets '
                            '${localizations.formatShortMonthDay(limit.resetsAt!.toLocal())} '
                            '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(limit.resetsAt!.toLocal()))}',
                ),
            ],
          ),
        ),
      ),
    );
  },
);

/// The context fill as a bar, with a tick where the provider compacts on
/// its own.
class const _ContextBar({required final double fraction, final double? tick})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final clamped = fraction.clamp(0.0, 1.0);
    final tick = this.tick;
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(AleraTokens.radiusXs),
            child: LinearProgressIndicator(
              value: clamped,
              minHeight: AleraTokens.space4,
              backgroundColor: AleraTokens.borderSubtle,
              color: clamped > 0.9
                  ? AleraTokens.warning
                  : AleraTokens.foregroundMuted,
            ),
          ),
          if (tick != null)
            Positioned(
              key: const ValueKey<String>('agent-chat-usage-auto-compact-tick'),
              left: (constraints.maxWidth * tick).clamp(
                0,
                constraints.maxWidth - 1,
              ),
              top: -AleraTokens.space2,
              bottom: -AleraTokens.space2,
              width: 1,
              child: const ColoredBox(color: AleraTokens.foreground),
            ),
        ],
      ),
    );
  }
}
