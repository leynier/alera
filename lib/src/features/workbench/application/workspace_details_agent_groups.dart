import 'package:alera/src/features/workbench/application/workbench_agent_activity_sort.dart';
import 'package:alera/src/features/workbench/application/workspace_agent_status_projection.dart';
import 'package:alera/src/features/workbench/domain/workspace_panel.dart';

/// A workspace's agent runs split by the panel that shows them, each side in
/// Agent Activity order.
class const WorkspaceDetailsAgentGroups({
  required final List<WorkspaceAgentRun> main,
  required final List<WorkspaceAgentRun> right,
}) {
  List<WorkspaceAgentRun> get all => [...main, ...right];

  List<WorkspaceAgentRun> runsIn(WorkspacePanelTree tree) => switch (tree) {
    WorkspacePanelTree.main => main,
    WorkspacePanelTree.right => right,
  };
}

/// Every tab outside the main panel lives in the right panel. Without a
/// saved panel the workspace has only shown its main panel, so all runs go
/// there. A delegated chat travels with the chat that delegated it, on that
/// chat's side and right below it, so each chat keeps its own tree.
WorkspaceDetailsAgentGroups groupWorkspaceDetailsAgentRuns(
  List<WorkspaceAgentRun> runs, {
  required WorkspacePanel? panel,
  required DateTime now,
}) {
  final mainIds = panel == null
      ? const <String>{}
      : workspacePanelMainTabIds(panel).toSet();
  // Runs arrive with each child chat already right after its parent.
  final trees = <WorkspaceAgentRun, List<WorkspaceAgentRun>>{};
  WorkspaceAgentRun? root;
  for (final run in runs) {
    if ((run.chat?.depth ?? 0) == 0 || root == null) {
      root = run;
      trees[run] = <WorkspaceAgentRun>[];
    } else {
      trees[root]!.add(run);
    }
  }
  final main = <WorkspaceAgentRun>[];
  final right = <WorkspaceAgentRun>[];
  for (final run in trees.keys) {
    if (mainIds.isEmpty || mainIds.contains(run.tab.id)) {
      main.add(run);
    } else {
      right.add(run);
    }
  }
  List<WorkspaceAgentRun> expand(List<WorkspaceAgentRun> roots) => [
    for (final root in sortWorkspaceAgentRunsByActivity(roots, now: now)) ...[
      root,
      ...trees[root]!,
    ],
  ];
  return WorkspaceDetailsAgentGroups(main: expand(main), right: expand(right));
}
