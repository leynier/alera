import 'package:alera/src/features/workbench/domain/terminal_tab_record.dart';
import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:alera/src/features/workbench/domain/workbench_tab_record.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';

abstract interface class WorkbenchRepository {
  Future<List<Workspace>> listWorkspaces(String projectId);

  Stream<List<Workspace>> watchWorkspaces(String projectId);

  Future<Workspace?> findWorkspaceById(String workspaceId);

  Future<Workspace> upsertWorkspace(Workspace workspace);

  Future<void> removeWorkspace(String workspaceId, {bool cascadeTabs = true});

  Future<void> removeWorkspacesForProject(String projectId);

  Future<List<WorkbenchTabRecord>> listWorkbenchTabs(String workspaceId);

  Stream<List<WorkbenchTabRecord>> watchWorkbenchTabs(String workspaceId);

  Future<WorkbenchTabRecord?> findWorkbenchTabById(String tabId);

  Future<WorkbenchTabRecord> upsertWorkbenchTab(WorkbenchTabRecord tab);

  Future<void> removeWorkbenchTab(String tabId);

  Future<void> removeWorkbenchTabsForWorkspace(String workspaceId);

  Future<WorkbenchLayout?> findWorkbenchLayout(String workspaceId);

  Future<WorkbenchLayout> upsertWorkbenchLayout(WorkbenchLayout layout);

  Future<void> removeWorkbenchLayout(String workspaceId);

  Future<List<TerminalTabRecord>> listTerminalTabs(String workspaceId);

  Stream<List<TerminalTabRecord>> watchTerminalTabs(String workspaceId);

  Future<TerminalTabRecord?> findTerminalTabById(String tabId);

  Future<TerminalTabRecord> upsertTerminalTab(TerminalTabRecord tab);

  Future<void> removeTerminalTab(String tabId);

  Future<void> removeTerminalTabsForWorkspace(String workspaceId);
}
