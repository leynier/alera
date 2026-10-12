import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/inbox/domain/inbox_models.dart';
import 'package:alera_mobile/src/features/inbox/presentation/inbox_delivery_labels.dart';
import 'package:flutter/material.dart';

/// Deliver: Now or When the Turn Ends. Shown only for hosts that advertise
/// `inboxV2`. Now is disabled, with the reason below, for an agent that
/// cannot take a question mid-turn; the choice then shows what is sent.
class const InboxDeliveryChoice({
  super.key,
  required final InboxDelivery selected,
  required final ValueChanged<InboxDelivery> onChanged,
  final InboxDeliveryMode? targetMode,
  final Duration expiry = inboxDefaultExpiry,
  final bool enabled = true,

  /// A labelled single row without the helper text, for the follow-up bar.
  final bool compact = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nowBlocked = targetMode == null
        ? null
        : inboxDeliverNowUnavailableReason(targetMode!);
    final effective = effectiveInboxDelivery(selected, targetMode);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: AleraTokens.foregroundMuted,
    );
    final buttons = SegmentedButton<InboxDelivery>(
      segments: <ButtonSegment<InboxDelivery>>[
        ButtonSegment<InboxDelivery>(
          value: InboxDelivery.now,
          label: const Text('Now'),
          enabled: nowBlocked == null,
        ),
        const ButtonSegment<InboxDelivery>(
          value: InboxDelivery.turnEnd,
          label: Text('When the Turn Ends'),
        ),
      ],
      selected: <InboxDelivery>{effective},
      showSelectedIcon: false,
      style: compact
          ? const ButtonStyle(visualDensity: VisualDensity.compact)
          : null,
      onSelectionChanged: enabled
          ? (selection) => onChanged(selection.first)
          : null,
    );
    final helper = compact
        ? null
        : effective == InboxDelivery.now
        ? inboxDeliverNowHelper
        : inboxDeliverTurnEndHelper(expiry);
    return Column(
      crossAxisAlignment: .start,
      spacing: AleraTokens.space4,
      children: <Widget>[
        if (compact)
          Row(
            spacing: AleraTokens.space8,
            children: <Widget>[
              Text('Deliver', style: theme.textTheme.labelMedium),
              Expanded(child: buttons),
            ],
          )
        else
          SizedBox(width: double.infinity, child: buttons),
        if (helper != null) Text(helper, style: muted),
        if (nowBlocked != null) Text(nowBlocked, style: muted),
      ],
    );
  }
}
