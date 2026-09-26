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

class ProjectCheckoutMapper extends ClassMapperBase<ProjectCheckout> {
  ProjectCheckoutMapper._();

  static ProjectCheckoutMapper? _instance;
  static ProjectCheckoutMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProjectCheckoutMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'ProjectCheckout';

  static String _$hostId(ProjectCheckout v) => v.hostId;
  static const Field<ProjectCheckout, String> _f$hostId = Field(
    'hostId',
    _$hostId,
  );
  static String _$path(ProjectCheckout v) => v.path;
  static const Field<ProjectCheckout, String> _f$path = Field('path', _$path);

  @override
  final MappableFields<ProjectCheckout> fields = const {
    #hostId: _f$hostId,
    #path: _f$path,
  };

  static ProjectCheckout _instantiate(DecodingData data) {
    return ProjectCheckout(
      hostId: data.dec(_f$hostId),
      path: data.dec(_f$path),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ProjectCheckout fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ProjectCheckout>(map);
  }

  static ProjectCheckout fromJson(String json) {
    return ensureInitialized().decodeJson<ProjectCheckout>(json);
  }
}

mixin ProjectCheckoutMappable {
  String toJson() {
    return ProjectCheckoutMapper.ensureInitialized()
        .encodeJson<ProjectCheckout>(this as ProjectCheckout);
  }

  Map<String, dynamic> toMap() {
    return ProjectCheckoutMapper.ensureInitialized().encodeMap<ProjectCheckout>(
      this as ProjectCheckout,
    );
  }

  ProjectCheckoutCopyWith<ProjectCheckout, ProjectCheckout, ProjectCheckout>
  get copyWith =>
      _ProjectCheckoutCopyWithImpl<ProjectCheckout, ProjectCheckout>(
        this as ProjectCheckout,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return ProjectCheckoutMapper.ensureInitialized().stringifyValue(
      this as ProjectCheckout,
    );
  }

  @override
  bool operator ==(Object other) {
    return ProjectCheckoutMapper.ensureInitialized().equalsValue(
      this as ProjectCheckout,
      other,
    );
  }

  @override
  int get hashCode {
    return ProjectCheckoutMapper.ensureInitialized().hashValue(
      this as ProjectCheckout,
    );
  }
}

extension ProjectCheckoutValueCopy<$R, $Out>
    on ObjectCopyWith<$R, ProjectCheckout, $Out> {
  ProjectCheckoutCopyWith<$R, ProjectCheckout, $Out> get $asProjectCheckout =>
      $base.as((v, t, t2) => _ProjectCheckoutCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class ProjectCheckoutCopyWith<$R, $In extends ProjectCheckout, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({String? hostId, String? path});
  ProjectCheckoutCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _ProjectCheckoutCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, ProjectCheckout, $Out>
    implements ProjectCheckoutCopyWith<$R, ProjectCheckout, $Out> {
  _ProjectCheckoutCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<ProjectCheckout> $mapper =
      ProjectCheckoutMapper.ensureInitialized();
  @override
  $R call({String? hostId, String? path}) => $apply(
    FieldCopyWithData({
      if (hostId != null) #hostId: hostId,
      if (path != null) #path: path,
    }),
  );
  @override
  ProjectCheckout $make(CopyWithData data) => ProjectCheckout(
    hostId: data.get(#hostId, or: $value.hostId),
    path: data.get(#path, or: $value.path),
  );

  @override
  ProjectCheckoutCopyWith<$R2, ProjectCheckout, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _ProjectCheckoutCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class ProjectMapper extends ClassMapperBase<Project> {
  ProjectMapper._();

  static ProjectMapper? _instance;
  static ProjectMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProjectMapper._());
      ProjectKindMapper.ensureInitialized();
      ProjectCheckoutMapper.ensureInitialized();
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
  static String _$primaryHostId(Project v) => v.primaryHostId;
  static const Field<Project, String> _f$primaryHostId = Field(
    'primaryHostId',
    _$primaryHostId,
    opt: true,
    def: 'local',
  );
  static List<ProjectCheckout> _$checkouts(Project v) => v.checkouts;
  static const Field<Project, List<ProjectCheckout>> _f$checkouts = Field(
    'checkouts',
    _$checkouts,
    opt: true,
    def: const <ProjectCheckout>[],
  );

  @override
  final MappableFields<Project> fields = const {
    #id: _f$id,
    #name: _f$name,
    #repoPath: _f$repoPath,
    #createdAt: _f$createdAt,
    #updatedAt: _f$updatedAt,
    #kind: _f$kind,
    #primaryHostId: _f$primaryHostId,
    #checkouts: _f$checkouts,
  };

  static Project _instantiate(DecodingData data) {
    return Project(
      id: data.dec(_f$id),
      name: data.dec(_f$name),
      repoPath: data.dec(_f$repoPath),
      createdAt: data.dec(_f$createdAt),
      updatedAt: data.dec(_f$updatedAt),
      kind: data.dec(_f$kind),
      primaryHostId: data.dec(_f$primaryHostId),
      checkouts: data.dec(_f$checkouts),
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
  ListCopyWith<
    $R,
    ProjectCheckout,
    ProjectCheckoutCopyWith<$R, ProjectCheckout, ProjectCheckout>
  >
  get checkouts;
  $R call({
    String? id,
    String? name,
    String? repoPath,
    DateTime? createdAt,
    DateTime? updatedAt,
    ProjectKind? kind,
    String? primaryHostId,
    List<ProjectCheckout>? checkouts,
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
  ListCopyWith<
    $R,
    ProjectCheckout,
    ProjectCheckoutCopyWith<$R, ProjectCheckout, ProjectCheckout>
  >
  get checkouts => ListCopyWith(
    $value.checkouts,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(checkouts: v),
  );
  @override
  $R call({
    String? id,
    String? name,
    String? repoPath,
    DateTime? createdAt,
    DateTime? updatedAt,
    ProjectKind? kind,
    String? primaryHostId,
    List<ProjectCheckout>? checkouts,
  }) => $apply(
    FieldCopyWithData({
      if (id != null) #id: id,
      if (name != null) #name: name,
      if (repoPath != null) #repoPath: repoPath,
      if (createdAt != null) #createdAt: createdAt,
      if (updatedAt != null) #updatedAt: updatedAt,
      if (kind != null) #kind: kind,
      if (primaryHostId != null) #primaryHostId: primaryHostId,
      if (checkouts != null) #checkouts: checkouts,
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
    primaryHostId: data.get(#primaryHostId, or: $value.primaryHostId),
    checkouts: data.get(#checkouts, or: $value.checkouts),
  );

  @override
  ProjectCopyWith<$R2, Project, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _ProjectCopyWithImpl<$R2, $Out2>($value, $cast, t);
}
