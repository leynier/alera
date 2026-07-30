import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera_mobile/src/features/runtime/domain/project_selection_order.dart';
import 'package:alera_mobile/src/features/workbench/application/mobile_view_prefs_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_list_controller.dart';
import 'package:alera_mobile/src/features/workbench/domain/mobile_view_prefs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> showWorkspaceViewOptionsSheet(
  BuildContext context,
  WidgetRef ref, {
  required String hostId,
  required WorkspaceListData data,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _WorkspaceViewOptions(hostId: hostId, data: data),
  );
}

class _WorkspaceViewOptions extends ConsumerWidget {
  const _WorkspaceViewOptions({required this.hostId, required this.data});

  final String hostId;
  final WorkspaceListData data;

  static const List<AleraDropdownFieldEntry<MobileWorkbenchSortBy>>
  _sortEntries = <AleraDropdownFieldEntry<MobileWorkbenchSortBy>>[
    AleraDropdownFieldEntry(value: MobileWorkbenchSortBy.name, label: 'Name'),
    AleraDropdownFieldEntry(
      value: MobileWorkbenchSortBy.recent,
      label: 'Recent',
    ),
    AleraDropdownFieldEntry(
      value: MobileWorkbenchSortBy.activity,
      label: 'Agent Activity',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(mobileViewPrefsControllerProvider(hostId)).value;
    if (prefs == null) {
      return const SafeArea(child: Center(child: CircularProgressIndicator()));
    }
    final controller = ref.read(
      mobileViewPrefsControllerProvider(hostId).notifier,
    );
    final groupByProject = prefs.groupBy == MobileWorkspaceGroupBy.project;
    final orderedProjects = sortProjectsForSelection(data.projects);
    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.78,
        builder: (context, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(AleraTokens.space16),
          children: <Widget>[
            Text('View Options', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AleraTokens.space12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Group By Project'),
              value: groupByProject,
              onChanged: (value) => controller.setGroupBy(
                value
                    ? MobileWorkspaceGroupBy.project
                    : MobileWorkspaceGroupBy.none,
              ),
            ),
            const SizedBox(height: AleraTokens.space8),
            if (groupByProject) ...<Widget>[
              AleraDropdownField<MobileWorkbenchSortBy>(
                labelText: 'Sort Projects By',
                value: prefs.projectSort,
                onChanged: controller.setProjectSort,
                entries: _sortEntries,
              ),
              const SizedBox(height: AleraTokens.space12),
              AleraDropdownField<MobileWorkbenchSortBy>(
                labelText: 'Then Workspaces By',
                value: prefs.workspaceSort,
                onChanged: controller.setWorkspaceSort,
                entries: _sortEntries,
              ),
            ] else
              AleraDropdownField<MobileWorkbenchSortBy>(
                labelText: 'Sort Workspaces By',
                value: prefs.workspaceSort,
                onChanged: controller.setWorkspaceSort,
                entries: _sortEntries,
              ),
            const SizedBox(height: AleraTokens.space12),
            AleraDropdownField<MobileWorkspaceKindFilter>(
              labelText: 'Show Workspaces',
              value: prefs.workspaceKindFilter,
              onChanged: controller.setKindFilter,
              entries:
                  const <AleraDropdownFieldEntry<MobileWorkspaceKindFilter>>[
                    AleraDropdownFieldEntry(
                      value: MobileWorkspaceKindFilter.all,
                      label: 'All',
                    ),
                    AleraDropdownFieldEntry(
                      value: MobileWorkspaceKindFilter.defaultOnly,
                      label: 'Default Only',
                    ),
                    AleraDropdownFieldEntry(
                      value: MobileWorkspaceKindFilter.nonDefaultOnly,
                      label: 'Non-Default Only',
                    ),
                  ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Repeat Pinned Workspaces'),
              value: prefs.showPinnedWorkspacesBelow,
              onChanged: controller.setShowPinnedWorkspacesBelow,
            ),
            const SizedBox(height: AleraTokens.space16),
            const Divider(height: 1),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Projects'),
            ),
            for (final project in orderedProjects)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(project.name),
                value: prefs.selectedProjectIds.contains(project.id),
                onChanged: (_) => controller.setProjectFilter(
                  _toggle(prefs.selectedProjectIds, project.id),
                ),
              ),
            const Divider(height: 1),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Tags'),
            ),
            for (final tag in data.tags)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tag.name),
                value: prefs.selectedTagIds.contains(tag.id),
                onChanged: (_) => controller.setTagFilter(
                  _toggle(prefs.selectedTagIds, tag.id),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Set<String> _toggle(Set<String> values, String value) {
  final next = <String>{...values};
  if (!next.remove(value)) next.add(value);
  return next;
}
