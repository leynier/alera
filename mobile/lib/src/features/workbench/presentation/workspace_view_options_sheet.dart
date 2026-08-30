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

class const _WorkspaceViewOptions({
  required final String hostId,
  required final WorkspaceListData data,
}) extends ConsumerWidget {
  static const List<AleraDropdownFieldEntry<MobileWorkbenchSortBy>>
  _sortEntries = <AleraDropdownFieldEntry<MobileWorkbenchSortBy>>[
    AleraDropdownFieldEntry(value: .name, label: 'Name'),
    AleraDropdownFieldEntry(value: .recent, label: 'Recent'),
    AleraDropdownFieldEntry(value: .activity, label: 'Agent Activity'),
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
            AleraDropdownField<MobileWorkspaceGroupBy>(
              labelText: 'Group By',
              value:
                  !data.supportsSections &&
                      prefs.groupBy == MobileWorkspaceGroupBy.section
                  ? MobileWorkspaceGroupBy.project
                  : prefs.groupBy,
              entries: [
                const AleraDropdownFieldEntry(
                  value: MobileWorkspaceGroupBy.none,
                  label: 'None',
                ),
                const AleraDropdownFieldEntry(
                  value: MobileWorkspaceGroupBy.project,
                  label: 'Project',
                ),
                if (data.supportsSections)
                  const AleraDropdownFieldEntry(
                    value: MobileWorkspaceGroupBy.section,
                    label: 'Section',
                  ),
              ],
              onChanged: controller.setGroupBy,
            ),
            const SizedBox(height: AleraTokens.space8),
            if (prefs.groupBy != MobileWorkspaceGroupBy.none) ...<Widget>[
              AleraDropdownField<MobileWorkbenchSortBy>(
                labelText: groupByProject
                    ? 'Sort Projects By'
                    : 'Sort Sections By',
                value: groupByProject ? prefs.projectSort : prefs.sectionSort,
                onChanged: groupByProject
                    ? controller.setProjectSort
                    : controller.setSectionSort,
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
                    AleraDropdownFieldEntry(value: .all, label: 'All'),
                    AleraDropdownFieldEntry(
                      value: .defaultOnly,
                      label: 'Default Only',
                    ),
                    AleraDropdownFieldEntry(
                      value: .nonDefaultOnly,
                      label: 'Non-Default Only',
                    ),
                  ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Active Workspaces Only'),
              value: prefs.showActiveWorkspacesOnly,
              onChanged: controller.setShowActiveWorkspacesOnly,
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
