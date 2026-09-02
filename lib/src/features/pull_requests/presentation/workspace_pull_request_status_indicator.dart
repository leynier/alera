import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/workspace_pull_request_summary.dart';
import 'package:flutter/material.dart';

/// GitHub-style pull-request lifecycle icon with a small, static check badge.
/// The badge deliberately does not animate: dozens of workspace rows still use
/// zero per-row tickers while running checks remain immediately recognizable.
class const WorkspacePullRequestStatusIndicator({
  super.key,
  required this.summary,
  this.size = AleraTokens.iconSm,
}) extends StatelessWidget {
  final WorkspacePullRequestSummary summary;
  final double size;

  @override
  Widget build(BuildContext context) {
    final badge = _badgeFor(summary);
    return Tooltip(
      message: workspacePullRequestStatusTooltip(summary),
      child: SizedBox.square(
        dimension: size + 2,
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Align(
              alignment: Alignment.topLeft,
              child: Icon(
                _iconFor(summary.review.state),
                size: size,
                color: _colorFor(summary.review.state),
              ),
            ),
            if (badge != null)
              Positioned(
                right: -1,
                bottom: -1,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: AleraTokens.surfaceVariant,
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(0.5),
                    child: Icon(
                      badge.icon,
                      size: size * 0.62,
                      color: badge.color,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String workspacePullRequestStatusTooltip(WorkspacePullRequestSummary summary) {
  final review = summary.review;
  final lines = <String>['PR #${review.number}: ${review.title}'];
  switch (review.state) {
    case HostedReviewState.merged:
      lines.add('Merged');
    case HostedReviewState.closed:
      lines.add('Closed without merging');
    case HostedReviewState.draft:
      lines.add('Draft');
      _appendCheckProgress(lines, summary);
    case HostedReviewState.open:
      if (summary.hasMergeConflict) {
        lines.add('Merge conflict');
      } else if (!_appendCheckProgress(lines, summary)) {
        lines.add(
          review.mergeable == HostedReviewMergeable.mergeable
              ? 'Ready to merge'
              : 'Open',
        );
      }
  }
  return lines.join('\n');
}

bool _appendCheckProgress(
  List<String> lines,
  WorkspacePullRequestSummary summary,
) {
  if (summary.checksFailed) {
    lines
      ..add('Checks failed')
      ..add(_failureDetails(summary));
    return true;
  }
  if (summary.checksPending) {
    lines.add(
      _countLabel(summary.pendingCheckCount, 'check running', 'checks running'),
    );
    return true;
  }
  return false;
}

String _failureDetails(WorkspacePullRequestSummary summary) {
  final names = summary.failingCheckNames.join(', ');
  final hidden = summary.failedCheckCount - summary.failingCheckNames.length;
  if (names.isEmpty) {
    return summary.failedCheckCount == 1
        ? '1 failed check'
        : '${summary.failedCheckCount} failed checks';
  }
  return hidden > 0 ? '$names, +$hidden more' : names;
}

String _countLabel(int count, String singular, String plural) {
  return count == 1 ? '1 $singular' : '$count $plural';
}

IconData _iconFor(HostedReviewState state) => switch (state) {
  HostedReviewState.open => AleraIcons.gitPullRequest,
  HostedReviewState.draft => AleraIcons.gitPullRequestDraft,
  HostedReviewState.merged => AleraIcons.gitMerge,
  HostedReviewState.closed => AleraIcons.gitPullRequestClosed,
};

Color _colorFor(HostedReviewState state) => switch (state) {
  HostedReviewState.open => AleraTokens.success,
  HostedReviewState.draft => AleraTokens.foregroundMuted,
  HostedReviewState.merged => AleraTokens.done,
  HostedReviewState.closed => AleraTokens.error,
};

({IconData icon, Color color})? _badgeFor(WorkspacePullRequestSummary summary) {
  if (summary.review.state
      case HostedReviewState.merged || HostedReviewState.closed) {
    return null;
  }
  if (summary.checksFailed || summary.hasMergeConflict) {
    return (icon: AleraIcons.cancel, color: AleraTokens.error);
  }
  if (summary.checksPending) {
    return (icon: AleraIcons.loading, color: AleraTokens.warning);
  }
  return null;
}
