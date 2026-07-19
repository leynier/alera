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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(mobileViewPrefsControllerProvider(hostId)).value;
    if (prefs == null) {
      return const SafeArea(child: Center(child: CircularProgressIndicator()));
    }
    final controller = ref.read(
      mobileViewPrefsControllerProvider(hostId).notifier,
    );
    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.78,
        builder: (context, scrollController) => ListView(
          controller: scrollController,
          children: <Widget>[
            const ListTile(title: Text('View Options')),
            const Divider(height: 1),
            SwitchListTile(
              title: const Text('Group By Project'),
              value: prefs.groupBy == MobileWorkspaceGroupBy.project,
              onChanged: (value) => controller.setGroupBy(
                value
                    ? MobileWorkspaceGroupBy.project
                    : MobileWorkspaceGroupBy.none,
              ),
            ),
            _SortTile(
              label: 'Project Sort',
              value: prefs.projectSort,
              onChanged: controller.setProjectSort,
            ),
            _SortTile(
              label: 'Workspace Sort',
              value: prefs.workspaceSort,
              onChanged: controller.setWorkspaceSort,
            ),
            ListTile(
              title: const Text('Workspace Type'),
              trailing: DropdownButton<MobileWorkspaceKindFilter>(
                value: prefs.workspaceKindFilter,
                onChanged: (value) {
                  if (value != null) controller.setKindFilter(value);
                },
                items: const <DropdownMenuItem<MobileWorkspaceKindFilter>>[
                  DropdownMenuItem(
                    value: MobileWorkspaceKindFilter.all,
                    child: Text('All'),
                  ),
                  DropdownMenuItem(
                    value: MobileWorkspaceKindFilter.defaultOnly,
                    child: Text('Default Only'),
                  ),
                  DropdownMenuItem(
                    value: MobileWorkspaceKindFilter.nonDefaultOnly,
                    child: Text('Non-Default Only'),
                  ),
                ],
              ),
            ),
            const Divider(),
            const ListTile(title: Text('Projects')),
            for (final project in data.projects)
              CheckboxListTile(
                title: Text(project.name),
                value: prefs.selectedProjectIds.contains(project.id),
                onChanged: (_) => controller.setProjectFilter(
                  _toggle(prefs.selectedProjectIds, project.id),
                ),
              ),
            const Divider(),
            const ListTile(title: Text('Tags')),
            for (final tag in data.tags)
              CheckboxListTile(
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

class _SortTile extends StatelessWidget {
  const _SortTile({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final MobileWorkbenchSortBy value;
  final ValueChanged<MobileWorkbenchSortBy> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      trailing: DropdownButton<MobileWorkbenchSortBy>(
        value: value,
        onChanged: (value) {
          if (value != null) onChanged(value);
        },
        items: const <DropdownMenuItem<MobileWorkbenchSortBy>>[
          DropdownMenuItem(
            value: MobileWorkbenchSortBy.name,
            child: Text('Name'),
          ),
          DropdownMenuItem(
            value: MobileWorkbenchSortBy.recent,
            child: Text('Recent'),
          ),
          DropdownMenuItem(
            value: MobileWorkbenchSortBy.activity,
            child: Text('Activity'),
          ),
        ],
      ),
    );
  }
}

Set<String> _toggle(Set<String> values, String value) {
  final next = <String>{...values};
  if (!next.remove(value)) next.add(value);
  return next;
}
