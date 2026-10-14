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
      onPressed: () => unawaited(_show(context)),
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

  Future<void> _show(BuildContext context) => showModalBottomSheet<void>(
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
                if (fraction != null && used != null && window != null)
                  AleraKeyValueRow(
                    label: 'Context Window',
                    value:
                        '${(fraction * 100).round()}% used, '
                        '${localizations.formatDecimal(used)} of '
                        '${localizations.formatDecimal(window)} tokens',
                  ),
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
}
