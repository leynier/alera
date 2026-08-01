import 'dart:typed_data';

import 'package:alera_mobile/src/features/runtime/domain/agent_profile_summary.dart';
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
const String mobileTabRenameCapability = 'mobileTabRenameV1';

/// The runtime can send terminal output as a binary WebSocket message instead
/// of base64 inside JSON. Feature-detected, never version-gated: the runtime
/// requires an exact `aleraMobileProtocolVersion` match, so bumping it would
/// lock out every device that has not updated at the same moment.
const String mobileBinaryFramesCapability = 'binaryFrames';

/// The runtime accepts `bracketedPaste` and `deferredEnter` on `write`, so a
/// composed prompt and its Enter reach the PTY as two separate writes. Agent
/// TUIs run paste heuristics over input bursts and read a CR inside the burst
/// as a literal newline instead of a submit. Unprefixed because the host
/// capability is not mobile-scoped, same as [mobileBinaryFramesCapability].
const String terminalDeferredInputCapability = 'terminalDeferredInputV1';
const String terminalRestartCapability = 'terminalRestartV1';
const String runtimeHostRestartCapability = 'runtimeHostRestartV1';
const String mobileTerminalTitlesCapability = 'mobileTerminalTitlesV1';
const String mobilePortableSettingsCapability = 'mobilePortableSettingsV1';
const String mobileAgentQuotaCapability = 'mobileAgentQuotaV1';
const String mobileAgentQuotaClaudeTuiCapability = 'agentQuotaClaudeTuiV1';
const String codexResetCreditsCapability = 'codexResetCreditsV1';
const String mobileHostToolsCapability = 'mobileHostToolsV1';
const String aiTextWorkspaceIdentityCapability = 'aiTextWorkspaceIdentityV1';
const String agentProfilePromptLaunchCapability = 'agentProfilePromptLaunchV1';

class MobileRuntimeEvent {
  const MobileRuntimeEvent(this.name, this.payload);

  final String name;
  final Map<String, Object?> payload;
}

class MobileTerminalOutputEvent {
  const MobileTerminalOutputEvent(
    this.sessionId,
    this.data, {
    this.replacesScrollback = false,
  });

  final String sessionId;
  final Uint8List data;

  /// A `delta: false` resume answer: the host could no longer place this client
  /// in the output stream, so these bytes replace the emulator contents instead
  /// of being appended to them.
  final bool replacesScrollback;
}

const int defaultTerminalCols = 80;
const int defaultTerminalRows = 24;

abstract interface class MobileTerminalClient {
  Stream<MobileRuntimeEvent> get events;
  Stream<MobileTerminalOutputEvent> get terminalOutput;
  bool get supportsTerminalTitles;
  bool get supportsTerminalRestart;

  /// Whether [writeTerminal] may use `bracketedPaste` and `deferredEnter`.
  bool get supportsDeferredTerminalInput;
  Future<List<WorkspaceTabSummary>> listTabs(String workspaceId);
  Future<MobileTerminalSession> createTerminal(
    String workspaceId, {
    String? title,
    int cols,
    int rows,
    bool autoCloseOnSuccess = false,
  });
  Future<MobileTerminalSession> attachTerminal(
    String tabId, {
    int cols,
    int rows,
  });
  Future<MobileTerminalSession> restartTerminal(
    String tabId, {
    String? sessionId,
    int cols,
    int rows,
  });

  /// Raw keystrokes pass both flags as false. A composed prompt sets
  /// [deferredEnter] so the host writes the submit CR separately, and
  /// [bracketedPaste] when the text carries newlines or other control
  /// characters that a line editor would otherwise treat as accept-line.
  Future<void> writeTerminal(
    String sessionId,
    List<int> bytes, {
    bool bracketedPaste = false,
    bool deferredEnter = false,
  });
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
  bool get supportsTabRename;
  bool get supportsPromptWorkspaceCreation;
  Future<WorkspaceSidebarSnapshot> workspaceSidebarSnapshot();
  Future<MobileViewPrefs> loadWorkbenchViewPrefs();
  Future<MobileViewPrefs> updateWorkbenchViewPrefs(MobileViewPrefs prefs);
  Future<List<AgentPresenceSummary>> listAgentPresence();
  Future<List<ProjectSummary>> listProjects();
  Future<ProjectBranches> listBranches(String projectId);
  Future<List<AgentProfileSummary>> listAgentProfiles();
  Future<GeneratedWorkspaceIdentity> generateWorkspaceIdentity({
    required String operationId,
    required String projectId,
    required String prompt,
  });
  Future<void> cancelWorkspaceIdentity(String operationId);
  Future<AgentProfileLaunchResult> launchAgentProfile({
    required String workspaceId,
    required String profileId,
    required String prompt,
  });
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
  Future<WorkspaceTabSummary> renameTab(String tabId, String title);
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
