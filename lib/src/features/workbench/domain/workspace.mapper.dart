// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'workspace.dart';

class WorkspaceKindMapper extends EnumMapper<WorkspaceKind> {
  WorkspaceKindMapper._();

  static WorkspaceKindMapper? _instance;
  static WorkspaceKindMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = WorkspaceKindMapper._());
    }
    return _instance!;
  }

  static WorkspaceKind fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  WorkspaceKind decode(dynamic value) {
    switch (value) {
      case r'main':
        return WorkspaceKind.main;
      case r'linked':
        return WorkspaceKind.linked;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(WorkspaceKind self) {
    switch (self) {
      case WorkspaceKind.main:
        return r'main';
      case WorkspaceKind.linked:
        return r'linked';
    }
  }
}

extension WorkspaceKindMapperExtension on WorkspaceKind {
  String toValue() {
    WorkspaceKindMapper.ensureInitialized();
    return MapperContainer.globals.toValue<WorkspaceKind>(this) as String;
  }
}

class WorkspaceStatusMapper extends EnumMapper<WorkspaceStatus> {
  WorkspaceStatusMapper._();

  static WorkspaceStatusMapper? _instance;
  static WorkspaceStatusMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = WorkspaceStatusMapper._());
    }
    return _instance!;
  }

  static WorkspaceStatus fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  WorkspaceStatus decode(dynamic value) {
    switch (value) {
      case r'active':
        return WorkspaceStatus.active;
      case r'removed':
        return WorkspaceStatus.removed;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(WorkspaceStatus self) {
    switch (self) {
      case WorkspaceStatus.active:
        return r'active';
      case WorkspaceStatus.removed:
        return r'removed';
    }
  }
}

extension WorkspaceStatusMapperExtension on WorkspaceStatus {
  String toValue() {
    WorkspaceStatusMapper.ensureInitialized();
    return MapperContainer.globals.toValue<WorkspaceStatus>(this) as String;
  }
}

class WorkspaceMapper extends ClassMapperBase<Workspace> {
  WorkspaceMapper._();

  static WorkspaceMapper? _instance;
  static WorkspaceMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = WorkspaceMapper._());
      WorkspaceKindMapper.ensureInitialized();
      WorkspaceStatusMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'Workspace';

  static String _$id(Workspace v) => v.id;
  static const Field<Workspace, String> _f$id = Field('id', _$id);
  static String _$projectId(Workspace v) => v.projectId;
  static const Field<Workspace, String> _f$projectId = Field(
    'projectId',
    _$projectId,
  );
  static String _$name(Workspace v) => v.name;
  static const Field<Workspace, String> _f$name = Field('name', _$name);
  static String _$path(Workspace v) => v.path;
  static const Field<Workspace, String> _f$path = Field('path', _$path);
  static DateTime _$createdAt(Workspace v) => v.createdAt;
  static const Field<Workspace, DateTime> _f$createdAt = Field(
    'createdAt',
    _$createdAt,
  );
  static DateTime _$updatedAt(Workspace v) => v.updatedAt;
  static const Field<Workspace, DateTime> _f$updatedAt = Field(
    'updatedAt',
    _$updatedAt,
  );
  static WorkspaceKind _$kind(Workspace v) => v.kind;
  static const Field<Workspace, WorkspaceKind> _f$kind = Field('kind', _$kind);
  static WorkspaceStatus _$status(Workspace v) => v.status;
  static const Field<Workspace, WorkspaceStatus> _f$status = Field(
    'status',
    _$status,
  );
  static String? _$branch(Workspace v) => v.branch;
  static const Field<Workspace, String> _f$branch = Field(
    'branch',
    _$branch,
    opt: true,
  );
  static String? _$sourceBranch(Workspace v) => v.sourceBranch;
  static const Field<Workspace, String> _f$sourceBranch = Field(
    'sourceBranch',
    _$sourceBranch,
    opt: true,
  );
  static bool _$reusesExistingBranch(Workspace v) => v.reusesExistingBranch;
  static const Field<Workspace, bool> _f$reusesExistingBranch = Field(
    'reusesExistingBranch',
    _$reusesExistingBranch,
    opt: true,
    def: false,
  );
  static String? _$instanceId(Workspace v) => v.instanceId;
  static const Field<Workspace, String> _f$instanceId = Field(
    'instanceId',
    _$instanceId,
    opt: true,
  );
  static String _$hostId(Workspace v) => v.hostId;
  static const Field<Workspace, String> _f$hostId = Field(
    'hostId',
    _$hostId,
    opt: true,
    def: 'local',
  );
  static bool _$isPinned(Workspace v) => v.isPinned;
  static const Field<Workspace, bool> _f$isPinned = Field(
    'isPinned',
    _$isPinned,
    opt: true,
    def: false,
  );
  static List<String> _$tagIds(Workspace v) => v.tagIds;
  static const Field<Workspace, List<String>> _f$tagIds = Field(
    'tagIds',
    _$tagIds,
    opt: true,
    def: const <String>[],
  );
  static List<String> _$tagNames(Workspace v) => v.tagNames;
  static const Field<Workspace, List<String>> _f$tagNames = Field(
    'tagNames',
    _$tagNames,
    opt: true,
    def: const <String>[],
  );
  static String? _$parentWorkspaceId(Workspace v) => v.parentWorkspaceId;
  static const Field<Workspace, String> _f$parentWorkspaceId = Field(
    'parentWorkspaceId',
    _$parentWorkspaceId,
    opt: true,
  );
  static int _$childCount(Workspace v) => v.childCount;
  static const Field<Workspace, int> _f$childCount = Field(
    'childCount',
    _$childCount,
    opt: true,
    def: 0,
  );

  @override
  final MappableFields<Workspace> fields = const {
    #id: _f$id,
    #projectId: _f$projectId,
    #name: _f$name,
    #path: _f$path,
    #createdAt: _f$createdAt,
    #updatedAt: _f$updatedAt,
    #kind: _f$kind,
    #status: _f$status,
    #branch: _f$branch,
    #sourceBranch: _f$sourceBranch,
    #reusesExistingBranch: _f$reusesExistingBranch,
    #instanceId: _f$instanceId,
    #hostId: _f$hostId,
    #isPinned: _f$isPinned,
    #tagIds: _f$tagIds,
    #tagNames: _f$tagNames,
    #parentWorkspaceId: _f$parentWorkspaceId,
    #childCount: _f$childCount,
  };

  static Workspace _instantiate(DecodingData data) {
    return Workspace(
      id: data.dec(_f$id),
      projectId: data.dec(_f$projectId),
      name: data.dec(_f$name),
      path: data.dec(_f$path),
      createdAt: data.dec(_f$createdAt),
      updatedAt: data.dec(_f$updatedAt),
      kind: data.dec(_f$kind),
      status: data.dec(_f$status),
      branch: data.dec(_f$branch),
      sourceBranch: data.dec(_f$sourceBranch),
      reusesExistingBranch: data.dec(_f$reusesExistingBranch),
      instanceId: data.dec(_f$instanceId),
      hostId: data.dec(_f$hostId),
      isPinned: data.dec(_f$isPinned),
      tagIds: data.dec(_f$tagIds),
      tagNames: data.dec(_f$tagNames),
      parentWorkspaceId: data.dec(_f$parentWorkspaceId),
      childCount: data.dec(_f$childCount),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static Workspace fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<Workspace>(map);
  }

  static Workspace fromJson(String json) {
    return ensureInitialized().decodeJson<Workspace>(json);
  }
}

mixin WorkspaceMappable {
  String toJson() {
    return WorkspaceMapper.ensureInitialized().encodeJson<Workspace>(
      this as Workspace,
    );
  }

  Map<String, dynamic> toMap() {
    return WorkspaceMapper.ensureInitialized().encodeMap<Workspace>(
      this as Workspace,
    );
  }

  WorkspaceCopyWith<Workspace, Workspace, Workspace> get copyWith =>
      _WorkspaceCopyWithImpl<Workspace, Workspace>(
        this as Workspace,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return WorkspaceMapper.ensureInitialized().stringifyValue(
      this as Workspace,
    );
  }

  @override
  bool operator ==(Object other) {
    return WorkspaceMapper.ensureInitialized().equalsValue(
      this as Workspace,
      other,
    );
  }

  @override
  int get hashCode {
    return WorkspaceMapper.ensureInitialized().hashValue(this as Workspace);
  }
}

extension WorkspaceValueCopy<$R, $Out> on ObjectCopyWith<$R, Workspace, $Out> {
  WorkspaceCopyWith<$R, Workspace, $Out> get $asWorkspace =>
      $base.as((v, t, t2) => _WorkspaceCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class WorkspaceCopyWith<$R, $In extends Workspace, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get tagIds;
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get tagNames;
  $R call({
    String? id,
    String? projectId,
    String? name,
    String? path,
    DateTime? createdAt,
    DateTime? updatedAt,
    WorkspaceKind? kind,
    WorkspaceStatus? status,
    String? branch,
    String? sourceBranch,
    bool? reusesExistingBranch,
    String? instanceId,
    String? hostId,
    bool? isPinned,
    List<String>? tagIds,
    List<String>? tagNames,
    String? parentWorkspaceId,
    int? childCount,
  });
  WorkspaceCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _WorkspaceCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, Workspace, $Out>
    implements WorkspaceCopyWith<$R, Workspace, $Out> {
  _WorkspaceCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<Workspace> $mapper =
      WorkspaceMapper.ensureInitialized();
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get tagIds =>
      ListCopyWith(
        $value.tagIds,
        (v, t) => ObjectCopyWith(v, $identity, t),
        (v) => call(tagIds: v),
      );
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get tagNames =>
      ListCopyWith(
        $value.tagNames,
        (v, t) => ObjectCopyWith(v, $identity, t),
        (v) => call(tagNames: v),
      );
  @override
  $R call({
    String? id,
    String? projectId,
    String? name,
    String? path,
    DateTime? createdAt,
    DateTime? updatedAt,
    WorkspaceKind? kind,
    WorkspaceStatus? status,
    Object? branch = $none,
    Object? sourceBranch = $none,
    bool? reusesExistingBranch,
    Object? instanceId = $none,
    String? hostId,
    bool? isPinned,
    List<String>? tagIds,
    List<String>? tagNames,
    Object? parentWorkspaceId = $none,
    int? childCount,
  }) => $apply(
    FieldCopyWithData({
      if (id != null) #id: id,
      if (projectId != null) #projectId: projectId,
      if (name != null) #name: name,
      if (path != null) #path: path,
      if (createdAt != null) #createdAt: createdAt,
      if (updatedAt != null) #updatedAt: updatedAt,
      if (kind != null) #kind: kind,
      if (status != null) #status: status,
      if (branch != $none) #branch: branch,
      if (sourceBranch != $none) #sourceBranch: sourceBranch,
      if (reusesExistingBranch != null)
        #reusesExistingBranch: reusesExistingBranch,
      if (instanceId != $none) #instanceId: instanceId,
      if (hostId != null) #hostId: hostId,
      if (isPinned != null) #isPinned: isPinned,
      if (tagIds != null) #tagIds: tagIds,
      if (tagNames != null) #tagNames: tagNames,
      if (parentWorkspaceId != $none) #parentWorkspaceId: parentWorkspaceId,
      if (childCount != null) #childCount: childCount,
    }),
  );
  @override
  Workspace $make(CopyWithData data) => Workspace(
    id: data.get(#id, or: $value.id),
    projectId: data.get(#projectId, or: $value.projectId),
    name: data.get(#name, or: $value.name),
    path: data.get(#path, or: $value.path),
    createdAt: data.get(#createdAt, or: $value.createdAt),
    updatedAt: data.get(#updatedAt, or: $value.updatedAt),
    kind: data.get(#kind, or: $value.kind),
    status: data.get(#status, or: $value.status),
    branch: data.get(#branch, or: $value.branch),
    sourceBranch: data.get(#sourceBranch, or: $value.sourceBranch),
    reusesExistingBranch: data.get(
      #reusesExistingBranch,
      or: $value.reusesExistingBranch,
    ),
    instanceId: data.get(#instanceId, or: $value.instanceId),
    hostId: data.get(#hostId, or: $value.hostId),
    isPinned: data.get(#isPinned, or: $value.isPinned),
    tagIds: data.get(#tagIds, or: $value.tagIds),
    tagNames: data.get(#tagNames, or: $value.tagNames),
    parentWorkspaceId: data.get(
      #parentWorkspaceId,
      or: $value.parentWorkspaceId,
    ),
    childCount: data.get(#childCount, or: $value.childCount),
  );

  @override
  WorkspaceCopyWith<$R2, Workspace, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _WorkspaceCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

