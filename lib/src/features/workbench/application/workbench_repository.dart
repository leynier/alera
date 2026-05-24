import 'package:alera/src/features/workbench/domain/terminal_tab_record.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';

abstract interface class WorkbenchRepository {
  Future<List<Workspace>> listWorkspaces(String projectId);

  Stream<List<Workspace>> watchWorkspaces(String projectId);

  Future<Workspace?> findWorkspaceById(String workspaceId);

  Future<Workspace> upsertWorkspace(Workspace workspace);

  Future<void> removeWorkspace(String workspaceId, {bool cascadeTabs = true});

  Future<void> removeWorkspacesForProject(String projectId);

  Future<List<TerminalTabRecord>> listTerminalTabs(String workspaceId);

  Stream<List<TerminalTabRecord>> watchTerminalTabs(String workspaceId);

  Future<TerminalTabRecord?> findTerminalTabById(String tabId);

  Future<TerminalTabRecord> upsertTerminalTab(TerminalTabRecord tab);

  Future<void> removeTerminalTab(String tabId);

  Future<void> removeTerminalTabsForWorkspace(String workspaceId);
}
