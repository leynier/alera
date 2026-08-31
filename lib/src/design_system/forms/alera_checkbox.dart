import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

/// Tokenized checkbox with an optional trailing [label].
///
/// Replaces the raw Material [Checkbox] so check controls share the Alera
/// accent, radius, and hover treatment.
class const AleraCheckbox({
  super.key,
  required final bool value,
  required final ValueChanged<bool> onChanged,
  final String? label,
  final bool enabled = true,
}) extends StatelessWidget {
  static const double _boxSize = 18;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final box = AnimatedContainer(
      duration: AleraTokens.durationFast,
      width: _boxSize,
      height: _boxSize,
      decoration: BoxDecoration(
        color: value
            ? (enabled ? AleraTokens.accent : AleraTokens.foregroundFaint)
            : AleraTokens.surfaceVariant,
        borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
        border: Border.all(
          color: value ? Colors.transparent : AleraTokens.border,
        ),
      ),
      child: value
          ? const Icon(AleraIcons.check, size: 14, color: AleraTokens.onAccent)
          : null,
    );
    return Semantics(
      checked: value,
      enabled: enabled,
      label: label,
      child: InkWell(
        onTap: enabled ? () => onChanged(!value) : null,
        borderRadius: .circular(AleraTokens.radiusSm),
        mouseCursor: enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        child: Padding(
          padding: const EdgeInsets.all(AleraTokens.space4),
          child: label == null
              ? box
              : Row(
                  mainAxisSize: .min,
                  children: <Widget>[
                    box,
                    const SizedBox(width: AleraTokens.space8),
                    Text(
                      label!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: enabled
                            ? AleraTokens.foreground
                            : AleraTokens.foregroundFaint,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
