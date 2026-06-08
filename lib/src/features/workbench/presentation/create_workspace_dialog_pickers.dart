part of 'create_workspace_dialog.dart';

class _ProjectPicker extends StatelessWidget {
  const _ProjectPicker({
    required this.projects,
    required this.selectedProject,
    required this.query,
    required this.controller,
    required this.onQueryChanged,
    required this.onSelectProject,
  });

  final List<Project> projects;
  final Project? selectedProject;
  final String query;
  final TextEditingController controller;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<Project> onSelectProject;

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
      crossAxisAlignment: CrossAxisAlignment.start,
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
          maxHeight: 128,
          isEmpty: filtered.isEmpty,
          emptyMessage: 'No projects match "$query"',
          itemCount: filtered.length,
          itemBuilder: (context, index) {
            final project = filtered[index];
            final selected = project.id == selectedProject?.id;
            return AleraMenuItem(
              label: project.name,
              subtitle: project.repoPath,
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

class _SourceBranchPicker extends StatelessWidget {
  const _SourceBranchPicker({
    required this.branches,
    required this.selectedBranch,
    required this.query,
    required this.controller,
    required this.onQueryChanged,
    required this.onSelectBranch,
  });

  final List<String> branches;
  final String? selectedBranch;
  final String query;
  final TextEditingController controller;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String> onSelectBranch;

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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Source branch',
          style: theme.textTheme.labelMedium?.copyWith(
            color: AleraTokens.foregroundMuted,
          ),
        ),
        const SizedBox(height: AleraTokens.space8),
        AleraSearchField(
          controller: controller,
          hintText: 'Search source branches',
          onChanged: onQueryChanged,
        ),
        const SizedBox(height: AleraTokens.space8),
        _PickerPanel(
          maxHeight: 144,
          isEmpty: filtered.isEmpty,
          emptyMessage: 'No source branches match "$query"',
          itemCount: filtered.length,
          itemBuilder: (context, index) {
            final branch = filtered[index];
            final selected = branch == selectedBranch;
            return AleraMenuItem(
              label: branch,
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

class _PickerPanel extends StatelessWidget {
  const _PickerPanel({
    required this.maxHeight,
    required this.isEmpty,
    required this.emptyMessage,
    required this.itemCount,
    required this.itemBuilder,
  });

  final double maxHeight;
  final bool isEmpty;
  final String emptyMessage;
  final int itemCount;
  final NullableIndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AleraTokens.radiusMd);
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      clipBehavior: Clip.antiAlias,
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

class _LoadingBranches extends StatelessWidget {
  const _LoadingBranches();

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
            mainAxisSize: MainAxisSize.min,
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
