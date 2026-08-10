part of 'codex_chat_surface.dart';

enum _CodexReviewTarget {
  uncommittedChanges,
  baseBranch,
  commit,
  custom;

  String get wireValue => switch (this) {
    uncommittedChanges => 'uncommittedChanges',
    baseBranch => 'baseBranch',
    commit => 'commit',
    custom => 'custom',
  };

  String get label => switch (this) {
    uncommittedChanges => 'Uncommitted Changes',
    baseBranch => 'Base Branch',
    commit => 'Commit',
    custom => 'Custom Instructions',
  };

  String get description => switch (this) {
    uncommittedChanges =>
      'Review staged, unstaged, and untracked changes in this workspace.',
    baseBranch =>
      'Review the current branch against the merge base of another branch.',
    commit => 'Review one commit by its SHA.',
    custom => 'Describe the exact scope and focus for the reviewer.',
  };
}

enum _CodexReviewDelivery {
  inline,
  detached;

  String get wireValue => name;

  String get label => switch (this) {
    inline => 'Inline',
    detached => 'Detached',
  };

  String get description => switch (this) {
    inline => 'Run the review in this conversation.',
    detached => 'Fork a separate review thread from this conversation.',
  };
}

final class _CodexReviewSelection {
  const _CodexReviewSelection({
    required this.target,
    required this.delivery,
    this.argument,
    this.commitTitle,
  });

  final _CodexReviewTarget target;
  final _CodexReviewDelivery delivery;
  final String? argument;
  final String? commitTitle;
}

class _CodexReviewDialog extends StatefulWidget {
  const _CodexReviewDialog({
    required this.branches,
    required this.branchLookupFailed,
  });

  final List<String> branches;
  final bool branchLookupFailed;

  @override
  State<_CodexReviewDialog> createState() => _CodexReviewDialogState();
}

class _CodexReviewDialogState extends State<_CodexReviewDialog> {
  final TextEditingController _branch = TextEditingController();
  final TextEditingController _commitSha = TextEditingController();
  final TextEditingController _commitTitle = TextEditingController();
  final TextEditingController _instructions = TextEditingController();
  _CodexReviewTarget _target = _CodexReviewTarget.uncommittedChanges;
  _CodexReviewDelivery _delivery = _CodexReviewDelivery.inline;
  String? _selectedBranch;

  @override
  void initState() {
    super.initState();
    _selectedBranch = _defaultBranch(widget.branches);
    for (final controller in <TextEditingController>[
      _branch,
      _commitSha,
      _commitTitle,
      _instructions,
    ]) {
      controller.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    for (final controller in <TextEditingController>[
      _branch,
      _commitSha,
      _commitTitle,
      _instructions,
    ]) {
      controller.removeListener(_refresh);
      controller.dispose();
    }
    super.dispose();
  }

  void _refresh() => setState(() {});

  bool get _canSubmit => switch (_target) {
    _CodexReviewTarget.uncommittedChanges => true,
    _CodexReviewTarget.baseBranch =>
      widget.branches.isNotEmpty
          ? _selectedBranch?.trim().isNotEmpty == true
          : _branch.text.trim().isNotEmpty,
    _CodexReviewTarget.commit => _commitSha.text.trim().isNotEmpty,
    _CodexReviewTarget.custom => _instructions.text.trim().isNotEmpty,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AleraDialog(
      maxWidth: AleraTokens.dialogWidth,
      maxHeight: AleraTokens.dialogMaxHeight,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AleraDialogHeader(
              title: 'Start Review',
              onClose: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: AleraTokens.space16),
            Flexible(
              child: SingleChildScrollView(
                key: const ValueKey<String>('codex-review-form-scroll'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    AleraDropdownField<_CodexReviewTarget>(
                      key: const ValueKey<String>('codex-review-target'),
                      labelText: 'Target',
                      value: _target,
                      entries: <AleraDropdownFieldEntry<_CodexReviewTarget>>[
                        for (final target in _CodexReviewTarget.values)
                          AleraDropdownFieldEntry<_CodexReviewTarget>(
                            value: target,
                            label: target.label,
                          ),
                      ],
                      onChanged: (target) => setState(() => _target = target),
                    ),
                    const SizedBox(height: AleraTokens.space6),
                    Text(
                      _target.description,
                      key: const ValueKey<String>(
                        'codex-review-target-description',
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AleraTokens.foregroundMuted,
                      ),
                    ),
                    const SizedBox(height: AleraTokens.space16),
                    ..._targetFields(),
                    AleraDropdownField<_CodexReviewDelivery>(
                      key: const ValueKey<String>('codex-review-delivery'),
                      labelText: 'Delivery',
                      value: _delivery,
                      entries: <AleraDropdownFieldEntry<_CodexReviewDelivery>>[
                        for (final delivery in _CodexReviewDelivery.values)
                          AleraDropdownFieldEntry<_CodexReviewDelivery>(
                            value: delivery,
                            label: delivery.label,
                          ),
                      ],
                      onChanged: (delivery) =>
                          setState(() => _delivery = delivery),
                    ),
                    const SizedBox(height: AleraTokens.space6),
                    Text(
                      _delivery.description,
                      key: const ValueKey<String>(
                        'codex-review-delivery-description',
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AleraTokens.foregroundMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AleraTokens.space20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: AleraTokens.space8),
                FilledButton(
                  key: const ValueKey<String>('codex-review-submit'),
                  onPressed: _canSubmit ? _submit : null,
                  child: const Text('Start Review'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _targetFields() => switch (_target) {
    _CodexReviewTarget.uncommittedChanges => const <Widget>[],
    _CodexReviewTarget.baseBranch => <Widget>[
      if (widget.branches.isNotEmpty)
        AleraDropdownField<String>(
          key: const ValueKey<String>('codex-review-branch'),
          labelText: 'Base Branch',
          hintText: 'Select Branch',
          value: _selectedBranch,
          entries: <AleraDropdownFieldEntry<String>>[
            for (final branch in widget.branches)
              AleraDropdownFieldEntry<String>(value: branch, label: branch),
          ],
          filterable: true,
          filterHintText: 'Search Branches',
          onChanged: (branch) => setState(() => _selectedBranch = branch),
        )
      else ...<Widget>[
        AleraTextField(
          key: const ValueKey<String>('codex-review-branch-input'),
          controller: _branch,
          labelText: 'Base Branch',
          hintText: 'Enter a branch name',
        ),
        if (widget.branchLookupFailed) ...<Widget>[
          const SizedBox(height: AleraTokens.space6),
          Text(
            'Branches could not be loaded. Enter the branch name manually.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AleraTokens.warning),
          ),
        ],
      ],
      const SizedBox(height: AleraTokens.space16),
    ],
    _CodexReviewTarget.commit => <Widget>[
      AleraTextField(
        key: const ValueKey<String>('codex-review-commit-sha'),
        controller: _commitSha,
        labelText: 'Commit SHA',
        hintText: 'Enter a commit SHA',
      ),
      const SizedBox(height: AleraTokens.space12),
      AleraTextField(
        key: const ValueKey<String>('codex-review-commit-title'),
        controller: _commitTitle,
        labelText: 'Commit Title',
        hintText: 'Optional subject',
      ),
      const SizedBox(height: AleraTokens.space16),
    ],
    _CodexReviewTarget.custom => <Widget>[
      AleraTextField(
        key: const ValueKey<String>('codex-review-instructions'),
        controller: _instructions,
        labelText: 'Review Instructions',
        hintText: 'Describe what the reviewer should inspect',
        keyboardType: TextInputType.multiline,
        minLines: 4,
        maxLines: 8,
      ),
      const SizedBox(height: AleraTokens.space16),
    ],
  };

  void _submit() {
    if (!_canSubmit) return;
    final argument = switch (_target) {
      _CodexReviewTarget.uncommittedChanges => null,
      _CodexReviewTarget.baseBranch =>
        widget.branches.isNotEmpty
            ? _selectedBranch?.trim()
            : _branch.text.trim(),
      _CodexReviewTarget.commit => _commitSha.text.trim(),
      _CodexReviewTarget.custom => _instructions.text.trim(),
    };
    Navigator.of(context).pop(
      _CodexReviewSelection(
        target: _target,
        delivery: _delivery,
        argument: argument,
        commitTitle: _target == _CodexReviewTarget.commit
            ? _commitTitle.text.trim()
            : null,
      ),
    );
  }
}

String? _defaultBranch(List<String> branches) {
  for (final candidate in const <String>[
    'main',
    'origin/main',
    'master',
    'origin/master',
  ]) {
    if (branches.contains(candidate)) return candidate;
  }
  return branches.isEmpty ? null : branches.first;
}
