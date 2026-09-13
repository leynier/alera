import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:flutter/material.dart';
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
class const PullRequestChecksSection({
  super.key,
  required final List<MobilePullRequestCheck> checks,
}) extends StatefulWidget {
  static const int _collapseSettledAbove = 5;

  @override
  State<PullRequestChecksSection> createState() =>
      _PullRequestChecksSectionState();
}

class _PullRequestChecksSectionState extends State<PullRequestChecksSection> {
  bool _showSettled = false;

  @override
  Widget build(BuildContext context) {
    final checks = widget.checks;
    final settled = <MobilePullRequestCheck>[
      for (final check in checks)
        if (_isSettled(check)) check,
    ];
    if (checks.length <= PullRequestChecksSection._collapseSettledAbove ||
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
                    pullRequestChecksSummary(settled),
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

String pullRequestChecksSummary(List<MobilePullRequestCheck> checks) {
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
