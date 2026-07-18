import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_listing_tree.dart';
import 'package:flutter/material.dart';

/// Picks a parent workspace for [child]. Pops with the chosen workspace id.
/// Candidates exclude the child itself and its descendants so relations stay
/// acyclic; the runtime enforces the same rule server-side.
Future<String?> showParentPickerSheet(
  BuildContext context, {
  required WorkspaceSummary child,
  required List<WorkspaceSummary> workspaces,
}) {
  final excluded = workspaceDescendantIds(workspaces, child.id)..add(child.id);
  final candidates = <WorkspaceSummary>[
    for (final workspace in workspaces)
      if (!excluded.contains(workspace.id)) workspace,
  ];
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
                'No Eligible Parents',
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
