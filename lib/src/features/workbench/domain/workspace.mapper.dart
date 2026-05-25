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
  );

  @override
  WorkspaceCopyWith<$R2, Workspace, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _WorkspaceCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

