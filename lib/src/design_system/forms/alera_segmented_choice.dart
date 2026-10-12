import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_segmented_button.dart';
import 'package:flutter/material.dart';

/// One option of an [AleraSegmentedChoice]. [helper] explains what picking it
/// does; [disabledReason] explains why it cannot be picked right now.
class const AleraSegmentedChoiceOption<T>({
  required final T value,
  required final String label,
  required final String helper,
  final bool enabled = true,
  final String? disabledReason,
});

/// A labelled choice between two or three options, with the helper text of
/// the selected option underneath and the reason any option is disabled.
///
/// The label sits above the segments rather than beside them: option labels
/// such as "When the Agent Finishes Its Turn" do not fit next to a label in a
/// dialog, and the segments share their width equally.
class const AleraSegmentedChoice<T>({
  super.key,
  required final String label,
  required final List<AleraSegmentedChoiceOption<T>> options,
  required final T selected,
  required final ValueChanged<T> onChanged,
  final bool enabled = true,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: AleraTokens.foregroundMuted,
    );
    final current = options.where((option) => option.value == selected);
    final reasons = <String>[
      for (final option in options)
        if (!option.enabled && option.disabledReason != null)
          option.disabledReason!,
    ];
    return Column(
      crossAxisAlignment: .stretch,
      mainAxisSize: .min,
      spacing: AleraTokens.space4,
      children: <Widget>[
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: AleraTokens.foregroundMuted,
          ),
        ),
        AleraSegmentedButton<T>(
          dense: true,
          selected: selected,
          onSelectionChanged: onChanged,
          segments: <ButtonSegment<T>>[
            for (final option in options)
              ButtonSegment<T>(
                value: option.value,
                label: Text(option.label),
                enabled: enabled && option.enabled,
                tooltip: option.enabled ? null : option.disabledReason,
              ),
          ],
        ),
        if (current.isNotEmpty) Text(current.first.helper, style: muted),
        for (final reason in reasons) Text(reason, style: muted),
      ],
    );
  }
}
