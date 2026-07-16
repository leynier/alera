import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_entry.dart';
import 'package:alera/src/features/pull_requests/application/workspace_pull_request_state.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/review_check.dart';
import 'package:alera/src/features/pull_requests/domain/review_check_details.dart';
import 'package:alera/src/features/pull_requests/domain/review_comment.dart';
import 'package:alera/src/features/pull_requests/domain/review_merge_method.dart';
import 'package:alera/src/features/pull_requests/domain/update_review_input.dart';
import 'package:alera/src/features/pull_requests/domain/update_review_result.dart';
import 'package:alera/src/features/pull_requests/presentation/pull_request_check_list.dart';
import 'package:alera/src/features/pull_requests/presentation/pull_request_field_decoration.dart';
import 'package:flutter/material.dart';

part 'pull_request_review_actions.dart';
part 'pull_request_review_comments.dart';

/// Presentational body for a linked review: header, inline title/base-branch
/// editing, expandable checks, and review actions. Pure: data and callbacks in
/// via parameters, no Riverpod reads.
class PullRequestReviewView extends StatefulWidget {
  const PullRequestReviewView({
    super.key,
    required this.review,
    required this.checks,
    required this.comments,
    required this.baseBranches,
    required this.mergeMethods,
    required this.canCloseReview,
    required this.canChangeDraftStatus,
    required this.canComment,
    required this.action,
    required this.onOpenUrl,
    required this.onUnlink,
    required this.onMerge,
    required this.onClose,
    required this.onDraftStatusChanged,
    required this.onAddComment,
    required this.onUpdate,
    required this.onLoadCheckDetails,
  });

  final HostedReview review;
  final List<ReviewCheck> checks;
  final List<ReviewComment> comments;
  final List<String> baseBranches;
  final List<ReviewMergeMethod> mergeMethods;
  final bool canCloseReview;
  final bool canChangeDraftStatus;
  final bool canComment;
  final PullRequestAction? action;
  final Future<void> Function(String url) onOpenUrl;
  final Future<void> Function() onUnlink;
  final Future<void> Function(ReviewMergeMethod method) onMerge;
  final Future<void> Function() onClose;
  final Future<void> Function(bool draft) onDraftStatusChanged;
  final Future<bool> Function(String body) onAddComment;
  final Future<UpdateReviewResult> Function(UpdateReviewInput input) onUpdate;
  final Future<ReviewCheckDetails?> Function(ReviewCheck check)
  onLoadCheckDetails;

  @override
  State<PullRequestReviewView> createState() => _PullRequestReviewViewState();
}

class _PullRequestReviewViewState extends State<PullRequestReviewView> {
  final TextEditingController _titleController = TextEditingController();
  bool _editing = false;
  String? _baseBranch;

  bool get _busy => widget.action != null;
  bool get _saving => widget.action == PullRequestAction.update;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  void _startEditing() {
    setState(() {
      _editing = true;
      _titleController.text = widget.review.title;
      _baseBranch = widget.review.baseBranch;
    });
  }

  Future<void> _save() async {
    final review = widget.review;
    final title = _titleController.text.trim();
    final base = _baseBranch;
    final input = UpdateReviewInput(
      title: title.isEmpty || title == review.title ? null : title,
      baseBranch: base == null || base == review.baseBranch ? null : base,
    );
    if (input.isEmpty) {
      setState(() => _editing = false);
      return;
    }
    final result = await widget.onUpdate(input);
    if (result is UpdateReviewSuccess && mounted) {
      setState(() => _editing = false);
    }
  }

  List<AleraDropdownFieldEntry<String>> get _baseEntries {
    final names = <String>{
      ...widget.baseBranches,
      if (widget.review.baseBranch != null) widget.review.baseBranch!,
    }.toList()..sort();
    return <AleraDropdownFieldEntry<String>>[
      for (final name in names)
        AleraDropdownFieldEntry<String>(value: name, label: name),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final review = widget.review;
    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: <Widget>[
                _header(theme, review),
                const SizedBox(height: AleraTokens.space8),
                if (_editing) _editor(theme) else _summary(theme, review),
                const SizedBox(height: AleraTokens.space16),
                Text(
                  widget.checks.isEmpty
                      ? 'Checks'
                      : 'Checks (${widget.checks.length})',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: AleraTokens.foregroundMuted,
                  ),
                ),
                const SizedBox(height: AleraTokens.space8),
                if (widget.checks.isEmpty)
                  Text(
                    'No Checks Reported',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AleraTokens.foregroundMuted,
                    ),
                  )
                else
                  PullRequestCheckList(
                    checks: widget.checks,
                    onOpenUrl: widget.onOpenUrl,
                    onLoadDetails: widget.onLoadCheckDetails,
                  ),
                const SizedBox(height: AleraTokens.space16),
                _PullRequestCommentsSection(
                  comments: widget.comments,
                  canComment: widget.canComment && review.isOpen,
                  action: widget.action,
                  onAddComment: widget.onAddComment,
                  onOpenUrl: widget.onOpenUrl,
                ),
              ],
            ),
          ),
          const SizedBox(height: AleraTokens.space8),
          _PullRequestReviewActions(
            review: review,
            mergeMethods: widget.mergeMethods,
            canCloseReview: widget.canCloseReview,
            canChangeDraftStatus: widget.canChangeDraftStatus,
            action: widget.action,
            onMerge: widget.onMerge,
            onClose: widget.onClose,
            onDraftStatusChanged: widget.onDraftStatusChanged,
            onUnlink: widget.onUnlink,
          ),
        ],
      ),
    );
  }

  Widget _header(ThemeData theme, HostedReview review) {
    return Row(
      children: <Widget>[
        const Icon(
          AleraIcons.gitPullRequest,
          size: 16,
          color: AleraTokens.foregroundMuted,
        ),
        const SizedBox(width: AleraTokens.space6),
        Text(
          '#${review.number}',
          style: theme.textTheme.labelLarge?.copyWith(
            color: AleraTokens.foreground,
          ),
        ),
        const SizedBox(width: AleraTokens.space8),
        _StateChip(state: review.state),
        const Spacer(),
        if (!_editing)
          AleraIconButton(
            tooltip: 'Edit Pull Request',
            icon: AleraIcons.edit,
            onPressed: _busy ? null : _startEditing,
          ),
        AleraIconButton(
          tooltip: 'Open In Browser',
          icon: AleraIcons.external,
          onPressed: () => widget.onOpenUrl(review.url),
        ),
      ],
    );
  }

  Widget _summary(ThemeData theme, HostedReview review) {
    final subtitle = <String>[
      if (review.author != null) review.author!,
      if (review.headBranch != null && review.baseBranch != null)
        '${review.headBranch} → ${review.baseBranch}'
      else if (review.headBranch != null)
        review.headBranch!,
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(review.title, style: theme.textTheme.bodyMedium),
        if (subtitle.isNotEmpty) ...<Widget>[
          const SizedBox(height: AleraTokens.space4),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          ),
        ],
      ],
    );
  }

  Widget _editor(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'Title',
          style: theme.textTheme.labelSmall?.copyWith(
            color: AleraTokens.foregroundMuted,
          ),
        ),
        const SizedBox(height: AleraTokens.space4),
        TextField(
          controller: _titleController,
          enabled: !_busy,
          autofocus: true,
          style: theme.textTheme.bodySmall?.copyWith(
            color: AleraTokens.foreground,
          ),
          cursorColor: AleraTokens.foreground,
          decoration: pullRequestFieldDecoration(theme, hint: 'Title'),
          onSubmitted: (_) {
            if (!_busy) {
              _save();
            }
          },
        ),
        const SizedBox(height: AleraTokens.space12),
        AleraDropdownField<String>(
          labelText: 'Base Branch',
          value: _baseBranch,
          enabled: !_busy,
          entries: _baseEntries,
          onChanged: (value) => setState(() => _baseBranch = value),
        ),
        const SizedBox(height: AleraTokens.space12),
        Row(
          children: <Widget>[
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(AleraIcons.success, size: 16),
              label: const Text('Save'),
            ),
            const SizedBox(width: AleraTokens.space8),
            TextButton(
              onPressed: _busy ? null : () => setState(() => _editing = false),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ],
    );
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.state});

  final HostedReviewState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color) = switch (state) {
      HostedReviewState.open => ('Open', AleraTokens.success),
      HostedReviewState.draft => ('Draft', AleraTokens.foregroundMuted),
      HostedReviewState.merged => ('Merged', AleraTokens.accent),
      HostedReviewState.closed => ('Closed', AleraTokens.error),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space8,
        vertical: AleraTokens.space2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
