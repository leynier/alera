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
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(WorkbenchContextPanelTab self) {
    switch (self) {
      case WorkbenchContextPanelTab.explorer:
        return r'explorer';
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

  @override
  final MappableFields<WorkbenchViewPrefs> fields = const {
    #groupBy: _f$groupBy,
    #projectSort: _f$projectSort,
    #workspaceSort: _f$workspaceSort,
    #selectedProjectIds: _f$selectedProjectIds,
    #collapsedProjectIds: _f$collapsedProjectIds,
    #expandedWorkspaceIds: _f$expandedWorkspaceIds,
    #rightSidebarVisible: _f$rightSidebarVisible,
    #rightSidebarWidth: _f$rightSidebarWidth,
    #activeContextPanelTab: _f$activeContextPanelTab,
    #explorerMode: _f$explorerMode,
  };

  static WorkbenchViewPrefs _instantiate(DecodingData data) {
    return WorkbenchViewPrefs(
      groupBy: data.dec(_f$groupBy),
      projectSort: data.dec(_f$projectSort),
      workspaceSort: data.dec(_f$workspaceSort),
      selectedProjectIds: data.dec(_f$selectedProjectIds),
      collapsedProjectIds: data.dec(_f$collapsedProjectIds),
      expandedWorkspaceIds: data.dec(_f$expandedWorkspaceIds),
      rightSidebarVisible: data.dec(_f$rightSidebarVisible),
      rightSidebarWidth: data.dec(_f$rightSidebarWidth),
      activeContextPanelTab: data.dec(_f$activeContextPanelTab),
      explorerMode: data.dec(_f$explorerMode),
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
  $R call({
    WorkbenchGroupBy? groupBy,
    WorkbenchSortBy? projectSort,
    WorkbenchSortBy? workspaceSort,
    Set<String>? selectedProjectIds,
    Set<String>? collapsedProjectIds,
    Set<String>? expandedWorkspaceIds,
    bool? rightSidebarVisible,
    double? rightSidebarWidth,
    WorkbenchContextPanelTab? activeContextPanelTab,
    WorkspaceExplorerMode? explorerMode,
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
  $R call({
    WorkbenchGroupBy? groupBy,
    WorkbenchSortBy? projectSort,
    WorkbenchSortBy? workspaceSort,
    Set<String>? selectedProjectIds,
    Set<String>? collapsedProjectIds,
    Set<String>? expandedWorkspaceIds,
    bool? rightSidebarVisible,
    double? rightSidebarWidth,
    WorkbenchContextPanelTab? activeContextPanelTab,
    WorkspaceExplorerMode? explorerMode,
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
      if (rightSidebarVisible != null)
        #rightSidebarVisible: rightSidebarVisible,
      if (rightSidebarWidth != null) #rightSidebarWidth: rightSidebarWidth,
      if (activeContextPanelTab != null)
        #activeContextPanelTab: activeContextPanelTab,
      if (explorerMode != null) #explorerMode: explorerMode,
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
    rightSidebarVisible: data.get(
      #rightSidebarVisible,
      or: $value.rightSidebarVisible,
    ),
    rightSidebarWidth: data.get(
      #rightSidebarWidth,
      or: $value.rightSidebarWidth,
    ),
    activeContextPanelTab: data.get(
      #activeContextPanelTab,
      or: $value.activeContextPanelTab,
    ),
    explorerMode: data.get(#explorerMode, or: $value.explorerMode),
  );

  @override
  WorkbenchViewPrefsCopyWith<$R2, WorkbenchViewPrefs, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _WorkbenchViewPrefsCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

