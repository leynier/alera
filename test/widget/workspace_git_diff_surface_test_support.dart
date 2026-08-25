part of 'workspace_git_diff_surface_test.dart';

Future<void> _pumpDiffSurface(
  WidgetTester tester, {
  required FakeGitBackend backend,
  WorkbenchController? controller,
  WorkspaceTabRecord? tab,
  ReadingDiffService? readingDiffService,
  SettingsController? settingsController,
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        gitBackendProvider.overrideWithValue(backend),
        if (settingsController == null)
          settingsControllerProvider.overrideWithValue(AleraSettings.defaults)
        else
          settingsControllerProvider.overrideWith(() => settingsController),
        if (readingDiffService != null)
          readingDiffServiceProvider.overrideWithValue(readingDiffService),
        if (controller != null)
          workbenchControllerProvider.overrideWith(() => controller),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 600,
            child: WorkspaceGitDiffSurface(
              workspace: _workspace(),
              tab: tab ?? _diffTab(),
            ),
          ),
        ),
      ),
    ),
  );
}

class _MutableSettingsController extends SettingsController {
  _MutableSettingsController(this._settings);

  final AleraSettings _settings;

  @override
  AleraSettings build() => _settings;

  void setAiTextEnabled(bool enabled) {
    state = state.copyWith(
      aiTextGeneration: state.aiTextGeneration.copyWith(enabled: enabled),
    );
  }
}

IconButton _openFileButton(WidgetTester tester) {
  final finder = find.ancestor(
    of: find.byIcon(AleraIcons.external),
    matching: find.byType(IconButton),
  );
  return tester.widget<IconButton>(finder);
}

Workspace _workspace() {
  final now = DateTime.utc(2026, 6, 6);
  return Workspace(
    id: 'workspace-1',
    projectId: 'project-1',
    name: 'Main',
    path: '/tmp/project',
    createdAt: now,
    updatedAt: now,
    kind: WorkspaceKind.main,
    status: WorkspaceStatus.active,
  );
}

WorkspaceTabRecord _diffTab({
  WorkspaceGitDiffSource source = WorkspaceGitDiffSource.workingTree,
  WorkspaceGitDiffScope scope = WorkspaceGitDiffScope.file,
  String? filePath = 'lib/large.dart',
  String title = 'large.dart unstaged',
  GitChangeArea? area = GitChangeArea.unstaged,
  String? gitDiffRoot,
  String? oldPath,
  String? commitOid,
  String? parentOid,
  String? compareRef,
}) {
  final now = DateTime.utc(2026, 6, 6);
  final payload = <String, Object?>{
    workspaceTabGitDiffSourcePayloadKey: source.key,
    workspaceTabGitDiffScopePayloadKey: scope.key,
    workspaceTabFilePathPayloadKey: ?filePath,
  };
  if (area != null) {
    payload[workspaceTabGitDiffAreaPayloadKey] = area.key;
  }
  if (oldPath != null) {
    payload[workspaceTabGitDiffOldPathPayloadKey] = oldPath;
  }
  if (commitOid != null) {
    payload[workspaceTabGitDiffCommitOidPayloadKey] = commitOid;
  }
  if (parentOid != null) {
    payload[workspaceTabGitDiffParentOidPayloadKey] = parentOid;
  }
  if (compareRef != null) {
    payload[workspaceTabGitDiffCompareRefPayloadKey] = compareRef;
  }
  if (gitDiffRoot != null) {
    payload[workspaceTabGitDiffRootPayloadKey] = gitDiffRoot;
  }
  return WorkspaceTabRecord(
    id: 'tab-1',
    workspaceId: 'workspace-1',
    kind: WorkspaceTabKind.gitDiff,
    title: title,
    createdAt: now,
    updatedAt: now,
    payload: payload,
  );
}

class _GitDiffSurfaceTestController extends WorkbenchController {
  final List<String> openedRelativePaths = <String>[];

  @override
  WorkbenchState build() => const WorkbenchState();

  @override
  Future<WorkspaceTabRecord> openEditorTab({
    required Workspace workspace,
    required String relativePath,
    String? targetGroupId,
    bool preview = false,
  }) async {
    openedRelativePaths.add(relativePath);
    final now = DateTime.utc(2026, 6, 6);
    return WorkspaceTabRecord(
      id: 'editor-${openedRelativePaths.length}',
      workspaceId: workspace.id,
      kind: WorkspaceTabKind.editor,
      title: relativePath.split('/').last,
      createdAt: now,
      updatedAt: now,
      payload: <String, Object?>{workspaceTabFilePathPayloadKey: relativePath},
    );
  }
}
