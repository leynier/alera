part of 'create_workspace_dialog.dart';

class const _ProjectPicker({
  required final List<Project> projects,
  required final Project? selectedProject,
  required final String query,
  required final TextEditingController controller,
  required final ValueChanged<String> onQueryChanged,
  required final ValueChanged<Project> onSelectProject,
  required final String? Function(Project project) getProjectActiveBranch,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final normalizedQuery = query.trim().toLowerCase();
    final filtered = <Project>[
      for (final project in projects)
        if (normalizedQuery.isEmpty ||
            project.name.toLowerCase().contains(normalizedQuery) ||
            project.repoPath.toLowerCase().contains(normalizedQuery))
          project,
    ];

    return Column(
      crossAxisAlignment: .start,
      children: <Widget>[
        Text(
          'Project',
          style: theme.textTheme.labelMedium?.copyWith(
            color: AleraTokens.foregroundMuted,
          ),
        ),
        const SizedBox(height: AleraTokens.space8),
        AleraSearchField(
          controller: controller,
          hintText: 'Search projects',
          onChanged: onQueryChanged,
        ),
        const SizedBox(height: AleraTokens.space8),
        _PickerPanel(
          maxHeight: 200,
          isEmpty: filtered.isEmpty,
          emptyMessage: 'No projects match "$query"',
          itemCount: filtered.length,
          itemBuilder: (context, index) {
            final project = filtered[index];
            final selected = project.id == selectedProject?.id;
            final activeBranch = getProjectActiveBranch(project);
            final subtitle =
                project.repoPath +
                (activeBranch != null ? '  •  ($activeBranch)' : '');
            return AleraMenuItem(
              label: project.name,
              subtitle: subtitle,
              selected: selected,
              leading: Icon(
                selected ? AleraIcons.radioOn : AleraIcons.radioOff,
                size: 16,
                color: selected
                    ? AleraTokens.accent
                    : AleraTokens.foregroundFaint,
              ),
              onTap: () => onSelectProject(project),
            );
          },
        ),
      ],
    );
  }
}

class const _SourceBranchPicker({
  required final String label,
  required final String searchHint,
  required final String emptyMessage,
  required final List<String> branches,
  required final String? selectedBranch,
  required final String query,
  required final TextEditingController controller,
  required final ValueChanged<String> onQueryChanged,
  required final ValueChanged<String> onSelectBranch,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final normalizedQuery = query.trim().toLowerCase();
    final filtered = <String>[
      for (final branch in branches)
        if (normalizedQuery.isEmpty ||
            branch.toLowerCase().contains(normalizedQuery))
          branch,
    ];

    return Column(
      crossAxisAlignment: .start,
      children: <Widget>[
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: AleraTokens.foregroundMuted,
          ),
        ),
        const SizedBox(height: AleraTokens.space8),
        AleraSearchField(
          controller: controller,
          hintText: searchHint,
          onChanged: onQueryChanged,
        ),
        const SizedBox(height: AleraTokens.space8),
        _PickerPanel(
          maxHeight: 240,
          isEmpty: filtered.isEmpty,
          emptyMessage: emptyMessage,
          itemCount: filtered.length,
          itemBuilder: (context, index) {
            final branch = filtered[index];
            final selected = branch == selectedBranch;
            final isDefault = const <String>[
              'main',
              'origin/main',
              'master',
              'origin/master',
            ].contains(branch);
            final label = branch + (isDefault ? ' (default)' : '');
            return AleraMenuItem(
              label: label,
              selected: selected,
              leading: Icon(
                selected ? AleraIcons.success : AleraIcons.circle,
                size: 16,
                color: selected
                    ? AleraTokens.accent
                    : AleraTokens.foregroundFaint,
              ),
              onTap: () => onSelectBranch(branch),
            );
          },
        ),
      ],
    );
  }
}

class const _PickerPanel({
  required final double maxHeight,
  required final bool isEmpty,
  required final String emptyMessage,
  required final int itemCount,
  required final NullableIndexedWidgetBuilder itemBuilder,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AleraTokens.radiusMd);
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      clipBehavior: .antiAlias,
      decoration: BoxDecoration(
        color: AleraTokens.surfaceVariant,
        borderRadius: radius,
        border: Border.all(color: AleraTokens.borderSubtle),
      ),
      child: isEmpty
          ? AleraEmptyState(message: emptyMessage)
          : ListView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: itemCount,
              itemBuilder: itemBuilder,
            ),
    );
  }
}

class const _LoadingBranches() extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AleraPanel(
      borderRadius: AleraTokens.radiusMd,
      children: <Widget>[
        Container(
          height: 72,
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: .min,
            children: <Widget>[
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: AleraTokens.space8),
              Text(
                'Loading source branches',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AleraTokens.foregroundMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
