import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

/// One row of [AleraComposerSuggestions]. A row with a [disabledReason]
/// stays listed with the reason in place of its [detail] and cannot be
/// picked.
final class const AleraComposerSuggestion({
  required final String id,
  required final String label,
  final String? detail,
  final Widget? leading,
  final String? disabledReason,
}) {
  bool get enabled => disabledReason == null;
}

/// Suggestions that open above the composer while the person types, such as
/// `@` file mentions or `/` commands: the phone's counterpart of the desktop
/// `AleraComposerMenu`. Tapping a row picks it and Close dismisses the list.
///
/// The list counts as part of the text field for taps, so picking a row does
/// not take the focus (and the keyboard) away from the field first. It shows
/// at most [maxVisibleRows] rows and scrolls the rest; an empty or loading
/// list says so in sentence case.
class const AleraComposerSuggestions({
  super.key,
  required final String title,
  required final List<AleraComposerSuggestion> items,
  required final ValueChanged<int> onPick,
  required final VoidCallback onDismiss,
  final String? semanticsLabel,
  final bool loading = false,
  final String loadingMessage = 'Loading…',
  final String emptyMessage = 'No suggestions.',
  final double maxVisibleRows = 4.5,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = items.isEmpty
        ? (loading ? loadingMessage : emptyMessage)
        : null;
    return LayoutBuilder(
      builder: (context, constraints) => _build(
        theme,
        message,
        // The rows give way to the header when the parent has less room
        // than their budget, such as a composer squeezed by the keyboard.
        constraints.hasBoundedHeight
            ? (constraints.maxHeight - AleraTokens.minTapTarget).clamp(
                0.0,
                AleraTokens.minTapTarget * maxVisibleRows,
              )
            : AleraTokens.minTapTarget * maxVisibleRows,
      ),
    );
  }

  Widget _build(ThemeData theme, String? message, double listHeight) {
    return TextFieldTapRegion(
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        label: semanticsLabel ?? title,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AleraTokens.surfaceElevated,
            borderRadius: BorderRadius.circular(AleraTokens.radiusXl),
            border: Border.all(color: AleraTokens.border),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AleraTokens.radiusXl),
            child: Column(
              mainAxisSize: .min,
              crossAxisAlignment: .stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(left: AleraTokens.space16),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          title,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: AleraTokens.foregroundMuted,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close Suggestions',
                        visualDensity: .compact,
                        onPressed: onDismiss,
                        icon: const Icon(
                          AleraIcons.close,
                          size: AleraTokens.iconMd,
                        ),
                      ),
                    ],
                  ),
                ),
                if (loading)
                  const LinearProgressIndicator(
                    minHeight: AleraTokens.progressBarHeight,
                  ),
                if (message != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AleraTokens.space16,
                      AleraTokens.space4,
                      AleraTokens.space16,
                      AleraTokens.space12,
                    ),
                    child: Text(
                      message,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AleraTokens.foregroundMuted,
                      ),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: listHeight),
                    child: ListView.builder(
                      shrinkWrap: true,
                      primary: false,
                      padding: const EdgeInsets.only(
                        bottom: AleraTokens.space4,
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, index) => _SuggestionRow(
                        item: items[index],
                        onTap: () => onPick(index),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class const _SuggestionRow({
  required final AleraComposerSuggestion item,
  required final VoidCallback onTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = item.enabled;
    final secondary = item.disabledReason ?? item.detail;
    return Semantics(
      button: true,
      enabled: enabled,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AleraTokens.minTapTarget,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AleraTokens.space16,
              vertical: AleraTokens.space6,
            ),
            child: Row(
              children: <Widget>[
                if (item.leading != null) ...<Widget>[
                  item.leading!,
                  const SizedBox(width: AleraTokens.space12),
                ],
                Expanded(
                  child: Column(
                    mainAxisSize: .min,
                    crossAxisAlignment: .start,
                    children: <Widget>[
                      Text(
                        item.label,
                        maxLines: 1,
                        overflow: .ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: enabled
                              ? AleraTokens.foreground
                              : AleraTokens.foregroundFaint,
                        ),
                      ),
                      if (secondary != null)
                        Text(
                          secondary,
                          maxLines: 1,
                          overflow: .ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: enabled
                                ? AleraTokens.foregroundMuted
                                : AleraTokens.foregroundFaint,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
