import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/buttons/alera_segmented_button.dart';
import 'package:alera/src/design_system/chips/alera_chip.dart';
import 'package:alera/src/design_system/feedback/alera_status_dot.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/design_system/layout/alera_dialog_header.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_entry.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'workbench_view_options_controls.dart';
part 'workbench_view_options_tags.dart';

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
        prefs.selectedTagIds.isNotEmpty ||
        prefs.workspaceKindFilter !=
            WorkbenchViewPrefs.defaults.workspaceKindFilter ||
        prefs.groupBy != WorkbenchViewPrefs.defaults.groupBy ||
        prefs.projectSort != WorkbenchViewPrefs.defaults.projectSort ||
        prefs.workspaceSort != WorkbenchViewPrefs.defaults.workspaceSort;
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        AleraIconButton(
          tooltip: 'View options',
          onPressed: () => _showOptions(context),
          icon: AleraIcons.tune,
        ),
        // Decorative only: without IgnorePointer the dot swallows clicks on
        // the small icon button underneath it.
        if (hasFilters)
          const Positioned(
            right: 6,
            top: 6,
            child: IgnorePointer(child: _ActiveDot()),
          ),
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
  final TextEditingController _tagSearchController = TextEditingController();
  String _projectQuery = '';
  String _tagQuery = '';

  /// Tags known to the runtime, loaded once when the panel opens. Until (or if
  /// ever) the fetch fails, the tags carried by the loaded workspaces act as a
  /// fallback so the filter stays usable offline.
  List<_TagOption>? _runtimeTags;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      final value = _searchController.text.trim().toLowerCase();
      if (value != _projectQuery) {
        setState(() => _projectQuery = value);
      }
    });
    _tagSearchController.addListener(() {
      final value = _tagSearchController.text.trim().toLowerCase();
      if (value != _tagQuery) {
        setState(() => _tagQuery = value);
      }
    });
    _loadRuntimeTags();
  }

  Future<void> _loadRuntimeTags() async {
    try {
      final tags = await ref
          .read(workbenchControllerProvider.notifier)
          .listWorkspaceTags();
      if (!mounted) {
        return;
      }
      setState(() {
        _runtimeTags = <_TagOption>[
          for (final tag in tags) (id: tag.id, name: tag.name),
        ];
      });
    } catch (_) {
      // Keep the workspace-derived fallback.
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tagSearchController.dispose();
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

  List<_TagOption> _knownTags(WorkbenchState state) {
    final runtime = _runtimeTags;
    if (runtime != null) {
      return runtime;
    }
    final byId = <String, String>{};
    for (final workspaces in state.workspacesByProject.values) {
      for (final workspace in workspaces) {
        for (var i = 0; i < workspace.tagIds.length; i++) {
          byId[workspace.tagIds[i]] = i < workspace.tagNames.length
              ? workspace.tagNames[i]
              : workspace.tagIds[i];
        }
      }
    }
    final options = <_TagOption>[
      for (final entry in byId.entries) (id: entry.key, name: entry.value),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return options;
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

    final knownTags = _knownTags(state);
    final tagNameById = <String, String>{
      for (final tag in knownTags) tag.id: tag.name,
    };
    final selectedTags = <_TagOption>[
      for (final id in prefs.selectedTagIds)
        (id: id, name: tagNameById[id] ?? id),
    ];
    final availableTags = knownTags
        .where((tag) => !prefs.selectedTagIds.contains(tag.id))
        .where(
          (tag) =>
              _tagQuery.isEmpty || tag.name.toLowerCase().contains(_tagQuery),
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
          AleraDialogHeader(title: 'View Options', onClose: widget.onDismiss),
          const SizedBox(height: AleraTokens.space12),
          // The option sections can outgrow short windows, so they scroll
          // under the fixed header.
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _SectionLabel(text: 'Group By'),
                  const SizedBox(height: AleraTokens.space6),
                  _GroupBySegmented(
                    value: prefs.groupBy,
                    onChanged: controller.setGroupBy,
                  ),
                  const SizedBox(height: AleraTokens.space12),
                  _SortRow(
                    label: prefs.groupBy == WorkbenchGroupBy.project
                        ? 'Sort Projects By'
                        : 'Sort Workspaces By',
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
                      label: 'Then Workspaces By',
                      value: prefs.workspaceSort,
                      onChanged: controller.setWorkspaceSort,
                    ),
                  ],
                  const SizedBox(height: AleraTokens.space12),
                  _SectionLabel(text: 'Show Workspaces'),
                  const SizedBox(height: AleraTokens.space6),
                  _WorkspaceKindSegmented(
                    value: prefs.workspaceKindFilter,
                    onChanged: controller.setWorkspaceKindFilter,
                  ),
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
                            onRemove: () =>
                                controller.removeProjectFilter(project.id),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: AleraTokens.space8),
                  AleraTextField(
                    dense: true,
                    prefixIcon: AleraIcons.add,
                    hintText: 'Add Project…',
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
                  const SizedBox(height: AleraTokens.space16),
                  const Divider(height: 1, color: AleraTokens.borderSubtle),
                  const SizedBox(height: AleraTokens.space12),
                  _TagsFilterSection(
                    selectedTags: selectedTags,
                    availableTags: availableTags,
                    query: _tagQuery,
                    searchController: _tagSearchController,
                    onAdd: (tagId) {
                      controller.addTagFilter(tagId);
                      _tagSearchController.clear();
                    },
                    onRemove: controller.removeTagFilter,
                    onClear: prefs.selectedTagIds.isEmpty
                        ? null
                        : controller.clearTagFilters,
                    theme: theme,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
