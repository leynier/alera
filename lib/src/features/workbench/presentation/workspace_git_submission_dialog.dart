import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_checkbox.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/features/pull_requests/domain/create_review_input.dart';
import 'package:alera/src/features/workbench/application/workspace_git_submission.dart';
import 'package:alera/src/features/workbench/domain/workspace_git_quick_action.dart';
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

  @override
  Widget build(BuildContext context) => AleraDialog(
    maxWidth: AleraTokens.dialogWideWidth,
    maxHeight: AleraTokens.dialogMaxHeight,
    child: Padding(
      padding: const EdgeInsets.all(AleraTokens.space16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.action.label,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AleraTokens.space12),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Branch: ${widget.branch}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (widget.isDefaultBranch) ...[
                    Text(
                      'This is the default branch. Continuing will run this action on ${widget.branch}.',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: AleraTokens.warning),
                    ),
                    if (widget.sharedCheckout)
                      Text(
                        'This checkout is shared. Creating a branch changes the branch used by its other workspaces and agents.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    AleraCheckbox(
                      value: _createBranch,
                      label: 'Create Branch Instead',
                      onChanged: (value) =>
                          setState(() => _createBranch = value),
                    ),
                    if (_createBranch)
                      AleraTextField(
                        controller: _newBranch,
                        labelText: 'Branch Name',
                      ),
                  ],
                  const SizedBox(height: AleraTokens.space12),
                  if (widget.action.includesCommit) ...[
                    AleraCheckbox(
                      value: _selected.length == widget.snapshot.entries.length,
                      label: 'Select All Files',
                      enabled: !_generating,
                      onChanged: (value) => setState(() {
                        _selected.clear();
                        if (value) {
                          _selected.addAll(
                            widget.snapshot.entries.map((entry) => entry.path),
                          );
                        }
                      }),
                    ),
                    SizedBox(
                      height: AleraTokens.activityLogHeight,
                      child: ListView.builder(
                        primary: false,
                        itemCount: widget.snapshot.entries.length,
                        itemBuilder: (context, index) {
                          final entry = widget.snapshot.entries[index];
                          return Row(
                            children: [
                              AleraCheckbox(
                                value: _selected.contains(entry.path),
                                enabled: !_generating,
                                onChanged: (value) => setState(() {
                                  if (value) {
                                    _selected.add(entry.path);
                                  } else {
                                    _selected.remove(entry.path);
                                  }
                                }),
                              ),
                              Expanded(
                                child: TextButton(
                                  onPressed: widget.onOpenFile == null
                                      ? null
                                      : () => widget.onOpenFile!(entry.path),
                                  child: Text(
                                    entry.path,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    AleraTextField(
                      controller: _message,
                      labelText: 'Commit Message',
                      minLines: 2,
                      maxLines: 4,
                      enabled: !_generating,
                    ),
                  ],
                  if (widget.action.includesPr) ...[
                    AleraTextField(
                      controller: _title,
                      labelText: 'Pull Request Title',
                    ),
                    AleraTextField(controller: _base, labelText: 'Base Branch'),
                    AleraCheckbox(
                      value: _draft,
                      label: 'Draft',
                      onChanged: (value) => setState(() => _draft = value),
                    ),
                  ],
                  if (_error != null)
                    Text(
                      _error!,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: AleraTokens.error),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AleraTokens.space12),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: AleraTokens.space8,
            runSpacing: AleraTokens.space4,
            children: [
              if (widget.action.includesCommit && widget.onGenerate != null)
                TextButton(
                  onPressed: _generating ? null : _generate,
                  child: Text(_generating ? 'Generating…' : 'Generate Message'),
                ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: _generating ? null : _confirm,
                child: const Text('Confirm'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
