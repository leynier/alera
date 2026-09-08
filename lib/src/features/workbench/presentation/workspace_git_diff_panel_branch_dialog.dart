part of 'workspace_git_diff_panel.dart';

sealed class _BranchDialogResult {
  const _BranchDialogResult();
}

class const _SwitchBranchResult(this.branch) extends _BranchDialogResult {
  final String branch;
}

class const _CreateBranchResult(this.branch) extends _BranchDialogResult {
  final String branch;
}

class const _SourceControlBranchDialog({
  required final List<String> branches,
  required final String currentBranch,
}) extends StatefulWidget {
  @override
  State<_SourceControlBranchDialog> createState() =>
      _SourceControlBranchDialogState();
}

class _SourceControlBranchDialogState
    extends State<_SourceControlBranchDialog> {
  final TextEditingController _filterController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  String _query = '';
  bool _creating = false;
  String? _nameError;

  @override
  void dispose() {
    _filterController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  List<String> get _filteredBranches {
    final normalized = _query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return widget.branches;
    }
    return <String>[
      for (final branch in widget.branches)
        if (branch.toLowerCase().contains(normalized)) branch,
    ];
  }

  void _switchTo(String branch) {
    Navigator.of(context).pop(_SwitchBranchResult(branch));
  }

  void _submitCreate() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Branch name is required');
      return;
    }
    if (widget.branches.contains(name)) {
      setState(() => _nameError = 'A branch named "$name" already exists');
      return;
    }
    Navigator.of(context).pop(_CreateBranchResult(name));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AleraDialog(
      maxWidth: 460,
      maxHeight: 520,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: <Widget>[
            Text(
              _creating ? 'Create Branch' : 'Switch Branch',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AleraTokens.space12),
            if (_creating)
              AleraTextField(
                controller: _nameController,
                autofocus: true,
                labelText: 'Branch Name',
                hintText: 'e.g. feature/login',
                errorText: _nameError,
                onChanged: (_) {
                  if (_nameError != null) {
                    setState(() => _nameError = null);
                  }
                },
                onSubmitted: (_) => _submitCreate(),
              )
            else
              AleraSearchField(
                controller: _filterController,
                hintText: 'Search branches',
                autofocus: true,
                onChanged: (value) => setState(() => _query = value),
              ),
            const SizedBox(height: AleraTokens.space12),
            if (!_creating)
              Flexible(
                child: _filteredBranches.isEmpty
                    ? AleraEmptyState(
                        message: _query.trim().isEmpty
                            ? 'No branches found'
                            : 'No branches match "$_query"',
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _filteredBranches.length,
                        itemBuilder: (context, index) {
                          final branch = _filteredBranches[index];
                          final selected = branch == widget.currentBranch;
                          return AleraMenuItem(
                            label: branch,
                            selected: selected,
                            onTap: () => _switchTo(branch),
                          );
                        },
                      ),
              ),
            const SizedBox(height: AleraTokens.space12),
            Row(
              children: <Widget>[
                if (!_creating)
                  TextButton(
                    onPressed: () => setState(() => _creating = true),
                    child: const Text('Create Branch'),
                  )
                else
                  TextButton(
                    onPressed: () => setState(() {
                      _creating = false;
                      _nameError = null;
                    }),
                    child: const Text('Back'),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                if (_creating) ...<Widget>[
                  const SizedBox(width: AleraTokens.space8),
                  FilledButton(
                    onPressed: _submitCreate,
                    child: const Text('Create'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
