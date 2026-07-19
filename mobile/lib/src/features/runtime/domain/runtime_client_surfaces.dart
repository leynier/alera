import 'dart:typed_data';

import 'package:alera_mobile/src/features/runtime/domain/project_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_creation_result.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_sidebar_snapshot.dart';
import 'package:alera_mobile/src/features/workbench/domain/mobile_view_prefs.dart';

/// Capability advertised by runtimes whose mobile gateway accepts workspace
/// mutations (pin, link/unlink, create/remove managed, tab removal).
const String mobileWorkspaceMutationsCapability = 'mobileWorkspaceMutations';
const String mobileWorkspaceSidebarParityCapability =
    'mobileWorkspaceSidebarParityV1';
const String mobileProjectManagementCapability = 'mobileProjectManagementV1';

class MobileRuntimeEvent {
  const MobileRuntimeEvent(this.name, this.payload);

  final String name;
  final Map<String, Object?> payload;
}

class MobileTerminalOutputEvent {
  const MobileTerminalOutputEvent(this.sessionId, this.data);

  final String sessionId;
  final Uint8List data;
}

const int defaultTerminalCols = 80;
const int defaultTerminalRows = 24;

abstract interface class MobileTerminalClient {
  Stream<MobileRuntimeEvent> get events;
  Stream<MobileTerminalOutputEvent> get terminalOutput;
  Future<List<WorkspaceTabSummary>> listTabs(String workspaceId);
  Future<MobileTerminalSession> createTerminal(
    String workspaceId, {
    String? title,
    int cols,
    int rows,
  });
  Future<MobileTerminalSession> attachTerminal(
    String tabId, {
    int cols,
    int rows,
  });
  Future<void> writeTerminal(String sessionId, List<int> bytes);
  Future<void> resizeTerminal(String sessionId, int cols, int rows);
  Future<void> detachTerminal(String sessionId);
  Future<void> terminateSession(String sessionId);
}

/// Workspace listing and mutation surface consumed by the workbench
/// controllers; kept as an interface so tests can fake the runtime.
abstract interface class MobileWorkspaceClient {
  Stream<MobileRuntimeEvent> get events;
  bool get supportsWorkspaceMutations;
  bool get supportsWorkspaceSidebarParity;
  Future<WorkspaceSidebarSnapshot> workspaceSidebarSnapshot();
  Future<MobileViewPrefs> loadWorkbenchViewPrefs();
  Future<MobileViewPrefs> updateWorkbenchViewPrefs(MobileViewPrefs prefs);
  Future<List<AgentPresenceSummary>> listAgentPresence();
  Future<List<ProjectSummary>> listProjects();
  Future<ProjectBranches> listBranches(String projectId);
  Future<List<WorkspaceSummary>> listWorkspaces();
  Future<void> setWorkspacePinned(String workspaceId, bool isPinned);
  Future<void> linkWorkspaces({
    required String parentWorkspaceId,
    required String childWorkspaceId,
  });
  Future<void> unlinkWorkspaces({
    required String parentWorkspaceId,
    required String childWorkspaceId,
  });
  Future<WorkspaceCreationResult> createManagedWorkspace({
    required String projectId,
    required String branch,
    String? sourceBranch,
    bool reuseExistingBranch = false,
    String? name,
    String? parentWorkspaceId,
  });
  Future<void> removeManagedWorkspace(String workspaceId, {bool? deleteBranch});
  Future<List<String>> cascadePreview(String workspaceId);
  Future<void> removeTab(String tabId);
  Future<WorkspaceSummary> renameWorkspace(String workspaceId, String name);
  Future<void> sleepWorkspace(String workspaceId);
  Future<String?> workspaceRepositoryRemoteUrl(String workspaceId);
  Future<WorkspaceTagSummary> createWorkspaceTag(String name, {String? color});
  Future<void> removeWorkspaceTag(String tagId);
  Future<WorkspaceSummary> setWorkspaceTags(
    String workspaceId,
    List<String> tagIds,
  );
}
