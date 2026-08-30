part of 'project_workbench_sidebar.dart';

class const _WorkspaceAgentRunList({
  required final Workspace workspace,
  required final List<WorkspaceAgentRun> runs,
  required final bool workspaceIsActive,
  required final String? activeTabId,
  required final _TerminalTabCallback onSelectTerminal,
  required final _TerminalTabCallback onCloseTerminal,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: .stretch,
      mainAxisSize: .min,
      children: <Widget>[
        // Keyed by tab so each row keeps its identity and state across the
        // status updates that refresh this list.
        for (final run in runs)
          _AgentRunRow(
            key: ValueKey<String>(run.tab.id),
            tab: run.tab,
            status: run.status,
            isActive: workspaceIsActive && activeTabId == run.tab.id,
            onTap: () => onSelectTerminal(workspace, run.tab.id),
            onClose: () => onCloseTerminal(workspace, run.tab.id),
          ),
      ],
    );
  }
}
