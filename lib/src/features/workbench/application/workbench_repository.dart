import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';

abstract interface class WorkbenchRepository {
  Future<List<Workspace>> listWorkspaces(String projectId);

  Stream<List<Workspace>> watchWorkspaces(String projectId);

  Future<Workspace?> findWorkspaceById(String workspaceId);

  Future<Workspace> upsertWorkspace(Workspace workspace);

  Future<void> removeWorkspace(String workspaceId, {bool cascadeTabs = true});

  Future<void> removeWorkspacesForProject(String projectId);

  Future<List<WorkspaceTabRecord>> listWorkspaceTabs(String workspaceId);

  Stream<List<WorkspaceTabRecord>> watchWorkspaceTabs(String workspaceId);

  Future<WorkspaceTabRecord?> findWorkspaceTabById(String tabId);

  Future<WorkspaceTabRecord> upsertWorkspaceTab(WorkspaceTabRecord tab);

  Future<void> removeWorkspaceTab(String tabId);

  Future<void> removeWorkspaceTabsForWorkspace(String workspaceId);

  Future<WorkbenchLayout?> findWorkbenchLayout(String workspaceId);

  Future<WorkbenchLayout> upsertWorkbenchLayout(WorkbenchLayout layout);

  Future<void> removeWorkbenchLayout(String workspaceId);
}
