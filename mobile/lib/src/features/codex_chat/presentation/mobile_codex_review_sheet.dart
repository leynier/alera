part of 'mobile_codex_chat_screen.dart';

class _MobileCodexReviewSheet extends StatefulWidget {
  const _MobileCodexReviewSheet({required this.branches});

  final Future<MobileCodexReviewBranches> branches;

  @override
  State<_MobileCodexReviewSheet> createState() =>
      _MobileCodexReviewSheetState();
}

class _MobileCodexReviewSheetState extends State<_MobileCodexReviewSheet> {
  final TextEditingController _branch = TextEditingController();
  final TextEditingController _commitSha = TextEditingController();
  final TextEditingController _commitTitle = TextEditingController();
  final TextEditingController _instructions = TextEditingController();
  _MobileCodexReviewTarget _target =
      _MobileCodexReviewTarget.uncommittedChanges;
  _MobileCodexReviewDelivery _delivery = _MobileCodexReviewDelivery.inline;
  List<String> _branches = const <String>[];
  String? _selectedBranch;
  bool _loadingBranches = true;
  bool _branchLookupFailed = false;

  @override
  void initState() {
    super.initState();
    for (final controller in <TextEditingController>[
      _branch,
      _commitSha,
      _commitTitle,
      _instructions,
    ]) {
      controller.addListener(_refresh);
    }
    unawaited(_loadBranches());
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

  Future<void> _loadBranches() async {
    final result = await widget.branches;
    if (!mounted) return;
    setState(() {
      _branches = result.branches;
      _selectedBranch = _defaultMobileReviewBranch(result.branches);
      _branchLookupFailed = result.lookupFailed;
      _loadingBranches = false;
    });
  }

  void _refresh() => setState(() {});

  bool get _canSubmit => switch (_target) {
    _MobileCodexReviewTarget.uncommittedChanges => true,
    _MobileCodexReviewTarget.baseBranch =>
      !_loadingBranches &&
          (_branches.isNotEmpty
              ? _selectedBranch?.trim().isNotEmpty == true
              : _branch.text.trim().isNotEmpty),
    _MobileCodexReviewTarget.commit => _commitSha.text.trim().isNotEmpty,
    _MobileCodexReviewTarget.custom => _instructions.text.trim().isNotEmpty,
  };

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final maxHeight =
        media.size.height - media.viewInsets.bottom - AleraTokens.space24;
    return AnimatedPadding(
      duration: AleraTokens.durationMid,
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: AleraTokens.emptyStateMaxWidth,
            maxHeight: maxHeight,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AleraTokens.space20,
              AleraTokens.space4,
              AleraTokens.space20,
              AleraTokens.space16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _buildHeader(context),
                const SizedBox(height: AleraTokens.space12),
                Flexible(
                  child: SingleChildScrollView(
                    key: const ValueKey<String>('mobile-codex-review-form'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _MobileReviewChoiceField(
                          key: const ValueKey<String>(
                            'mobile-codex-review-target',
                          ),
                          label: 'Target',
                          value: _target.label,
                          description: _target.description,
                          onTap: _selectTarget,
                        ),
                        const SizedBox(height: AleraTokens.space16),
                        ..._buildTargetFields(),
                        _MobileReviewChoiceField(
                          key: const ValueKey<String>(
                            'mobile-codex-review-delivery',
                          ),
                          label: 'Delivery',
                          value: _delivery.label,
                          description: _delivery.description,
                          onTap: _selectDelivery,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AleraTokens.space16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: AleraTokens.space8),
                    FilledButton(
                      key: const ValueKey<String>('mobile-codex-review-submit'),
                      onPressed: _canSubmit ? _submit : null,
                      child: const Text('Start Review'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) => Row(
    children: <Widget>[
      Expanded(
        child: Text(
          'Start Review',
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
      IconButton(
        tooltip: 'Close',
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(AleraIcons.close),
      ),
    ],
  );

  List<Widget> _buildTargetFields() => switch (_target) {
    _MobileCodexReviewTarget.uncommittedChanges => const <Widget>[],
    _MobileCodexReviewTarget.baseBranch => <Widget>[
      if (_loadingBranches)
        const _MobileReviewLoadingField()
      else if (_branches.isNotEmpty)
        _MobileReviewChoiceField(
          key: const ValueKey<String>('mobile-codex-review-branch'),
          label: 'Base Branch',
          value: _selectedBranch ?? 'Select Branch',
          description: 'Choose the branch used as the comparison base.',
          onTap: _selectBranch,
        )
      else
        AleraTextField(
          key: const ValueKey<String>('mobile-codex-review-branch-input'),
          controller: _branch,
          labelText: 'Base Branch',
          hintText: 'Enter a branch name',
          autofocus: true,
        ),
      if (_branchLookupFailed) ...<Widget>[
        const SizedBox(height: AleraTokens.space6),
        Text(
          'Branches could not be loaded. Enter the branch name manually.',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: AleraTokens.warning),
        ),
      ],
      const SizedBox(height: AleraTokens.space16),
    ],
    _MobileCodexReviewTarget.commit => <Widget>[
      AleraTextField(
        key: const ValueKey<String>('mobile-codex-review-commit-sha'),
        controller: _commitSha,
        labelText: 'Commit SHA',
        hintText: 'Enter a commit SHA',
        autofocus: true,
      ),
      const SizedBox(height: AleraTokens.space12),
      AleraTextField(
        key: const ValueKey<String>('mobile-codex-review-commit-title'),
        controller: _commitTitle,
        labelText: 'Commit Title',
        hintText: 'Optional subject',
      ),
      const SizedBox(height: AleraTokens.space16),
    ],
    _MobileCodexReviewTarget.custom => <Widget>[
      AleraTextField(
        key: const ValueKey<String>('mobile-codex-review-instructions'),
        controller: _instructions,
        labelText: 'Review Instructions',
        hintText: 'Describe what the reviewer should inspect',
        keyboardType: TextInputType.multiline,
        minLines: 4,
        maxLines: 8,
        autofocus: true,
      ),
      const SizedBox(height: AleraTokens.space16),
    ],
  };

  Future<void> _selectTarget() async {
    final value = await _showMobileReviewOptions<_MobileCodexReviewTarget>(
      context,
      title: 'Select Target',
      selected: _target,
      values: _MobileCodexReviewTarget.values,
      label: (value) => value.label,
      description: (value) => value.description,
    );
    if (value != null && mounted) setState(() => _target = value);
  }

  Future<void> _selectDelivery() async {
    final value = await _showMobileReviewOptions<_MobileCodexReviewDelivery>(
      context,
      title: 'Select Delivery',
      selected: _delivery,
      values: _MobileCodexReviewDelivery.values,
      label: (value) => value.label,
      description: (value) => value.description,
    );
    if (value != null && mounted) setState(() => _delivery = value);
  }

  Future<void> _selectBranch() async {
    final value = await _showMobileReviewBranchPicker(
      context,
      branches: _branches,
      selected: _selectedBranch,
    );
    if (value != null && mounted) setState(() => _selectedBranch = value);
  }

  void _submit() {
    if (!_canSubmit) return;
    final argument = switch (_target) {
      _MobileCodexReviewTarget.uncommittedChanges => null,
      _MobileCodexReviewTarget.baseBranch =>
        _branches.isNotEmpty ? _selectedBranch?.trim() : _branch.text.trim(),
      _MobileCodexReviewTarget.commit => _commitSha.text.trim(),
      _MobileCodexReviewTarget.custom => _instructions.text.trim(),
    };
    Navigator.of(context).pop(
      _MobileCodexReviewSelection(
        target: _target,
        delivery: _delivery,
        argument: argument,
        commitTitle: _target == _MobileCodexReviewTarget.commit
            ? _commitTitle.text.trim()
            : null,
      ),
    );
  }
}

class _MobileReviewChoiceField extends StatelessWidget {
  const _MobileReviewChoiceField({
    super.key,
    required this.label,
    required this.value,
    required this.description,
    required this.onTap,
  });

  final String label;
  final String value;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(
        label,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: AleraTokens.foregroundMuted),
      ),
      const SizedBox(height: AleraTokens.space4),
      Material(
        color: AleraTokens.surfaceVariant,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
          side: const BorderSide(color: AleraTokens.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AleraTokens.minTapTarget,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AleraTokens.space12,
                vertical: AleraTokens.space8,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(value),
                        const SizedBox(height: AleraTokens.space2),
                        Text(
                          description,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AleraTokens.foregroundMuted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AleraTokens.space8),
                  const Icon(
                    AleraIcons.chevronRight,
                    size: AleraTokens.space16,
                    color: AleraTokens.foregroundMuted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

class _MobileReviewLoadingField extends StatelessWidget {
  const _MobileReviewLoadingField();

  @override
  Widget build(BuildContext context) => const SizedBox(
    height: AleraTokens.minTapTarget,
    child: Center(
      child: SizedBox.square(
        dimension: AleraTokens.space20,
        child: CircularProgressIndicator(strokeWidth: AleraTokens.strokeSm),
      ),
    ),
  );
}

Future<T?> _showMobileReviewOptions<T>(
  BuildContext context, {
  required String title,
  required T selected,
  required List<T> values,
  required String Function(T value) label,
  required String Function(T value) description,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  backgroundColor: AleraTokens.surface,
  builder: (context) => FractionallySizedBox(
    heightFactor: AleraTokens.codexPickerHeightFactor,
    child: Padding(
      padding: const EdgeInsets.only(bottom: AleraTokens.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AleraTokens.space20,
              vertical: AleraTokens.space8,
            ),
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          Expanded(
            child: ListView(
              children: <Widget>[
                for (final value in values)
                  ListTile(
                    key: ValueKey<String>(
                      'mobile-codex-review-option-${value.toString().split('.').last}',
                    ),
                    minTileHeight: AleraTokens.minTapTarget,
                    selected: value == selected,
                    title: Text(label(value)),
                    subtitle: Text(description(value)),
                    trailing: value == selected
                        ? const Icon(
                            AleraIcons.check,
                            size: AleraTokens.space16,
                          )
                        : null,
                    onTap: () => Navigator.of(context).pop(value),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  ),
);

String? _defaultMobileReviewBranch(List<String> branches) {
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
