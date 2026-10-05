import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/badges/alera_badge.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/automations/domain/automation_status_labels.dart';
import 'package:flutter/material.dart';

AleraBadgeTone mobileAutomationBadgeTone(AutomationTone tone) => switch (tone) {
  AutomationTone.info => AleraBadgeTone.info,
  AutomationTone.success => AleraBadgeTone.success,
  AutomationTone.warning => AleraBadgeTone.attention,
  AutomationTone.error => AleraBadgeTone.error,
  AutomationTone.neutral => AleraBadgeTone.neutral,
};

Color mobileAutomationToneColor(AutomationTone tone) => switch (tone) {
  AutomationTone.info => AleraTokens.info,
  AutomationTone.success => AleraTokens.success,
  AutomationTone.warning => AleraTokens.warning,
  AutomationTone.error => AleraTokens.error,
  AutomationTone.neutral => AleraTokens.foregroundMuted,
};

/// Final runs never use the progress icon, so a skipped run cannot read as
/// still working.
IconData mobileAutomationStatusIcon(AutomationStatusLabel status) {
  if (status.inProgress) return AleraIcons.loading;
  return switch (status.tone) {
    AutomationTone.success => AleraIcons.success,
    AutomationTone.error || AutomationTone.warning => AleraIcons.warning,
    AutomationTone.info => AleraIcons.info,
    AutomationTone.neutral => AleraIcons.cancel,
  };
}

class const MobileAutomationStatusText({
  required final AutomationStatusLabel status,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final color = mobileAutomationToneColor(status.tone);
    return Row(
      mainAxisSize: .min,
      children: <Widget>[
        Icon(
          mobileAutomationStatusIcon(status),
          size: AleraTokens.iconSm,
          color: color,
        ),
        const SizedBox(width: AleraTokens.spaceXs),
        Flexible(
          child: Text(
            status.label,
            maxLines: 1,
            overflow: .ellipsis,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}
