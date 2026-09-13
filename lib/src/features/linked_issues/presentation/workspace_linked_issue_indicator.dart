import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/linked_issues/application/linked_issue_providers.dart';
import 'package:alera/src/features/linked_issues/domain/linked_issue.dart';
import 'package:alera/src/features/linked_issues/presentation/linked_issue_state_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Issue glyph for a workspace row. Tooltip only: clicking the row still opens
/// the workspace, and the issue itself opens from the context menu.
class const WorkspaceLinkedIssueIndicator({
  super.key,
  required final LinkedIssue issue,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: workspaceLinkedIssueTooltip(issue),
      child: LinkedIssueStateIcon(state: issue.state),
    );
  }
}

String workspaceLinkedIssueTooltip(LinkedIssue issue) {
  final title = issue.title;
  final lines = <String>[
    if (title != null)
      'Issue ${issue.reference}: $title'
    else
      'Issue ${issue.reference}',
  ];
  final state = issue.displayState;
  if (state != null) {
    lines.add(state);
  }
  if (title != null && issue.number != null) {
    lines.add(issue.url);
  }
  final fetchError = issue.fetchError;
  if (fetchError != null) {
    lines.add('Details unavailable: $fetchError');
  } else if (!issue.isFetchable) {
    lines.add('No provider can read this tracker, so only the link is kept');
  }
  return lines.join('\n');
}

/// The indicator for [workspaceId] with its leading gap, or nothing when the
/// workspace has no linked issue.
class const WorkspaceLinkedIssueTrayIcon({
  super.key,
  required final String workspaceId,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final issue = ref.watch(workspaceLinkedIssueProvider(workspaceId));
    if (issue == null) {
      return const SizedBox.shrink();
    }
    return Row(
      mainAxisSize: .min,
      children: <Widget>[
        const SizedBox(width: AleraTokens.space6),
        WorkspaceLinkedIssueIndicator(
          key: const Key('workspace-tray-linked-issue'),
          issue: issue,
        ),
      ],
    );
  }
}
