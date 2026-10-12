import 'package:alera/src/design_system/forms/alera_segmented_choice.dart';
import 'package:alera/src/features/inbox/domain/inbox_models.dart';
import 'package:alera/src/features/inbox/presentation/question_status.dart';
import 'package:flutter/material.dart';

/// The delivery actually sent: `now` falls back to `turnEnd` for an agent
/// that cannot take a question mid-turn.
InboxDelivery effectiveQuestionDelivery(
  InboxDelivery chosen,
  InboxDeliveryMode? targetMode,
) => chosen == InboxDelivery.now && !(targetMode?.acceptsNow ?? true)
    ? InboxDelivery.turnEnd
    : chosen;

/// Deliver: Now or When the Agent Finishes Its Turn, with what each does.
/// Shown only for hosts that advertise `inboxV2`.
class const QuestionDeliveryChoice({
  super.key,
  required final InboxDelivery selected,
  required final ValueChanged<InboxDelivery> onChanged,
  final InboxDeliveryMode? targetMode,
  final Duration expiry = questionDefaultExpiry,
  final bool enabled = true,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final nowBlocked = targetMode == null
        ? null
        : questionDeliverNowUnavailableReason(targetMode!);
    return AleraSegmentedChoice<InboxDelivery>(
      label: 'Deliver',
      selected: effectiveQuestionDelivery(selected, targetMode),
      onChanged: onChanged,
      enabled: enabled,
      options: <AleraSegmentedChoiceOption<InboxDelivery>>[
        AleraSegmentedChoiceOption<InboxDelivery>(
          value: InboxDelivery.now,
          label: 'Now',
          helper: questionDeliverNowHelper,
          enabled: nowBlocked == null,
          disabledReason: nowBlocked,
        ),
        AleraSegmentedChoiceOption<InboxDelivery>(
          value: InboxDelivery.turnEnd,
          label: 'When the Agent Finishes Its Turn',
          helper: questionDeliverTurnEndHelper(expiry),
        ),
      ],
    );
  }
}
