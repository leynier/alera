// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'workbench_layout.dart';

class WorkbenchSplitAxisMapper extends EnumMapper<WorkbenchSplitAxis> {
  WorkbenchSplitAxisMapper._();

  static WorkbenchSplitAxisMapper? _instance;
  static WorkbenchSplitAxisMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = WorkbenchSplitAxisMapper._());
    }
    return _instance!;
  }

  static WorkbenchSplitAxis fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  WorkbenchSplitAxis decode(dynamic value) {
    switch (value) {
      case r'horizontal':
        return WorkbenchSplitAxis.horizontal;
      case r'vertical':
        return WorkbenchSplitAxis.vertical;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(WorkbenchSplitAxis self) {
    switch (self) {
      case WorkbenchSplitAxis.horizontal:
        return r'horizontal';
      case WorkbenchSplitAxis.vertical:
        return r'vertical';
    }
  }
}

extension WorkbenchSplitAxisMapperExtension on WorkbenchSplitAxis {
  String toValue() {
    WorkbenchSplitAxisMapper.ensureInitialized();
    return MapperContainer.globals.toValue<WorkbenchSplitAxis>(this) as String;
  }
}

class WorkbenchPaneGroupMapper extends ClassMapperBase<WorkbenchPaneGroup> {
  WorkbenchPaneGroupMapper._();

  static WorkbenchPaneGroupMapper? _instance;
  static WorkbenchPaneGroupMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = WorkbenchPaneGroupMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'WorkbenchPaneGroup';

  static String _$id(WorkbenchPaneGroup v) => v.id;
  static const Field<WorkbenchPaneGroup, String> _f$id = Field('id', _$id);
  static List<String> _$tabIds(WorkbenchPaneGroup v) => v.tabIds;
  static const Field<WorkbenchPaneGroup, List<String>> _f$tabIds = Field(
    'tabIds',
    _$tabIds,
  );
  static String? _$activeTabId(WorkbenchPaneGroup v) => v.activeTabId;
  static const Field<WorkbenchPaneGroup, String> _f$activeTabId = Field(
    'activeTabId',
    _$activeTabId,
  );

  @override
  final MappableFields<WorkbenchPaneGroup> fields = const {
    #id: _f$id,
    #tabIds: _f$tabIds,
    #activeTabId: _f$activeTabId,
  };

  static WorkbenchPaneGroup _instantiate(DecodingData data) {
    return WorkbenchPaneGroup(
      id: data.dec(_f$id),
      tabIds: data.dec(_f$tabIds),
      activeTabId: data.dec(_f$activeTabId),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static WorkbenchPaneGroup fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<WorkbenchPaneGroup>(map);
  }

  static WorkbenchPaneGroup fromJson(String json) {
    return ensureInitialized().decodeJson<WorkbenchPaneGroup>(json);
  }
}

mixin WorkbenchPaneGroupMappable {
  String toJson() {
    return WorkbenchPaneGroupMapper.ensureInitialized()
        .encodeJson<WorkbenchPaneGroup>(this as WorkbenchPaneGroup);
  }

  Map<String, dynamic> toMap() {
    return WorkbenchPaneGroupMapper.ensureInitialized()
        .encodeMap<WorkbenchPaneGroup>(this as WorkbenchPaneGroup);
  }

  WorkbenchPaneGroupCopyWith<
    WorkbenchPaneGroup,
    WorkbenchPaneGroup,
    WorkbenchPaneGroup
  >
  get copyWith =>
      _WorkbenchPaneGroupCopyWithImpl<WorkbenchPaneGroup, WorkbenchPaneGroup>(
        this as WorkbenchPaneGroup,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return WorkbenchPaneGroupMapper.ensureInitialized().stringifyValue(
      this as WorkbenchPaneGroup,
    );
  }

  @override
  bool operator ==(Object other) {
    return WorkbenchPaneGroupMapper.ensureInitialized().equalsValue(
      this as WorkbenchPaneGroup,
      other,
    );
  }

  @override
  int get hashCode {
    return WorkbenchPaneGroupMapper.ensureInitialized().hashValue(
      this as WorkbenchPaneGroup,
    );
  }
}

extension WorkbenchPaneGroupValueCopy<$R, $Out>
    on ObjectCopyWith<$R, WorkbenchPaneGroup, $Out> {
  WorkbenchPaneGroupCopyWith<$R, WorkbenchPaneGroup, $Out>
  get $asWorkbenchPaneGroup => $base.as(
    (v, t, t2) => _WorkbenchPaneGroupCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class WorkbenchPaneGroupCopyWith<
  $R,
  $In extends WorkbenchPaneGroup,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get tabIds;
  $R call({String? id, List<String>? tabIds, String? activeTabId});
  WorkbenchPaneGroupCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _WorkbenchPaneGroupCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, WorkbenchPaneGroup, $Out>
    implements WorkbenchPaneGroupCopyWith<$R, WorkbenchPaneGroup, $Out> {
  _WorkbenchPaneGroupCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<WorkbenchPaneGroup> $mapper =
      WorkbenchPaneGroupMapper.ensureInitialized();
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get tabIds =>
      ListCopyWith(
        $value.tabIds,
        (v, t) => ObjectCopyWith(v, $identity, t),
        (v) => call(tabIds: v),
      );
  @override
  $R call({String? id, List<String>? tabIds, Object? activeTabId = $none}) =>
      $apply(
        FieldCopyWithData({
          if (id != null) #id: id,
          if (tabIds != null) #tabIds: tabIds,
          if (activeTabId != $none) #activeTabId: activeTabId,
        }),
      );
  @override
  WorkbenchPaneGroup $make(CopyWithData data) => WorkbenchPaneGroup(
    id: data.get(#id, or: $value.id),
    tabIds: data.get(#tabIds, or: $value.tabIds),
    activeTabId: data.get(#activeTabId, or: $value.activeTabId),
  );

  @override
  WorkbenchPaneGroupCopyWith<$R2, WorkbenchPaneGroup, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _WorkbenchPaneGroupCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class WorkbenchLayoutNodeMapper extends ClassMapperBase<WorkbenchLayoutNode> {
  WorkbenchLayoutNodeMapper._();

  static WorkbenchLayoutNodeMapper? _instance;
  static WorkbenchLayoutNodeMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = WorkbenchLayoutNodeMapper._());
      WorkbenchLeafLayoutNodeMapper.ensureInitialized();
      WorkbenchSplitLayoutNodeMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'WorkbenchLayoutNode';

  @override
  final MappableFields<WorkbenchLayoutNode> fields = const {};

  static WorkbenchLayoutNode _instantiate(DecodingData data) {
    throw MapperException.missingSubclass(
      'WorkbenchLayoutNode',
      'type',
      '${data.value['type']}',
    );
  }

  @override
  final Function instantiate = _instantiate;

  static WorkbenchLayoutNode fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<WorkbenchLayoutNode>(map);
  }

  static WorkbenchLayoutNode fromJson(String json) {
    return ensureInitialized().decodeJson<WorkbenchLayoutNode>(json);
  }
}

mixin WorkbenchLayoutNodeMappable {
  String toJson();
  Map<String, dynamic> toMap();
  WorkbenchLayoutNodeCopyWith<
    WorkbenchLayoutNode,
    WorkbenchLayoutNode,
    WorkbenchLayoutNode
  >
  get copyWith;
}

abstract class WorkbenchLayoutNodeCopyWith<
  $R,
  $In extends WorkbenchLayoutNode,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call();
  WorkbenchLayoutNodeCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class WorkbenchLeafLayoutNodeMapper
    extends SubClassMapperBase<WorkbenchLeafLayoutNode> {
  WorkbenchLeafLayoutNodeMapper._();

  static WorkbenchLeafLayoutNodeMapper? _instance;
  static WorkbenchLeafLayoutNodeMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = WorkbenchLeafLayoutNodeMapper._(),
      );
      WorkbenchLayoutNodeMapper.ensureInitialized().addSubMapper(_instance!);
    }
    return _instance!;
  }

  @override
  final String id = 'WorkbenchLeafLayoutNode';

  static String _$groupId(WorkbenchLeafLayoutNode v) => v.groupId;
  static const Field<WorkbenchLeafLayoutNode, String> _f$groupId = Field(
    'groupId',
    _$groupId,
  );

  @override
  final MappableFields<WorkbenchLeafLayoutNode> fields = const {
    #groupId: _f$groupId,
  };

  @override
  final String discriminatorKey = 'type';
  @override
  final dynamic discriminatorValue = 'leaf';
  @override
  late final ClassMapperBase superMapper =
      WorkbenchLayoutNodeMapper.ensureInitialized();

  static WorkbenchLeafLayoutNode _instantiate(DecodingData data) {
    return WorkbenchLeafLayoutNode(data.dec(_f$groupId));
  }

  @override
  final Function instantiate = _instantiate;

  static WorkbenchLeafLayoutNode fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<WorkbenchLeafLayoutNode>(map);
  }

  static WorkbenchLeafLayoutNode fromJson(String json) {
    return ensureInitialized().decodeJson<WorkbenchLeafLayoutNode>(json);
  }
}

mixin WorkbenchLeafLayoutNodeMappable {
  String toJson() {
    return WorkbenchLeafLayoutNodeMapper.ensureInitialized()
        .encodeJson<WorkbenchLeafLayoutNode>(this as WorkbenchLeafLayoutNode);
  }

  Map<String, dynamic> toMap() {
    return WorkbenchLeafLayoutNodeMapper.ensureInitialized()
        .encodeMap<WorkbenchLeafLayoutNode>(this as WorkbenchLeafLayoutNode);
  }

  WorkbenchLeafLayoutNodeCopyWith<
    WorkbenchLeafLayoutNode,
    WorkbenchLeafLayoutNode,
    WorkbenchLeafLayoutNode
  >
  get copyWith =>
      _WorkbenchLeafLayoutNodeCopyWithImpl<
        WorkbenchLeafLayoutNode,
        WorkbenchLeafLayoutNode
      >(this as WorkbenchLeafLayoutNode, $identity, $identity);
  @override
  String toString() {
    return WorkbenchLeafLayoutNodeMapper.ensureInitialized().stringifyValue(
      this as WorkbenchLeafLayoutNode,
    );
  }

  @override
  bool operator ==(Object other) {
    return WorkbenchLeafLayoutNodeMapper.ensureInitialized().equalsValue(
      this as WorkbenchLeafLayoutNode,
      other,
    );
  }

  @override
  int get hashCode {
    return WorkbenchLeafLayoutNodeMapper.ensureInitialized().hashValue(
      this as WorkbenchLeafLayoutNode,
    );
  }
}

extension WorkbenchLeafLayoutNodeValueCopy<$R, $Out>
    on ObjectCopyWith<$R, WorkbenchLeafLayoutNode, $Out> {
  WorkbenchLeafLayoutNodeCopyWith<$R, WorkbenchLeafLayoutNode, $Out>
  get $asWorkbenchLeafLayoutNode => $base.as(
    (v, t, t2) => _WorkbenchLeafLayoutNodeCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class WorkbenchLeafLayoutNodeCopyWith<
  $R,
  $In extends WorkbenchLeafLayoutNode,
  $Out
>
    implements WorkbenchLayoutNodeCopyWith<$R, $In, $Out> {
  @override
  $R call({String? groupId});
  WorkbenchLeafLayoutNodeCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _WorkbenchLeafLayoutNodeCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, WorkbenchLeafLayoutNode, $Out>
    implements
        WorkbenchLeafLayoutNodeCopyWith<$R, WorkbenchLeafLayoutNode, $Out> {
  _WorkbenchLeafLayoutNodeCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<WorkbenchLeafLayoutNode> $mapper =
      WorkbenchLeafLayoutNodeMapper.ensureInitialized();
  @override
  $R call({String? groupId}) =>
      $apply(FieldCopyWithData({if (groupId != null) #groupId: groupId}));
  @override
  WorkbenchLeafLayoutNode $make(CopyWithData data) =>
      WorkbenchLeafLayoutNode(data.get(#groupId, or: $value.groupId));

  @override
  WorkbenchLeafLayoutNodeCopyWith<$R2, WorkbenchLeafLayoutNode, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _WorkbenchLeafLayoutNodeCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class WorkbenchSplitLayoutNodeMapper
    extends SubClassMapperBase<WorkbenchSplitLayoutNode> {
  WorkbenchSplitLayoutNodeMapper._();

  static WorkbenchSplitLayoutNodeMapper? _instance;
  static WorkbenchSplitLayoutNodeMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = WorkbenchSplitLayoutNodeMapper._(),
      );
      WorkbenchLayoutNodeMapper.ensureInitialized().addSubMapper(_instance!);
      WorkbenchSplitAxisMapper.ensureInitialized();
      WorkbenchLayoutNodeMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'WorkbenchSplitLayoutNode';

  static WorkbenchSplitAxis _$axis(WorkbenchSplitLayoutNode v) => v.axis;
  static const Field<WorkbenchSplitLayoutNode, WorkbenchSplitAxis> _f$axis =
      Field('axis', _$axis);
  static WorkbenchLayoutNode _$first(WorkbenchSplitLayoutNode v) => v.first;
  static const Field<WorkbenchSplitLayoutNode, WorkbenchLayoutNode> _f$first =
      Field('first', _$first);
  static WorkbenchLayoutNode _$second(WorkbenchSplitLayoutNode v) => v.second;
  static const Field<WorkbenchSplitLayoutNode, WorkbenchLayoutNode> _f$second =
      Field('second', _$second);
  static double _$ratio(WorkbenchSplitLayoutNode v) => v.ratio;
  static const Field<WorkbenchSplitLayoutNode, double> _f$ratio = Field(
    'ratio',
    _$ratio,
  );

  @override
  final MappableFields<WorkbenchSplitLayoutNode> fields = const {
    #axis: _f$axis,
    #first: _f$first,
    #second: _f$second,
    #ratio: _f$ratio,
  };

  @override
  final String discriminatorKey = 'type';
  @override
  final dynamic discriminatorValue = 'split';
  @override
  late final ClassMapperBase superMapper =
      WorkbenchLayoutNodeMapper.ensureInitialized();

  static WorkbenchSplitLayoutNode _instantiate(DecodingData data) {
    return WorkbenchSplitLayoutNode(
      axis: data.dec(_f$axis),
      first: data.dec(_f$first),
      second: data.dec(_f$second),
      ratio: data.dec(_f$ratio),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static WorkbenchSplitLayoutNode fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<WorkbenchSplitLayoutNode>(map);
  }

  static WorkbenchSplitLayoutNode fromJson(String json) {
    return ensureInitialized().decodeJson<WorkbenchSplitLayoutNode>(json);
  }
}

mixin WorkbenchSplitLayoutNodeMappable {
  String toJson() {
    return WorkbenchSplitLayoutNodeMapper.ensureInitialized()
        .encodeJson<WorkbenchSplitLayoutNode>(this as WorkbenchSplitLayoutNode);
  }

  Map<String, dynamic> toMap() {
    return WorkbenchSplitLayoutNodeMapper.ensureInitialized()
        .encodeMap<WorkbenchSplitLayoutNode>(this as WorkbenchSplitLayoutNode);
  }

  WorkbenchSplitLayoutNodeCopyWith<
    WorkbenchSplitLayoutNode,
    WorkbenchSplitLayoutNode,
    WorkbenchSplitLayoutNode
  >
  get copyWith =>
      _WorkbenchSplitLayoutNodeCopyWithImpl<
        WorkbenchSplitLayoutNode,
        WorkbenchSplitLayoutNode
      >(this as WorkbenchSplitLayoutNode, $identity, $identity);
  @override
  String toString() {
    return WorkbenchSplitLayoutNodeMapper.ensureInitialized().stringifyValue(
      this as WorkbenchSplitLayoutNode,
    );
  }

  @override
  bool operator ==(Object other) {
    return WorkbenchSplitLayoutNodeMapper.ensureInitialized().equalsValue(
      this as WorkbenchSplitLayoutNode,
      other,
    );
  }

  @override
  int get hashCode {
    return WorkbenchSplitLayoutNodeMapper.ensureInitialized().hashValue(
      this as WorkbenchSplitLayoutNode,
    );
  }
}

extension WorkbenchSplitLayoutNodeValueCopy<$R, $Out>
    on ObjectCopyWith<$R, WorkbenchSplitLayoutNode, $Out> {
  WorkbenchSplitLayoutNodeCopyWith<$R, WorkbenchSplitLayoutNode, $Out>
  get $asWorkbenchSplitLayoutNode => $base.as(
    (v, t, t2) => _WorkbenchSplitLayoutNodeCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class WorkbenchSplitLayoutNodeCopyWith<
  $R,
  $In extends WorkbenchSplitLayoutNode,
  $Out
>
    implements WorkbenchLayoutNodeCopyWith<$R, $In, $Out> {
  WorkbenchLayoutNodeCopyWith<$R, WorkbenchLayoutNode, WorkbenchLayoutNode>
  get first;
  WorkbenchLayoutNodeCopyWith<$R, WorkbenchLayoutNode, WorkbenchLayoutNode>
  get second;
  @override
  $R call({
    WorkbenchSplitAxis? axis,
    WorkbenchLayoutNode? first,
    WorkbenchLayoutNode? second,
    double? ratio,
  });
  WorkbenchSplitLayoutNodeCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _WorkbenchSplitLayoutNodeCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, WorkbenchSplitLayoutNode, $Out>
    implements
        WorkbenchSplitLayoutNodeCopyWith<$R, WorkbenchSplitLayoutNode, $Out> {
  _WorkbenchSplitLayoutNodeCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<WorkbenchSplitLayoutNode> $mapper =
      WorkbenchSplitLayoutNodeMapper.ensureInitialized();
  @override
  WorkbenchLayoutNodeCopyWith<$R, WorkbenchLayoutNode, WorkbenchLayoutNode>
  get first => $value.first.copyWith.$chain((v) => call(first: v));
  @override
  WorkbenchLayoutNodeCopyWith<$R, WorkbenchLayoutNode, WorkbenchLayoutNode>
  get second => $value.second.copyWith.$chain((v) => call(second: v));
  @override
  $R call({
    WorkbenchSplitAxis? axis,
    WorkbenchLayoutNode? first,
    WorkbenchLayoutNode? second,
    double? ratio,
  }) => $apply(
    FieldCopyWithData({
      if (axis != null) #axis: axis,
      if (first != null) #first: first,
      if (second != null) #second: second,
      if (ratio != null) #ratio: ratio,
    }),
  );
  @override
  WorkbenchSplitLayoutNode $make(CopyWithData data) => WorkbenchSplitLayoutNode(
    axis: data.get(#axis, or: $value.axis),
    first: data.get(#first, or: $value.first),
    second: data.get(#second, or: $value.second),
    ratio: data.get(#ratio, or: $value.ratio),
  );

  @override
  WorkbenchSplitLayoutNodeCopyWith<$R2, WorkbenchSplitLayoutNode, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _WorkbenchSplitLayoutNodeCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class WorkbenchLayoutMapper extends ClassMapperBase<WorkbenchLayout> {
  WorkbenchLayoutMapper._();

  static WorkbenchLayoutMapper? _instance;
  static WorkbenchLayoutMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = WorkbenchLayoutMapper._());
      WorkbenchLayoutNodeMapper.ensureInitialized();
      WorkbenchPaneGroupMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'WorkbenchLayout';

  static String _$workspaceId(WorkbenchLayout v) => v.workspaceId;
  static const Field<WorkbenchLayout, String> _f$workspaceId = Field(
    'workspaceId',
    _$workspaceId,
  );
  static WorkbenchLayoutNode _$root(WorkbenchLayout v) => v.root;
  static const Field<WorkbenchLayout, WorkbenchLayoutNode> _f$root = Field(
    'root',
    _$root,
  );
  static Map<String, WorkbenchPaneGroup> _$groups(WorkbenchLayout v) =>
      v.groups;
  static const Field<WorkbenchLayout, Map<String, WorkbenchPaneGroup>>
  _f$groups = Field('groups', _$groups);
  static String _$activeGroupId(WorkbenchLayout v) => v.activeGroupId;
  static const Field<WorkbenchLayout, String> _f$activeGroupId = Field(
    'activeGroupId',
    _$activeGroupId,
  );

  @override
  final MappableFields<WorkbenchLayout> fields = const {
    #workspaceId: _f$workspaceId,
    #root: _f$root,
    #groups: _f$groups,
    #activeGroupId: _f$activeGroupId,
  };

  static WorkbenchLayout _instantiate(DecodingData data) {
    return WorkbenchLayout(
      workspaceId: data.dec(_f$workspaceId),
      root: data.dec(_f$root),
      groups: data.dec(_f$groups),
      activeGroupId: data.dec(_f$activeGroupId),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static WorkbenchLayout fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<WorkbenchLayout>(map);
  }

  static WorkbenchLayout fromJson(String json) {
    return ensureInitialized().decodeJson<WorkbenchLayout>(json);
  }
}

mixin WorkbenchLayoutMappable {
  String toJson() {
    return WorkbenchLayoutMapper.ensureInitialized()
        .encodeJson<WorkbenchLayout>(this as WorkbenchLayout);
  }

  Map<String, dynamic> toMap() {
    return WorkbenchLayoutMapper.ensureInitialized().encodeMap<WorkbenchLayout>(
      this as WorkbenchLayout,
    );
  }

  WorkbenchLayoutCopyWith<WorkbenchLayout, WorkbenchLayout, WorkbenchLayout>
  get copyWith =>
      _WorkbenchLayoutCopyWithImpl<WorkbenchLayout, WorkbenchLayout>(
        this as WorkbenchLayout,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return WorkbenchLayoutMapper.ensureInitialized().stringifyValue(
      this as WorkbenchLayout,
    );
  }

  @override
  bool operator ==(Object other) {
    return WorkbenchLayoutMapper.ensureInitialized().equalsValue(
      this as WorkbenchLayout,
      other,
    );
  }

  @override
  int get hashCode {
    return WorkbenchLayoutMapper.ensureInitialized().hashValue(
      this as WorkbenchLayout,
    );
  }
}

extension WorkbenchLayoutValueCopy<$R, $Out>
    on ObjectCopyWith<$R, WorkbenchLayout, $Out> {
  WorkbenchLayoutCopyWith<$R, WorkbenchLayout, $Out> get $asWorkbenchLayout =>
      $base.as((v, t, t2) => _WorkbenchLayoutCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class WorkbenchLayoutCopyWith<$R, $In extends WorkbenchLayout, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  WorkbenchLayoutNodeCopyWith<$R, WorkbenchLayoutNode, WorkbenchLayoutNode>
  get root;
  MapCopyWith<
    $R,
    String,
    WorkbenchPaneGroup,
    WorkbenchPaneGroupCopyWith<$R, WorkbenchPaneGroup, WorkbenchPaneGroup>
  >
  get groups;
  $R call({
    String? workspaceId,
    WorkbenchLayoutNode? root,
    Map<String, WorkbenchPaneGroup>? groups,
    String? activeGroupId,
  });
  WorkbenchLayoutCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _WorkbenchLayoutCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, WorkbenchLayout, $Out>
    implements WorkbenchLayoutCopyWith<$R, WorkbenchLayout, $Out> {
  _WorkbenchLayoutCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<WorkbenchLayout> $mapper =
      WorkbenchLayoutMapper.ensureInitialized();
  @override
  WorkbenchLayoutNodeCopyWith<$R, WorkbenchLayoutNode, WorkbenchLayoutNode>
  get root => $value.root.copyWith.$chain((v) => call(root: v));
  @override
  MapCopyWith<
    $R,
    String,
    WorkbenchPaneGroup,
    WorkbenchPaneGroupCopyWith<$R, WorkbenchPaneGroup, WorkbenchPaneGroup>
  >
  get groups => MapCopyWith(
    $value.groups,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(groups: v),
  );
  @override
  $R call({
    String? workspaceId,
    WorkbenchLayoutNode? root,
    Map<String, WorkbenchPaneGroup>? groups,
    String? activeGroupId,
  }) => $apply(
    FieldCopyWithData({
      if (workspaceId != null) #workspaceId: workspaceId,
      if (root != null) #root: root,
      if (groups != null) #groups: groups,
      if (activeGroupId != null) #activeGroupId: activeGroupId,
    }),
  );
  @override
  WorkbenchLayout $make(CopyWithData data) => WorkbenchLayout(
    workspaceId: data.get(#workspaceId, or: $value.workspaceId),
    root: data.get(#root, or: $value.root),
    groups: data.get(#groups, or: $value.groups),
    activeGroupId: data.get(#activeGroupId, or: $value.activeGroupId),
  );

  @override
  WorkbenchLayoutCopyWith<$R2, WorkbenchLayout, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _WorkbenchLayoutCopyWithImpl<$R2, $Out2>($value, $cast, t);
}
