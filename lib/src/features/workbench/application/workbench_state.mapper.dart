// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'workbench_state.dart';

class WorkbenchStateMapper extends ClassMapperBase<WorkbenchState> {
  WorkbenchStateMapper._();

  static WorkbenchStateMapper? _instance;
  static WorkbenchStateMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = WorkbenchStateMapper._());
      ProjectMapper.ensureInitialized();
      WorkspaceMapper.ensureInitialized();
      WorkspaceTabRecordMapper.ensureInitialized();
      WorkbenchLayoutMapper.ensureInitialized();
      WorkbenchViewPrefsMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'WorkbenchState';

  static List<Project> _$projects(WorkbenchState v) => v.projects;
  static const Field<WorkbenchState, List<Project>> _f$projects = Field(
    'projects',
    _$projects,
    opt: true,
    def: const <Project>[],
  );
  static Map<String, List<Workspace>> _$workspacesByProject(WorkbenchState v) =>
      v.workspacesByProject;
  static const Field<WorkbenchState, Map<String, List<Workspace>>>
  _f$workspacesByProject = Field(
    'workspacesByProject',
    _$workspacesByProject,
    opt: true,
    def: const <String, List<Workspace>>{},
  );
  static Map<String, List<WorkspaceTabRecord>> _$tabsByWorkspace(
    WorkbenchState v,
  ) => v.tabsByWorkspace;
  static const Field<WorkbenchState, Map<String, List<WorkspaceTabRecord>>>
  _f$tabsByWorkspace = Field(
    'tabsByWorkspace',
    _$tabsByWorkspace,
    opt: true,
    def: const <String, List<WorkspaceTabRecord>>{},
  );
  static Map<String, WorkbenchLayout> _$layoutByWorkspace(WorkbenchState v) =>
      v.layoutByWorkspace;
  static const Field<WorkbenchState, Map<String, WorkbenchLayout>>
  _f$layoutByWorkspace = Field(
    'layoutByWorkspace',
    _$layoutByWorkspace,
    opt: true,
    def: const <String, WorkbenchLayout>{},
  );
  static WorkbenchViewPrefs _$viewPrefs(WorkbenchState v) => v.viewPrefs;
  static const Field<WorkbenchState, WorkbenchViewPrefs> _f$viewPrefs = Field(
    'viewPrefs',
    _$viewPrefs,
    opt: true,
    def: WorkbenchViewPrefs.defaults,
  );
  static String? _$activeProjectId(WorkbenchState v) => v.activeProjectId;
  static const Field<WorkbenchState, String> _f$activeProjectId = Field(
    'activeProjectId',
    _$activeProjectId,
    opt: true,
  );
  static String? _$activeWorkspaceId(WorkbenchState v) => v.activeWorkspaceId;
  static const Field<WorkbenchState, String> _f$activeWorkspaceId = Field(
    'activeWorkspaceId',
    _$activeWorkspaceId,
    opt: true,
  );
  static Map<String, String> _$activeTabIdByWorkspace(WorkbenchState v) =>
      v.activeTabIdByWorkspace;
  static const Field<WorkbenchState, Map<String, String>>
  _f$activeTabIdByWorkspace = Field(
    'activeTabIdByWorkspace',
    _$activeTabIdByWorkspace,
    opt: true,
    def: const <String, String>{},
  );
  static bool _$bootstrapped(WorkbenchState v) => v.bootstrapped;
  static const Field<WorkbenchState, bool> _f$bootstrapped = Field(
    'bootstrapped',
    _$bootstrapped,
    opt: true,
    def: false,
  );
  static String? _$error(WorkbenchState v) => v.error;
  static const Field<WorkbenchState, String> _f$error = Field(
    'error',
    _$error,
    opt: true,
  );
  static String _$searchQuery(WorkbenchState v) => v.searchQuery;
  static const Field<WorkbenchState, String> _f$searchQuery = Field(
    'searchQuery',
    _$searchQuery,
    opt: true,
    def: '',
  );
  static bool _$collapsed(WorkbenchState v) => v.collapsed;
  static const Field<WorkbenchState, bool> _f$collapsed = Field(
    'collapsed',
    _$collapsed,
    opt: true,
    def: false,
  );

  @override
  final MappableFields<WorkbenchState> fields = const {
    #projects: _f$projects,
    #workspacesByProject: _f$workspacesByProject,
    #tabsByWorkspace: _f$tabsByWorkspace,
    #layoutByWorkspace: _f$layoutByWorkspace,
    #viewPrefs: _f$viewPrefs,
    #activeProjectId: _f$activeProjectId,
    #activeWorkspaceId: _f$activeWorkspaceId,
    #activeTabIdByWorkspace: _f$activeTabIdByWorkspace,
    #bootstrapped: _f$bootstrapped,
    #error: _f$error,
    #searchQuery: _f$searchQuery,
    #collapsed: _f$collapsed,
  };

  static WorkbenchState _instantiate(DecodingData data) {
    return WorkbenchState(
      projects: data.dec(_f$projects),
      workspacesByProject: data.dec(_f$workspacesByProject),
      tabsByWorkspace: data.dec(_f$tabsByWorkspace),
      layoutByWorkspace: data.dec(_f$layoutByWorkspace),
      viewPrefs: data.dec(_f$viewPrefs),
      activeProjectId: data.dec(_f$activeProjectId),
      activeWorkspaceId: data.dec(_f$activeWorkspaceId),
      activeTabIdByWorkspace: data.dec(_f$activeTabIdByWorkspace),
      bootstrapped: data.dec(_f$bootstrapped),
      error: data.dec(_f$error),
      searchQuery: data.dec(_f$searchQuery),
      collapsed: data.dec(_f$collapsed),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static WorkbenchState fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<WorkbenchState>(map);
  }

  static WorkbenchState fromJson(String json) {
    return ensureInitialized().decodeJson<WorkbenchState>(json);
  }
}

mixin WorkbenchStateMappable {
  String toJson() {
    return WorkbenchStateMapper.ensureInitialized().encodeJson<WorkbenchState>(
      this as WorkbenchState,
    );
  }

  Map<String, dynamic> toMap() {
    return WorkbenchStateMapper.ensureInitialized().encodeMap<WorkbenchState>(
      this as WorkbenchState,
    );
  }

  WorkbenchStateCopyWith<WorkbenchState, WorkbenchState, WorkbenchState>
  get copyWith => _WorkbenchStateCopyWithImpl<WorkbenchState, WorkbenchState>(
    this as WorkbenchState,
    $identity,
    $identity,
  );
  @override
  String toString() {
    return WorkbenchStateMapper.ensureInitialized().stringifyValue(
      this as WorkbenchState,
    );
  }

  @override
  bool operator ==(Object other) {
    return WorkbenchStateMapper.ensureInitialized().equalsValue(
      this as WorkbenchState,
      other,
    );
  }

  @override
  int get hashCode {
    return WorkbenchStateMapper.ensureInitialized().hashValue(
      this as WorkbenchState,
    );
  }
}

extension WorkbenchStateValueCopy<$R, $Out>
    on ObjectCopyWith<$R, WorkbenchState, $Out> {
  WorkbenchStateCopyWith<$R, WorkbenchState, $Out> get $asWorkbenchState =>
      $base.as((v, t, t2) => _WorkbenchStateCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class WorkbenchStateCopyWith<$R, $In extends WorkbenchState, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, Project, ProjectCopyWith<$R, Project, Project>> get projects;
  MapCopyWith<
    $R,
    String,
    List<Workspace>,
    ObjectCopyWith<$R, List<Workspace>, List<Workspace>>
  >
  get workspacesByProject;
  MapCopyWith<
    $R,
    String,
    List<WorkspaceTabRecord>,
    ObjectCopyWith<$R, List<WorkspaceTabRecord>, List<WorkspaceTabRecord>>
  >
  get tabsByWorkspace;
  MapCopyWith<
    $R,
    String,
    WorkbenchLayout,
    WorkbenchLayoutCopyWith<$R, WorkbenchLayout, WorkbenchLayout>
  >
  get layoutByWorkspace;
  WorkbenchViewPrefsCopyWith<$R, WorkbenchViewPrefs, WorkbenchViewPrefs>
  get viewPrefs;
  MapCopyWith<$R, String, String, ObjectCopyWith<$R, String, String>>
  get activeTabIdByWorkspace;
  $R call({
    List<Project>? projects,
    Map<String, List<Workspace>>? workspacesByProject,
    Map<String, List<WorkspaceTabRecord>>? tabsByWorkspace,
    Map<String, WorkbenchLayout>? layoutByWorkspace,
    WorkbenchViewPrefs? viewPrefs,
    String? activeProjectId,
    String? activeWorkspaceId,
    Map<String, String>? activeTabIdByWorkspace,
    bool? bootstrapped,
    String? error,
    String? searchQuery,
    bool? collapsed,
  });
  WorkbenchStateCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _WorkbenchStateCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, WorkbenchState, $Out>
    implements WorkbenchStateCopyWith<$R, WorkbenchState, $Out> {
  _WorkbenchStateCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<WorkbenchState> $mapper =
      WorkbenchStateMapper.ensureInitialized();
  @override
  ListCopyWith<$R, Project, ProjectCopyWith<$R, Project, Project>>
  get projects => ListCopyWith(
    $value.projects,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(projects: v),
  );
  @override
  MapCopyWith<
    $R,
    String,
    List<Workspace>,
    ObjectCopyWith<$R, List<Workspace>, List<Workspace>>
  >
  get workspacesByProject => MapCopyWith(
    $value.workspacesByProject,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(workspacesByProject: v),
  );
  @override
  MapCopyWith<
    $R,
    String,
    List<WorkspaceTabRecord>,
    ObjectCopyWith<$R, List<WorkspaceTabRecord>, List<WorkspaceTabRecord>>
  >
  get tabsByWorkspace => MapCopyWith(
    $value.tabsByWorkspace,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(tabsByWorkspace: v),
  );
  @override
  MapCopyWith<
    $R,
    String,
    WorkbenchLayout,
    WorkbenchLayoutCopyWith<$R, WorkbenchLayout, WorkbenchLayout>
  >
  get layoutByWorkspace => MapCopyWith(
    $value.layoutByWorkspace,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(layoutByWorkspace: v),
  );
  @override
  WorkbenchViewPrefsCopyWith<$R, WorkbenchViewPrefs, WorkbenchViewPrefs>
  get viewPrefs => $value.viewPrefs.copyWith.$chain((v) => call(viewPrefs: v));
  @override
  MapCopyWith<$R, String, String, ObjectCopyWith<$R, String, String>>
  get activeTabIdByWorkspace => MapCopyWith(
    $value.activeTabIdByWorkspace,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(activeTabIdByWorkspace: v),
  );
  @override
  $R call({
    List<Project>? projects,
    Map<String, List<Workspace>>? workspacesByProject,
    Map<String, List<WorkspaceTabRecord>>? tabsByWorkspace,
    Map<String, WorkbenchLayout>? layoutByWorkspace,
    WorkbenchViewPrefs? viewPrefs,
    Object? activeProjectId = $none,
    Object? activeWorkspaceId = $none,
    Map<String, String>? activeTabIdByWorkspace,
    bool? bootstrapped,
    Object? error = $none,
    String? searchQuery,
    bool? collapsed,
  }) => $apply(
    FieldCopyWithData({
      if (projects != null) #projects: projects,
      if (workspacesByProject != null)
        #workspacesByProject: workspacesByProject,
      if (tabsByWorkspace != null) #tabsByWorkspace: tabsByWorkspace,
      if (layoutByWorkspace != null) #layoutByWorkspace: layoutByWorkspace,
      if (viewPrefs != null) #viewPrefs: viewPrefs,
      if (activeProjectId != $none) #activeProjectId: activeProjectId,
      if (activeWorkspaceId != $none) #activeWorkspaceId: activeWorkspaceId,
      if (activeTabIdByWorkspace != null)
        #activeTabIdByWorkspace: activeTabIdByWorkspace,
      if (bootstrapped != null) #bootstrapped: bootstrapped,
      if (error != $none) #error: error,
      if (searchQuery != null) #searchQuery: searchQuery,
      if (collapsed != null) #collapsed: collapsed,
    }),
  );
  @override
  WorkbenchState $make(CopyWithData data) => WorkbenchState(
    projects: data.get(#projects, or: $value.projects),
    workspacesByProject: data.get(
      #workspacesByProject,
      or: $value.workspacesByProject,
    ),
    tabsByWorkspace: data.get(#tabsByWorkspace, or: $value.tabsByWorkspace),
    layoutByWorkspace: data.get(
      #layoutByWorkspace,
      or: $value.layoutByWorkspace,
    ),
    viewPrefs: data.get(#viewPrefs, or: $value.viewPrefs),
    activeProjectId: data.get(#activeProjectId, or: $value.activeProjectId),
    activeWorkspaceId: data.get(
      #activeWorkspaceId,
      or: $value.activeWorkspaceId,
    ),
    activeTabIdByWorkspace: data.get(
      #activeTabIdByWorkspace,
      or: $value.activeTabIdByWorkspace,
    ),
    bootstrapped: data.get(#bootstrapped, or: $value.bootstrapped),
    error: data.get(#error, or: $value.error),
    searchQuery: data.get(#searchQuery, or: $value.searchQuery),
    collapsed: data.get(#collapsed, or: $value.collapsed),
  );

  @override
  WorkbenchStateCopyWith<$R2, WorkbenchState, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _WorkbenchStateCopyWithImpl<$R2, $Out2>($value, $cast, t);
}
