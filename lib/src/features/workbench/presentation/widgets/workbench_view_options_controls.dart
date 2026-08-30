part of 'workbench_view_options_menu.dart';

class const _ProjectsHeader({
  required final int count,
  required final VoidCallback? onClear,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: <Widget>[
        _SectionLabel(text: 'Projects'),
        const SizedBox(width: AleraTokens.space6),
        if (count > 0) AleraBadge(label: count.toString()),
        const Spacer(),
        MouseRegion(
          cursor: onClear == null
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          child: TextButton(
            onPressed: onClear,
            style: TextButton.styleFrom(
              foregroundColor: AleraTokens.foregroundMuted,
              padding: const EdgeInsets.symmetric(
                horizontal: AleraTokens.space8,
              ),
              minimumSize: const Size(0, 24),
              tapTargetSize: .shrinkWrap,
            ),
            child: Text('Clear', style: theme.textTheme.labelSmall),
          ),
        ),
      ],
    );
  }
}

class const _SectionLabel({required final String text})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: AleraTokens.foregroundFaint,
        fontWeight: .w600,
        letterSpacing: 0.4,
      ),
    );
  }
}

class const _GroupBySegmented({
  required final WorkbenchGroupBy value,
  required final ValueChanged<WorkbenchGroupBy> onChanged,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AleraSegmentedButton<WorkbenchGroupBy>(
      dense: true,
      backgroundColor: AleraTokens.surface,
      foregroundColor: AleraTokens.foregroundMuted,
      selectedBackgroundColor: AleraTokens.accentSubtle,
      selectedForegroundColor: AleraTokens.foreground,
      borderColor: AleraTokens.borderSubtle,
      textStyle: Theme.of(context).textTheme.labelSmall,
      selected: value,
      onSelectionChanged: onChanged,
      segments: const <ButtonSegment<WorkbenchGroupBy>>[
        ButtonSegment(value: .none, label: Text('None')),
        ButtonSegment(value: .project, label: Text('Project')),
      ],
    );
  }
}

class const _WorkspaceKindSegmented({
  required final WorkspaceKindFilter value,
  required final ValueChanged<WorkspaceKindFilter> onChanged,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AleraSegmentedButton<WorkspaceKindFilter>(
      dense: true,
      backgroundColor: AleraTokens.surface,
      foregroundColor: AleraTokens.foregroundMuted,
      selectedBackgroundColor: AleraTokens.accentSubtle,
      selectedForegroundColor: AleraTokens.foreground,
      borderColor: AleraTokens.borderSubtle,
      textStyle: Theme.of(context).textTheme.labelSmall,
      selected: value,
      onSelectionChanged: onChanged,
      segments: const <ButtonSegment<WorkspaceKindFilter>>[
        ButtonSegment(value: .all, label: Text('All')),
        ButtonSegment(value: .defaultOnly, label: Text('Default')),
        ButtonSegment(value: .nonDefaultOnly, label: Text('Non-Default')),
      ],
    );
  }
}

class const _SortRow({
  required final String label,
  required final WorkbenchSortBy value,
  required final ValueChanged<WorkbenchSortBy> onChanged,
}) extends StatelessWidget {
  static const Map<WorkbenchSortBy, String> _labels = <WorkbenchSortBy, String>{
    WorkbenchSortBy.name: 'Name',
    WorkbenchSortBy.recent: 'Recent',
    WorkbenchSortBy.activity: 'Agent Activity',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          ),
        ),
        _SortPopupButton(value: value, labels: _labels, onChanged: onChanged),
      ],
    );
  }
}

class const _SortPopupButton({
  required final WorkbenchSortBy value,
  required final Map<WorkbenchSortBy, String> labels,
  required final ValueChanged<WorkbenchSortBy> onChanged,
}) extends StatelessWidget {
  Future<void> _openMenu(BuildContext context) async {
    final button = context.findRenderObject()! as RenderBox;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final topLeft = button.localToGlobal(
      button.size.bottomLeft(.zero),
      ancestor: overlay,
    );
    final bottomRight = button.localToGlobal(
      button.size.bottomRight(.zero) + const Offset(0, 200),
      ancestor: overlay,
    );
    final selected = await showMenu<WorkbenchSortBy>(
      context: context,
      position: .fromRect(
        .fromPoints(topLeft, bottomRight),
        Offset.zero & overlay.size,
      ),
      constraints: const BoxConstraints(minWidth: 160),
      items: <PopupMenuEntry<WorkbenchSortBy>>[
        for (final option in WorkbenchSortBy.values)
          AleraDropdownEntry<WorkbenchSortBy>(
            value: option,
            label: labels[option] ?? option.name,
            selected: option == value,
          ),
      ],
    );
    if (selected != null) {
      onChanged(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
      child: InkWell(
        onTap: () => _openMenu(context),
        mouseCursor: SystemMouseCursors.click,
        borderRadius: .circular(AleraTokens.radiusMd),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AleraTokens.space8,
            vertical: AleraTokens.space4,
          ),
          child: Row(
            mainAxisSize: .min,
            children: <Widget>[
              Text(
                labels[value] ?? value.name,
                style: const TextStyle(
                  color: AleraTokens.foregroundMuted,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: AleraTokens.space4),
              const Icon(
                AleraIcons.chevronDown,
                size: 14,
                color: AleraTokens.foregroundFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class const _AvailableProjectsList({
  required final List<Project> projects,
  required final bool hasSelection,
  required final String query,
  required final ValueChanged<Project> onPick,
  required final ThemeData theme,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (projects.isEmpty) {
      final emptyMessage = query.isNotEmpty
          ? 'No projects match "$query"'
          : (hasSelection ? 'All projects selected' : 'No projects yet');
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AleraTokens.space8),
        child: Center(
          child: Text(
            emptyMessage,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AleraTokens.foregroundFaint,
            ),
          ),
        ),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 240),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: <Widget>[
            for (final project in projects)
              _AvailableProjectRow(
                project: project,
                onPick: () => onPick(project),
              ),
          ],
        ),
      ),
    );
  }
}

class const _AvailableProjectRow({
  required final Project project,
  required final VoidCallback onPick,
}) extends StatefulWidget {
  @override
  State<_AvailableProjectRow> createState() => _AvailableProjectRowState();
}

class _AvailableProjectRowState extends State<_AvailableProjectRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: InkWell(
        onTap: widget.onPick,
        mouseCursor: SystemMouseCursors.click,
        borderRadius: .circular(AleraTokens.radiusSm),
        child: AnimatedContainer(
          duration: AleraTokens.durationFast,
          decoration: BoxDecoration(
            color: _hovered ? AleraTokens.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AleraTokens.space8,
            vertical: AleraTokens.space6,
          ),
          child: Row(
            children: <Widget>[
              const AleraStatusDot(active: false, size: 6),
              const SizedBox(width: AleraTokens.space8),
              Expanded(
                child: Text(
                  widget.project.name,
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: AleraTokens.foreground),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
