// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'run_board_location.dart';

class RunBoardLocationMapper extends ClassMapperBase<RunBoardLocation> {
  RunBoardLocationMapper._();

  static RunBoardLocationMapper? _instance;
  static RunBoardLocationMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RunBoardLocationMapper._());
      RunBoardBucketMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'RunBoardLocation';

  static bool _$visible(RunBoardLocation v) => v.visible;
  static const Field<RunBoardLocation, bool> _f$visible = Field(
    'visible',
    _$visible,
    opt: true,
    def: false,
  );
  static String? _$projectId(RunBoardLocation v) => v.projectId;
  static const Field<RunBoardLocation, String> _f$projectId = Field(
    'projectId',
    _$projectId,
    opt: true,
  );
  static String? _$workspaceId(RunBoardLocation v) => v.workspaceId;
  static const Field<RunBoardLocation, String> _f$workspaceId = Field(
    'workspaceId',
    _$workspaceId,
    opt: true,
  );
  static String _$search(RunBoardLocation v) => v.search;
  static const Field<RunBoardLocation, String> _f$search = Field(
    'search',
    _$search,
    opt: true,
    def: '',
  );
  static RunBoardBucket? _$bucket(RunBoardLocation v) => v.bucket;
  static const Field<RunBoardLocation, RunBoardBucket> _f$bucket = Field(
    'bucket',
    _$bucket,
    opt: true,
  );
  static String? _$runId(RunBoardLocation v) => v.runId;
  static const Field<RunBoardLocation, String> _f$runId = Field(
    'runId',
    _$runId,
    opt: true,
  );
  static String? _$taskId(RunBoardLocation v) => v.taskId;
  static const Field<RunBoardLocation, String> _f$taskId = Field(
    'taskId',
    _$taskId,
    opt: true,
  );

  @override
  final MappableFields<RunBoardLocation> fields = const {
    #visible: _f$visible,
    #projectId: _f$projectId,
    #workspaceId: _f$workspaceId,
    #search: _f$search,
    #bucket: _f$bucket,
    #runId: _f$runId,
    #taskId: _f$taskId,
  };

  static RunBoardLocation _instantiate(DecodingData data) {
    return RunBoardLocation(
      visible: data.dec(_f$visible),
      projectId: data.dec(_f$projectId),
      workspaceId: data.dec(_f$workspaceId),
      search: data.dec(_f$search),
      bucket: data.dec(_f$bucket),
      runId: data.dec(_f$runId),
      taskId: data.dec(_f$taskId),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static RunBoardLocation fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<RunBoardLocation>(map);
  }

  static RunBoardLocation fromJson(String json) {
    return ensureInitialized().decodeJson<RunBoardLocation>(json);
  }
}

mixin RunBoardLocationMappable {
  String toJson() {
    return RunBoardLocationMapper.ensureInitialized()
        .encodeJson<RunBoardLocation>(this as RunBoardLocation);
  }

  Map<String, dynamic> toMap() {
    return RunBoardLocationMapper.ensureInitialized()
        .encodeMap<RunBoardLocation>(this as RunBoardLocation);
  }

  RunBoardLocationCopyWith<RunBoardLocation, RunBoardLocation, RunBoardLocation>
  get copyWith =>
      _RunBoardLocationCopyWithImpl<RunBoardLocation, RunBoardLocation>(
        this as RunBoardLocation,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return RunBoardLocationMapper.ensureInitialized().stringifyValue(
      this as RunBoardLocation,
    );
  }

  @override
  bool operator ==(Object other) {
    return RunBoardLocationMapper.ensureInitialized().equalsValue(
      this as RunBoardLocation,
      other,
    );
  }

  @override
  int get hashCode {
    return RunBoardLocationMapper.ensureInitialized().hashValue(
      this as RunBoardLocation,
    );
  }
}

extension RunBoardLocationValueCopy<$R, $Out>
    on ObjectCopyWith<$R, RunBoardLocation, $Out> {
  RunBoardLocationCopyWith<$R, RunBoardLocation, $Out>
  get $asRunBoardLocation =>
      $base.as((v, t, t2) => _RunBoardLocationCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class RunBoardLocationCopyWith<$R, $In extends RunBoardLocation, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    bool? visible,
    String? projectId,
    String? workspaceId,
    String? search,
    RunBoardBucket? bucket,
    String? runId,
    String? taskId,
  });
  RunBoardLocationCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _RunBoardLocationCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, RunBoardLocation, $Out>
    implements RunBoardLocationCopyWith<$R, RunBoardLocation, $Out> {
  _RunBoardLocationCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<RunBoardLocation> $mapper =
      RunBoardLocationMapper.ensureInitialized();
  @override
  $R call({
    bool? visible,
    Object? projectId = $none,
    Object? workspaceId = $none,
    String? search,
    Object? bucket = $none,
    Object? runId = $none,
    Object? taskId = $none,
  }) => $apply(
    FieldCopyWithData({
      if (visible != null) #visible: visible,
      if (projectId != $none) #projectId: projectId,
      if (workspaceId != $none) #workspaceId: workspaceId,
      if (search != null) #search: search,
      if (bucket != $none) #bucket: bucket,
      if (runId != $none) #runId: runId,
      if (taskId != $none) #taskId: taskId,
    }),
  );
  @override
  RunBoardLocation $make(CopyWithData data) => RunBoardLocation(
    visible: data.get(#visible, or: $value.visible),
    projectId: data.get(#projectId, or: $value.projectId),
    workspaceId: data.get(#workspaceId, or: $value.workspaceId),
    search: data.get(#search, or: $value.search),
    bucket: data.get(#bucket, or: $value.bucket),
    runId: data.get(#runId, or: $value.runId),
    taskId: data.get(#taskId, or: $value.taskId),
  );

  @override
  RunBoardLocationCopyWith<$R2, RunBoardLocation, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _RunBoardLocationCopyWithImpl<$R2, $Out2>($value, $cast, t);
}
