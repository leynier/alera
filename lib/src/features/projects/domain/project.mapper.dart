// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'project.dart';

class ProjectKindMapper extends EnumMapper<ProjectKind> {
  ProjectKindMapper._();

  static ProjectKindMapper? _instance;
  static ProjectKindMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProjectKindMapper._());
    }
    return _instance!;
  }

  static ProjectKind fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  ProjectKind decode(dynamic value) {
    switch (value) {
      case r'gitRepository':
        return ProjectKind.gitRepository;
      case r'folder':
        return ProjectKind.folder;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(ProjectKind self) {
    switch (self) {
      case ProjectKind.gitRepository:
        return r'gitRepository';
      case ProjectKind.folder:
        return r'folder';
    }
  }
}

extension ProjectKindMapperExtension on ProjectKind {
  String toValue() {
    ProjectKindMapper.ensureInitialized();
    return MapperContainer.globals.toValue<ProjectKind>(this) as String;
  }
}

class ProjectMapper extends ClassMapperBase<Project> {
  ProjectMapper._();

  static ProjectMapper? _instance;
  static ProjectMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProjectMapper._());
      ProjectKindMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'Project';

  static String _$id(Project v) => v.id;
  static const Field<Project, String> _f$id = Field('id', _$id);
  static String _$name(Project v) => v.name;
  static const Field<Project, String> _f$name = Field('name', _$name);
  static String _$repoPath(Project v) => v.repoPath;
  static const Field<Project, String> _f$repoPath = Field(
    'repoPath',
    _$repoPath,
  );
  static DateTime _$createdAt(Project v) => v.createdAt;
  static const Field<Project, DateTime> _f$createdAt = Field(
    'createdAt',
    _$createdAt,
  );
  static DateTime _$updatedAt(Project v) => v.updatedAt;
  static const Field<Project, DateTime> _f$updatedAt = Field(
    'updatedAt',
    _$updatedAt,
  );
  static ProjectKind _$kind(Project v) => v.kind;
  static const Field<Project, ProjectKind> _f$kind = Field(
    'kind',
    _$kind,
    opt: true,
    def: ProjectKind.gitRepository,
  );

  @override
  final MappableFields<Project> fields = const {
    #id: _f$id,
    #name: _f$name,
    #repoPath: _f$repoPath,
    #createdAt: _f$createdAt,
    #updatedAt: _f$updatedAt,
    #kind: _f$kind,
  };

  static Project _instantiate(DecodingData data) {
    return Project(
      id: data.dec(_f$id),
      name: data.dec(_f$name),
      repoPath: data.dec(_f$repoPath),
      createdAt: data.dec(_f$createdAt),
      updatedAt: data.dec(_f$updatedAt),
      kind: data.dec(_f$kind),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static Project fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<Project>(map);
  }

  static Project fromJson(String json) {
    return ensureInitialized().decodeJson<Project>(json);
  }
}

mixin ProjectMappable {
  String toJson() {
    return ProjectMapper.ensureInitialized().encodeJson<Project>(
      this as Project,
    );
  }

  Map<String, dynamic> toMap() {
    return ProjectMapper.ensureInitialized().encodeMap<Project>(
      this as Project,
    );
  }

  ProjectCopyWith<Project, Project, Project> get copyWith =>
      _ProjectCopyWithImpl<Project, Project>(
        this as Project,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return ProjectMapper.ensureInitialized().stringifyValue(this as Project);
  }

  @override
  bool operator ==(Object other) {
    return ProjectMapper.ensureInitialized().equalsValue(
      this as Project,
      other,
    );
  }

  @override
  int get hashCode {
    return ProjectMapper.ensureInitialized().hashValue(this as Project);
  }
}

extension ProjectValueCopy<$R, $Out> on ObjectCopyWith<$R, Project, $Out> {
  ProjectCopyWith<$R, Project, $Out> get $asProject =>
      $base.as((v, t, t2) => _ProjectCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class ProjectCopyWith<$R, $In extends Project, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    String? id,
    String? name,
    String? repoPath,
    DateTime? createdAt,
    DateTime? updatedAt,
    ProjectKind? kind,
  });
  ProjectCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _ProjectCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, Project, $Out>
    implements ProjectCopyWith<$R, Project, $Out> {
  _ProjectCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<Project> $mapper =
      ProjectMapper.ensureInitialized();
  @override
  $R call({
    String? id,
    String? name,
    String? repoPath,
    DateTime? createdAt,
    DateTime? updatedAt,
    ProjectKind? kind,
  }) => $apply(
    FieldCopyWithData({
      if (id != null) #id: id,
      if (name != null) #name: name,
      if (repoPath != null) #repoPath: repoPath,
      if (createdAt != null) #createdAt: createdAt,
      if (updatedAt != null) #updatedAt: updatedAt,
      if (kind != null) #kind: kind,
    }),
  );
  @override
  Project $make(CopyWithData data) => Project(
    id: data.get(#id, or: $value.id),
    name: data.get(#name, or: $value.name),
    repoPath: data.get(#repoPath, or: $value.repoPath),
    createdAt: data.get(#createdAt, or: $value.createdAt),
    updatedAt: data.get(#updatedAt, or: $value.updatedAt),
    kind: data.get(#kind, or: $value.kind),
  );

  @override
  ProjectCopyWith<$R2, Project, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _ProjectCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

