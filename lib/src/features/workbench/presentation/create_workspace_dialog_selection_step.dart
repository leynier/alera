part of 'create_workspace_dialog.dart';

class const _CreateWorkspaceSelectionStep({
  required final List<Project> projects,
  required final Project? selectedProject,
  required final String projectQuery,
  required final TextEditingController projectSearchController,
  required final ValueChanged<String> onProjectQueryChanged,
  required final ValueChanged<Project> onSelectProject,
  required final String? Function(Project project) getProjectActiveBranch,
  required final bool reuseExistingBranch,
  required final ValueChanged<bool> onReuseExistingBranchChanged,
  required final bool loadingBranches,
  required final List<String> branches,
  required final String? selectedBranch,
  required final String branchQuery,
  required final TextEditingController branchSearchController,
  required final ValueChanged<String> onBranchQueryChanged,
  required final ValueChanged<String> onSelectBranch,
  required final String? branchesError,
  required final VoidCallback onRetryBranches,
  required final TextEditingController sourceBranchController,
  required final String? sourceBranchError,
  required final ValueChanged<String> onManualSourceBranchChanged,
}) extends StatelessWidget {
  String get _branchLabel =>
      reuseExistingBranch ? 'Existing Branch' : 'Source Branch';

  String get _branchSearchHint => reuseExistingBranch
      ? 'Search existing branches'
      : 'Search source branches';

  String get _emptyBranchesMessage => reuseExistingBranch
      ? 'No existing branches match "$branchQuery"'
      : 'No source branches match "$branchQuery"';

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      children: <Widget>[
        _ProjectPicker(
          projects: projects,
          selectedProject: selectedProject,
          query: projectQuery,
          controller: projectSearchController,
          onQueryChanged: onProjectQueryChanged,
          onSelectProject: onSelectProject,
          getProjectActiveBranch: getProjectActiveBranch,
        ),
        const SizedBox(height: AleraTokens.space16),
        AleraSegmentedButton<bool>(
          segments: const <ButtonSegment<bool>>[
            ButtonSegment<bool>(value: false, label: Text('New Branch')),
            ButtonSegment<bool>(value: true, label: Text('Existing Branch')),
          ],
          selected: reuseExistingBranch,
          onSelectionChanged: onReuseExistingBranchChanged,
        ),
        const SizedBox(height: AleraTokens.space16),
        if (loadingBranches)
          const _LoadingBranches()
        else if (branches.isNotEmpty)
          _SourceBranchPicker(
            label: _branchLabel,
            searchHint: _branchSearchHint,
            emptyMessage: _emptyBranchesMessage,
            branches: branches,
            selectedBranch: selectedBranch,
            query: branchQuery,
            controller: branchSearchController,
            onQueryChanged: onBranchQueryChanged,
            onSelectBranch: onSelectBranch,
          )
        else
          _ManualSourceBranchField(
            label: _branchLabel,
            controller: sourceBranchController,
            errorText: sourceBranchError,
            loadError: branchesError,
            onRetry: onRetryBranches,
            onChanged: onManualSourceBranchChanged,
          ),
      ],
    );
  }
}

class const _ManualSourceBranchField({
  required final String label,
  required final TextEditingController controller,
  required final String? errorText,
  required final String? loadError,
  required final VoidCallback onRetry,
  required final ValueChanged<String> onChanged,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: .min,
      children: <Widget>[
        if (loadError case final message?) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AleraTokens.error,
                  ),
                ),
              ),
              const SizedBox(width: AleraTokens.space8),
              IconButton(
                icon: const Icon(AleraIcons.refresh, size: 16),
                onPressed: onRetry,
              ),
            ],
          ),
          const SizedBox(height: AleraTokens.space8),
        ],
        AleraTextField(
          controller: controller,
          autofocus: true,
          labelText: label,
          hintText: 'e.g. main',
          errorText: errorText,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
