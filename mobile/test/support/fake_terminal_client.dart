import 'dart:async';
import 'dart:typed_data';

import 'package:alera_mobile/src/features/runtime/domain/project_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_creation_result.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_sidebar_snapshot.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';
import 'package:alera_mobile/src/features/workbench/domain/mobile_view_prefs.dart';

WorkspaceTabSummary fakeTab({
  required String id,
  required String title,
  String kind = 'terminal',
  String workspaceId = 'workspace-1',
}) {
  return WorkspaceTabSummary(
    id: id,
    workspaceId: workspaceId,
    kind: kind,
    title: title,
    payload: <String, Object?>{'terminalSessionId': 'session-$id'},
  );
}

/// In-memory stand-in for the runtime gateway covering both the terminal and
/// workspace client surfaces. Records calls as readable strings.
class FakeTerminalClient
    implements MobileTerminalClient, MobileWorkspaceClient {
  final StreamController<MobileRuntimeEvent> _events =
      StreamController<MobileRuntimeEvent>.broadcast();
  final StreamController<MobileTerminalOutputEvent> _output =
      StreamController<MobileTerminalOutputEvent>.broadcast();
  final List<String> calls = <String>[];
  List<WorkspaceTabSummary> tabs = <WorkspaceTabSummary>[];
  int _createdTabs = 0;

  void emitEvent(String name) {
    _events.add(MobileRuntimeEvent(name, const <String, Object?>{}));
  }

  void emitDriverChanged(String sessionId, String driverKind) {
    _events.add(
      MobileRuntimeEvent('terminalDriverChanged', <String, Object?>{
        'sessionId': sessionId,
        'driver': <String, Object?>{'kind': driverKind},
        'cols': 80,
        'rows': 24,
      }),
    );
  }

  void emitOutput(String sessionId, Uint8List data) {
    _output.add(MobileTerminalOutputEvent(sessionId, data));
  }

  Future<void> dispose() async {
    await _events.close();
    await _output.close();
  }

  @override
  Stream<MobileRuntimeEvent> get events => _events.stream;

  @override
  Stream<MobileTerminalOutputEvent> get terminalOutput => _output.stream;

  @override
  bool get supportsWorkspaceMutations => true;

  @override
  bool get supportsWorkspaceSidebarParity => true;

  @override
  bool get supportsTabRename => true;

  @override
  Future<WorkspaceSidebarSnapshot> workspaceSidebarSnapshot() async {
    return const WorkspaceSidebarSnapshot(
      projects: <ProjectSummary>[],
      workspaces: <WorkspaceSummary>[],
      tags: <WorkspaceTagSummary>[],
      activity: <String, DateTime>{},
      viewPrefs: MobileViewPrefs(),
      confirmWorkspaceRemoval: true,
    );
  }

  @override
  Future<MobileViewPrefs> loadWorkbenchViewPrefs() async =>
      const MobileViewPrefs();

  @override
  Future<MobileViewPrefs> updateWorkbenchViewPrefs(
    MobileViewPrefs prefs,
  ) async => prefs.copyWith(revision: prefs.revision + 1);

  @override
  Future<List<AgentPresenceSummary>> listAgentPresence() async =>
      const <AgentPresenceSummary>[];

  @override
  Future<List<WorkspaceTabSummary>> listTabs(String workspaceId) async {
    calls.add('listTabs $workspaceId');
    return tabs;
  }

  @override
  Future<MobileTerminalSession> createTerminal(
    String workspaceId, {
    String? title,
    int cols = defaultTerminalCols,
    int rows = defaultTerminalRows,
  }) async {
    calls.add('create $workspaceId $title');
    _createdTabs += 1;
    final tab = fakeTab(
      id: 'created-$_createdTabs',
      title: title ?? 'Terminal',
      workspaceId: workspaceId,
    );
    tabs = <WorkspaceTabSummary>[...tabs, tab];
    return MobileTerminalSession(
      tab: tab,
      attachment: MobileTerminalAttachment(
        sessionId: tab.terminalSessionId,
        created: true,
        running: true,
        snapshot: const <int>[],
      ),
    );
  }

  @override
  Future<MobileTerminalSession> attachTerminal(
    String tabId, {
    int cols = defaultTerminalCols,
    int rows = defaultTerminalRows,
  }) async {
    calls.add('attach $tabId');
    final tab = tabs.firstWhere((tab) => tab.id == tabId);
    return MobileTerminalSession(
      tab: tab,
      attachment: MobileTerminalAttachment(
        sessionId: tab.terminalSessionId,
        created: false,
        running: true,
        snapshot: const <int>[],
      ),
    );
  }

  @override
  Future<void> writeTerminal(String sessionId, List<int> bytes) async {
    calls.add('write $sessionId ${bytes.length}');
  }

  @override
  Future<void> resizeTerminal(String sessionId, int cols, int rows) async {
    calls.add('resize $sessionId $cols $rows');
  }

  @override
  Future<void> detachTerminal(String sessionId) async {
    calls.add('detach $sessionId');
  }

  @override
  Future<void> terminateSession(String sessionId) async {
    calls.add('terminate $sessionId');
  }

  @override
  Future<List<ProjectSummary>> listProjects() async {
    return const <ProjectSummary>[];
  }

  @override
  Future<ProjectBranches> listBranches(String projectId) async {
    return ProjectBranches(
      projectId: projectId,
      branches: const <String>[],
      localBranches: const <String>[],
    );
  }

  @override
  Future<List<WorkspaceSummary>> listWorkspaces() async {
    return const <WorkspaceSummary>[];
  }

  @override
  Future<void> setWorkspacePinned(String workspaceId, bool isPinned) async {
    calls.add('setPinned $workspaceId $isPinned');
  }

  @override
  Future<void> linkWorkspaces({
    required String parentWorkspaceId,
    required String childWorkspaceId,
  }) async {
    calls.add('link $parentWorkspaceId $childWorkspaceId');
  }

  @override
  Future<void> unlinkWorkspaces({
    required String parentWorkspaceId,
    required String childWorkspaceId,
  }) async {
    calls.add('unlink $parentWorkspaceId $childWorkspaceId');
  }

  @override
  Future<WorkspaceCreationResult> createManagedWorkspace({
    required String projectId,
    required String branch,
    String? sourceBranch,
    bool reuseExistingBranch = false,
    String? name,
    String? parentWorkspaceId,
  }) async {
    calls.add('createWorkspace $projectId $branch');
    return WorkspaceCreationResult(
      workspace: WorkspaceSummary(
        id: 'created',
        projectId: projectId,
        name: name ?? branch,
        path: '/tmp/created',
      ),
      steps: const <WorkspaceSetupStep>[],
    );
  }

  @override
  Future<void> removeManagedWorkspace(
    String workspaceId, {
    bool? deleteBranch,
  }) async {
    calls.add('removeWorkspace $workspaceId $deleteBranch');
  }

  @override
  Future<List<String>> cascadePreview(String workspaceId) async {
    return <String>[workspaceId];
  }

  @override
  Future<void> removeTab(String tabId) async {
    calls.add('removeTab $tabId');
    tabs = <WorkspaceTabSummary>[
      for (final tab in tabs)
        if (tab.id != tabId) tab,
    ];
  }

  @override
  Future<WorkspaceTabSummary> renameTab(String tabId, String title) async {
    calls.add('renameTab $tabId $title');
    final current = tabs.firstWhere((tab) => tab.id == tabId);
    final renamed = WorkspaceTabSummary(
      id: current.id,
      workspaceId: current.workspaceId,
      kind: current.kind,
      title: title,
      payload: current.payload,
    );
    tabs = <WorkspaceTabSummary>[
      for (final tab in tabs)
        if (tab.id == tabId) renamed else tab,
    ];
    return renamed;
  }

  @override
  Future<WorkspaceSummary> renameWorkspace(String id, String name) async =>
      WorkspaceSummary(id: id, projectId: 'p1', name: name, path: '/tmp/$id');

  @override
  Future<void> sleepWorkspace(String workspaceId) async {}

  @override
  Future<String?> workspaceRepositoryRemoteUrl(String workspaceId) async =>
      null;

  @override
  Future<WorkspaceTagSummary> createWorkspaceTag(
    String name, {
    String? color,
  }) async => WorkspaceTagSummary(id: name, name: name, color: color);

  @override
  Future<void> removeWorkspaceTag(String tagId) async {}

  @override
  Future<WorkspaceSummary> setWorkspaceTags(
    String workspaceId,
    List<String> tagIds,
  ) async => WorkspaceSummary(
    id: workspaceId,
    projectId: 'p1',
    name: workspaceId,
    path: '/tmp/$workspaceId',
    tagIds: tagIds,
  );
}
