import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_checkbox.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/design_system/layout/alera_dialog_header.dart';
import 'package:alera/src/design_system/surfaces/alera_workspace_details_card.dart';
import 'package:alera/src/features/pull_requests/domain/create_review_input.dart';
import 'package:alera/src/features/workbench/application/workspace_git_submission.dart';
import 'package:alera/src/features/workbench/domain/workspace_git_quick_action.dart';
import 'package:alera/src/features/workbench/presentation/git_change_status_style.dart';
import 'package:alera/src/shared/git_hosting/domain/git_hosting_provider.dart';
import 'package:alera/src/shared/infra/git/git_workspace_comparison.dart';
import 'package:flutter/material.dart';

class const WorkspaceGitSubmissionDialog({
  super.key,
  required this.path,
  required this.snapshot,
  required this.action,
  required this.branch,
  required this.baseBranch,
  required this.isDefaultBranch,
  required this.provider,
  this.onOpenFile,
  this.onGenerate,
  this.initialTitle = '',
  this.sharedCheckout = false,
}) extends StatefulWidget {
  final void Function(String)? onOpenFile;
  final String initialTitle;
  final bool sharedCheckout;
  final String path;
  final GitWorkspaceComparison snapshot;
  final WorkspaceGitQuickAction action;
  final String branch;
  final String baseBranch;
  final bool isDefaultBranch;
  final GitHostingProvider? provider;
  final Future<String> Function(List<String> files)? onGenerate;
  @override
  State<WorkspaceGitSubmissionDialog> createState() =>
      _WorkspaceGitSubmissionDialogState();
}

class _WorkspaceGitSubmissionDialogState
    extends State<WorkspaceGitSubmissionDialog> {
  final _message = TextEditingController();
  final _title = TextEditingController();
  final _base = TextEditingController();
  final _newBranch = TextEditingController();
  late final Set<String> _selected;
  bool _draft = false;
  bool _createBranch = false;
  bool _generating = false;
  String? _error;
  int _revision = 0;
  @override
  void initState() {
    super.initState();
    _selected = {for (final file in widget.snapshot.entries) file.path};
    _title.text = widget.initialTitle;
    _base.text = widget.baseBranch;
    if (widget.action.includesCommit && widget.onGenerate != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _generate());
    }
  }

  @override
  void dispose() {
    _revision++;
    _message.dispose();
    _title.dispose();
    _base.dispose();
    _newBranch.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final generate = widget.onGenerate;
    if (generate == null || _selected.isEmpty) return;
    final revision = ++_revision;
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final message = await generate(_selected.toList(growable: false));
      if (!mounted || revision != _revision) return;
      _message.text = message;
      if (_title.text.isEmpty) _title.text = message.split('\n').first;
    } catch (error) {
      if (mounted && revision == _revision) {
        setState(
          () => _error =
              'Could not generate a message. Enter one manually: $error',
        );
      }
    } finally {
      if (mounted && revision == _revision) setState(() => _generating = false);
    }
  }

  void _confirm() {
    if (widget.action.includesCommit &&
        (_selected.isEmpty || _message.text.trim().isEmpty)) {
      setState(() => _error = 'Select files and enter a commit message.');
      return;
    }
    if (_createBranch && _newBranch.text.trim().isEmpty) {
      setState(() => _error = 'Enter a branch name.');
      return;
    }
    final title = _title.text.trim().isEmpty
        ? _message.text.split('\n').first.trim()
        : _title.text.trim();
    if (widget.action.includesPr &&
        (title.isEmpty ||
            _base.text.trim().isEmpty ||
            widget.provider == null)) {
      setState(() => _error = 'Enter a pull request title and base branch.');
      return;
    }
    if (widget.action.includesPr &&
        !_createBranch &&
        _base.text.trim() == widget.branch) {
      setState(
        () => _error = 'Choose a different base or create a feature branch.',
      );
      return;
    }
    Navigator.of(context).pop(
      WorkspaceGitSubmission(
        path: widget.path,
        action: widget.action,
        snapshot: widget.snapshot,
        files: _selected.toList(growable: false),
        message: _message.text.trim(),
        newBranch: _createBranch ? _newBranch.text.trim() : null,
        review: widget.action.includesPr
            ? CreateReviewInput(
                provider: widget.provider!,
                title: title,
                body: _message.text.trim(),
                baseBranch: _base.text.trim(),
                headBranch: _createBranch
                    ? _newBranch.text.trim()
                    : widget.branch,
                draft: _draft,
              )
            : null,
      ),
    );
  }

  void _toggle(String path, bool value) => setState(() {
    if (value) {
      _selected.add(path);
    } else {
      _selected.remove(path);
    }
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: AleraTokens.foregroundMuted,
    );
    final entries = widget.snapshot.entries;
    return AleraDialog(
      maxWidth: AleraTokens.dialogWideWidth,
      maxHeight: AleraTokens.dialogMaxHeight,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AleraDialogHeader(
              title: widget.action.label,
              onClose: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: AleraTokens.space4),
            Row(
              children: [
                const Icon(
                  AleraIcons.gitBranch,
                  size: AleraTokens.iconSm,
                  color: AleraTokens.foregroundMuted,
                ),
                const SizedBox(width: AleraTokens.space6),
                Flexible(
                  child: Text(
                    widget.action.includesPr
                        ? '${widget.branch}  →  ${_base.text}'
                        : widget.branch,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: muted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AleraTokens.space16),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  spacing: AleraTokens.space16,
                  children: [
                    if (widget.isDefaultBranch) _defaultBranchNotice(theme),
                    if (widget.action.includesCommit) ...[
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: AleraTokens.space6,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: AleraCheckbox(
                                  value: _selected.length == entries.length,
                                  label: 'Select All Files',
                                  enabled: !_generating,
                                  onChanged: (value) => setState(() {
                                    _selected.clear();
                                    if (value) {
                                      _selected.addAll(
                                        entries.map((entry) => entry.path),
                                      );
                                    }
                                  }),
                                ),
                              ),
                              Text(
                                '${_selected.length} of ${entries.length}',
                                style: muted,
                              ),
                            ],
                          ),
                          _fileList(theme),
                        ],
                      ),
                      AleraTextField(
                        controller: _message,
                        labelText: 'Commit Message',
                        minLines: 3,
                        maxLines: 6,
                        enabled: !_generating,
                      ),
                    ],
                    if (widget.action.includesPr) ...[
                      AleraTextField(
                        controller: _title,
                        labelText: 'Pull Request Title',
                      ),
                      Row(
                        spacing: AleraTokens.space12,
                        children: [
                          Expanded(
                            child: AleraTextField(
                              controller: _base,
                              labelText: 'Base Branch',
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          AleraCheckbox(
                            value: _draft,
                            label: 'Draft',
                            onChanged: (value) =>
                                setState(() => _draft = value),
                          ),
                        ],
                      ),
                    ],
                    if (_error != null)
                      Text(
                        _error!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AleraTokens.error,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AleraTokens.space20),
            Row(
              children: [
                if (widget.action.includesCommit && widget.onGenerate != null)
                  TextButton.icon(
                    onPressed: _generating ? null : _generate,
                    icon: _generating
                        ? const AleraWorkspaceDetailSpinner()
                        : const Icon(AleraIcons.ai, size: AleraTokens.iconMd),
                    label: Text(
                      _generating ? 'Generating…' : 'Generate Message',
                    ),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: AleraTokens.space8),
                FilledButton(
                  onPressed: _generating ? null : _confirm,
                  child: Text(widget.action.label),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _defaultBranchNotice(ThemeData theme) => DecoratedBox(
    decoration: BoxDecoration(
      color: AleraTokens.warning.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
      border: Border.all(color: AleraTokens.warning.withValues(alpha: 0.3)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(AleraTokens.space12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AleraTokens.space8,
        children: [
          Text(
            'This is the default branch. Continuing will run this action on ${widget.branch}.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AleraTokens.warning,
            ),
          ),
          if (widget.sharedCheckout)
            Text(
              'This checkout is shared. Creating a branch changes the branch used by its other workspaces and agents.',
              style: theme.textTheme.bodySmall,
            ),
          AleraCheckbox(
            value: _createBranch,
            label: 'Create Branch Instead',
            onChanged: (value) => setState(() => _createBranch = value),
          ),
          if (_createBranch)
            AleraTextField(controller: _newBranch, labelText: 'Branch Name'),
        ],
      ),
    ),
  );

  Widget _fileList(ThemeData theme) {
    final entries = widget.snapshot.entries;
    final mono = AleraTokens.monoCompactStyle;
    return Container(
      constraints: const BoxConstraints(
        maxHeight: AleraTokens.activityLogHeight,
      ),
      decoration: BoxDecoration(
        color: AleraTokens.bg,
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        border: Border.all(color: AleraTokens.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListView.builder(
        primary: false,
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: AleraTokens.space4),
        itemCount: entries.length,
        itemBuilder: (context, index) {
          final entry = entries[index];
          final (badge, tone) = gitChangeStatusStyle(entry.status);
          final slash = entry.path.lastIndexOf('/');
          final directory = slash < 0 ? '' : entry.path.substring(0, slash + 1);
          final name = entry.path.substring(slash + 1);
          final enabled = !_generating;
          return InkWell(
            onTap: widget.onOpenFile == null
                ? null
                : () => widget.onOpenFile!(entry.path),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AleraTokens.space8,
                vertical: AleraTokens.space2,
              ),
              child: Row(
                spacing: AleraTokens.space8,
                children: [
                  AleraCheckbox(
                    value: _selected.contains(entry.path),
                    enabled: enabled,
                    onChanged: (value) => _toggle(entry.path, value),
                  ),
                  SizedBox(
                    width: AleraTokens.space12,
                    child: Text(
                      badge,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall?.copyWith(color: tone),
                    ),
                  ),
                  Expanded(
                    child: Tooltip(
                      message: entry.path,
                      waitDuration: AleraTokens.durationSlow,
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: name),
                            if (directory.isNotEmpty)
                              TextSpan(
                                text: '  $directory',
                                style: const TextStyle(
                                  color: AleraTokens.foregroundMuted,
                                ),
                              ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AleraTokens.foreground,
                        ),
                      ),
                    ),
                  ),
                  if (entry.added != null || entry.removed != null) ...[
                    Text(
                      '+${entry.added ?? 0}',
                      style: mono.copyWith(color: AleraTokens.success),
                    ),
                    Text(
                      '-${entry.removed ?? 0}',
                      style: mono.copyWith(color: AleraTokens.error),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
