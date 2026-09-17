import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/design_system/menus/alera_action_sheet.dart';
import 'package:alera_mobile/src/features/workbench/domain/pull_request_agent_watch.dart';
import 'package:alera_mobile/src/features/workbench/domain/pull_request_agent_watch_scope.dart';
import 'package:flutter/material.dart';

class const PullRequestWatchSheetResult({
  required final PullRequestAgentWatchMode mode,
  required final PullRequestAgentWatchScope scope,
});

/// Scope toggles plus Watch and Fix / Watch, Fix and Merge. Phone counterpart
/// of the desktop Ask Agent menu.
Future<PullRequestWatchSheetResult?> showPullRequestWatchSheet(
  BuildContext context, {
  required PullRequestAgentWatchScope initialScope,
  required bool canFixAndMerge,
}) {
  return showModalBottomSheet<PullRequestWatchSheetResult>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => _PullRequestWatchSheet(
      initialScope: initialScope,
      canFixAndMerge: canFixAndMerge,
    ),
  );
}

class const _PullRequestWatchSheet({
  required this.initialScope,
  required this.canFixAndMerge,
}) extends StatefulWidget {
  final PullRequestAgentWatchScope initialScope;
  final bool canFixAndMerge;

  @override
  State<_PullRequestWatchSheet> createState() => _PullRequestWatchSheetState();
}

class _PullRequestWatchSheetState extends State<_PullRequestWatchSheet> {
  late PullRequestAgentWatchScope _scope = widget.initialScope;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canStart = !_scope.isEmpty;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AleraTokens.space16,
          0,
          AleraTokens.space16,
          AleraTokens.space16,
        ),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: <Widget>[
            Text('Ask Agent', style: theme.textTheme.titleMedium),
            const SizedBox(height: AleraTokens.space8),
            Text(
              'Watch the pull request and send a prompt when new problems appear.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Failed Checks'),
              value: _scope.checks,
              onChanged: (value) => setState(
                () => _scope = _scope.copyWith(checks: value ?? false),
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Review Comments'),
              value: _scope.comments,
              onChanged: (value) => setState(
                () => _scope = _scope.copyWith(comments: value ?? false),
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Merge Conflicts'),
              value: _scope.conflicts,
              onChanged: (value) => setState(
                () => _scope = _scope.copyWith(conflicts: value ?? false),
              ),
            ),
            const SizedBox(height: AleraTokens.space8),
            FilledButton.icon(
              onPressed: canStart
                  ? () => Navigator.of(context).pop(
                      PullRequestWatchSheetResult(
                        mode: PullRequestAgentWatchMode.fix,
                        scope: _scope,
                      ),
                    )
                  : null,
              icon: const Icon(AleraIcons.agent),
              label: const Text('Watch and Fix'),
            ),
            if (widget.canFixAndMerge) ...<Widget>[
              const SizedBox(height: AleraTokens.space8),
              OutlinedButton.icon(
                onPressed: canStart
                    ? () => Navigator.of(context).pop(
                        PullRequestWatchSheetResult(
                          mode: PullRequestAgentWatchMode.fixAndMerge,
                          scope: _scope,
                        ),
                      )
                    : null,
                icon: const Icon(AleraIcons.gitMerge),
                label: const Text('Watch, Fix and Merge'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class const PullRequestWatchHeaderButton({
  super.key,
  required this.reviewIsOpen,
  required this.busy,
  required this.watchMode,
  required this.watchScope,
  required this.canFixAndMerge,
  required this.onWatchScopeChanged,
  required this.onWatchStarted,
  required this.onStopAgentWatch,
}) extends StatelessWidget {
  final bool reviewIsOpen;
  final bool busy;
  final PullRequestAgentWatchMode? watchMode;
  final PullRequestAgentWatchScope watchScope;
  final bool canFixAndMerge;
  final ValueChanged<PullRequestAgentWatchScope> onWatchScopeChanged;
  final ValueChanged<PullRequestWatchSheetResult> onWatchStarted;
  final VoidCallback? onStopAgentWatch;

  @override
  Widget build(BuildContext context) {
    final mode = watchMode;
    if (mode != null) {
      return AleraIconButton(
        tooltip: pullRequestAgentWatchModeLabel(mode),
        icon: AleraIcons.visible,
        onPressed: onStopAgentWatch == null
            ? null
            : () => unawaited(_openStopSheet(context)),
      );
    }
    if (!reviewIsOpen) {
      return const SizedBox.shrink();
    }
    return AleraIconButton(
      tooltip: 'Ask Agent',
      icon: AleraIcons.agent,
      onPressed: busy ? null : () => unawaited(_openWatchSheet(context)),
    );
  }

  Future<void> _openStopSheet(BuildContext context) async {
    final selected = await showAleraActionSheet<bool>(
      context,
      entries: const <AleraActionSheetEntry<bool>>[
        AleraActionSheetEntry<bool>(
          value: true,
          label: 'Stop Watching',
          leading: Icon(AleraIcons.hidden),
        ),
      ],
    );
    if (selected == true) {
      onStopAgentWatch?.call();
    }
  }

  Future<void> _openWatchSheet(BuildContext context) async {
    final result = await showPullRequestWatchSheet(
      context,
      initialScope: watchScope,
      canFixAndMerge: canFixAndMerge,
    );
    if (result == null) {
      return;
    }
    onWatchScopeChanged(result.scope);
    onWatchStarted(result);
  }
}

class const PullRequestWatchStatus({super.key, required this.mode})
    extends StatelessWidget {
  final PullRequestAgentWatchMode mode;

  @override
  Widget build(BuildContext context) {
    return Text(
      pullRequestAgentWatchModeLabel(mode),
      style: Theme.of(context).textTheme.labelSmall
          ?.copyWith(color: AleraTokens.foregroundMuted),
    );
  }
}

class const PullRequestFixFailedChecksButton({
  super.key,
  required this.visible,
  required this.onPressed,
}) extends StatelessWidget {
  final bool visible;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (!visible) {
      return const SizedBox.shrink();
    }
    return TextButton(
      key: const Key('pull-request-fix-failed-checks'),
      onPressed: onPressed,
      child: const Text('Fix Failed Checks'),
    );
  }
}
