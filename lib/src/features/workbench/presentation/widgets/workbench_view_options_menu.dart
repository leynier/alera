import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/buttons/alera_segmented_button.dart';
import 'package:alera/src/design_system/chips/alera_chip.dart';
import 'package:alera/src/design_system/feedback/alera_status_dot.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/design_system/layout/alera_dialog_header.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_entry.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Filter/sort/group icon button that opens the view-options modal centered on
/// screen. Using a centered dialog (instead of an anchored popover) sidesteps
/// the dropdown clipping issues we hit with the previous overlay-based panel.
class WorkbenchViewOptionsButton extends ConsumerWidget {
  const WorkbenchViewOptionsButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(
      workbenchControllerProvider.select((state) => state.viewPrefs),
    );
    final hasFilters =
        prefs.selectedProjectIds.isNotEmpty ||
        prefs.groupBy != WorkbenchViewPrefs.defaults.groupBy ||
        prefs.projectSort != WorkbenchViewPrefs.defaults.projectSort ||
        prefs.workspaceSort != WorkbenchViewPrefs.defaults.workspaceSort;
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        AleraIconButton(
          tooltip: 'View options',
          onPressed: () => _showOptions(context),
          icon: Icons.tune,
        ),
        if (hasFilters) const Positioned(right: 6, top: 6, child: _ActiveDot()),
      ],
    );
  }

  Future<void> _showOptions(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierColor: const Color(0xCC000000),
      builder: (dialogContext) {
        return AleraDialog(
          backgroundColor: AleraTokens.surfaceElevated,
          elevation: 0,
          maxWidth: 460,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: AleraTokens.space24,
            vertical: AleraTokens.space32,
          ),
          child: _WorkbenchViewOptionsPanel(
            onDismiss: () => Navigator.of(dialogContext).pop(),
          ),
        );
      },
    );
  }
}

class _ActiveDot extends StatelessWidget {
  const _ActiveDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: const BoxDecoration(
        color: AleraTokens.accent,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _WorkbenchViewOptionsPanel extends ConsumerStatefulWidget {
  const _WorkbenchViewOptionsPanel({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  ConsumerState<_WorkbenchViewOptionsPanel> createState() =>
      _WorkbenchViewOptionsPanelState();
}

class _WorkbenchViewOptionsPanelState
    extends ConsumerState<_WorkbenchViewOptionsPanel> {
  final TextEditingController _searchController = TextEditingController();
  String _projectQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      final value = _searchController.text.trim().toLowerCase();
      if (value != _projectQuery) {
        setState(() => _projectQuery = value);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _addFirstMatch(List<Project> available) {
    if (available.isEmpty) {
      return;
    }
    ref
        .read(workbenchControllerProvider.notifier)
        .addProjectFilter(available.first.id);
    _searchController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(workbenchControllerProvider);
    final controller = ref.read(workbenchControllerProvider.notifier);
    final prefs = state.viewPrefs;
    final theme = Theme.of(context);

    final selectedProjects = <Project>[
      for (final id in prefs.selectedProjectIds)
        ...state.projects.where((p) => p.id == id),
    ];
    final availableProjects = state.projects
        .where((p) => !prefs.selectedProjectIds.contains(p.id))
        .where(
          (p) =>
              _projectQuery.isEmpty ||
              p.name.toLowerCase().contains(_projectQuery),
        )
        .toList(growable: false);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AleraTokens.space16,
        AleraTokens.space12,
        AleraTokens.space16,
        AleraTokens.space16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AleraDialogHeader(title: 'View options', onClose: widget.onDismiss),
          const SizedBox(height: AleraTokens.space12),
          _SectionLabel(text: 'Group by'),
          const SizedBox(height: AleraTokens.space6),
          _GroupBySegmented(
            value: prefs.groupBy,
            onChanged: controller.setGroupBy,
          ),
          const SizedBox(height: AleraTokens.space12),
          _SortRow(
            label: prefs.groupBy == WorkbenchGroupBy.project
                ? 'Sort projects by'
                : 'Sort workspaces by',
            value: prefs.groupBy == WorkbenchGroupBy.project
                ? prefs.projectSort
                : prefs.workspaceSort,
            onChanged: prefs.groupBy == WorkbenchGroupBy.project
                ? controller.setProjectSort
                : controller.setWorkspaceSort,
          ),
          if (prefs.groupBy == WorkbenchGroupBy.project) ...<Widget>[
            const SizedBox(height: AleraTokens.space8),
            _SortRow(
              label: 'Then by',
              value: prefs.workspaceSort,
              onChanged: controller.setWorkspaceSort,
            ),
          ],
          const SizedBox(height: AleraTokens.space16),
          const Divider(height: 1, color: AleraTokens.borderSubtle),
          const SizedBox(height: AleraTokens.space12),
          _ProjectsHeader(
            count: prefs.selectedProjectIds.length,
            onClear: prefs.selectedProjectIds.isEmpty
                ? null
                : controller.clearProjectFilters,
          ),
          if (selectedProjects.isNotEmpty) ...<Widget>[
            const SizedBox(height: AleraTokens.space8),
            Wrap(
              spacing: AleraTokens.space6,
              runSpacing: AleraTokens.space6,
              children: <Widget>[
                for (final project in selectedProjects)
                  AleraChip(
                    label: project.name,
                    onRemove: () => controller.removeProjectFilter(project.id),
                  ),
              ],
            ),
          ],
          const SizedBox(height: AleraTokens.space8),
          AleraTextField(
            dense: true,
            prefixIcon: Icons.add,
            hintText: 'Add project…',
            controller: _searchController,
            onSubmitted: (_) => _addFirstMatch(availableProjects),
          ),
          const SizedBox(height: AleraTokens.space8),
          _AvailableProjectsList(
            projects: availableProjects,
            hasSelection: prefs.selectedProjectIds.isNotEmpty,
            query: _projectQuery,
            onPick: (project) {
              controller.addProjectFilter(project.id);
              _searchController.clear();
            },
            theme: theme,
          ),
        ],
      ),
    );
  }
}

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
                Icons.keyboard_arrow_down,
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
