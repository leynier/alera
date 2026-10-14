import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/surfaces/alera_popover.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';

/// Above this share a usage bar turns to the warning tone.
const double _nearLimit = 0.9;

/// How full the context window is, as a ring beside Send, opening a popover
/// with the context window and the provider's usage limits and when each
/// resets. Hidden when the provider reports neither.
class const AgentChatUsageButton({
  super.key,
  required final AgentChatUsage usage,
}) extends StatefulWidget {
  @override
  State<AgentChatUsageButton> createState() => _AgentChatUsageButtonState();
}

class _AgentChatUsageButtonState extends State<AgentChatUsageButton> {
  final AleraPopoverController _popover = AleraPopoverController();

  @override
  void dispose() {
    _popover.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final usage = widget.usage;
    final fraction = usage.contextFraction;
    if (fraction == null && usage.windows.isEmpty) {
      return const SizedBox.shrink();
    }
    final nearLimit =
        (fraction ?? 0) > _nearLimit ||
        usage.windows.any((window) => window.usedPercent / 100 > _nearLimit);
    return AleraPopover(
      controller: _popover,
      toggleOnAnchorTap: false,
      width: AleraTokens.dialogCompactWidth,
      builder: (context, close) => AgentChatUsageDetails(usage: usage),
      child: IconButton(
        key: const ValueKey<String>('agent-chat-usage'),
        tooltip: fraction == null
            ? 'Usage'
            : 'Context ${(fraction * 100).round()}% Used',
        onPressed: _popover.toggle,
        visualDensity: VisualDensity.compact,
        icon: SizedBox.square(
          dimension: AleraTokens.iconLg,
          child: CircularProgressIndicator(
            value: fraction ?? 0,
            strokeWidth: AleraTokens.strokeSm,
            backgroundColor: AleraTokens.border,
            color: nearLimit
                ? AleraTokens.warning
                : AleraTokens.foregroundMuted,
          ),
        ),
      ),
    );
  }
}

/// The popover body: the context window, then each usage limit with its
/// reset time. Presentational, so it previews and tests without a chat.
class const AgentChatUsageDetails({
  super.key,
  required final AgentChatUsage usage,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = MaterialLocalizations.of(context);
    final fraction = usage.contextFraction;
    final used = usage.contextTokens;
    final window = usage.contextWindow;
    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AleraTokens.space12,
        children: <Widget>[
          Text('Usage', style: theme.textTheme.titleSmall),
          if (fraction != null && used != null && window != null)
            _UsageMeter(
              label: 'Context Window',
              fraction: fraction,
              detail:
                  '${(fraction * 100).round()}% used, '
                  '${localizations.formatDecimal(used)} of '
                  '${localizations.formatDecimal(window)} tokens',
            ),
          for (final limit in usage.windows)
            _UsageMeter(
              label: limit.label.isEmpty ? 'Usage Limit' : limit.label,
              fraction: limit.usedPercent / 100,
              detail: switch (limit.resetsAt) {
                null => '${limit.usedPercent.round()}% used',
                final resetsAt =>
                  '${limit.usedPercent.round()}% used, resets '
                      '${_resetLabel(localizations, resetsAt)}',
              },
            ),
        ],
      ),
    );
  }

  static String _resetLabel(
    MaterialLocalizations localizations,
    DateTime resetsAt,
  ) {
    final local = resetsAt.toLocal();
    return '${localizations.formatShortMonthDay(local)} '
        '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
  }
}

class const _UsageMeter({
  required final String label,
  required final double fraction,
  required final String detail,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final clamped = fraction.clamp(0.0, 1.0);
    return Semantics(
      label: '$label, $detail',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AleraTokens.space4,
        children: <Widget>[
          Text(label, style: theme.textTheme.bodySmall),
          ClipRRect(
            borderRadius: BorderRadius.circular(AleraTokens.radiusXs),
            child: LinearProgressIndicator(
              value: clamped,
              minHeight: AleraTokens.space4,
              backgroundColor: AleraTokens.border,
              color: clamped > _nearLimit
                  ? AleraTokens.warning
                  : AleraTokens.foregroundMuted,
            ),
          ),
          Text(
            detail,
            style: theme.textTheme.labelSmall?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          ),
        ],
      ),
    );
  }
}
