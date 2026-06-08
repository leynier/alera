part of 'workbench_view_options_menu.dart';

class _ProjectsHeader extends StatelessWidget {
  const _ProjectsHeader({required this.count, required this.onClear});

  final int count;
  final VoidCallback? onClear;

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
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text('Clear', style: theme.textTheme.labelSmall),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: AleraTokens.foregroundFaint,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
      ),
    );
  }
}

class _GroupBySegmented extends StatelessWidget {
  const _GroupBySegmented({required this.value, required this.onChanged});

  final WorkbenchGroupBy value;
  final ValueChanged<WorkbenchGroupBy> onChanged;

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
        ButtonSegment(value: WorkbenchGroupBy.none, label: Text('None')),
        ButtonSegment(value: WorkbenchGroupBy.project, label: Text('Project')),
      ],
    );
  }
}

class _SortRow extends StatelessWidget {
  const _SortRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final WorkbenchSortBy value;
  final ValueChanged<WorkbenchSortBy> onChanged;

  static const Map<WorkbenchSortBy, String> _labels = <WorkbenchSortBy, String>{
    WorkbenchSortBy.name: 'Name',
    WorkbenchSortBy.recent: 'Recent',
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

class _SortPopupButton extends StatelessWidget {
  const _SortPopupButton({
    required this.value,
    required this.labels,
    required this.onChanged,
  });

  final WorkbenchSortBy value;
  final Map<WorkbenchSortBy, String> labels;
  final ValueChanged<WorkbenchSortBy> onChanged;

  Future<void> _openMenu(BuildContext context) async {
    final button = context.findRenderObject()! as RenderBox;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final topLeft = button.localToGlobal(
      button.size.bottomLeft(Offset.zero),
      ancestor: overlay,
    );
    final bottomRight = button.localToGlobal(
      button.size.bottomRight(Offset.zero) + const Offset(0, 200),
      ancestor: overlay,
    );
    final selected = await showMenu<WorkbenchSortBy>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(topLeft, bottomRight),
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
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AleraTokens.space8,
            vertical: AleraTokens.space4,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
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

class _AvailableProjectsList extends StatelessWidget {
  const _AvailableProjectsList({
    required this.projects,
    required this.hasSelection,
    required this.query,
    required this.onPick,
    required this.theme,
  });

  final List<Project> projects;
  final bool hasSelection;
  final String query;
  final ValueChanged<Project> onPick;
  final ThemeData theme;

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
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
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

class _AvailableProjectRow extends StatefulWidget {
  const _AvailableProjectRow({required this.project, required this.onPick});

  final Project project;
  final VoidCallback onPick;

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
        borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
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
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AleraTokens.foreground,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
