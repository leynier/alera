import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/badges/alera_badge.dart';
import 'package:alera_mobile/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_notice.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/design_system/layout/alera_section_header.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/workbench/application/pull_request_controller.dart';
import 'package:alera_mobile/src/features/workbench/presentation/pull_request_conversation_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

final _githubExpression = RegExp(r'\$\{\{\s*([^}]+?)\s*\}\}');

/// Collapses GitHub Actions `${{ matrix.platform }}` tokens so check names
/// stay readable on a phone.
String displayPullRequestCheckName(String name) {
  return name.replaceAllMapped(_githubExpression, (match) {
    final inner = match[1]!.trim();
    final parts = inner.split('.');
    return '{${parts.last.trim()}}';
  });
}

class const PullRequestPanel({
  super.key,
  required final String hostId,
  required final String workspaceId,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pullRequestControllerProvider(hostId, workspaceId));
    return switch (state) {
      AsyncData(value: final snapshot) => _Body(snapshot: snapshot),
      AsyncError(:final error) => AleraEmptyState(
        icon: AleraIcons.gitPullRequest,
        message: error.toString(),
        action: FilledButton(
          onPressed: () => ref
              .read(pullRequestControllerProvider(hostId, workspaceId).notifier)
              .reload(),
          child: const Text('Retry'),
        ),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

class const _Body({required final MobilePullRequestSnapshot snapshot})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final review = snapshot.review;
    if (review == null) {
      return AleraEmptyState(
        icon: AleraIcons.gitPullRequest,
        title: snapshot.identity?.label ?? snapshot.branch ?? 'Pull Request',
        message:
            snapshot.unavailableReason ??
            'No pull request is available for this workspace.',
      );
    }
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AleraTokens.space16,
        AleraTokens.space16,
        AleraTokens.space16,
        AleraTokens.space24,
      ),
      children: <Widget>[
        _Header(snapshot: snapshot, review: review),
        const SizedBox(height: AleraTokens.space12),
        const AleraNotice(
          icon: AleraIcons.info,
          message:
              'Comments are read-only. Reply, edit, and merge stay on desktop.',
        ),
        const SizedBox(height: AleraTokens.space16),
        AleraSectionHeader(
          label: 'Checks',
          padding: const EdgeInsets.only(bottom: AleraTokens.space8),
          trailing: review.checks.isEmpty
              ? null
              : Text(
                  _checksSummary(review.checks),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AleraTokens.foregroundFaint,
                  ),
                ),
        ),
        if (review.checks.isEmpty)
          Text(
            'No checks were returned for this pull request.',
            style: theme.textTheme.bodySmall,
          )
        else
          _ChecksSection(checks: review.checks),
        const SizedBox(height: AleraTokens.space16),
        PullRequestConversationSection(comments: review.comments),
      ],
    );
  }
}

class const _Header({
  required final MobilePullRequestSnapshot snapshot,
  required final MobilePullRequestReview review,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final identity = snapshot.identity?.label;
    final stateLabel = _reviewStateLabel(review);
    return Column(
      crossAxisAlignment: .start,
      children: <Widget>[
        if (identity != null)
          Text(
            identity,
            maxLines: 1,
            overflow: .ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          ),
        Row(
          crossAxisAlignment: .center,
          children: <Widget>[
            Expanded(
              child: Text(review.title, style: theme.textTheme.titleLarge),
            ),
            if (review.url.isNotEmpty)
              AleraIconButton(
                tooltip: 'Open In Browser',
                icon: AleraIcons.external,
                onPressed: () => _openUrl(review.url),
              ),
          ],
        ),
        const SizedBox(height: AleraTokens.space8),
        Wrap(
          spacing: AleraTokens.space8,
          runSpacing: AleraTokens.space6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            AleraBadge(
              label: stateLabel,
              color: _reviewStateColor(stateLabel).withValues(alpha: 0.16),
              foregroundColor: _reviewStateColor(stateLabel),
            ),
            Text('#${review.number}', style: theme.textTheme.bodySmall),
            if (review.author != null)
              Text(review.author!, style: theme.textTheme.bodySmall),
          ],
        ),
        if (review.baseRefName != null &&
            review.headRefName != null) ...<Widget>[
          const SizedBox(height: AleraTokens.space8),
          Row(
            children: <Widget>[
              const Icon(
                AleraIcons.gitBranch,
                size: 14,
                color: AleraTokens.foregroundMuted,
              ),
              const SizedBox(width: AleraTokens.space6),
              Expanded(
                child: Text(
                  review.headRefName!,
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: AleraTokens.monoStyle,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AleraTokens.space6,
                ),
                child: Text('into', style: theme.textTheme.bodySmall),
              ),
              Flexible(
                child: Text(
                  review.baseRefName!,
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: AleraTokens.monoStyle,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class const _CheckRow({required final MobilePullRequestCheck check})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visual = pullRequestCheckVisual(check);
    final displayName = displayPullRequestCheckName(check.name);
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AleraTokens.minTapTarget),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AleraTokens.space6),
        child: Row(
          children: <Widget>[
            Icon(visual.icon, size: 16, color: visual.color),
            const SizedBox(width: AleraTokens.space8),
            Expanded(
              child: Text(
                displayName,
                maxLines: 1,
                overflow: .ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            const SizedBox(width: AleraTokens.space8),
            Text(
              visual.label,
              style: theme.textTheme.labelSmall?.copyWith(color: visual.color),
            ),
          ],
        ),
      ),
    );
    final url = check.url;
    return Tooltip(
      message: check.name,
      child: url == null
          ? row
          : InkWell(onTap: () => _openUrl(url), child: row),
    );
  }
}

/// Failing and pending checks always show; above [_collapseSettledAbove]
/// checks the passed and skipped ones fold behind one row, so a long CI run
/// does not push the conversation off the screen.
class const _ChecksSection({required final List<MobilePullRequestCheck> checks})
    extends StatefulWidget {
  static const int _collapseSettledAbove = 5;

  @override
  State<_ChecksSection> createState() => _ChecksSectionState();
}

class _ChecksSectionState extends State<_ChecksSection> {
  bool _showSettled = false;

  @override
  Widget build(BuildContext context) {
    final checks = widget.checks;
    final settled = <MobilePullRequestCheck>[
      for (final check in checks)
        if (_isSettled(check)) check,
    ];
    if (checks.length <= _ChecksSection._collapseSettledAbove ||
        settled.isEmpty) {
      return Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[for (final check in checks) _CheckRow(check: check)],
      );
    }
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        for (final check in checks)
          if (!_isSettled(check)) _CheckRow(check: check),
        InkWell(
          onTap: () => setState(() => _showSettled = !_showSettled),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AleraTokens.minTapTarget,
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  _showSettled
                      ? AleraIcons.chevronDown
                      : AleraIcons.chevronRight,
                  size: AleraTokens.iconSm,
                  color: AleraTokens.foregroundMuted,
                ),
                const SizedBox(width: AleraTokens.space8),
                Expanded(
                  child: Text(
                    _checksSummary(settled),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AleraTokens.foregroundMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_showSettled)
          for (final check in settled) _CheckRow(check: check),
      ],
    );
  }

  bool _isSettled(MobilePullRequestCheck check) =>
      switch (pullRequestCheckVisual(check).label) {
        'Pass' || 'Skipped' || 'Cancelled' => true,
        _ => false,
      };
}

class const PullRequestCheckVisual({
  required final String label,
  required final IconData icon,
  required final Color color,
});

PullRequestCheckVisual pullRequestCheckVisual(MobilePullRequestCheck check) {
  final key = (check.bucket.isEmpty ? check.state : check.bucket).toLowerCase();
  return switch (key) {
    'pass' || 'success' => const PullRequestCheckVisual(
      label: 'Pass',
      icon: AleraIcons.success,
      color: AleraTokens.success,
    ),
    'fail' || 'failure' || 'error' => const PullRequestCheckVisual(
      label: 'Fail',
      icon: AleraIcons.cancel,
      color: AleraTokens.error,
    ),
    'skipping' ||
    'skipped' ||
    'skip' ||
    'neutral' => const PullRequestCheckVisual(
      label: 'Skipped',
      icon: AleraIcons.circle,
      color: AleraTokens.foregroundMuted,
    ),
    'cancel' || 'cancelled' => const PullRequestCheckVisual(
      label: 'Cancelled',
      icon: AleraIcons.cancel,
      color: AleraTokens.foregroundMuted,
    ),
    'pending' ||
    'in_progress' ||
    'queued' ||
    'waiting' => const PullRequestCheckVisual(
      label: 'Pending',
      icon: AleraIcons.loading,
      color: AleraTokens.warning,
    ),
    _ => PullRequestCheckVisual(
      label: key.isEmpty ? 'Check' : _titleCase(key),
      icon: AleraIcons.review,
      color: AleraTokens.foregroundMuted,
    ),
  };
}

String _checksSummary(List<MobilePullRequestCheck> checks) {
  var passed = 0;
  var failed = 0;
  var skipped = 0;
  var pending = 0;
  for (final check in checks) {
    switch (pullRequestCheckVisual(check).label) {
      case 'Pass':
        passed += 1;
      case 'Fail':
        failed += 1;
      case 'Skipped' || 'Cancelled':
        skipped += 1;
      default:
        pending += 1;
    }
  }
  return <String>[
    if (failed > 0) '$failed failed',
    if (pending > 0) '$pending pending',
    if (passed > 0) '$passed passed',
    if (skipped > 0) '$skipped skipped',
  ].join(' · ');
}

String _reviewStateLabel(MobilePullRequestReview review) {
  if (review.isDraft) {
    return 'Draft';
  }
  return switch (review.state.toUpperCase()) {
    'MERGED' => 'Merged',
    'CLOSED' => 'Closed',
    'OPEN' => 'Open',
    _ => _titleCase(review.state),
  };
}

Color _reviewStateColor(String label) {
  return switch (label) {
    'Open' => AleraTokens.success,
    'Merged' => AleraTokens.info,
    'Draft' => AleraTokens.warning,
    'Closed' => AleraTokens.foregroundMuted,
    _ => AleraTokens.foregroundMuted,
  };
}

String _titleCase(String value) {
  if (value.isEmpty) {
    return value;
  }
  final lower = value.toLowerCase().replaceAll('_', ' ');
  return lower[0].toUpperCase() + lower.substring(1);
}

void _openUrl(String url) {
  final parsed = Uri.tryParse(url);
  if (parsed == null) {
    return;
  }
  unawaited(launchUrl(parsed, mode: .externalApplication));
}
