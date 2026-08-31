import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/pull_requests/domain/review_check.dart';
import 'package:alera/src/features/pull_requests/domain/review_check_details.dart';
import 'package:alera/src/features/pull_requests/presentation/pull_request_check_icon.dart';
import 'package:flutter/material.dart';

/// Presentational list of review checks with expandable rows. Expanding a row
/// lazily fetches that check's details through [onLoadDetails]. Pure: data and
/// callbacks in via parameters, no Riverpod reads.
class const PullRequestCheckList({
  super.key,
  required final List<ReviewCheck> checks,
  required final Future<void> Function(String url) onOpenUrl,
  required final Future<ReviewCheckDetails?> Function(ReviewCheck check)
  onLoadDetails,
}) extends StatefulWidget {
  @override
  State<PullRequestCheckList> createState() => _PullRequestCheckListState();
}

/// A run-status bucket used to group checks in the list.
enum _CheckGroup { failing, inProgress, successful }

/// Buckets a check by its lifecycle/outcome: unfinished runs (or a pending
/// conclusion) are in progress, terminal non-passing outcomes are failing, and
/// everything else counts as successful.
_CheckGroup _groupOf(ReviewCheck check) {
  if (check.status != ReviewCheckStatus.completed ||
      check.conclusion == ReviewCheckConclusion.pending) {
    return _CheckGroup.inProgress;
  }
  return switch (check.conclusion) {
    ReviewCheckConclusion.failure ||
    ReviewCheckConclusion.cancelled ||
    ReviewCheckConclusion.timedOut ||
    ReviewCheckConclusion.actionRequired => _CheckGroup.failing,
    ReviewCheckConclusion.success ||
    ReviewCheckConclusion.neutral ||
    ReviewCheckConclusion.skipped ||
    ReviewCheckConclusion.pending => _CheckGroup.successful,
  };
}

String _groupLabel(_CheckGroup group, int count) {
  final noun = count == 1 ? 'Check' : 'Checks';
  return switch (group) {
    _CheckGroup.failing => '$count failing $noun',
    _CheckGroup.inProgress => '$count in progress $noun',
    _CheckGroup.successful => '$count successful $noun',
  };
}

class _PullRequestCheckListState extends State<PullRequestCheckList> {
  final Set<String> _expandedKeys = <String>{};
  final Map<String, _CheckDetailsState> _detailsByKey =
      <String, _CheckDetailsState>{};
  final Set<_CheckGroup> _collapsedGroups = <_CheckGroup>{};

  // Checks have no stable id; name+url is the closest unique key.
  String _key(ReviewCheck check) => '${check.name}|${check.url ?? ''}';

  @override
  void didUpdateWidget(PullRequestCheckList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final alive = <String>{for (final check in widget.checks) _key(check)};
    _expandedKeys.retainAll(alive);
    _detailsByKey.removeWhere((key, _) => !alive.contains(key));
  }

  void _toggleGroup(_CheckGroup group) {
    setState(() {
      if (!_collapsedGroups.remove(group)) {
        _collapsedGroups.add(group);
      }
    });
  }

  void _toggle(ReviewCheck check) {
    final key = _key(check);
    final expanding = !_expandedKeys.contains(key);
    setState(() {
      if (expanding) {
        _expandedKeys.add(key);
        _detailsByKey[key] = const _CheckDetailsState.loading();
      } else {
        _expandedKeys.remove(key);
      }
    });
    if (!expanding) {
      return;
    }
    widget
        .onLoadDetails(check)
        .then(
          (details) {
            if (!mounted || !_expandedKeys.contains(key)) {
              return;
            }
            setState(() {
              _detailsByKey[key] = _CheckDetailsState.ready(details);
            });
          },
          onError: (Object error) {
            if (!mounted || !_expandedKeys.contains(key)) {
              return;
            }
            setState(() {
              _detailsByKey[key] = _CheckDetailsState.error(error.toString());
            });
          },
        );
  }

  @override
  Widget build(BuildContext context) {
    final grouped = <_CheckGroup, List<ReviewCheck>>{};
    for (final check in widget.checks) {
      grouped.putIfAbsent(_groupOf(check), () => <ReviewCheck>[]).add(check);
    }
    for (final checks in grouped.values) {
      checks.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    }
    return Column(
      mainAxisSize: .min,
      children: <Widget>[
        for (final group in _CheckGroup.values)
          if (grouped[group] case final checks?)
            _CheckGroupSection(
              label: _groupLabel(group, checks.length),
              expanded: !_collapsedGroups.contains(group),
              onToggle: () => _toggleGroup(group),
              children: <Widget>[
                for (final check in checks)
                  Column(
                    mainAxisSize: .min,
                    children: <Widget>[
                      _CheckRow(
                        check: check,
                        expanded: _expandedKeys.contains(_key(check)),
                        onTap: () => _toggle(check),
                        onOpenUrl: widget.onOpenUrl,
                      ),
                      if (_expandedKeys.contains(_key(check)))
                        _CheckDetailsView(
                          state:
                              _detailsByKey[_key(check)] ??
                              const _CheckDetailsState.loading(),
                        ),
                    ],
                  ),
              ],
            ),
      ],
    );
  }
}

class const _CheckGroupSection({
  required final String label,
  required final bool expanded,
  required final VoidCallback onToggle,
  required final List<Widget> children,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: <Widget>[
        InkWell(
          onTap: onToggle,
          mouseCursor: SystemMouseCursors.click,
          borderRadius: .circular(AleraTokens.radiusSm),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AleraTokens.space4),
            child: Row(
              children: <Widget>[
                Icon(
                  expanded ? AleraIcons.chevronDown : AleraIcons.chevronRight,
                  size: 16,
                  color: AleraTokens.foregroundMuted,
                ),
                const SizedBox(width: AleraTokens.space4),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: AleraTokens.foregroundMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.only(left: AleraTokens.space8),
            child: Column(mainAxisSize: .min, children: children),
          ),
      ],
    );
  }
}

class const _CheckRow({
  required final ReviewCheck check,
  required final bool expanded,
  required final VoidCallback onTap,
  required final Future<void> Function(String url) onOpenUrl,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = check.url;
    return InkWell(
      onTap: onTap,
      mouseCursor: SystemMouseCursors.click,
      borderRadius: .circular(AleraTokens.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AleraTokens.space4),
        child: Row(
          children: <Widget>[
            PullRequestCheckIcon(
              status: check.status,
              conclusion: check.conclusion,
            ),
            const SizedBox(width: AleraTokens.space8),
            Expanded(
              child: Text(
                check.name,
                maxLines: 1,
                overflow: .ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ),
            if (url != null && url.isNotEmpty)
              AleraIconButton(
                tooltip: 'Open Check',
                icon: AleraIcons.external,
                onPressed: () => onOpenUrl(url),
              ),
            const SizedBox(width: AleraTokens.space4),
            Icon(
              expanded ? AleraIcons.chevronUp : AleraIcons.chevronDown,
              size: 16,
              color: AleraTokens.foregroundMuted,
            ),
          ],
        ),
      ),
    );
  }
}

class const _CheckDetailsView({required final _CheckDetailsState state})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(
        left: AleraTokens.space24,
        bottom: AleraTokens.space8,
      ),
      child: Align(alignment: Alignment.centerLeft, child: _body(theme)),
    );
  }

  Widget _body(ThemeData theme) {
    if (state.loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AleraTokens.space4),
        child: SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final error = state.error;
    if (error != null) {
      return Text(
        error,
        style: theme.textTheme.bodySmall?.copyWith(color: AleraTokens.error),
      );
    }
    final details = state.details;
    final lines = details == null
        ? const <(String, String)>[]
        : <(String, String)>[
            if (details.workflow != null) ('Workflow', details.workflow!),
            if (details.event != null) ('Event', details.event!),
            if (details.description != null)
              ('Description', details.description!),
            if (details.startedAt != null)
              ('Started', _formatTimestamp(details.startedAt!)),
            if (details.completedAt != null)
              ('Completed', _formatTimestamp(details.completedAt!)),
          ];
    if (lines.isEmpty) {
      return Text(
        'No details available',
        style: theme.textTheme.bodySmall?.copyWith(
          color: AleraTokens.foregroundMuted,
        ),
      );
    }
    return Column(
      crossAxisAlignment: .start,
      children: <Widget>[
        for (final (label, value) in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: AleraTokens.space2),
            child: Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  TextSpan(
                    text: '$label: ',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AleraTokens.foregroundMuted,
                    ),
                  ),
                  TextSpan(
                    text: value,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AleraTokens.foreground,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final local = timestamp.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }
}

class _CheckDetailsState {
  const new loading() : loading = true, details = null, error = null;

  const new ready(this.details) : loading = false, error = null;

  const new error(this.error) : loading = false, details = null;

  final bool loading;
  final ReviewCheckDetails? details;
  final String? error;
}
