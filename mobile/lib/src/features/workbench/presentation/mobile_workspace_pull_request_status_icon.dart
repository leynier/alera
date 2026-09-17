import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_pull_request_summary.dart';
import 'package:flutter/material.dart';

/// GitHub-style pull-request lifecycle icon with a small, static check badge,
/// mirroring the desktop `WorkspacePullRequestStatusIndicator`. The badge does
/// not animate so dozens of workspace rows add zero per-row tickers.
class const MobileWorkspacePullRequestStatusIcon({
  super.key,
  required this.summary,
  this.size = AleraTokens.iconSm,
}) extends StatelessWidget {
  final MobileWorkspacePullRequestSummary summary;
  final double size;

  @override
  Widget build(BuildContext context) {
    final badge = _badgeFor(summary);
    return Tooltip(
      message: mobileWorkspacePullRequestStatusTooltip(summary),
      child: SizedBox.square(
        dimension: size + 2,
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Align(
              alignment: Alignment.topLeft,
              child: Icon(
                _iconFor(summary.state),
                size: size,
                color: _colorFor(summary.state),
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

String mobileWorkspacePullRequestStatusTooltip(
  MobileWorkspacePullRequestSummary summary,
) {
  final lines = <String>['PR #${summary.number}: ${summary.title}'];
  switch (summary.state) {
    case MobileWorkspacePullRequestState.merged:
      lines.add('Merged');
    case MobileWorkspacePullRequestState.closed:
      lines.add('Closed without merging');
    case MobileWorkspacePullRequestState.draft:
      lines.add('Draft');
      _appendCheckProgress(lines, summary);
    case MobileWorkspacePullRequestState.open:
      if (summary.hasMergeConflict) {
        lines.add('Merge conflict');
      } else if (!_appendCheckProgress(lines, summary)) {
        lines.add(
          summary.mergeable == MobileWorkspacePullRequestMergeable.mergeable
              ? 'Ready to merge'
              : 'Open',
        );
      }
  }
  return lines.join('\n');
}

bool _appendCheckProgress(
  List<String> lines,
  MobileWorkspacePullRequestSummary summary,
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

String _failureDetails(MobileWorkspacePullRequestSummary summary) {
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

IconData _iconFor(MobileWorkspacePullRequestState state) => switch (state) {
  MobileWorkspacePullRequestState.open => AleraIcons.gitPullRequest,
  MobileWorkspacePullRequestState.draft => AleraIcons.gitPullRequestDraft,
  MobileWorkspacePullRequestState.merged => AleraIcons.gitMerge,
  MobileWorkspacePullRequestState.closed => AleraIcons.gitPullRequestClosed,
};

Color _colorFor(MobileWorkspacePullRequestState state) => switch (state) {
  MobileWorkspacePullRequestState.open => AleraTokens.success,
  MobileWorkspacePullRequestState.draft => AleraTokens.warning,
  MobileWorkspacePullRequestState.merged => AleraTokens.info,
  MobileWorkspacePullRequestState.closed => AleraTokens.foregroundMuted,
};

({IconData icon, Color color})? _badgeFor(
  MobileWorkspacePullRequestSummary summary,
) {
  if (summary.state
      case MobileWorkspacePullRequestState.merged ||
          MobileWorkspacePullRequestState.closed) {
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
