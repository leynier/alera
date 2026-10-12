// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'run_create_request.dart';

class RunIsolationMapper extends EnumMapper<RunIsolation> {
  RunIsolationMapper._();

  static RunIsolationMapper? _instance;
  static RunIsolationMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RunIsolationMapper._());
    }
    return _instance!;
  }

  static RunIsolation fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  RunIsolation decode(dynamic value) {
    switch (value) {
      case r'isolated':
        return RunIsolation.isolated;
      case r'shared':
        return RunIsolation.shared;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(RunIsolation self) {
    switch (self) {
      case RunIsolation.isolated:
        return r'isolated';
      case RunIsolation.shared:
        return r'shared';
    }
  }
}

extension RunIsolationMapperExtension on RunIsolation {
  String toValue() {
    RunIsolationMapper.ensureInitialized();
    return MapperContainer.globals.toValue<RunIsolation>(this) as String;
  }
}

class RunControlActionMapper extends EnumMapper<RunControlAction> {
  RunControlActionMapper._();

  static RunControlActionMapper? _instance;
  static RunControlActionMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RunControlActionMapper._());
    }
    return _instance!;
  }

  static RunControlAction fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  RunControlAction decode(dynamic value) {
    switch (value) {
      case r'cancel':
        return RunControlAction.cancel;
      case r'pause':
        return RunControlAction.pause;
      case r'resume':
        return RunControlAction.resume;
      case r'replan':
        return RunControlAction.replan;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(RunControlAction self) {
    switch (self) {
      case RunControlAction.cancel:
        return r'cancel';
      case RunControlAction.pause:
        return r'pause';
      case RunControlAction.resume:
        return r'resume';
      case RunControlAction.replan:
        return r'replan';
    }
  }
}

extension RunControlActionMapperExtension on RunControlAction {
  String toValue() {
    RunControlActionMapper.ensureInitialized();
    return MapperContainer.globals.toValue<RunControlAction>(this) as String;
  }
}

class RunCreateRequestMapper extends ClassMapperBase<RunCreateRequest> {
  RunCreateRequestMapper._();

  static RunCreateRequestMapper? _instance;
  static RunCreateRequestMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RunCreateRequestMapper._());
      RunIsolationMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'RunCreateRequest';

  static String _$requestId(RunCreateRequest v) => v.requestId;
  static const Field<RunCreateRequest, String> _f$requestId = Field(
    'requestId',
    _$requestId,
  );
  static String _$workspaceId(RunCreateRequest v) => v.workspaceId;
  static const Field<RunCreateRequest, String> _f$workspaceId = Field(
    'workspaceId',
    _$workspaceId,
  );
  static String _$objective(RunCreateRequest v) => v.objective;
  static const Field<RunCreateRequest, String> _f$objective = Field(
    'objective',
    _$objective,
  );
  static Map<String, Object?>? _$recipeSource(RunCreateRequest v) =>
      v.recipeSource;
  static const Field<RunCreateRequest, Map<String, Object?>> _f$recipeSource =
      Field('recipeSource', _$recipeSource, opt: true);
  static RunIsolation _$isolation(RunCreateRequest v) => v.isolation;
  static const Field<RunCreateRequest, RunIsolation> _f$isolation = Field(
    'isolation',
    _$isolation,
    opt: true,
    def: RunIsolation.isolated,
  );
  static String _$coordinatorProfileId(RunCreateRequest v) =>
      v.coordinatorProfileId;
  static const Field<RunCreateRequest, String> _f$coordinatorProfileId = Field(
    'coordinatorProfileId',
    _$coordinatorProfileId,
  );
  static Map<String, String> _$roleProfiles(RunCreateRequest v) =>
      v.roleProfiles;
  static const Field<RunCreateRequest, Map<String, String>> _f$roleProfiles =
      Field(
        'roleProfiles',
        _$roleProfiles,
        opt: true,
        def: const <String, String>{},
      );
  static String? _$workerProfileId(RunCreateRequest v) => v.workerProfileId;
  static const Field<RunCreateRequest, String> _f$workerProfileId = Field(
    'workerProfileId',
    _$workerProfileId,
    opt: true,
  );
  static int? _$maxConcurrent(RunCreateRequest v) => v.maxConcurrent;
  static const Field<RunCreateRequest, int> _f$maxConcurrent = Field(
    'maxConcurrent',
    _$maxConcurrent,
    opt: true,
  );
  static bool _$approvalRequired(RunCreateRequest v) => v.approvalRequired;
  static const Field<RunCreateRequest, bool> _f$approvalRequired = Field(
    'approvalRequired',
    _$approvalRequired,
    opt: true,
    def: false,
  );

  @override
  final MappableFields<RunCreateRequest> fields = const {
    #requestId: _f$requestId,
    #workspaceId: _f$workspaceId,
    #objective: _f$objective,
    #recipeSource: _f$recipeSource,
    #isolation: _f$isolation,
    #coordinatorProfileId: _f$coordinatorProfileId,
    #roleProfiles: _f$roleProfiles,
    #workerProfileId: _f$workerProfileId,
    #maxConcurrent: _f$maxConcurrent,
    #approvalRequired: _f$approvalRequired,
  };

  static RunCreateRequest _instantiate(DecodingData data) {
    return RunCreateRequest(
      requestId: data.dec(_f$requestId),
      workspaceId: data.dec(_f$workspaceId),
      objective: data.dec(_f$objective),
      recipeSource: data.dec(_f$recipeSource),
      isolation: data.dec(_f$isolation),
      coordinatorProfileId: data.dec(_f$coordinatorProfileId),
      roleProfiles: data.dec(_f$roleProfiles),
      workerProfileId: data.dec(_f$workerProfileId),
      maxConcurrent: data.dec(_f$maxConcurrent),
      approvalRequired: data.dec(_f$approvalRequired),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static RunCreateRequest fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<RunCreateRequest>(map);
  }

  static RunCreateRequest fromJson(String json) {
    return ensureInitialized().decodeJson<RunCreateRequest>(json);
  }
}

mixin RunCreateRequestMappable {
  String toJson() {
    return RunCreateRequestMapper.ensureInitialized()
        .encodeJson<RunCreateRequest>(this as RunCreateRequest);
  }

  Map<String, dynamic> toMap() {
    return RunCreateRequestMapper.ensureInitialized()
        .encodeMap<RunCreateRequest>(this as RunCreateRequest);
  }

  RunCreateRequestCopyWith<RunCreateRequest, RunCreateRequest, RunCreateRequest>
  get copyWith =>
      _RunCreateRequestCopyWithImpl<RunCreateRequest, RunCreateRequest>(
        this as RunCreateRequest,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return RunCreateRequestMapper.ensureInitialized().stringifyValue(
      this as RunCreateRequest,
    );
  }

  @override
  bool operator ==(Object other) {
    return RunCreateRequestMapper.ensureInitialized().equalsValue(
      this as RunCreateRequest,
      other,
    );
  }

  @override
  int get hashCode {
    return RunCreateRequestMapper.ensureInitialized().hashValue(
      this as RunCreateRequest,
    );
  }
}

extension RunCreateRequestValueCopy<$R, $Out>
    on ObjectCopyWith<$R, RunCreateRequest, $Out> {
  RunCreateRequestCopyWith<$R, RunCreateRequest, $Out>
  get $asRunCreateRequest =>
      $base.as((v, t, t2) => _RunCreateRequestCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class RunCreateRequestCopyWith<$R, $In extends RunCreateRequest, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  MapCopyWith<$R, String, Object?, ObjectCopyWith<$R, Object?, Object?>?>?
  get recipeSource;
  MapCopyWith<$R, String, String, ObjectCopyWith<$R, String, String>>
  get roleProfiles;
  $R call({
    String? requestId,
    String? workspaceId,
    String? objective,
    Map<String, Object?>? recipeSource,
    RunIsolation? isolation,
    String? coordinatorProfileId,
    Map<String, String>? roleProfiles,
    String? workerProfileId,
    int? maxConcurrent,
    bool? approvalRequired,
  });
  RunCreateRequestCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _RunCreateRequestCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, RunCreateRequest, $Out>
    implements RunCreateRequestCopyWith<$R, RunCreateRequest, $Out> {
  _RunCreateRequestCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<RunCreateRequest> $mapper =
      RunCreateRequestMapper.ensureInitialized();
  @override
  MapCopyWith<$R, String, Object?, ObjectCopyWith<$R, Object?, Object?>?>?
  get recipeSource => $value.recipeSource != null
      ? MapCopyWith(
          $value.recipeSource!,
          (v, t) => ObjectCopyWith(v, $identity, t),
          (v) => call(recipeSource: v),
        )
      : null;
  @override
  MapCopyWith<$R, String, String, ObjectCopyWith<$R, String, String>>
  get roleProfiles => MapCopyWith(
    $value.roleProfiles,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(roleProfiles: v),
  );
  @override
  $R call({
    String? requestId,
    String? workspaceId,
    String? objective,
    Object? recipeSource = $none,
    RunIsolation? isolation,
    String? coordinatorProfileId,
    Map<String, String>? roleProfiles,
    Object? workerProfileId = $none,
    Object? maxConcurrent = $none,
    bool? approvalRequired,
  }) => $apply(
    FieldCopyWithData({
      if (requestId != null) #requestId: requestId,
      if (workspaceId != null) #workspaceId: workspaceId,
      if (objective != null) #objective: objective,
      if (recipeSource != $none) #recipeSource: recipeSource,
      if (isolation != null) #isolation: isolation,
      if (coordinatorProfileId != null)
        #coordinatorProfileId: coordinatorProfileId,
      if (roleProfiles != null) #roleProfiles: roleProfiles,
      if (workerProfileId != $none) #workerProfileId: workerProfileId,
      if (maxConcurrent != $none) #maxConcurrent: maxConcurrent,
      if (approvalRequired != null) #approvalRequired: approvalRequired,
    }),
  );
  @override
  RunCreateRequest $make(CopyWithData data) => RunCreateRequest(
    requestId: data.get(#requestId, or: $value.requestId),
    workspaceId: data.get(#workspaceId, or: $value.workspaceId),
    objective: data.get(#objective, or: $value.objective),
    recipeSource: data.get(#recipeSource, or: $value.recipeSource),
    isolation: data.get(#isolation, or: $value.isolation),
    coordinatorProfileId: data.get(
      #coordinatorProfileId,
      or: $value.coordinatorProfileId,
    ),
    roleProfiles: data.get(#roleProfiles, or: $value.roleProfiles),
    workerProfileId: data.get(#workerProfileId, or: $value.workerProfileId),
    maxConcurrent: data.get(#maxConcurrent, or: $value.maxConcurrent),
    approvalRequired: data.get(#approvalRequired, or: $value.approvalRequired),
  );

  @override
  RunCreateRequestCopyWith<$R2, RunCreateRequest, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _RunCreateRequestCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class RunCreatedMapper extends ClassMapperBase<RunCreated> {
  RunCreatedMapper._();

  static RunCreatedMapper? _instance;
  static RunCreatedMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RunCreatedMapper._());
      RunIsolationMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'RunCreated';

  static String _$runId(RunCreated v) => v.runId;
  static const Field<RunCreated, String> _f$runId = Field('runId', _$runId);
  static String _$status(RunCreated v) => v.status;
  static const Field<RunCreated, String> _f$status = Field('status', _$status);
  static RunIsolation _$isolation(RunCreated v) => v.isolation;
  static const Field<RunCreated, RunIsolation> _f$isolation = Field(
    'isolation',
    _$isolation,
    opt: true,
    def: RunIsolation.isolated,
  );
  static String? _$coordinatorTabId(RunCreated v) => v.coordinatorTabId;
  static const Field<RunCreated, String> _f$coordinatorTabId = Field(
    'coordinatorTabId',
    _$coordinatorTabId,
    opt: true,
  );
  static String? _$coordinatorProfileId(RunCreated v) => v.coordinatorProfileId;
  static const Field<RunCreated, String> _f$coordinatorProfileId = Field(
    'coordinatorProfileId',
    _$coordinatorProfileId,
    opt: true,
  );

  @override
  final MappableFields<RunCreated> fields = const {
    #runId: _f$runId,
    #status: _f$status,
    #isolation: _f$isolation,
    #coordinatorTabId: _f$coordinatorTabId,
    #coordinatorProfileId: _f$coordinatorProfileId,
  };

  static RunCreated _instantiate(DecodingData data) {
    return RunCreated(
      runId: data.dec(_f$runId),
      status: data.dec(_f$status),
      isolation: data.dec(_f$isolation),
      coordinatorTabId: data.dec(_f$coordinatorTabId),
      coordinatorProfileId: data.dec(_f$coordinatorProfileId),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static RunCreated fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<RunCreated>(map);
  }

  static RunCreated fromJson(String json) {
    return ensureInitialized().decodeJson<RunCreated>(json);
  }
}

mixin RunCreatedMappable {
  String toJson() {
    return RunCreatedMapper.ensureInitialized().encodeJson<RunCreated>(
      this as RunCreated,
    );
  }

  Map<String, dynamic> toMap() {
    return RunCreatedMapper.ensureInitialized().encodeMap<RunCreated>(
      this as RunCreated,
    );
  }

  RunCreatedCopyWith<RunCreated, RunCreated, RunCreated> get copyWith =>
      _RunCreatedCopyWithImpl<RunCreated, RunCreated>(
        this as RunCreated,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return RunCreatedMapper.ensureInitialized().stringifyValue(
      this as RunCreated,
    );
  }

  @override
  bool operator ==(Object other) {
    return RunCreatedMapper.ensureInitialized().equalsValue(
      this as RunCreated,
      other,
    );
  }

  @override
  int get hashCode {
    return RunCreatedMapper.ensureInitialized().hashValue(this as RunCreated);
  }
}

extension RunCreatedValueCopy<$R, $Out>
    on ObjectCopyWith<$R, RunCreated, $Out> {
  RunCreatedCopyWith<$R, RunCreated, $Out> get $asRunCreated =>
      $base.as((v, t, t2) => _RunCreatedCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class RunCreatedCopyWith<$R, $In extends RunCreated, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    String? runId,
    String? status,
    RunIsolation? isolation,
    String? coordinatorTabId,
    String? coordinatorProfileId,
  });
  RunCreatedCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _RunCreatedCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, RunCreated, $Out>
    implements RunCreatedCopyWith<$R, RunCreated, $Out> {
  _RunCreatedCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<RunCreated> $mapper =
      RunCreatedMapper.ensureInitialized();
  @override
  $R call({
    String? runId,
    String? status,
    RunIsolation? isolation,
    Object? coordinatorTabId = $none,
    Object? coordinatorProfileId = $none,
  }) => $apply(
    FieldCopyWithData({
      if (runId != null) #runId: runId,
      if (status != null) #status: status,
      if (isolation != null) #isolation: isolation,
      if (coordinatorTabId != $none) #coordinatorTabId: coordinatorTabId,
      if (coordinatorProfileId != $none)
        #coordinatorProfileId: coordinatorProfileId,
    }),
  );
  @override
  RunCreated $make(CopyWithData data) => RunCreated(
    runId: data.get(#runId, or: $value.runId),
    status: data.get(#status, or: $value.status),
    isolation: data.get(#isolation, or: $value.isolation),
    coordinatorTabId: data.get(#coordinatorTabId, or: $value.coordinatorTabId),
    coordinatorProfileId: data.get(
      #coordinatorProfileId,
      or: $value.coordinatorProfileId,
    ),
  );

  @override
  RunCreatedCopyWith<$R2, RunCreated, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _RunCreatedCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class RunCreateResultMapper extends ClassMapperBase<RunCreateResult> {
  RunCreateResultMapper._();

  static RunCreateResultMapper? _instance;
  static RunCreateResultMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RunCreateResultMapper._());
      RunCreatedMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'RunCreateResult';

  static RunCreated _$run(RunCreateResult v) => v.run;
  static const Field<RunCreateResult, RunCreated> _f$run = Field('run', _$run);
  static Map<String, Object?>? _$coordinator(RunCreateResult v) =>
      v.coordinator;
  static const Field<RunCreateResult, Map<String, Object?>> _f$coordinator =
      Field('coordinator', _$coordinator, opt: true);

  @override
  final MappableFields<RunCreateResult> fields = const {
    #run: _f$run,
    #coordinator: _f$coordinator,
  };

  static RunCreateResult _instantiate(DecodingData data) {
    return RunCreateResult(
      run: data.dec(_f$run),
      coordinator: data.dec(_f$coordinator),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static RunCreateResult fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<RunCreateResult>(map);
  }

  static RunCreateResult fromJson(String json) {
    return ensureInitialized().decodeJson<RunCreateResult>(json);
  }
}

mixin RunCreateResultMappable {
  String toJson() {
    return RunCreateResultMapper.ensureInitialized()
        .encodeJson<RunCreateResult>(this as RunCreateResult);
  }

  Map<String, dynamic> toMap() {
    return RunCreateResultMapper.ensureInitialized().encodeMap<RunCreateResult>(
      this as RunCreateResult,
    );
  }

  RunCreateResultCopyWith<RunCreateResult, RunCreateResult, RunCreateResult>
  get copyWith =>
      _RunCreateResultCopyWithImpl<RunCreateResult, RunCreateResult>(
        this as RunCreateResult,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return RunCreateResultMapper.ensureInitialized().stringifyValue(
      this as RunCreateResult,
    );
  }

  @override
  bool operator ==(Object other) {
    return RunCreateResultMapper.ensureInitialized().equalsValue(
      this as RunCreateResult,
      other,
    );
  }

  @override
  int get hashCode {
    return RunCreateResultMapper.ensureInitialized().hashValue(
      this as RunCreateResult,
    );
  }
}

extension RunCreateResultValueCopy<$R, $Out>
    on ObjectCopyWith<$R, RunCreateResult, $Out> {
  RunCreateResultCopyWith<$R, RunCreateResult, $Out> get $asRunCreateResult =>
      $base.as((v, t, t2) => _RunCreateResultCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class RunCreateResultCopyWith<$R, $In extends RunCreateResult, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  RunCreatedCopyWith<$R, RunCreated, RunCreated> get run;
  MapCopyWith<$R, String, Object?, ObjectCopyWith<$R, Object?, Object?>?>?
  get coordinator;
  $R call({RunCreated? run, Map<String, Object?>? coordinator});
  RunCreateResultCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _RunCreateResultCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, RunCreateResult, $Out>
    implements RunCreateResultCopyWith<$R, RunCreateResult, $Out> {
  _RunCreateResultCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<RunCreateResult> $mapper =
      RunCreateResultMapper.ensureInitialized();
  @override
  RunCreatedCopyWith<$R, RunCreated, RunCreated> get run =>
      $value.run.copyWith.$chain((v) => call(run: v));
  @override
  MapCopyWith<$R, String, Object?, ObjectCopyWith<$R, Object?, Object?>?>?
  get coordinator => $value.coordinator != null
      ? MapCopyWith(
          $value.coordinator!,
          (v, t) => ObjectCopyWith(v, $identity, t),
          (v) => call(coordinator: v),
        )
      : null;
  @override
  $R call({RunCreated? run, Object? coordinator = $none}) => $apply(
    FieldCopyWithData({
      if (run != null) #run: run,
      if (coordinator != $none) #coordinator: coordinator,
    }),
  );
  @override
  RunCreateResult $make(CopyWithData data) => RunCreateResult(
    run: data.get(#run, or: $value.run),
    coordinator: data.get(#coordinator, or: $value.coordinator),
  );

  @override
  RunCreateResultCopyWith<$R2, RunCreateResult, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _RunCreateResultCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class RunSourceMapper extends ClassMapperBase<RunSource> {
  RunSourceMapper._();

  static RunSourceMapper? _instance;
  static RunSourceMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RunSourceMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'RunSource';

  static Map<String, Object?> _$workspace(RunSource v) => v.workspace;
  static const Field<RunSource, Map<String, Object?>> _f$workspace = Field(
    'workspace',
    _$workspace,
    opt: true,
    def: const <String, Object?>{},
  );
  static String _$sha(RunSource v) => v.sha;
  static const Field<RunSource, String> _f$sha = Field('sha', _$sha);
  static bool _$hasUncommittedChanges(RunSource v) => v.hasUncommittedChanges;
  static const Field<RunSource, bool> _f$hasUncommittedChanges = Field(
    'hasUncommittedChanges',
    _$hasUncommittedChanges,
    opt: true,
    def: false,
  );

  @override
  final MappableFields<RunSource> fields = const {
    #workspace: _f$workspace,
    #sha: _f$sha,
    #hasUncommittedChanges: _f$hasUncommittedChanges,
  };

  static RunSource _instantiate(DecodingData data) {
    return RunSource(
      workspace: data.dec(_f$workspace),
      sha: data.dec(_f$sha),
      hasUncommittedChanges: data.dec(_f$hasUncommittedChanges),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static RunSource fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<RunSource>(map);
  }

  static RunSource fromJson(String json) {
    return ensureInitialized().decodeJson<RunSource>(json);
  }
}

mixin RunSourceMappable {
  String toJson() {
    return RunSourceMapper.ensureInitialized().encodeJson<RunSource>(
      this as RunSource,
    );
  }

  Map<String, dynamic> toMap() {
    return RunSourceMapper.ensureInitialized().encodeMap<RunSource>(
      this as RunSource,
    );
  }

  RunSourceCopyWith<RunSource, RunSource, RunSource> get copyWith =>
      _RunSourceCopyWithImpl<RunSource, RunSource>(
        this as RunSource,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return RunSourceMapper.ensureInitialized().stringifyValue(
      this as RunSource,
    );
  }

  @override
  bool operator ==(Object other) {
    return RunSourceMapper.ensureInitialized().equalsValue(
      this as RunSource,
      other,
    );
  }

  @override
  int get hashCode {
    return RunSourceMapper.ensureInitialized().hashValue(this as RunSource);
  }
}

extension RunSourceValueCopy<$R, $Out> on ObjectCopyWith<$R, RunSource, $Out> {
  RunSourceCopyWith<$R, RunSource, $Out> get $asRunSource =>
      $base.as((v, t, t2) => _RunSourceCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class RunSourceCopyWith<$R, $In extends RunSource, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  MapCopyWith<$R, String, Object?, ObjectCopyWith<$R, Object?, Object?>?>
  get workspace;
  $R call({
    Map<String, Object?>? workspace,
    String? sha,
    bool? hasUncommittedChanges,
  });
  RunSourceCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _RunSourceCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, RunSource, $Out>
    implements RunSourceCopyWith<$R, RunSource, $Out> {
  _RunSourceCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<RunSource> $mapper =
      RunSourceMapper.ensureInitialized();
  @override
  MapCopyWith<$R, String, Object?, ObjectCopyWith<$R, Object?, Object?>?>
  get workspace => MapCopyWith(
    $value.workspace,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(workspace: v),
  );
  @override
  $R call({
    Map<String, Object?>? workspace,
    String? sha,
    bool? hasUncommittedChanges,
  }) => $apply(
    FieldCopyWithData({
      if (workspace != null) #workspace: workspace,
      if (sha != null) #sha: sha,
      if (hasUncommittedChanges != null)
        #hasUncommittedChanges: hasUncommittedChanges,
    }),
  );
  @override
  RunSource $make(CopyWithData data) => RunSource(
    workspace: data.get(#workspace, or: $value.workspace),
    sha: data.get(#sha, or: $value.sha),
    hasUncommittedChanges: data.get(
      #hasUncommittedChanges,
      or: $value.hasUncommittedChanges,
    ),
  );

  @override
  RunSourceCopyWith<$R2, RunSource, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _RunSourceCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class RunControlReceiptMapper extends ClassMapperBase<RunControlReceipt> {
  RunControlReceiptMapper._();

  static RunControlReceiptMapper? _instance;
  static RunControlReceiptMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RunControlReceiptMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'RunControlReceipt';

  static String _$requestId(RunControlReceipt v) => v.requestId;
  static const Field<RunControlReceipt, String> _f$requestId = Field(
    'requestId',
    _$requestId,
  );
  static String _$runId(RunControlReceipt v) => v.runId;
  static const Field<RunControlReceipt, String> _f$runId = Field(
    'runId',
    _$runId,
  );
  static String _$action(RunControlReceipt v) => v.action;
  static const Field<RunControlReceipt, String> _f$action = Field(
    'action',
    _$action,
  );
  static int _$sequence(RunControlReceipt v) => v.sequence;
  static const Field<RunControlReceipt, int> _f$sequence = Field(
    'sequence',
    _$sequence,
    opt: true,
    def: 0,
  );
  static String _$status(RunControlReceipt v) => v.status;
  static const Field<RunControlReceipt, String> _f$status = Field(
    'status',
    _$status,
    opt: true,
    def: '',
  );
  static int? _$planRevision(RunControlReceipt v) => v.planRevision;
  static const Field<RunControlReceipt, int> _f$planRevision = Field(
    'planRevision',
    _$planRevision,
    opt: true,
  );
  static bool _$changesRequested(RunControlReceipt v) => v.changesRequested;
  static const Field<RunControlReceipt, bool> _f$changesRequested = Field(
    'changesRequested',
    _$changesRequested,
    opt: true,
    def: false,
  );
  static String _$coordinatorAction(RunControlReceipt v) => v.coordinatorAction;
  static const Field<RunControlReceipt, String> _f$coordinatorAction = Field(
    'coordinatorAction',
    _$coordinatorAction,
    opt: true,
    def: 'none',
  );

  @override
  final MappableFields<RunControlReceipt> fields = const {
    #requestId: _f$requestId,
    #runId: _f$runId,
    #action: _f$action,
    #sequence: _f$sequence,
    #status: _f$status,
    #planRevision: _f$planRevision,
    #changesRequested: _f$changesRequested,
    #coordinatorAction: _f$coordinatorAction,
  };

  static RunControlReceipt _instantiate(DecodingData data) {
    return RunControlReceipt(
      requestId: data.dec(_f$requestId),
      runId: data.dec(_f$runId),
      action: data.dec(_f$action),
      sequence: data.dec(_f$sequence),
      status: data.dec(_f$status),
      planRevision: data.dec(_f$planRevision),
      changesRequested: data.dec(_f$changesRequested),
      coordinatorAction: data.dec(_f$coordinatorAction),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static RunControlReceipt fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<RunControlReceipt>(map);
  }

  static RunControlReceipt fromJson(String json) {
    return ensureInitialized().decodeJson<RunControlReceipt>(json);
  }
}

mixin RunControlReceiptMappable {
  String toJson() {
    return RunControlReceiptMapper.ensureInitialized()
        .encodeJson<RunControlReceipt>(this as RunControlReceipt);
  }

  Map<String, dynamic> toMap() {
    return RunControlReceiptMapper.ensureInitialized()
        .encodeMap<RunControlReceipt>(this as RunControlReceipt);
  }

  RunControlReceiptCopyWith<
    RunControlReceipt,
    RunControlReceipt,
    RunControlReceipt
  >
  get copyWith =>
      _RunControlReceiptCopyWithImpl<RunControlReceipt, RunControlReceipt>(
        this as RunControlReceipt,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return RunControlReceiptMapper.ensureInitialized().stringifyValue(
      this as RunControlReceipt,
    );
  }

  @override
  bool operator ==(Object other) {
    return RunControlReceiptMapper.ensureInitialized().equalsValue(
      this as RunControlReceipt,
      other,
    );
  }

  @override
  int get hashCode {
    return RunControlReceiptMapper.ensureInitialized().hashValue(
      this as RunControlReceipt,
    );
  }
}

extension RunControlReceiptValueCopy<$R, $Out>
    on ObjectCopyWith<$R, RunControlReceipt, $Out> {
  RunControlReceiptCopyWith<$R, RunControlReceipt, $Out>
  get $asRunControlReceipt => $base.as(
    (v, t, t2) => _RunControlReceiptCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class RunControlReceiptCopyWith<
  $R,
  $In extends RunControlReceipt,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    String? requestId,
    String? runId,
    String? action,
    int? sequence,
    String? status,
    int? planRevision,
    bool? changesRequested,
    String? coordinatorAction,
  });
  RunControlReceiptCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _RunControlReceiptCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, RunControlReceipt, $Out>
    implements RunControlReceiptCopyWith<$R, RunControlReceipt, $Out> {
  _RunControlReceiptCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<RunControlReceipt> $mapper =
      RunControlReceiptMapper.ensureInitialized();
  @override
  $R call({
    String? requestId,
    String? runId,
    String? action,
    int? sequence,
    String? status,
    Object? planRevision = $none,
    bool? changesRequested,
    String? coordinatorAction,
  }) => $apply(
    FieldCopyWithData({
      if (requestId != null) #requestId: requestId,
      if (runId != null) #runId: runId,
      if (action != null) #action: action,
      if (sequence != null) #sequence: sequence,
      if (status != null) #status: status,
      if (planRevision != $none) #planRevision: planRevision,
      if (changesRequested != null) #changesRequested: changesRequested,
      if (coordinatorAction != null) #coordinatorAction: coordinatorAction,
    }),
  );
  @override
  RunControlReceipt $make(CopyWithData data) => RunControlReceipt(
    requestId: data.get(#requestId, or: $value.requestId),
    runId: data.get(#runId, or: $value.runId),
    action: data.get(#action, or: $value.action),
    sequence: data.get(#sequence, or: $value.sequence),
    status: data.get(#status, or: $value.status),
    planRevision: data.get(#planRevision, or: $value.planRevision),
    changesRequested: data.get(#changesRequested, or: $value.changesRequested),
    coordinatorAction: data.get(
      #coordinatorAction,
      or: $value.coordinatorAction,
    ),
  );

  @override
  RunControlReceiptCopyWith<$R2, RunControlReceipt, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _RunControlReceiptCopyWithImpl<$R2, $Out2>($value, $cast, t);
}
