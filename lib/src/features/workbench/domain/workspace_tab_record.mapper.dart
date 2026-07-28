// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'workspace_tab_record.dart';

class WorkspaceTabKindMapper extends EnumMapper<WorkspaceTabKind> {
  WorkspaceTabKindMapper._();

  static WorkspaceTabKindMapper? _instance;
  static WorkspaceTabKindMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = WorkspaceTabKindMapper._());
    }
    return _instance!;
  }

  static WorkspaceTabKind fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  WorkspaceTabKind decode(dynamic value) {
    switch (value) {
      case r'terminal':
        return WorkspaceTabKind.terminal;
      case r'editor':
        return WorkspaceTabKind.editor;
      case r'markdownViewer':
        return WorkspaceTabKind.markdownViewer;
      case r'pdf':
        return WorkspaceTabKind.pdf;
      case r'gitDiff':
        return WorkspaceTabKind.gitDiff;
      case r'browser':
        return WorkspaceTabKind.browser;
      case r'mobileEmulator':
        return WorkspaceTabKind.mobileEmulator;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(WorkspaceTabKind self) {
    switch (self) {
      case WorkspaceTabKind.terminal:
        return r'terminal';
      case WorkspaceTabKind.editor:
        return r'editor';
      case WorkspaceTabKind.markdownViewer:
        return r'markdownViewer';
      case WorkspaceTabKind.pdf:
        return r'pdf';
      case WorkspaceTabKind.gitDiff:
        return r'gitDiff';
      case WorkspaceTabKind.browser:
        return r'browser';
      case WorkspaceTabKind.mobileEmulator:
        return r'mobileEmulator';
    }
  }
}

extension WorkspaceTabKindMapperExtension on WorkspaceTabKind {
  String toValue() {
    WorkspaceTabKindMapper.ensureInitialized();
    return MapperContainer.globals.toValue<WorkspaceTabKind>(this) as String;
  }
}

class WorkspaceTabRecordMapper extends ClassMapperBase<WorkspaceTabRecord> {
  WorkspaceTabRecordMapper._();

  static WorkspaceTabRecordMapper? _instance;
  static WorkspaceTabRecordMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = WorkspaceTabRecordMapper._());
      WorkspaceTabKindMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'WorkspaceTabRecord';

  static String _$id(WorkspaceTabRecord v) => v.id;
  static const Field<WorkspaceTabRecord, String> _f$id = Field('id', _$id);
  static String _$workspaceId(WorkspaceTabRecord v) => v.workspaceId;
  static const Field<WorkspaceTabRecord, String> _f$workspaceId = Field(
    'workspaceId',
    _$workspaceId,
  );
  static String _$title(WorkspaceTabRecord v) => v.title;
  static const Field<WorkspaceTabRecord, String> _f$title = Field(
    'title',
    _$title,
  );
  static DateTime _$createdAt(WorkspaceTabRecord v) => v.createdAt;
  static const Field<WorkspaceTabRecord, DateTime> _f$createdAt = Field(
    'createdAt',
    _$createdAt,
  );
  static DateTime _$updatedAt(WorkspaceTabRecord v) => v.updatedAt;
  static const Field<WorkspaceTabRecord, DateTime> _f$updatedAt = Field(
    'updatedAt',
    _$updatedAt,
  );
  static WorkspaceTabKind _$kind(WorkspaceTabRecord v) => v.kind;
  static const Field<WorkspaceTabRecord, WorkspaceTabKind> _f$kind = Field(
    'kind',
    _$kind,
    opt: true,
    def: WorkspaceTabKind.terminal,
  );
  static Map<String, Object?> _$payload(WorkspaceTabRecord v) => v.payload;
  static const Field<WorkspaceTabRecord, Map<String, Object?>> _f$payload =
      Field('payload', _$payload, opt: true, def: const <String, Object?>{});

  @override
  final MappableFields<WorkspaceTabRecord> fields = const {
    #id: _f$id,
    #workspaceId: _f$workspaceId,
    #title: _f$title,
    #createdAt: _f$createdAt,
    #updatedAt: _f$updatedAt,
    #kind: _f$kind,
    #payload: _f$payload,
  };

  static WorkspaceTabRecord _instantiate(DecodingData data) {
    return WorkspaceTabRecord(
      id: data.dec(_f$id),
      workspaceId: data.dec(_f$workspaceId),
      title: data.dec(_f$title),
      createdAt: data.dec(_f$createdAt),
      updatedAt: data.dec(_f$updatedAt),
      kind: data.dec(_f$kind),
      payload: data.dec(_f$payload),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static WorkspaceTabRecord fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<WorkspaceTabRecord>(map);
  }

  static WorkspaceTabRecord fromJson(String json) {
    return ensureInitialized().decodeJson<WorkspaceTabRecord>(json);
  }
}

mixin WorkspaceTabRecordMappable {
  String toJson() {
    return WorkspaceTabRecordMapper.ensureInitialized()
        .encodeJson<WorkspaceTabRecord>(this as WorkspaceTabRecord);
  }

  Map<String, dynamic> toMap() {
    return WorkspaceTabRecordMapper.ensureInitialized()
        .encodeMap<WorkspaceTabRecord>(this as WorkspaceTabRecord);
  }

  WorkspaceTabRecordCopyWith<
    WorkspaceTabRecord,
    WorkspaceTabRecord,
    WorkspaceTabRecord
  >
  get copyWith =>
      _WorkspaceTabRecordCopyWithImpl<WorkspaceTabRecord, WorkspaceTabRecord>(
        this as WorkspaceTabRecord,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return WorkspaceTabRecordMapper.ensureInitialized().stringifyValue(
      this as WorkspaceTabRecord,
    );
  }

  @override
  bool operator ==(Object other) {
    return WorkspaceTabRecordMapper.ensureInitialized().equalsValue(
      this as WorkspaceTabRecord,
      other,
    );
  }

  @override
  int get hashCode {
    return WorkspaceTabRecordMapper.ensureInitialized().hashValue(
      this as WorkspaceTabRecord,
    );
  }
}

extension WorkspaceTabRecordValueCopy<$R, $Out>
    on ObjectCopyWith<$R, WorkspaceTabRecord, $Out> {
  WorkspaceTabRecordCopyWith<$R, WorkspaceTabRecord, $Out>
  get $asWorkspaceTabRecord => $base.as(
    (v, t, t2) => _WorkspaceTabRecordCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class WorkspaceTabRecordCopyWith<
  $R,
  $In extends WorkspaceTabRecord,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  MapCopyWith<$R, String, Object?, ObjectCopyWith<$R, Object?, Object?>?>
  get payload;
  $R call({
    String? id,
    String? workspaceId,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
    WorkspaceTabKind? kind,
    Map<String, Object?>? payload,
  });
  WorkspaceTabRecordCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _WorkspaceTabRecordCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, WorkspaceTabRecord, $Out>
    implements WorkspaceTabRecordCopyWith<$R, WorkspaceTabRecord, $Out> {
  _WorkspaceTabRecordCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<WorkspaceTabRecord> $mapper =
      WorkspaceTabRecordMapper.ensureInitialized();
  @override
  MapCopyWith<$R, String, Object?, ObjectCopyWith<$R, Object?, Object?>?>
  get payload => MapCopyWith(
    $value.payload,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(payload: v),
  );
  @override
  $R call({
    String? id,
    String? workspaceId,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
    WorkspaceTabKind? kind,
    Map<String, Object?>? payload,
  }) => $apply(
    FieldCopyWithData({
      if (id != null) #id: id,
      if (workspaceId != null) #workspaceId: workspaceId,
      if (title != null) #title: title,
      if (createdAt != null) #createdAt: createdAt,
      if (updatedAt != null) #updatedAt: updatedAt,
      if (kind != null) #kind: kind,
      if (payload != null) #payload: payload,
    }),
  );
  @override
  WorkspaceTabRecord $make(CopyWithData data) => WorkspaceTabRecord(
    id: data.get(#id, or: $value.id),
    workspaceId: data.get(#workspaceId, or: $value.workspaceId),
    title: data.get(#title, or: $value.title),
    createdAt: data.get(#createdAt, or: $value.createdAt),
    updatedAt: data.get(#updatedAt, or: $value.updatedAt),
    kind: data.get(#kind, or: $value.kind),
    payload: data.get(#payload, or: $value.payload),
  );

  @override
  WorkspaceTabRecordCopyWith<$R2, WorkspaceTabRecord, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _WorkspaceTabRecordCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

