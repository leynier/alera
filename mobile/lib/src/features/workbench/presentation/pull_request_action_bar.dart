import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/design_system/menus/alera_action_sheet.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_pull_request_actions.dart';
import 'package:flutter/material.dart';

/// The phone counterpart of the desktop split button: the first action as a
/// full-width button, disabled when it cannot run, and the other available
/// actions in a bottom sheet behind the overflow button.
///
/// The primary stays the first action even when it is disabled, because a
/// conflicting pull request must still read as "merge, but not yet" rather
/// than silently promoting Convert To Draft into the button the user taps.
class const PullRequestActionBar({
  super.key,
  required final List<MobilePullRequestReviewAction> actions,
  required final bool Function(MobilePullRequestReviewAction action) isEnabled,
  required final bool busy,
  required final ValueChanged<MobilePullRequestReviewAction> onSelected,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) {
      return const SizedBox.shrink();
    }
    final primary = actions.first;
    final primaryEnabled = isEnabled(primary);
    final others = <MobilePullRequestReviewAction>[
      for (final action in actions)
        if (action != primary && isEnabled(action)) action,
    ];
    final style = primary.destructive
        ? FilledButton.styleFrom(
            backgroundColor: AleraTokens.error,
            foregroundColor: AleraTokens.onError,
          )
        : null;
    return Row(
      children: <Widget>[
        Expanded(
          child: FilledButton.icon(
            key: ValueKey<String>('pull-request-action-${primary.label}'),
            style: style,
            onPressed: busy || !primaryEnabled
                ? null
                : () => onSelected(primary),
            icon: busy
                ? const SizedBox.square(
                    dimension: AleraTokens.iconSm,
                    child: CircularProgressIndicator(
                      strokeWidth: AleraTokens.strokeMd,
                    ),
                  )
                : Icon(pullRequestReviewActionIcon(primary)),
            label: Text(primary.label, maxLines: 1, overflow: .ellipsis),
          ),
        ),
        if (others.isNotEmpty) ...<Widget>[
          const SizedBox(width: AleraTokens.space8),
          IconButton.outlined(
            tooltip: 'Pull Request Actions',
            onPressed: busy
                ? null
                : () => unawaited(_openSheet(context, others)),
            icon: const Icon(AleraIcons.more),
          ),
        ],
      ],
    );
  }

  Future<void> _openSheet(
    BuildContext context,
    List<MobilePullRequestReviewAction> options,
  ) async {
    final selected = await showAleraActionSheet<MobilePullRequestReviewAction>(
      context,
      entries: <AleraActionSheetEntry<MobilePullRequestReviewAction>>[
        for (final action in options)
          AleraActionSheetEntry<MobilePullRequestReviewAction>(
            value: action,
            label: action.label,
            leading: Icon(
              pullRequestReviewActionIcon(action),
              color: action.destructive ? AleraTokens.error : null,
            ),
          ),
      ],
    );
    if (selected != null) {
      onSelected(selected);
    }
  }
}

IconData pullRequestReviewActionIcon(MobilePullRequestReviewAction action) {
  return switch (action.kind) {
    .markReady => AleraIcons.success,
    .merge => AleraIcons.gitMerge,
    .convertToDraft => AleraIcons.gitPullRequestDraft,
    .close => AleraIcons.gitPullRequestClosed,
    .unlink => AleraIcons.unlink,
  };
}
