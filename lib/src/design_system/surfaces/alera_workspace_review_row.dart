import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/surfaces/alera_workspace_details_card.dart';
import 'package:flutter/material.dart';

/// A pull request inside the workspace details card: the title row opens the
/// review, and a meta line beneath it, aligned with the title, carries the
/// state, the checks summary and the one contextual action.
class const AleraWorkspaceReviewRow({
  super.key,
  required this.label,
  required this.stateLabel,
  required this.stateIcon,
  required this.stateColor,
  required this.tooltip,
  required this.onOpen,
  required this.onMenu,
  this.checksLabel,
  this.checksIcon,
  this.checksColor,
  this.onChecks,
  this.actionLabel,
  this.actionHint,
  this.onAction,
  this.actionCritical = false,
  this.actionPending = false,
  this.compact = false,
}) extends StatelessWidget {
  // Leading padding, icon slot and gap of a detail row, so the meta line
  // starts under the title text.
  static const double _textInset =
      AleraTokens.space8 + AleraTokens.iconLg + AleraTokens.space8;

  final String label;
  final String stateLabel;
  final IconData stateIcon;
  final Color stateColor;
  final String tooltip;
  final VoidCallback onOpen;
  final VoidCallback onMenu;
  final String? checksLabel;
  final IconData? checksIcon;
  final Color? checksColor;
  final VoidCallback? onChecks;
  final String? actionLabel;
  final String? actionHint;
  final VoidCallback? onAction;

  /// Resolve and Fix answer a problem, so they take the error tone.
  final bool actionCritical;
  final bool actionPending;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final checksTone = checksColor ?? AleraTokens.foregroundMuted;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AleraWorkspaceDetailControl(
          tooltip: tooltip,
          onPressed: onOpen,
          onMenu: onMenu,
          menuTooltip: '$label Options',
          child: Row(
            children: [
              AleraWorkspaceDetailLeading(
                child: Icon(stateIcon, color: stateColor),
              ),
              const SizedBox(width: AleraTokens.space8),
              Expanded(
                child: Text(
                  label,
                  maxLines: compact ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(
            left: _textInset,
            right: AleraTokens.space2,
            bottom: AleraTokens.space4,
          ),
          child: SizedBox(
            height: AleraTokens.iconButtonSm,
            child: Row(
              children: [
                Text(
                  stateLabel,
                  maxLines: 1,
                  style: theme.textTheme.bodySmall?.copyWith(color: stateColor),
                ),
                if (checksLabel != null) ...[
                  const SizedBox(width: AleraTokens.space4),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: AleraWorkspaceDetailSegment(
                        tooltip: '$checksLabel · Show Checks',
                        onPressed: onChecks,
                        borderRadius: BorderRadius.circular(
                          AleraTokens.radiusSm,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AleraTokens.space6,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (checksIcon != null) ...[
                              Icon(
                                checksIcon,
                                size: AleraTokens.iconSm,
                                color: checksTone,
                              ),
                              const SizedBox(width: AleraTokens.space4),
                            ],
                            Flexible(
                              child: Text(
                                checksLabel!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: checksTone,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ] else
                  const Spacer(),
                if (actionLabel != null) _action(theme),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _action(ThemeData theme) {
    final tone = actionCritical ? AleraTokens.error : AleraTokens.foreground;
    final tint = actionCritical
        ? AleraTokens.error.withValues(alpha: AleraTokens.statusTintAlpha)
        : AleraTokens.accentSubtle;
    final enabled = onAction != null && !actionPending;
    return AleraWorkspaceDetailSegment(
      tooltip: actionHint ?? actionLabel,
      onPressed: actionPending ? null : onAction,
      borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
      baseColor: tint,
      hoverColor: Color.alphaBlend(tint, tint),
      padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (actionPending) ...[
            AleraWorkspaceDetailSpinner(size: AleraTokens.iconSm, color: tone),
            const SizedBox(width: AleraTokens.space6),
          ],
          Text(
            actionLabel!,
            maxLines: 1,
            style: theme.textTheme.labelLarge?.copyWith(
              color: enabled || actionPending
                  ? tone
                  : AleraTokens.foregroundMuted,
            ),
          ),
        ],
      ),
    );
  }
}
