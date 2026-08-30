// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'dart_constructor_compatibility.dart';

class RecordRoleMapper extends EnumMapper<RecordRole> {
  RecordRoleMapper._();

  static RecordRoleMapper? _instance;
  static RecordRoleMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RecordRoleMapper._());
    }
    return _instance!;
  }

  static RecordRole fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  RecordRole decode(dynamic value) {
    switch (value) {
      case 'read':
        return RecordRole.reader;
      case 'write':
        return RecordRole.writer;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(RecordRole self) {
    switch (self) {
      case RecordRole.reader:
        return 'read';
      case RecordRole.writer:
        return 'write';
    }
  }
}

extension RecordRoleMapperExtension on RecordRole {
  dynamic toValue() {
    RecordRoleMapper.ensureInitialized();
    return MapperContainer.globals.toValue<RecordRole>(this);
  }
}

class BaseRecordMapper extends ClassMapperBase<BaseRecord> {
  BaseRecordMapper._();

  static BaseRecordMapper? _instance;
  static BaseRecordMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = BaseRecordMapper._());
      ChildRecordMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'BaseRecord';

  static String _$id(BaseRecord v) => v.id;
  static const Field<BaseRecord, String> _f$id = Field(
    'id',
    _$id,
    key: r'record_id',
  );

  @override
  final MappableFields<BaseRecord> fields = const {#id: _f$id};

  static BaseRecord _instantiate(DecodingData data) {
    return BaseRecord(data.dec(_f$id));
  }

  @override
  final Function instantiate = _instantiate;

  static BaseRecord fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<BaseRecord>(map);
  }

  static BaseRecord fromJson(String json) {
    return ensureInitialized().decodeJson<BaseRecord>(json);
  }
}

mixin BaseRecordMappable {
  String toJson() {
    return BaseRecordMapper.ensureInitialized().encodeJson<BaseRecord>(
      this as BaseRecord,
    );
  }

  Map<String, dynamic> toMap() {
    return BaseRecordMapper.ensureInitialized().encodeMap<BaseRecord>(
      this as BaseRecord,
    );
  }

  BaseRecordCopyWith<BaseRecord, BaseRecord, BaseRecord> get copyWith =>
      _BaseRecordCopyWithImpl<BaseRecord, BaseRecord>(
        this as BaseRecord,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return BaseRecordMapper.ensureInitialized().stringifyValue(
      this as BaseRecord,
    );
  }

  @override
  bool operator ==(Object other) {
    return BaseRecordMapper.ensureInitialized().equalsValue(
      this as BaseRecord,
      other,
    );
  }

  @override
  int get hashCode {
    return BaseRecordMapper.ensureInitialized().hashValue(this as BaseRecord);
  }
}

extension BaseRecordValueCopy<$R, $Out>
    on ObjectCopyWith<$R, BaseRecord, $Out> {
  BaseRecordCopyWith<$R, BaseRecord, $Out> get $asBaseRecord =>
      $base.as((v, t, t2) => _BaseRecordCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class BaseRecordCopyWith<$R, $In extends BaseRecord, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({String? id});
  BaseRecordCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _BaseRecordCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, BaseRecord, $Out>
    implements BaseRecordCopyWith<$R, BaseRecord, $Out> {
  _BaseRecordCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<BaseRecord> $mapper =
      BaseRecordMapper.ensureInitialized();
  @override
  $R call({String? id}) => $apply(FieldCopyWithData({if (id != null) #id: id}));
  @override
  BaseRecord $make(CopyWithData data) =>
      BaseRecord(data.get(#id, or: $value.id));

  @override
  BaseRecordCopyWith<$R2, BaseRecord, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _BaseRecordCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class ChildRecordMapper extends ClassMapperBase<ChildRecord> {
  ChildRecordMapper._();

  static ChildRecordMapper? _instance;
  static ChildRecordMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ChildRecordMapper._());
      BaseRecordMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ChildRecord';

  static String _$id(ChildRecord v) => v.id;
  static const Field<ChildRecord, String> _f$id = Field(
    'id',
    _$id,
    key: r'record_id',
  );
  static String _$label(ChildRecord v) => v.label;
  static const Field<ChildRecord, String> _f$label = Field(
    'label',
    _$label,
    opt: true,
    def: 'default',
  );
  static List<String> _$values(ChildRecord v) => v.values;
  static const Field<ChildRecord, List<String>> _f$values = Field(
    'values',
    _$values,
    opt: true,
    def: const [],
  );

  @override
  final MappableFields<ChildRecord> fields = const {
    #id: _f$id,
    #label: _f$label,
    #values: _f$values,
  };

  static ChildRecord _instantiate(DecodingData data) {
    return ChildRecord(
      data.dec(_f$id),
      label: data.dec(_f$label),
      values: data.dec(_f$values),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ChildRecord fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ChildRecord>(map);
  }

  static ChildRecord fromJson(String json) {
    return ensureInitialized().decodeJson<ChildRecord>(json);
  }
}

mixin ChildRecordMappable {
  String toJson() {
    return ChildRecordMapper.ensureInitialized().encodeJson<ChildRecord>(
      this as ChildRecord,
    );
  }

  Map<String, dynamic> toMap() {
    return ChildRecordMapper.ensureInitialized().encodeMap<ChildRecord>(
      this as ChildRecord,
    );
  }

  ChildRecordCopyWith<ChildRecord, ChildRecord, ChildRecord> get copyWith =>
      _ChildRecordCopyWithImpl<ChildRecord, ChildRecord>(
        this as ChildRecord,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return ChildRecordMapper.ensureInitialized().stringifyValue(
      this as ChildRecord,
    );
  }

  @override
  bool operator ==(Object other) {
    return ChildRecordMapper.ensureInitialized().equalsValue(
      this as ChildRecord,
      other,
    );
  }

  @override
  int get hashCode {
    return ChildRecordMapper.ensureInitialized().hashValue(this as ChildRecord);
  }
}

extension ChildRecordValueCopy<$R, $Out>
    on ObjectCopyWith<$R, ChildRecord, $Out> {
  ChildRecordCopyWith<$R, ChildRecord, $Out> get $asChildRecord =>
      $base.as((v, t, t2) => _ChildRecordCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class ChildRecordCopyWith<$R, $In extends ChildRecord, $Out>
    implements BaseRecordCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get values;
  @override
  $R call({String? id, String? label, List<String>? values});
  ChildRecordCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _ChildRecordCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, ChildRecord, $Out>
    implements ChildRecordCopyWith<$R, ChildRecord, $Out> {
  _ChildRecordCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<ChildRecord> $mapper =
      ChildRecordMapper.ensureInitialized();
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get values =>
      ListCopyWith(
        $value.values,
        (v, t) => ObjectCopyWith(v, $identity, t),
        (v) => call(values: v),
      );
  @override
  $R call({String? id, String? label, List<String>? values}) => $apply(
    FieldCopyWithData({
      if (id != null) #id: id,
      if (label != null) #label: label,
      if (values != null) #values: values,
    }),
  );
  @override
  ChildRecord $make(CopyWithData data) => ChildRecord(
    data.get(#id, or: $value.id),
    label: data.get(#label, or: $value.label),
    values: data.get(#values, or: $value.values),
  );

  @override
  ChildRecordCopyWith<$R2, ChildRecord, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _ChildRecordCopyWithImpl<$R2, $Out2>($value, $cast, t);
}
