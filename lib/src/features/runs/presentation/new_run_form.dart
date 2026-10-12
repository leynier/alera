import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/forms/alera_segmented_choice.dart';
import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/runs/domain/recipe_catalog_entry.dart';
import 'package:alera/src/features/runs/domain/run_create_request.dart';
import 'package:alera/src/features/runs/presentation/run_remote_workspaces_notice.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/domain/remote_workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:flutter/material.dart';

/// Isolated runs need a local Git workspace to branch worktrees from; shared
/// runs work in any active local workspace.
List<AleraDropdownFieldEntry<String>> newRunWorkspaceEntries(
  WorkbenchState workbench,
  RunIsolation isolation,
) {
  final projects = <String, Project>{
    for (final project in workbench.projects) project.id: project,
  };
  return <AleraDropdownFieldEntry<String>>[
    for (final workspace in workbench.workspacesByProject.values.expand(
      (items) => items,
    ))
      if (projects[workspace.projectId] case final project?)
        if (workspace.isActive &&
            !isRemoteWorkspaceHostId(workspace.hostId) &&
            !workspace.workflowOwned &&
            (isolation == RunIsolation.shared ||
                project.kind == ProjectKind.gitRepository))
          AleraDropdownFieldEntry<String>(
            value: workspace.id,
            label: '${project.name} / ${workspace.name}',
            group: project.name,
          ),
  ];
}

/// Whether the workspace picker left out workspaces on another host.
bool newRunHidesRemoteWorkspaces(WorkbenchState workbench) {
  final projects = {for (final project in workbench.projects) project.id};
  return hidesRemoteWorkspaces(<Workspace>[
    for (final workspace in workbench.workspacesByProject.values.expand(
      (items) => items,
    ))
      if (projects.contains(workspace.projectId) &&
          workspace.isActive &&
          !workspace.workflowOwned)
        workspace,
  ]);
}

List<AleraDropdownFieldEntry<String>> newRunProfileEntries(
  List<AgentProfile> profiles,
) => <AleraDropdownFieldEntry<String>>[
  for (final profile in profiles)
    AleraDropdownFieldEntry<String>(
      value: profile.id,
      label: '${profile.name} (${profile.agentType})',
    ),
];

AleraSegmentedChoice<RunIsolation> newRunIsolationChoice({
  required RunIsolation selected,
  required ValueChanged<RunIsolation> onChanged,
  required bool enabled,
}) => AleraSegmentedChoice<RunIsolation>(
  key: const ValueKey<String>('newRunIsolation'),
  label: 'Isolation',
  selected: selected,
  enabled: enabled,
  onChanged: onChanged,
  options: const <AleraSegmentedChoiceOption<RunIsolation>>[
    AleraSegmentedChoiceOption<RunIsolation>(
      value: RunIsolation.isolated,
      label: 'Isolated',
      helper: 'Every task runs in its own worktree and branch; results integrate as squash commits.',
    ),
    AleraSegmentedChoiceOption<RunIsolation>(
      value: RunIsolation.shared,
      label: 'Shared',
      helper: 'Workers share this workspace and its working tree. Uncommitted changes stay in place.',
    ),
  ],
);

/// Template dropdown, Manage Recipes, the template's description and one
/// profile per recipe role.
class const NewRunTemplateFields({
  super.key,
  required final List<RecipeCatalogEntry> entries,
  required final String? selectedKey,
  required final ValueChanged<String> onSelected,
  required final VoidCallback onManage,
  required final List<RecipeRole> roles,
  required final Map<String, String> roleProfiles,
  required final ValueChanged<(String, String)> onRoleProfile,
  required final List<AleraDropdownFieldEntry<String>> profiles,
  required final bool enabled,
  final String? catalogError,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: AleraTokens.foregroundMuted);
    final selected = entries
        .where((entry) => entry.key == selectedKey)
        .firstOrNull;
    return Column(
      crossAxisAlignment: .stretch,
      spacing: AleraTokens.space8,
      children: <Widget>[
        Row(
          crossAxisAlignment: .end,
          spacing: AleraTokens.space8,
          children: <Widget>[
            Expanded(
              child: AleraDropdownField<String>(
                key: const ValueKey<String>('newRunTemplate'),
                labelText: 'Template',
                hintText: entries.isEmpty
                    ? 'Choose a workspace first'
                    : 'Choose a recipe',
                value: selectedKey,
                enabled: enabled && entries.isNotEmpty,
                filterable: entries.length > 6,
                filterHintText: 'Search Recipes',
                entries: <AleraDropdownFieldEntry<String>>[
                  for (final entry in entries)
                    AleraDropdownFieldEntry<String>(
                      value: entry.key,
                      label: entry.label,
                      enabled: entry.usable,
                    ),
                ],
                onChanged: onSelected,
              ),
            ),
            TextButton(
              key: const ValueKey<String>('newRunManageRecipes'),
              onPressed: onManage,
              child: const Text('Manage Recipes…'),
            ),
          ],
        ),
        if (selected?.description case final description?)
          Text(description, style: muted),
        if (catalogError != null)
          Text('Project recipes are unavailable: $catalogError', style: muted),
        for (final role in roles)
          AleraDropdownField<String>(
            key: ValueKey<String>('newRunRole:${role.id}'),
            labelText: '${role.name} Profile',
            hintText: 'Choose an Agent Profile',
            value: roleProfiles[role.id],
            entries: profiles,
            enabled: enabled,
            filterable: profiles.length > 6,
            filterHintText: 'Search Profiles',
            onChanged: (id) => onRoleProfile((role.id, id)),
          ),
      ],
    );
  }
}
