part of 'create_workspace_dialog.dart';

class _CreateWorkspaceSelectionStep extends StatelessWidget {
  const _CreateWorkspaceSelectionStep({
    required this.projects,
    required this.selectedProject,
    required this.projectQuery,
    required this.projectSearchController,
    required this.onProjectQueryChanged,
    required this.onSelectProject,
    required this.getProjectActiveBranch,
    required this.reuseExistingBranch,
    required this.onReuseExistingBranchChanged,
    required this.loadingBranches,
    required this.branches,
    required this.selectedBranch,
    required this.branchQuery,
    required this.branchSearchController,
    required this.onBranchQueryChanged,
    required this.onSelectBranch,
    required this.branchesError,
    required this.onRetryBranches,
    required this.sourceBranchController,
    required this.sourceBranchError,
    required this.onManualSourceBranchChanged,
  });

  final List<Project> projects;
  final Project? selectedProject;
  final String projectQuery;
  final TextEditingController projectSearchController;
  final ValueChanged<String> onProjectQueryChanged;
  final ValueChanged<Project> onSelectProject;
  final String? Function(Project project) getProjectActiveBranch;
  final bool reuseExistingBranch;
  final ValueChanged<bool> onReuseExistingBranchChanged;
  final bool loadingBranches;
  final List<String> branches;
  final String? selectedBranch;
  final String branchQuery;
  final TextEditingController branchSearchController;
  final ValueChanged<String> onBranchQueryChanged;
  final ValueChanged<String> onSelectBranch;
  final String? branchesError;
  final VoidCallback onRetryBranches;
  final TextEditingController sourceBranchController;
  final String? sourceBranchError;
  final ValueChanged<String> onManualSourceBranchChanged;

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
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
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

class _ManualSourceBranchField extends StatelessWidget {
  const _ManualSourceBranchField({
    required this.label,
    required this.controller,
    required this.errorText,
    required this.loadError,
    required this.onRetry,
    required this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final String? errorText;
  final String? loadError;
  final VoidCallback onRetry;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
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
