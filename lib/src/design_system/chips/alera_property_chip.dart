import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/surfaces/hover_container.dart';
import 'package:flutter/material.dart';

/// Inline property pill for prompt-first forms: an optional [icon] and dim
/// [label], the current [value], and a trailing chevron. It is the anchor of
/// an `AleraPopover`, so [onTap] usually toggles that popover's controller.
///
/// - [active]: the popover it anchors is open.
/// - [hasError]: the value blocks submission; the border turns to the error
///   token.
/// - [fromContext]: the value was seeded from where the form was opened and
///   carries a "From Context" badge.
/// - [onClear]: shows a Clear button that resets the property, in place of
///   the chevron.
/// - Without [onTap] the chip is disabled: muted, not focusable, no hover.
///
/// Built on [HoverContainer], so Tab focuses it, Enter or Space activates it,
/// and a focus ring shows while navigating by keyboard.
class const AleraPropertyChip({
  super.key,
  required final String value,
  final IconData? icon,
  final String? label,
  final VoidCallback? onTap,
  final VoidCallback? onClear,
  final String clearTooltip = 'Clear',
  final bool active = false,
  final bool hasError = false,
  final bool fromContext = false,
  final bool showChevron = true,
  final String? tooltip,
}) extends StatelessWidget {
  static const String fromContextLabel = 'From Context';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onTap != null;
    final valueColor = enabled
        ? AleraTokens.foreground
        : AleraTokens.foregroundFaint;
    final dimColor = enabled
        ? AleraTokens.foregroundMuted
        : AleraTokens.foregroundFaint;
    final borderColor = hasError
        ? AleraTokens.error
        : active
        ? AleraTokens.foregroundFaint
        : AleraTokens.border;
    final baseColor = active
        ? AleraTokens.surfaceElevated
        : AleraTokens.surfaceVariant;
    final textStyle = theme.textTheme.bodySmall;
    final content = Row(
      mainAxisSize: .min,
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Icon(
            icon,
            size: AleraTokens.iconSm,
            color: hasError ? AleraTokens.error : dimColor,
          ),
          const SizedBox(width: AleraTokens.space6),
        ],
        if (label case final label? when label.isNotEmpty) ...<Widget>[
          Text(label, style: textStyle?.copyWith(color: dimColor)),
          const SizedBox(width: AleraTokens.space4),
        ],
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: .ellipsis,
            style: textStyle?.copyWith(color: valueColor, fontWeight: .w500),
          ),
        ),
        if (fromContext) ...<Widget>[
          const SizedBox(width: AleraTokens.space6),
          const AleraBadge(label: fromContextLabel),
        ],
        if (onClear != null) ...<Widget>[
          const SizedBox(width: AleraTokens.space2),
          AleraIconButton(
            tooltip: clearTooltip,
            icon: AleraIcons.close,
            iconSize: AleraTokens.iconSm,
            minSize: AleraTokens.iconButtonXs,
            borderRadius: AleraTokens.radiusXs,
            onPressed: enabled ? onClear : null,
          ),
        ] else if (showChevron) ...<Widget>[
          const SizedBox(width: AleraTokens.space4),
          Icon(
            active ? AleraIcons.chevronUp : AleraIcons.chevronDown,
            size: AleraTokens.iconSm,
            color: dimColor,
          ),
        ],
      ],
    );
    Widget chip = HoverContainer(
      onTap: onTap,
      baseColor: baseColor,
      hoverColor: enabled ? AleraTokens.surfaceElevated : baseColor,
      borderRadius: AleraTokens.radiusSm,
      child: Container(
        constraints: const BoxConstraints(minHeight: AleraTokens.iconButtonSm),
        padding: EdgeInsets.only(
          left: AleraTokens.space8,
          right: onClear != null ? AleraTokens.space2 : AleraTokens.space8,
          top: AleraTokens.space2,
          bottom: AleraTokens.space2,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
          border: Border.all(color: borderColor),
        ),
        child: content,
      ),
    );
    if (tooltip case final message? when message.isNotEmpty) {
      chip = Tooltip(message: message, child: chip);
    }
    return Semantics(enabled: enabled, child: chip);
  }
}
