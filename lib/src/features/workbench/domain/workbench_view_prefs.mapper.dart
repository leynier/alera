// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'workbench_view_prefs.dart';

class WorkbenchGroupByMapper extends EnumMapper<WorkbenchGroupBy> {
  WorkbenchGroupByMapper._();

  static WorkbenchGroupByMapper? _instance;
  static WorkbenchGroupByMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = WorkbenchGroupByMapper._());
    }
    return _instance!;
  }

  static WorkbenchGroupBy fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  WorkbenchGroupBy decode(dynamic value) {
    switch (value) {
      case r'none':
        return WorkbenchGroupBy.none;
      case r'project':
        return WorkbenchGroupBy.project;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(WorkbenchGroupBy self) {
    switch (self) {
      case WorkbenchGroupBy.none:
        return r'none';
      case WorkbenchGroupBy.project:
        return r'project';
    }
  }
}

extension WorkbenchGroupByMapperExtension on WorkbenchGroupBy {
  String toValue() {
    WorkbenchGroupByMapper.ensureInitialized();
    return MapperContainer.globals.toValue<WorkbenchGroupBy>(this) as String;
  }
}

class WorkbenchSortByMapper extends EnumMapper<WorkbenchSortBy> {
  WorkbenchSortByMapper._();

  static WorkbenchSortByMapper? _instance;
  static WorkbenchSortByMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = WorkbenchSortByMapper._());
    }
    return _instance!;
  }

  static WorkbenchSortBy fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  WorkbenchSortBy decode(dynamic value) {
    switch (value) {
      case r'name':
        return WorkbenchSortBy.name;
      case r'recent':
        return WorkbenchSortBy.recent;
      case r'activity':
        return WorkbenchSortBy.activity;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(WorkbenchSortBy self) {
    switch (self) {
      case WorkbenchSortBy.name:
        return r'name';
      case WorkbenchSortBy.recent:
        return r'recent';
      case WorkbenchSortBy.activity:
        return r'activity';
    }
  }
}

extension WorkbenchSortByMapperExtension on WorkbenchSortBy {
  String toValue() {
    WorkbenchSortByMapper.ensureInitialized();
    return MapperContainer.globals.toValue<WorkbenchSortBy>(this) as String;
  }
}

class WorkbenchContextPanelTabMapper
    extends EnumMapper<WorkbenchContextPanelTab> {
  WorkbenchContextPanelTabMapper._();

  static WorkbenchContextPanelTabMapper? _instance;
  static WorkbenchContextPanelTabMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = WorkbenchContextPanelTabMapper._(),
      );
    }
    return _instance!;
  }

  static WorkbenchContextPanelTab fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  WorkbenchContextPanelTab decode(dynamic value) {
    switch (value) {
      case r'explorer':
        return WorkbenchContextPanelTab.explorer;
      case r'search':
        return WorkbenchContextPanelTab.search;
      case r'gitDiff':
        return WorkbenchContextPanelTab.gitDiff;
      case r'pullRequests':
        return WorkbenchContextPanelTab.pullRequests;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(WorkbenchContextPanelTab self) {
    switch (self) {
      case WorkbenchContextPanelTab.explorer:
        return r'explorer';
      case WorkbenchContextPanelTab.search:
        return r'search';
      case WorkbenchContextPanelTab.gitDiff:
        return r'gitDiff';
      case WorkbenchContextPanelTab.pullRequests:
        return r'pullRequests';
    }
  }
}

extension WorkbenchContextPanelTabMapperExtension on WorkbenchContextPanelTab {
  String toValue() {
    WorkbenchContextPanelTabMapper.ensureInitialized();
    return MapperContainer.globals.toValue<WorkbenchContextPanelTab>(this)
        as String;
  }
}

class WorkspaceExplorerModeMapper extends EnumMapper<WorkspaceExplorerMode> {
  WorkspaceExplorerModeMapper._();

  static WorkspaceExplorerModeMapper? _instance;
  static WorkspaceExplorerModeMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = WorkspaceExplorerModeMapper._());
    }
    return _instance!;
  }

  static WorkspaceExplorerMode fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  WorkspaceExplorerMode decode(dynamic value) {
    switch (value) {
      case r'hideIgnored':
        return WorkspaceExplorerMode.hideIgnored;
      case r'showAll':
        return WorkspaceExplorerMode.showAll;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(WorkspaceExplorerMode self) {
    switch (self) {
      case WorkspaceExplorerMode.hideIgnored:
        return r'hideIgnored';
      case WorkspaceExplorerMode.showAll:
        return r'showAll';
    }
  }
}

extension WorkspaceExplorerModeMapperExtension on WorkspaceExplorerMode {
  String toValue() {
    WorkspaceExplorerModeMapper.ensureInitialized();
    return MapperContainer.globals.toValue<WorkspaceExplorerMode>(this)
        as String;
  }
}

class GitDiffViewModeMapper extends EnumMapper<GitDiffViewMode> {
  GitDiffViewModeMapper._();

  static GitDiffViewModeMapper? _instance;
  static GitDiffViewModeMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = GitDiffViewModeMapper._());
    }
    return _instance!;
  }

  static GitDiffViewMode fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  GitDiffViewMode decode(dynamic value) {
    switch (value) {
      case r'tree':
        return GitDiffViewMode.tree;
      case r'flat':
        return GitDiffViewMode.flat;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(GitDiffViewMode self) {
    switch (self) {
      case GitDiffViewMode.tree:
        return r'tree';
      case GitDiffViewMode.flat:
        return r'flat';
    }
  }
}

extension GitDiffViewModeMapperExtension on GitDiffViewMode {
  String toValue() {
    GitDiffViewModeMapper.ensureInitialized();
    return MapperContainer.globals.toValue<GitDiffViewMode>(this) as String;
  }
}

class PullRequestCreateActionMapper
    extends EnumMapper<PullRequestCreateAction> {
  PullRequestCreateActionMapper._();

  static PullRequestCreateActionMapper? _instance;
  static PullRequestCreateActionMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = PullRequestCreateActionMapper._(),
      );
    }
    return _instance!;
  }

  static PullRequestCreateAction fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  PullRequestCreateAction decode(dynamic value) {
    switch (value) {
      case r'publish':
        return PullRequestCreateAction.publish;
      case r'draft':
        return PullRequestCreateAction.draft;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(PullRequestCreateAction self) {
    switch (self) {
      case PullRequestCreateAction.publish:
        return r'publish';
      case PullRequestCreateAction.draft:
        return r'draft';
    }
  }
}

extension PullRequestCreateActionMapperExtension on PullRequestCreateAction {
  String toValue() {
    PullRequestCreateActionMapper.ensureInitialized();
    return MapperContainer.globals.toValue<PullRequestCreateAction>(this)
        as String;
  }
}

class WorkbenchViewPrefsMapper extends ClassMapperBase<WorkbenchViewPrefs> {
  WorkbenchViewPrefsMapper._();

  static WorkbenchViewPrefsMapper? _instance;
  static WorkbenchViewPrefsMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = WorkbenchViewPrefsMapper._());
      WorkbenchGroupByMapper.ensureInitialized();
      WorkbenchSortByMapper.ensureInitialized();
      WorkbenchContextPanelTabMapper.ensureInitialized();
      WorkspaceExplorerModeMapper.ensureInitialized();
      GitDiffViewModeMapper.ensureInitialized();
      PullRequestCreateActionMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'WorkbenchViewPrefs';

  static WorkbenchGroupBy _$groupBy(WorkbenchViewPrefs v) => v.groupBy;
  static const Field<WorkbenchViewPrefs, WorkbenchGroupBy> _f$groupBy = Field(
    'groupBy',
    _$groupBy,
  );
  static WorkbenchSortBy _$projectSort(WorkbenchViewPrefs v) => v.projectSort;
  static const Field<WorkbenchViewPrefs, WorkbenchSortBy> _f$projectSort =
      Field('projectSort', _$projectSort);
  static WorkbenchSortBy _$workspaceSort(WorkbenchViewPrefs v) =>
      v.workspaceSort;
  static const Field<WorkbenchViewPrefs, WorkbenchSortBy> _f$workspaceSort =
      Field('workspaceSort', _$workspaceSort);
  static Set<String> _$selectedProjectIds(WorkbenchViewPrefs v) =>
      v.selectedProjectIds;
  static const Field<WorkbenchViewPrefs, Set<String>> _f$selectedProjectIds =
      Field('selectedProjectIds', _$selectedProjectIds);
  static Set<String> _$collapsedProjectIds(WorkbenchViewPrefs v) =>
      v.collapsedProjectIds;
  static const Field<WorkbenchViewPrefs, Set<String>> _f$collapsedProjectIds =
      Field('collapsedProjectIds', _$collapsedProjectIds);
  static Set<String> _$expandedWorkspaceIds(WorkbenchViewPrefs v) =>
      v.expandedWorkspaceIds;
  static const Field<WorkbenchViewPrefs, Set<String>> _f$expandedWorkspaceIds =
      Field('expandedWorkspaceIds', _$expandedWorkspaceIds);
  static Set<String> _$selectedTagIds(WorkbenchViewPrefs v) => v.selectedTagIds;
  static const Field<WorkbenchViewPrefs, Set<String>> _f$selectedTagIds = Field(
    'selectedTagIds',
    _$selectedTagIds,
    opt: true,
    def: const <String>{},
  );
  static Set<String> _$collapsedParentWorkspaceIds(WorkbenchViewPrefs v) =>
      v.collapsedParentWorkspaceIds;
  static const Field<WorkbenchViewPrefs, Set<String>>
  _f$collapsedParentWorkspaceIds = Field(
    'collapsedParentWorkspaceIds',
    _$collapsedParentWorkspaceIds,
    opt: true,
    def: const <String>{},
  );
  static bool _$pinnedSectionCollapsed(WorkbenchViewPrefs v) =>
      v.pinnedSectionCollapsed;
  static const Field<WorkbenchViewPrefs, bool> _f$pinnedSectionCollapsed =
      Field(
        'pinnedSectionCollapsed',
        _$pinnedSectionCollapsed,
        opt: true,
        def: false,
      );
  static bool _$allSectionCollapsed(WorkbenchViewPrefs v) =>
      v.allSectionCollapsed;
  static const Field<WorkbenchViewPrefs, bool> _f$allSectionCollapsed = Field(
    'allSectionCollapsed',
    _$allSectionCollapsed,
    opt: true,
    def: false,
  );
  static Map<String, String> _$sourceControlRootByWorkspaceId(
    WorkbenchViewPrefs v,
  ) => v.sourceControlRootByWorkspaceId;
  static const Field<WorkbenchViewPrefs, Map<String, String>>
  _f$sourceControlRootByWorkspaceId = Field(
    'sourceControlRootByWorkspaceId',
    _$sourceControlRootByWorkspaceId,
    opt: true,
    def: const <String, String>{},
  );
  static bool _$rightSidebarVisible(WorkbenchViewPrefs v) =>
      v.rightSidebarVisible;
  static const Field<WorkbenchViewPrefs, bool> _f$rightSidebarVisible = Field(
    'rightSidebarVisible',
    _$rightSidebarVisible,
    opt: true,
    def: true,
  );
  static double _$rightSidebarWidth(WorkbenchViewPrefs v) =>
      v.rightSidebarWidth;
  static const Field<WorkbenchViewPrefs, double> _f$rightSidebarWidth = Field(
    'rightSidebarWidth',
    _$rightSidebarWidth,
    opt: true,
    def: 280,
  );
  static double _$sidebarWidth(WorkbenchViewPrefs v) => v.sidebarWidth;
  static const Field<WorkbenchViewPrefs, double> _f$sidebarWidth = Field(
    'sidebarWidth',
    _$sidebarWidth,
    opt: true,
    def: AleraTokens.sidebarDefaultWidth,
  );
  static WorkbenchContextPanelTab _$activeContextPanelTab(
    WorkbenchViewPrefs v,
  ) => v.activeContextPanelTab;
  static const Field<WorkbenchViewPrefs, WorkbenchContextPanelTab>
  _f$activeContextPanelTab = Field(
    'activeContextPanelTab',
    _$activeContextPanelTab,
    opt: true,
    def: WorkbenchContextPanelTab.explorer,
  );
  static WorkspaceExplorerMode _$explorerMode(WorkbenchViewPrefs v) =>
      v.explorerMode;
  static const Field<WorkbenchViewPrefs, WorkspaceExplorerMode>
  _f$explorerMode = Field(
    'explorerMode',
    _$explorerMode,
    opt: true,
    def: WorkspaceExplorerMode.hideIgnored,
  );
  static GitDiffViewMode _$gitDiffViewMode(WorkbenchViewPrefs v) =>
      v.gitDiffViewMode;
  static const Field<WorkbenchViewPrefs, GitDiffViewMode> _f$gitDiffViewMode =
      Field(
        'gitDiffViewMode',
        _$gitDiffViewMode,
        opt: true,
        def: GitDiffViewMode.tree,
      );
  static PullRequestCreateAction _$pullRequestCreateAction(
    WorkbenchViewPrefs v,
  ) => v.pullRequestCreateAction;
  static const Field<WorkbenchViewPrefs, PullRequestCreateAction>
  _f$pullRequestCreateAction = Field(
    'pullRequestCreateAction',
    _$pullRequestCreateAction,
    opt: true,
    def: PullRequestCreateAction.publish,
  );

  @override
  final MappableFields<WorkbenchViewPrefs> fields = const {
    #groupBy: _f$groupBy,
    #projectSort: _f$projectSort,
    #workspaceSort: _f$workspaceSort,
    #selectedProjectIds: _f$selectedProjectIds,
    #collapsedProjectIds: _f$collapsedProjectIds,
    #expandedWorkspaceIds: _f$expandedWorkspaceIds,
    #selectedTagIds: _f$selectedTagIds,
    #collapsedParentWorkspaceIds: _f$collapsedParentWorkspaceIds,
    #pinnedSectionCollapsed: _f$pinnedSectionCollapsed,
    #allSectionCollapsed: _f$allSectionCollapsed,
    #sourceControlRootByWorkspaceId: _f$sourceControlRootByWorkspaceId,
    #rightSidebarVisible: _f$rightSidebarVisible,
    #rightSidebarWidth: _f$rightSidebarWidth,
    #sidebarWidth: _f$sidebarWidth,
    #activeContextPanelTab: _f$activeContextPanelTab,
    #explorerMode: _f$explorerMode,
    #gitDiffViewMode: _f$gitDiffViewMode,
    #pullRequestCreateAction: _f$pullRequestCreateAction,
  };

  static WorkbenchViewPrefs _instantiate(DecodingData data) {
    return WorkbenchViewPrefs(
      groupBy: data.dec(_f$groupBy),
      projectSort: data.dec(_f$projectSort),
      workspaceSort: data.dec(_f$workspaceSort),
      selectedProjectIds: data.dec(_f$selectedProjectIds),
      collapsedProjectIds: data.dec(_f$collapsedProjectIds),
      expandedWorkspaceIds: data.dec(_f$expandedWorkspaceIds),
      selectedTagIds: data.dec(_f$selectedTagIds),
      collapsedParentWorkspaceIds: data.dec(_f$collapsedParentWorkspaceIds),
      pinnedSectionCollapsed: data.dec(_f$pinnedSectionCollapsed),
      allSectionCollapsed: data.dec(_f$allSectionCollapsed),
      sourceControlRootByWorkspaceId: data.dec(
        _f$sourceControlRootByWorkspaceId,
      ),
      rightSidebarVisible: data.dec(_f$rightSidebarVisible),
      rightSidebarWidth: data.dec(_f$rightSidebarWidth),
      sidebarWidth: data.dec(_f$sidebarWidth),
      activeContextPanelTab: data.dec(_f$activeContextPanelTab),
      explorerMode: data.dec(_f$explorerMode),
      gitDiffViewMode: data.dec(_f$gitDiffViewMode),
      pullRequestCreateAction: data.dec(_f$pullRequestCreateAction),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static WorkbenchViewPrefs fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<WorkbenchViewPrefs>(map);
  }

  static WorkbenchViewPrefs fromJson(String json) {
    return ensureInitialized().decodeJson<WorkbenchViewPrefs>(json);
  }
}

mixin WorkbenchViewPrefsMappable {
  String toJson() {
    return WorkbenchViewPrefsMapper.ensureInitialized()
        .encodeJson<WorkbenchViewPrefs>(this as WorkbenchViewPrefs);
  }

  Map<String, dynamic> toMap() {
    return WorkbenchViewPrefsMapper.ensureInitialized()
        .encodeMap<WorkbenchViewPrefs>(this as WorkbenchViewPrefs);
  }

  WorkbenchViewPrefsCopyWith<
    WorkbenchViewPrefs,
    WorkbenchViewPrefs,
    WorkbenchViewPrefs
  >
  get copyWith =>
      _WorkbenchViewPrefsCopyWithImpl<WorkbenchViewPrefs, WorkbenchViewPrefs>(
        this as WorkbenchViewPrefs,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return WorkbenchViewPrefsMapper.ensureInitialized().stringifyValue(
      this as WorkbenchViewPrefs,
    );
  }

  @override
  bool operator ==(Object other) {
    return WorkbenchViewPrefsMapper.ensureInitialized().equalsValue(
      this as WorkbenchViewPrefs,
      other,
    );
  }

  @override
  int get hashCode {
    return WorkbenchViewPrefsMapper.ensureInitialized().hashValue(
      this as WorkbenchViewPrefs,
    );
  }
}

extension WorkbenchViewPrefsValueCopy<$R, $Out>
    on ObjectCopyWith<$R, WorkbenchViewPrefs, $Out> {
  WorkbenchViewPrefsCopyWith<$R, WorkbenchViewPrefs, $Out>
  get $asWorkbenchViewPrefs => $base.as(
    (v, t, t2) => _WorkbenchViewPrefsCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class WorkbenchViewPrefsCopyWith<
  $R,
  $In extends WorkbenchViewPrefs,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  MapCopyWith<$R, String, String, ObjectCopyWith<$R, String, String>>
  get sourceControlRootByWorkspaceId;
  $R call({
    WorkbenchGroupBy? groupBy,
    WorkbenchSortBy? projectSort,
    WorkbenchSortBy? workspaceSort,
    Set<String>? selectedProjectIds,
    Set<String>? collapsedProjectIds,
    Set<String>? expandedWorkspaceIds,
    Set<String>? selectedTagIds,
    Set<String>? collapsedParentWorkspaceIds,
    bool? pinnedSectionCollapsed,
    bool? allSectionCollapsed,
    Map<String, String>? sourceControlRootByWorkspaceId,
    bool? rightSidebarVisible,
    double? rightSidebarWidth,
    double? sidebarWidth,
    WorkbenchContextPanelTab? activeContextPanelTab,
    WorkspaceExplorerMode? explorerMode,
    GitDiffViewMode? gitDiffViewMode,
    PullRequestCreateAction? pullRequestCreateAction,
  });
  WorkbenchViewPrefsCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _WorkbenchViewPrefsCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, WorkbenchViewPrefs, $Out>
    implements WorkbenchViewPrefsCopyWith<$R, WorkbenchViewPrefs, $Out> {
  _WorkbenchViewPrefsCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<WorkbenchViewPrefs> $mapper =
      WorkbenchViewPrefsMapper.ensureInitialized();
  @override
  MapCopyWith<$R, String, String, ObjectCopyWith<$R, String, String>>
  get sourceControlRootByWorkspaceId => MapCopyWith(
    $value.sourceControlRootByWorkspaceId,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(sourceControlRootByWorkspaceId: v),
  );
  @override
  $R call({
    WorkbenchGroupBy? groupBy,
    WorkbenchSortBy? projectSort,
    WorkbenchSortBy? workspaceSort,
    Set<String>? selectedProjectIds,
    Set<String>? collapsedProjectIds,
    Set<String>? expandedWorkspaceIds,
    Set<String>? selectedTagIds,
    Set<String>? collapsedParentWorkspaceIds,
    bool? pinnedSectionCollapsed,
    bool? allSectionCollapsed,
    Map<String, String>? sourceControlRootByWorkspaceId,
    bool? rightSidebarVisible,
    double? rightSidebarWidth,
    double? sidebarWidth,
    WorkbenchContextPanelTab? activeContextPanelTab,
    WorkspaceExplorerMode? explorerMode,
    GitDiffViewMode? gitDiffViewMode,
    PullRequestCreateAction? pullRequestCreateAction,
  }) => $apply(
    FieldCopyWithData({
      if (groupBy != null) #groupBy: groupBy,
      if (projectSort != null) #projectSort: projectSort,
      if (workspaceSort != null) #workspaceSort: workspaceSort,
      if (selectedProjectIds != null) #selectedProjectIds: selectedProjectIds,
      if (collapsedProjectIds != null)
        #collapsedProjectIds: collapsedProjectIds,
      if (expandedWorkspaceIds != null)
        #expandedWorkspaceIds: expandedWorkspaceIds,
      if (selectedTagIds != null) #selectedTagIds: selectedTagIds,
      if (collapsedParentWorkspaceIds != null)
        #collapsedParentWorkspaceIds: collapsedParentWorkspaceIds,
      if (pinnedSectionCollapsed != null)
        #pinnedSectionCollapsed: pinnedSectionCollapsed,
      if (allSectionCollapsed != null)
        #allSectionCollapsed: allSectionCollapsed,
      if (sourceControlRootByWorkspaceId != null)
        #sourceControlRootByWorkspaceId: sourceControlRootByWorkspaceId,
      if (rightSidebarVisible != null)
        #rightSidebarVisible: rightSidebarVisible,
      if (rightSidebarWidth != null) #rightSidebarWidth: rightSidebarWidth,
      if (sidebarWidth != null) #sidebarWidth: sidebarWidth,
      if (activeContextPanelTab != null)
        #activeContextPanelTab: activeContextPanelTab,
      if (explorerMode != null) #explorerMode: explorerMode,
      if (gitDiffViewMode != null) #gitDiffViewMode: gitDiffViewMode,
      if (pullRequestCreateAction != null)
        #pullRequestCreateAction: pullRequestCreateAction,
    }),
  );
  @override
  WorkbenchViewPrefs $make(CopyWithData data) => WorkbenchViewPrefs(
    groupBy: data.get(#groupBy, or: $value.groupBy),
    projectSort: data.get(#projectSort, or: $value.projectSort),
    workspaceSort: data.get(#workspaceSort, or: $value.workspaceSort),
    selectedProjectIds: data.get(
      #selectedProjectIds,
      or: $value.selectedProjectIds,
    ),
    collapsedProjectIds: data.get(
      #collapsedProjectIds,
      or: $value.collapsedProjectIds,
    ),
    expandedWorkspaceIds: data.get(
      #expandedWorkspaceIds,
      or: $value.expandedWorkspaceIds,
    ),
    selectedTagIds: data.get(#selectedTagIds, or: $value.selectedTagIds),
    collapsedParentWorkspaceIds: data.get(
      #collapsedParentWorkspaceIds,
      or: $value.collapsedParentWorkspaceIds,
    ),
    pinnedSectionCollapsed: data.get(
      #pinnedSectionCollapsed,
      or: $value.pinnedSectionCollapsed,
    ),
    allSectionCollapsed: data.get(
      #allSectionCollapsed,
      or: $value.allSectionCollapsed,
    ),
    sourceControlRootByWorkspaceId: data.get(
      #sourceControlRootByWorkspaceId,
      or: $value.sourceControlRootByWorkspaceId,
    ),
    rightSidebarVisible: data.get(
      #rightSidebarVisible,
      or: $value.rightSidebarVisible,
    ),
    rightSidebarWidth: data.get(
      #rightSidebarWidth,
      or: $value.rightSidebarWidth,
    ),
    sidebarWidth: data.get(#sidebarWidth, or: $value.sidebarWidth),
    activeContextPanelTab: data.get(
      #activeContextPanelTab,
      or: $value.activeContextPanelTab,
    ),
    explorerMode: data.get(#explorerMode, or: $value.explorerMode),
    gitDiffViewMode: data.get(#gitDiffViewMode, or: $value.gitDiffViewMode),
    pullRequestCreateAction: data.get(
      #pullRequestCreateAction,
      or: $value.pullRequestCreateAction,
    ),
  );

  @override
  WorkbenchViewPrefsCopyWith<$R2, WorkbenchViewPrefs, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _WorkbenchViewPrefsCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

