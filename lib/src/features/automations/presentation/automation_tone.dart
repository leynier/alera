import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/automations/domain/automation_status_labels.dart';
import 'package:flutter/material.dart';

AleraBadgeTone automationBadgeTone(AutomationTone tone) => switch (tone) {
  AutomationTone.info => AleraBadgeTone.info,
  AutomationTone.success => AleraBadgeTone.success,
  AutomationTone.warning => AleraBadgeTone.attention,
  AutomationTone.error => AleraBadgeTone.error,
  AutomationTone.neutral => AleraBadgeTone.neutral,
};

Color automationToneColor(AutomationTone tone) =>
    automationBadgeTone(tone).foreground;

/// A badge tinted with the tone and labeled in it.
class const AutomationToneBadge({
  required final String label,
  required final AutomationTone tone,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AleraBadge(label: label, tone: automationBadgeTone(tone));
  }
}

/// Final runs never use the progress icon, so a skipped run cannot read as
/// still working.
IconData automationStatusIcon(AutomationStatusLabel status) {
  if (status.inProgress) return AleraIcons.loading;
  return switch (status.tone) {
    AutomationTone.success => AleraIcons.success,
    AutomationTone.error => AleraIcons.error,
    AutomationTone.warning => AleraIcons.warning,
    AutomationTone.info => AleraIcons.info,
    AutomationTone.neutral => AleraIcons.blocked,
  };
}

class const AutomationStatusText({
  required final AutomationStatusLabel status,
  final TextStyle? style,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final color = automationToneColor(status.tone);
    return Row(
      mainAxisSize: .min,
      children: <Widget>[
        Icon(
          automationStatusIcon(status),
          size: AleraTokens.iconSm,
          color: color,
        ),
        const SizedBox(width: AleraTokens.space4),
        Flexible(
          child: Text(
            status.label,
            maxLines: 1,
            overflow: .ellipsis,
            style: (style ?? Theme.of(context).textTheme.bodySmall)?.copyWith(
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}
