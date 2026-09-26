part of 'workspace_list_controller_test.dart';

class _FakeWorkspaceClient()
    implements MobileWorkspaceClient, MobileWorkspaceSectionClient {
  this {
    _events = StreamController<MobileRuntimeEvent>.broadcast(
      onListen: () => eventSubscriptionCount += 1,
      onCancel: () => eventSubscriptionCount -= 1,
    );
  }

  late final StreamController<MobileRuntimeEvent> _events;
  final List<String> calls = <String>[];
  final List<void Function(MobileRuntimeEvent)> _eventListeners =
      <void Function(MobileRuntimeEvent)>[];
  Object? linkError;
  Completer<void>? pinCompletion;
  int eventSubscriptionCount = 0;
  List<WorkspaceSummary> workspaces = <WorkspaceSummary>[_workspace('a')];
  Map<String, List<String>> workspaceMainTabIds =
      const <String, List<String>>{};
  Map<String, int> terminalTabCountByWorkspaceId = const <String, int>{};
  List<String> cascadeIds = <String>['a'];

  void emit(String name) {
    _events.add(MobileRuntimeEvent(name, const <String, Object?>{}));
  }

  void emitAfterDispose(String name) {
    final event = MobileRuntimeEvent(name, const <String, Object?>{});
    for (final listener in List<void Function(MobileRuntimeEvent)>.of(
      _eventListeners,
    )) {
      listener(event);
    }
  }

  Future<void> dispose() => _events.close();

  @override
  Stream<MobileRuntimeEvent> get events =>
      _CapturingEventStream(_events.stream, _eventListeners.add);

  @override
  bool get supportsWorkspaceMutations => true;

  @override
  bool get supportsWorkspaceArchive => true;

  @override
  bool get supportsWorkspaceSidebarParity => true;

  @override
  bool get supportsTabRename => true;

  @override
  bool get supportsPromptWorkspaceCreation => true;

  @override
  bool get supportsIdempotentAgentProfileLaunch => true;

  @override
  bool get supportsPromptImageUpload => true;

  @override
  Future<WorkspaceSidebarSnapshot> workspaceSidebarSnapshot() async {
    return WorkspaceSidebarSnapshot(
      projects: await listProjects(),
      workspaces: workspaces,
      tags: const <WorkspaceTagSummary>[],
      activity: const <String, DateTime>{},
      viewPrefs: const MobileViewPrefs(),
      confirmWorkspaceRemoval: true,
      workspaceMainTabIds: workspaceMainTabIds,
      terminalTabCountByWorkspaceId: terminalTabCountByWorkspaceId,
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
  Future<List<ProjectSummary>> listProjects() async {
    return <ProjectSummary>[
      const ProjectSummary(id: 'p1', name: 'Project', repoPath: '/repo'),
    ];
  }

  @override
  Future<ProjectBranches> listBranches(
    String projectId, {
    String? checkoutHostId,
  }) async {
    return ProjectBranches(
      projectId: projectId,
      branches: const <String>['main'],
      localBranches: const <String>['main'],
    );
  }

  @override
  Future<List<AgentProfileSummary>> listAgentProfiles() async {
    return const <AgentProfileSummary>[
      AgentProfileSummary(id: 'profile-1', name: 'Codex', agentType: 'codex'),
    ];
  }

  @override
  Future<GeneratedWorkspaceIdentity> generateWorkspaceIdentity({
    required String operationId,
    required String projectId,
    required String prompt,
    bool autoAssignSection = false,
  }) async {
    return const GeneratedWorkspaceIdentity(
      workspaceName: 'Generated Workspace',
      branchName: 'feat/generated-workspace',
    );
  }

  @override
  Future<void> cancelWorkspaceIdentity(String operationId) async {}

  @override
  Future<PromptImageUploadResult> uploadPromptImage({
    required String format,
    required int sizeBytes,
    required Stream<List<int>> Function() openRead,
  }) async {
    return PromptImageUploadResult(
      hostPath: '/runtime/prompt-images/test.$format',
    );
  }

  @override
  Future<AgentProfileLaunchResult> launchAgentProfile({
    required String workspaceId,
    required String profileId,
    String prompt = '',
    required String clientMutationId,
  }) async {
    return const AgentProfileLaunchResult(
      tabId: 'agent-tab',
      agentType: 'codex',
    );
  }

  @override
  Future<List<WorkspaceSummary>> listWorkspaces() async {
    return workspaces;
  }

  @override
  Future<void> setWorkspacePinned(String workspaceId, bool isPinned) async {
    calls.add('setPinned $workspaceId $isPinned');
    await pinCompletion?.future;
  }

  @override
  Future<void> linkWorkspaces({
    required String parentWorkspaceId,
    required String childWorkspaceId,
  }) async {
    calls.add('link $parentWorkspaceId $childWorkspaceId');
    final error = linkError;
    if (error != null) {
      throw error;
    }
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
    String? checkoutHostId,
    required String branch,
    String? sourceBranch,
    bool reuseExistingBranch = false,
    String? name,
    String? parentWorkspaceId,
    String? issueUrl,
  }) async {
    calls.add('create $projectId $branch $sourceBranch $parentWorkspaceId');
    return WorkspaceCreationResult(
      workspace: _workspace('created'),
      steps: const <WorkspaceSetupStep>[],
    );
  }

  @override
  Future<void> removeManagedWorkspace(
    String workspaceId, {
    bool? deleteBranch,
  }) async {
    calls.add('remove $workspaceId $deleteBranch');
  }

  @override
  Future<List<String>> cascadePreview(String workspaceId) async {
    return cascadeIds;
  }

  @override
  Future<void> removeTab(String tabId) async {
    calls.add('removeTab $tabId');
  }

  @override
  Future<WorkspaceTabSummary> renameTab(String tabId, String title) async {
    calls.add('renameTab $tabId $title');
    return WorkspaceTabSummary(
      id: tabId,
      workspaceId: 'a',
      kind: 'terminal',
      title: title,
      payload: const <String, Object?>{},
    );
  }

  @override
  Future<WorkspaceSummary> renameWorkspace(String id, String name) async {
    calls.add('rename $id $name');
    return WorkspaceSummary(
      id: id,
      projectId: 'p1',
      name: name,
      path: '/tmp/$id',
    );
  }

  @override
  Future<void> sleepWorkspace(String workspaceId) async {
    calls.add('sleep $workspaceId');
  }

  @override
  Future<void> archiveWorkspace(String workspaceId) async {
    calls.add('archive $workspaceId');
  }

  @override
  Future<void> unarchiveWorkspace(String workspaceId) async {
    calls.add('unarchive $workspaceId');
  }

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
  ) async => _workspace(workspaceId);

  @override
  bool get supportsWorkspaceSections => true;

  @override
  Future<List<WorkspaceSectionSummary>> listWorkspaceSections() async =>
      const <WorkspaceSectionSummary>[];

  @override
  Future<WorkspaceSectionSummary> createWorkspaceSection(
    String name,
    String workspaceId,
  ) async {
    calls.add('createSection $name $workspaceId');
    return WorkspaceSectionSummary(
      id: 'created',
      name: name,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
  }

  @override
  Future<void> setWorkspaceSection(
    String workspaceId,
    String? sectionId,
  ) async {
    calls.add('setSection $workspaceId $sectionId');
  }

  @override
  Future<void> removeWorkspaceSection(String sectionId) async {
    calls.add('removeSection $sectionId');
  }
}

final class _CapturingEventStream(
  final Stream<MobileRuntimeEvent> _source,
  final void Function(void Function(MobileRuntimeEvent)) _capture,
) extends Stream<MobileRuntimeEvent> {
  @override
  bool get isBroadcast => _source.isBroadcast;

  @override
  StreamSubscription<MobileRuntimeEvent> listen(
    void Function(MobileRuntimeEvent)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    if (onData != null) {
      _capture(onData);
    }
    return _source.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}
