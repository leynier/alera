// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'workspace_section.dart';

class WorkspaceSectionMapper extends ClassMapperBase<WorkspaceSection> {
  WorkspaceSectionMapper._();

  static WorkspaceSectionMapper? _instance;
  static WorkspaceSectionMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = WorkspaceSectionMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'WorkspaceSection';

  static String _$id(WorkspaceSection v) => v.id;
  static const Field<WorkspaceSection, String> _f$id = Field('id', _$id);
  static String _$name(WorkspaceSection v) => v.name;
  static const Field<WorkspaceSection, String> _f$name = Field('name', _$name);
  static DateTime _$createdAt(WorkspaceSection v) => v.createdAt;
  static const Field<WorkspaceSection, DateTime> _f$createdAt = Field(
    'createdAt',
    _$createdAt,
  );
  static DateTime _$updatedAt(WorkspaceSection v) => v.updatedAt;
  static const Field<WorkspaceSection, DateTime> _f$updatedAt = Field(
    'updatedAt',
    _$updatedAt,
  );

  @override
  final MappableFields<WorkspaceSection> fields = const {
    #id: _f$id,
    #name: _f$name,
    #createdAt: _f$createdAt,
    #updatedAt: _f$updatedAt,
  };

  static WorkspaceSection _instantiate(DecodingData data) {
    return WorkspaceSection(
      id: data.dec(_f$id),
      name: data.dec(_f$name),
      createdAt: data.dec(_f$createdAt),
      updatedAt: data.dec(_f$updatedAt),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static WorkspaceSection fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<WorkspaceSection>(map);
  }

  static WorkspaceSection fromJson(String json) {
    return ensureInitialized().decodeJson<WorkspaceSection>(json);
  }
}

mixin WorkspaceSectionMappable {
  String toJson() {
    return WorkspaceSectionMapper.ensureInitialized()
        .encodeJson<WorkspaceSection>(this as WorkspaceSection);
  }

  Map<String, dynamic> toMap() {
    return WorkspaceSectionMapper.ensureInitialized()
        .encodeMap<WorkspaceSection>(this as WorkspaceSection);
  }

  WorkspaceSectionCopyWith<WorkspaceSection, WorkspaceSection, WorkspaceSection>
  get copyWith =>
      _WorkspaceSectionCopyWithImpl<WorkspaceSection, WorkspaceSection>(
        this as WorkspaceSection,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return WorkspaceSectionMapper.ensureInitialized().stringifyValue(
      this as WorkspaceSection,
    );
  }

  @override
  bool operator ==(Object other) {
    return WorkspaceSectionMapper.ensureInitialized().equalsValue(
      this as WorkspaceSection,
      other,
    );
  }

  @override
  int get hashCode {
    return WorkspaceSectionMapper.ensureInitialized().hashValue(
      this as WorkspaceSection,
    );
  }
}

extension WorkspaceSectionValueCopy<$R, $Out>
    on ObjectCopyWith<$R, WorkspaceSection, $Out> {
  WorkspaceSectionCopyWith<$R, WorkspaceSection, $Out>
  get $asWorkspaceSection =>
      $base.as((v, t, t2) => _WorkspaceSectionCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class WorkspaceSectionCopyWith<$R, $In extends WorkspaceSection, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({String? id, String? name, DateTime? createdAt, DateTime? updatedAt});
  WorkspaceSectionCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _WorkspaceSectionCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, WorkspaceSection, $Out>
    implements WorkspaceSectionCopyWith<$R, WorkspaceSection, $Out> {
  _WorkspaceSectionCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<WorkspaceSection> $mapper =
      WorkspaceSectionMapper.ensureInitialized();
  @override
  $R call({
    String? id,
    String? name,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => $apply(
    FieldCopyWithData({
      if (id != null) #id: id,
      if (name != null) #name: name,
      if (createdAt != null) #createdAt: createdAt,
      if (updatedAt != null) #updatedAt: updatedAt,
    }),
  );
  @override
  WorkspaceSection $make(CopyWithData data) => WorkspaceSection(
    id: data.get(#id, or: $value.id),
    name: data.get(#name, or: $value.name),
    createdAt: data.get(#createdAt, or: $value.createdAt),
    updatedAt: data.get(#updatedAt, or: $value.updatedAt),
  );

  @override
  WorkspaceSectionCopyWith<$R2, WorkspaceSection, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _WorkspaceSectionCopyWithImpl<$R2, $Out2>($value, $cast, t);
}
