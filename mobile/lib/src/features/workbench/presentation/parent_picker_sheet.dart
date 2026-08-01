import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/runtime/domain/project_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_listing_tree.dart';
import 'package:alera_mobile/src/features/workbench/domain/workspace_parent_selection_order.dart';
import 'package:flutter/material.dart';

/// Picks a parent workspace for [child]. Pops with the chosen workspace id.
/// Candidates exclude the child itself and its descendants so relations stay
/// acyclic; the runtime enforces the same rule server-side.
Future<String?> showParentPickerSheet(
  BuildContext context, {
  required WorkspaceSummary child,
  required List<WorkspaceSummary> workspaces,
  required List<ProjectSummary> projects,
}) {
  final excluded = workspaceDescendantIds(workspaces, child.id)..add(child.id);
  final projectNameById = <String, String>{
    for (final project in projects) project.id: project.name,
  };
  final candidates =
      <WorkspaceSummary>[
        for (final workspace in workspaces)
          if (!excluded.contains(workspace.id)) workspace,
      ]..sort(
        (left, right) => compareWorkspaceParentSelectionKeys(
          (
            isDefault: left.isMain,
            projectId: left.projectId,
            projectName: projectNameById[left.projectId] ?? left.projectId,
            workspaceId: left.id,
            workspaceName: left.name,
          ),
          (
            isDefault: right.isMain,
            projectId: right.projectId,
            projectName: projectNameById[right.projectId] ?? right.projectId,
            workspaceId: right.id,
            workspaceName: right.name,
          ),
          preferredProjectId: child.projectId,
        ),
      );
  return showModalBottomSheet<String>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: AleraTokens.contentPadding,
            child: Text(
              'Select Parent Workspace',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (candidates.isEmpty)
            Padding(
              padding: AleraTokens.contentPadding,
              child: Text(
                'No eligible parents',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: candidates.length,
                itemBuilder: (context, index) {
                  final workspace = candidates[index];
                  return ListTile(
                    leading: Icon(
                      workspace.isMain
                          ? Icons.home_outlined
                          : Icons.account_tree_outlined,
                    ),
                    title: Text(
                      workspace.name,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      workspace.branch ?? workspace.path,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => Navigator.of(context).pop(workspace.id),
                  );
                },
              ),
            ),
        ],
      ),
    ),
  );
}
