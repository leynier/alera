import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/forms/alera_text_actions_scope.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_entry.dart';
import 'package:alera/src/features/pull_requests/application/workspace_pull_request_state.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review_stack.dart';
import 'package:alera/src/features/pull_requests/domain/review_check.dart';
import 'package:alera/src/features/pull_requests/domain/review_check_details.dart';
import 'package:alera/src/features/pull_requests/domain/review_comment.dart';
import 'package:alera/src/features/pull_requests/domain/review_merge_method.dart';
import 'package:alera/src/features/pull_requests/domain/review_stack_workspace_models.dart';
import 'package:alera/src/features/pull_requests/domain/update_review_input.dart';
import 'package:alera/src/features/pull_requests/domain/update_review_result.dart';
import 'package:alera/src/features/pull_requests/presentation/pull_request_check_list.dart';
import 'package:alera/src/features/pull_requests/presentation/pull_request_comment_markdown.dart';
import 'package:alera/src/features/pull_requests/presentation/pull_request_field_decoration.dart';
import 'package:alera/src/features/pull_requests/presentation/pull_request_stack_link_dialog.dart';
import 'package:alera/src/features/pull_requests/presentation/pull_request_stack_section.dart';
import 'package:alera/src/features/pull_requests/presentation/pull_request_stack_workspace_dialog.dart';
import 'package:flutter/material.dart';

part 'pull_request_review_actions.dart';
part 'pull_request_review_comments.dart';

/// Presentational body for a linked review: header, inline title/base-branch
/// editing, expandable checks, and review actions. Pure: data and callbacks in
/// via parameters, no Riverpod reads.
class const PullRequestReviewView({
  super.key,
  required final HostedReview review,
  final HostedReviewStack? stack,
  final bool stackSupported = false,
  final String? stackErrorMessage,
  final Set<String> localWorkspaceBranches = const <String>{},
  final List<ReviewStackWorkspaceCandidate> stackWorkspaceCandidates =
      const <ReviewStackWorkspaceCandidate>[],
  final bool stackDefaultDraft = false,
  required final List<ReviewCheck> checks,
  required final List<ReviewComment> comments,
  required final List<String> baseBranches,
  required final List<ReviewMergeMethod> mergeMethods,
  required final bool canCloseReview,
  required final bool canChangeDraftStatus,
  required final bool canComment,
  final bool canEditComments = false,
  final Set<String> savingCommentIds = const <String>{},
  required final PullRequestAction? action,
  required final Future<void> Function(String url) onOpenUrl,
  final VoidCallback? onOpenDiff,
  final Future<void> Function(String branch)? onOpenWorkspaceBranch,
  required final Future<void> Function() onUnlink,
  final Future<void> Function(List<int> reviewNumbers) onLinkStack =
      _ignorePullRequestStackLink,
  final Future<void> Function(ReviewStackWorkspaceRequest request)
      onCreateStackFromWorkspaces =
      _ignorePullRequestWorkspaceStack,
  required final Future<void> Function(ReviewMergeMethod method) onMerge,
  required final Future<void> Function() onClose,
  required final Future<void> Function(bool draft) onDraftStatusChanged,
  required final Future<bool> Function(String body) onAddComment,
  final Future<void> Function(String commentId, int itemIndex) onToggleTask =
      _ignorePullRequestTaskToggle,
  required final Future<UpdateReviewResult> Function(UpdateReviewInput input)
  onUpdate,
  required final Future<ReviewCheckDetails?> Function(ReviewCheck check)
  onLoadCheckDetails,
}) extends StatefulWidget {
  @override
  State<PullRequestReviewView> createState() => _PullRequestReviewViewState();
}

Future<void> _ignorePullRequestTaskToggle(
  String commentId,
  int itemIndex,
) async {}

Future<void> _ignorePullRequestStackLink(List<int> reviewNumbers) async {}

Future<void> _ignorePullRequestWorkspaceStack(
  ReviewStackWorkspaceRequest request,
) async {}

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
      baseBranch:
          widget.stack != null || base == null || base == review.baseBranch
          ? null
          : base,
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

  bool get _canCreateStackFromWorkspaces {
    final existingBranches = widget.stack?.entries
        .map((entry) => entry.review.headBranch)
        .whereType<String>()
        .toSet();
    final eligible = widget.stackWorkspaceCandidates.where(
      (candidate) => !(existingBranches?.contains(candidate.branch) ?? false),
    );
    if (widget.stack != null) {
      return eligible.isNotEmpty;
    }
    return eligible.length >= 2 &&
        eligible.any((candidate) => candidate.current);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final review = widget.review;
    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space12),
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: <Widget>[
                _header(theme, review),
                const SizedBox(height: AleraTokens.space8),
                if (_editing) _editor(theme) else _summary(theme, review),
                if (widget.stackSupported) ...<Widget>[
                  const SizedBox(height: AleraTokens.space16),
                  PullRequestStackSection(
                    stack: widget.stack,
                    currentReviewNumber: review.number,
                    canManage: review.isOpen,
                    enabled: !_busy,
                    managing: widget.action == PullRequestAction.linkStack,
                    canCreateFromWorkspaces: _canCreateStackFromWorkspaces,
                    creatingFromWorkspaces:
                        widget.action == PullRequestAction.createStack,
                    errorMessage: widget.stackErrorMessage,
                    localWorkspaceBranches: widget.localWorkspaceBranches,
                    onOpenUrl: widget.onOpenUrl,
                    onOpenWorkspaceBranch: widget.onOpenWorkspaceBranch,
                    onManage: () => unawaited(_openStackDialog()),
                    onCreateFromWorkspaces: () =>
                        unawaited(_openWorkspaceStackDialog()),
                  ),
                ],
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
                    'No checks reported',
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
                  canEditComments: widget.canEditComments && review.isOpen,
                  savingCommentIds: widget.savingCommentIds,
                  action: widget.action,
                  onAddComment: widget.onAddComment,
                  onToggleTask: widget.onToggleTask,
                  onOpenUrl: widget.onOpenUrl,
                ),
              ],
            ),
          ),
          const SizedBox(height: AleraTokens.space8),
          _PullRequestReviewActions(
            review: review,
            stack: widget.stack,
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

  Future<void> _openStackDialog() async {
    if (_busy) {
      return;
    }
    final reviewNumbers = await showDialog<List<int>>(
      context: context,
      builder: (_) => PullRequestStackLinkDialog(
        currentReviewNumber: widget.review.number,
        stack: widget.stack,
      ),
    );
    if (!mounted || reviewNumbers == null) {
      return;
    }
    await widget.onLinkStack(reviewNumbers);
  }

  Future<void> _openWorkspaceStackDialog() async {
    if (_busy || !_canCreateStackFromWorkspaces) {
      return;
    }
    final suggestedBase =
        widget.stack?.baseBranch ??
        widget.review.baseBranch ??
        (widget.baseBranches.isEmpty ? 'main' : widget.baseBranches.first);
    final request = await showDialog<ReviewStackWorkspaceRequest>(
      context: context,
      builder: (_) => PullRequestStackWorkspaceDialog(
        currentTitle: widget.review.title,
        currentDraft: widget.review.state == HostedReviewState.draft,
        stack: widget.stack,
        candidates: widget.stackWorkspaceCandidates,
        baseBranches: widget.baseBranches,
        suggestedBaseBranch: suggestedBase,
        defaultDraft: widget.stackDefaultDraft,
      ),
    );
    if (!mounted || request == null) {
      return;
    }
    await widget.onCreateStackFromWorkspaces(request);
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
          tooltip: 'Open Pull Request Diff',
          icon: AleraIcons.diff,
          onPressed: widget.onOpenDiff,
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
      crossAxisAlignment: .start,
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
      crossAxisAlignment: .stretch,
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
          contextMenuBuilder: AleraTextActionsScope.buildContextMenu,
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
          enabled: !_busy && widget.stack == null,
          entries: _baseEntries,
          onChanged: (value) => setState(() => _baseBranch = value),
        ),
        if (widget.stack != null) ...<Widget>[
          const SizedBox(height: AleraTokens.space4),
          Text(
            'The base branch is managed by the pull request stack.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          ),
        ],
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

class const _StateChip({required final HostedReviewState state})
    extends StatelessWidget {
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
          fontWeight: .w600,
        ),
      ),
    );
  }
}
