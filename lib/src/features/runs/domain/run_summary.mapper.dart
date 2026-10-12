// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'run_summary.dart';

class RunBucketMapper extends EnumMapper<RunBucket> {
  RunBucketMapper._();

  static RunBucketMapper? _instance;
  static RunBucketMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RunBucketMapper._());
    }
    return _instance!;
  }

  static RunBucket fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  RunBucket decode(dynamic value) {
    switch (value) {
      case r'attention':
        return RunBucket.attention;
      case r'active':
        return RunBucket.active;
      case r'history':
        return RunBucket.history;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(RunBucket self) {
    switch (self) {
      case RunBucket.attention:
        return r'attention';
      case RunBucket.active:
        return r'active';
      case RunBucket.history:
        return r'history';
    }
  }
}

extension RunBucketMapperExtension on RunBucket {
  String toValue() {
    RunBucketMapper.ensureInitialized();
    return MapperContainer.globals.toValue<RunBucket>(this) as String;
  }
}

class RunBoardCursorMapper extends ClassMapperBase<RunBoardCursor> {
  RunBoardCursorMapper._();

  static RunBoardCursorMapper? _instance;
  static RunBoardCursorMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RunBoardCursorMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'RunBoardCursor';

  static String _$createdAt(RunBoardCursor v) => v.createdAt;
  static const Field<RunBoardCursor, String> _f$createdAt = Field(
    'createdAt',
    _$createdAt,
  );
  static String _$id(RunBoardCursor v) => v.id;
  static const Field<RunBoardCursor, String> _f$id = Field('id', _$id);
  static int _$revision(RunBoardCursor v) => v.revision;
  static const Field<RunBoardCursor, int> _f$revision = Field(
    'revision',
    _$revision,
  );

  @override
  final MappableFields<RunBoardCursor> fields = const {
    #createdAt: _f$createdAt,
    #id: _f$id,
    #revision: _f$revision,
  };

  static RunBoardCursor _instantiate(DecodingData data) {
    return RunBoardCursor(
      createdAt: data.dec(_f$createdAt),
      id: data.dec(_f$id),
      revision: data.dec(_f$revision),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static RunBoardCursor fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<RunBoardCursor>(map);
  }

  static RunBoardCursor fromJson(String json) {
    return ensureInitialized().decodeJson<RunBoardCursor>(json);
  }
}

mixin RunBoardCursorMappable {
  String toJson() {
    return RunBoardCursorMapper.ensureInitialized().encodeJson<RunBoardCursor>(
      this as RunBoardCursor,
    );
  }

  Map<String, dynamic> toMap() {
    return RunBoardCursorMapper.ensureInitialized().encodeMap<RunBoardCursor>(
      this as RunBoardCursor,
    );
  }

  RunBoardCursorCopyWith<RunBoardCursor, RunBoardCursor, RunBoardCursor>
  get copyWith => _RunBoardCursorCopyWithImpl<RunBoardCursor, RunBoardCursor>(
    this as RunBoardCursor,
    $identity,
    $identity,
  );
  @override
  String toString() {
    return RunBoardCursorMapper.ensureInitialized().stringifyValue(
      this as RunBoardCursor,
    );
  }

  @override
  bool operator ==(Object other) {
    return RunBoardCursorMapper.ensureInitialized().equalsValue(
      this as RunBoardCursor,
      other,
    );
  }

  @override
  int get hashCode {
    return RunBoardCursorMapper.ensureInitialized().hashValue(
      this as RunBoardCursor,
    );
  }
}

extension RunBoardCursorValueCopy<$R, $Out>
    on ObjectCopyWith<$R, RunBoardCursor, $Out> {
  RunBoardCursorCopyWith<$R, RunBoardCursor, $Out> get $asRunBoardCursor =>
      $base.as((v, t, t2) => _RunBoardCursorCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class RunBoardCursorCopyWith<$R, $In extends RunBoardCursor, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({String? createdAt, String? id, int? revision});
  RunBoardCursorCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _RunBoardCursorCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, RunBoardCursor, $Out>
    implements RunBoardCursorCopyWith<$R, RunBoardCursor, $Out> {
  _RunBoardCursorCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<RunBoardCursor> $mapper =
      RunBoardCursorMapper.ensureInitialized();
  @override
  $R call({String? createdAt, String? id, int? revision}) => $apply(
    FieldCopyWithData({
      if (createdAt != null) #createdAt: createdAt,
      if (id != null) #id: id,
      if (revision != null) #revision: revision,
    }),
  );
  @override
  RunBoardCursor $make(CopyWithData data) => RunBoardCursor(
    createdAt: data.get(#createdAt, or: $value.createdAt),
    id: data.get(#id, or: $value.id),
    revision: data.get(#revision, or: $value.revision),
  );

  @override
  RunBoardCursorCopyWith<$R2, RunBoardCursor, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _RunBoardCursorCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class RunPendingGateRefMapper extends ClassMapperBase<RunPendingGateRef> {
  RunPendingGateRefMapper._();

  static RunPendingGateRefMapper? _instance;
  static RunPendingGateRefMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RunPendingGateRefMapper._());
      RunGateKindMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'RunPendingGateRef';

  static String _$id(RunPendingGateRef v) => v.id;
  static const Field<RunPendingGateRef, String> _f$id = Field('id', _$id);
  static RunGateKind _$kind(RunPendingGateRef v) => v.kind;
  static const Field<RunPendingGateRef, RunGateKind> _f$kind = Field(
    'kind',
    _$kind,
  );
  static String? _$taskId(RunPendingGateRef v) => v.taskId;
  static const Field<RunPendingGateRef, String> _f$taskId = Field(
    'taskId',
    _$taskId,
    opt: true,
  );

  @override
  final MappableFields<RunPendingGateRef> fields = const {
    #id: _f$id,
    #kind: _f$kind,
    #taskId: _f$taskId,
  };

  static RunPendingGateRef _instantiate(DecodingData data) {
    return RunPendingGateRef(
      id: data.dec(_f$id),
      kind: data.dec(_f$kind),
      taskId: data.dec(_f$taskId),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static RunPendingGateRef fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<RunPendingGateRef>(map);
  }

  static RunPendingGateRef fromJson(String json) {
    return ensureInitialized().decodeJson<RunPendingGateRef>(json);
  }
}

mixin RunPendingGateRefMappable {
  String toJson() {
    return RunPendingGateRefMapper.ensureInitialized()
        .encodeJson<RunPendingGateRef>(this as RunPendingGateRef);
  }

  Map<String, dynamic> toMap() {
    return RunPendingGateRefMapper.ensureInitialized()
        .encodeMap<RunPendingGateRef>(this as RunPendingGateRef);
  }

  RunPendingGateRefCopyWith<
    RunPendingGateRef,
    RunPendingGateRef,
    RunPendingGateRef
  >
  get copyWith =>
      _RunPendingGateRefCopyWithImpl<RunPendingGateRef, RunPendingGateRef>(
        this as RunPendingGateRef,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return RunPendingGateRefMapper.ensureInitialized().stringifyValue(
      this as RunPendingGateRef,
    );
  }

  @override
  bool operator ==(Object other) {
    return RunPendingGateRefMapper.ensureInitialized().equalsValue(
      this as RunPendingGateRef,
      other,
    );
  }

  @override
  int get hashCode {
    return RunPendingGateRefMapper.ensureInitialized().hashValue(
      this as RunPendingGateRef,
    );
  }
}

extension RunPendingGateRefValueCopy<$R, $Out>
    on ObjectCopyWith<$R, RunPendingGateRef, $Out> {
  RunPendingGateRefCopyWith<$R, RunPendingGateRef, $Out>
  get $asRunPendingGateRef => $base.as(
    (v, t, t2) => _RunPendingGateRefCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class RunPendingGateRefCopyWith<
  $R,
  $In extends RunPendingGateRef,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({String? id, RunGateKind? kind, String? taskId});
  RunPendingGateRefCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _RunPendingGateRefCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, RunPendingGateRef, $Out>
    implements RunPendingGateRefCopyWith<$R, RunPendingGateRef, $Out> {
  _RunPendingGateRefCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<RunPendingGateRef> $mapper =
      RunPendingGateRefMapper.ensureInitialized();
  @override
  $R call({String? id, RunGateKind? kind, Object? taskId = $none}) => $apply(
    FieldCopyWithData({
      if (id != null) #id: id,
      if (kind != null) #kind: kind,
      if (taskId != $none) #taskId: taskId,
    }),
  );
  @override
  RunPendingGateRef $make(CopyWithData data) => RunPendingGateRef(
    id: data.get(#id, or: $value.id),
    kind: data.get(#kind, or: $value.kind),
    taskId: data.get(#taskId, or: $value.taskId),
  );

  @override
  RunPendingGateRefCopyWith<$R2, RunPendingGateRef, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _RunPendingGateRefCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class RunBoardCountsMapper extends ClassMapperBase<RunBoardCounts> {
  RunBoardCountsMapper._();

  static RunBoardCountsMapper? _instance;
  static RunBoardCountsMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RunBoardCountsMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'RunBoardCounts';

  static int _$attention(RunBoardCounts v) => v.attention;
  static const Field<RunBoardCounts, int> _f$attention = Field(
    'attention',
    _$attention,
    opt: true,
    def: 0,
  );
  static int _$active(RunBoardCounts v) => v.active;
  static const Field<RunBoardCounts, int> _f$active = Field(
    'active',
    _$active,
    opt: true,
    def: 0,
  );
  static int _$history(RunBoardCounts v) => v.history;
  static const Field<RunBoardCounts, int> _f$history = Field(
    'history',
    _$history,
    opt: true,
    def: 0,
  );

  @override
  final MappableFields<RunBoardCounts> fields = const {
    #attention: _f$attention,
    #active: _f$active,
    #history: _f$history,
  };

  static RunBoardCounts _instantiate(DecodingData data) {
    return RunBoardCounts(
      attention: data.dec(_f$attention),
      active: data.dec(_f$active),
      history: data.dec(_f$history),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static RunBoardCounts fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<RunBoardCounts>(map);
  }

  static RunBoardCounts fromJson(String json) {
    return ensureInitialized().decodeJson<RunBoardCounts>(json);
  }
}

mixin RunBoardCountsMappable {
  String toJson() {
    return RunBoardCountsMapper.ensureInitialized().encodeJson<RunBoardCounts>(
      this as RunBoardCounts,
    );
  }

  Map<String, dynamic> toMap() {
    return RunBoardCountsMapper.ensureInitialized().encodeMap<RunBoardCounts>(
      this as RunBoardCounts,
    );
  }

  RunBoardCountsCopyWith<RunBoardCounts, RunBoardCounts, RunBoardCounts>
  get copyWith => _RunBoardCountsCopyWithImpl<RunBoardCounts, RunBoardCounts>(
    this as RunBoardCounts,
    $identity,
    $identity,
  );
  @override
  String toString() {
    return RunBoardCountsMapper.ensureInitialized().stringifyValue(
      this as RunBoardCounts,
    );
  }

  @override
  bool operator ==(Object other) {
    return RunBoardCountsMapper.ensureInitialized().equalsValue(
      this as RunBoardCounts,
      other,
    );
  }

  @override
  int get hashCode {
    return RunBoardCountsMapper.ensureInitialized().hashValue(
      this as RunBoardCounts,
    );
  }
}

extension RunBoardCountsValueCopy<$R, $Out>
    on ObjectCopyWith<$R, RunBoardCounts, $Out> {
  RunBoardCountsCopyWith<$R, RunBoardCounts, $Out> get $asRunBoardCounts =>
      $base.as((v, t, t2) => _RunBoardCountsCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class RunBoardCountsCopyWith<$R, $In extends RunBoardCounts, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({int? attention, int? active, int? history});
  RunBoardCountsCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _RunBoardCountsCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, RunBoardCounts, $Out>
    implements RunBoardCountsCopyWith<$R, RunBoardCounts, $Out> {
  _RunBoardCountsCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<RunBoardCounts> $mapper =
      RunBoardCountsMapper.ensureInitialized();
  @override
  $R call({int? attention, int? active, int? history}) => $apply(
    FieldCopyWithData({
      if (attention != null) #attention: attention,
      if (active != null) #active: active,
      if (history != null) #history: history,
    }),
  );
  @override
  RunBoardCounts $make(CopyWithData data) => RunBoardCounts(
    attention: data.get(#attention, or: $value.attention),
    active: data.get(#active, or: $value.active),
    history: data.get(#history, or: $value.history),
  );

  @override
  RunBoardCountsCopyWith<$R2, RunBoardCounts, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _RunBoardCountsCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class RunSummaryMapper extends ClassMapperBase<RunSummary> {
  RunSummaryMapper._();

  static RunSummaryMapper? _instance;
  static RunSummaryMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RunSummaryMapper._());
      RunBucketMapper.ensureInitialized();
      RunPendingGateRefMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'RunSummary';

  static String _$id(RunSummary v) => v.id;
  static const Field<RunSummary, String> _f$id = Field('id', _$id);
  static String _$objective(RunSummary v) => v.objective;
  static const Field<RunSummary, String> _f$objective = Field(
    'objective',
    _$objective,
  );
  static String _$status(RunSummary v) => v.status;
  static const Field<RunSummary, String> _f$status = Field('status', _$status);
  static RunBucket _$bucket(RunSummary v) => v.bucket;
  static const Field<RunSummary, RunBucket> _f$bucket = Field(
    'bucket',
    _$bucket,
  );
  static String _$workspaceId(RunSummary v) => v.workspaceId;
  static const Field<RunSummary, String> _f$workspaceId = Field(
    'workspaceId',
    _$workspaceId,
  );
  static String? _$workspaceName(RunSummary v) => v.workspaceName;
  static const Field<RunSummary, String> _f$workspaceName = Field(
    'workspaceName',
    _$workspaceName,
    opt: true,
  );
  static String? _$projectId(RunSummary v) => v.projectId;
  static const Field<RunSummary, String> _f$projectId = Field(
    'projectId',
    _$projectId,
    opt: true,
  );
  static String? _$projectName(RunSummary v) => v.projectName;
  static const Field<RunSummary, String> _f$projectName = Field(
    'projectName',
    _$projectName,
    opt: true,
  );
  static String _$createdAt(RunSummary v) => v.createdAt;
  static const Field<RunSummary, String> _f$createdAt = Field(
    'createdAt',
    _$createdAt,
  );
  static String _$lastActivityAt(RunSummary v) => v.lastActivityAt;
  static const Field<RunSummary, String> _f$lastActivityAt = Field(
    'lastActivityAt',
    _$lastActivityAt,
  );
  static String? _$completedAt(RunSummary v) => v.completedAt;
  static const Field<RunSummary, String> _f$completedAt = Field(
    'completedAt',
    _$completedAt,
    opt: true,
  );
  static bool _$planGatePending(RunSummary v) => v.planGatePending;
  static const Field<RunSummary, bool> _f$planGatePending = Field(
    'planGatePending',
    _$planGatePending,
    opt: true,
    def: false,
  );
  static String _$isolation(RunSummary v) => v.isolation;
  static const Field<RunSummary, String> _f$isolation = Field(
    'isolation',
    _$isolation,
    opt: true,
    def: 'shared',
  );
  static bool _$approvalRequired(RunSummary v) => v.approvalRequired;
  static const Field<RunSummary, bool> _f$approvalRequired = Field(
    'approvalRequired',
    _$approvalRequired,
    opt: true,
    def: false,
  );
  static int? _$planRevision(RunSummary v) => v.planRevision;
  static const Field<RunSummary, int> _f$planRevision = Field(
    'planRevision',
    _$planRevision,
    opt: true,
  );
  static String? _$attentionReason(RunSummary v) => v.attentionReason;
  static const Field<RunSummary, String> _f$attentionReason = Field(
    'attentionReason',
    _$attentionReason,
    opt: true,
  );
  static String _$coordinatorState(RunSummary v) => v.coordinatorState;
  static const Field<RunSummary, String> _f$coordinatorState = Field(
    'coordinatorState',
    _$coordinatorState,
    opt: true,
    def: 'none',
  );
  static String? _$pausedBy(RunSummary v) => v.pausedBy;
  static const Field<RunSummary, String> _f$pausedBy = Field(
    'pausedBy',
    _$pausedBy,
    opt: true,
  );
  static int _$controlSequence(RunSummary v) => v.controlSequence;
  static const Field<RunSummary, int> _f$controlSequence = Field(
    'controlSequence',
    _$controlSequence,
    opt: true,
    def: 0,
  );
  static List<String> _$pendingGateKinds(RunSummary v) => v.pendingGateKinds;
  static const Field<RunSummary, List<String>> _f$pendingGateKinds = Field(
    'pendingGateKinds',
    _$pendingGateKinds,
    opt: true,
    def: const <String>[],
  );
  static int _$taskCount(RunSummary v) => v.taskCount;
  static const Field<RunSummary, int> _f$taskCount = Field(
    'taskCount',
    _$taskCount,
    opt: true,
    def: 0,
  );
  static int _$completedCount(RunSummary v) => v.completedCount;
  static const Field<RunSummary, int> _f$completedCount = Field(
    'completedCount',
    _$completedCount,
    opt: true,
    def: 0,
  );
  static int _$runningCount(RunSummary v) => v.runningCount;
  static const Field<RunSummary, int> _f$runningCount = Field(
    'runningCount',
    _$runningCount,
    opt: true,
    def: 0,
  );
  static int _$failedCount(RunSummary v) => v.failedCount;
  static const Field<RunSummary, int> _f$failedCount = Field(
    'failedCount',
    _$failedCount,
    opt: true,
    def: 0,
  );
  static int _$stalledCount(RunSummary v) => v.stalledCount;
  static const Field<RunSummary, int> _f$stalledCount = Field(
    'stalledCount',
    _$stalledCount,
    opt: true,
    def: 0,
  );
  static int _$blockedCount(RunSummary v) => v.blockedCount;
  static const Field<RunSummary, int> _f$blockedCount = Field(
    'blockedCount',
    _$blockedCount,
    opt: true,
    def: 0,
  );
  static int _$pendingGateCount(RunSummary v) => v.pendingGateCount;
  static const Field<RunSummary, int> _f$pendingGateCount = Field(
    'pendingGateCount',
    _$pendingGateCount,
    opt: true,
    def: 0,
  );
  static bool _$cleanupAttention(RunSummary v) => v.cleanupAttention;
  static const Field<RunSummary, bool> _f$cleanupAttention = Field(
    'cleanupAttention',
    _$cleanupAttention,
    opt: true,
    def: false,
  );
  static bool _$cleanupApplying(RunSummary v) => v.cleanupApplying;
  static const Field<RunSummary, bool> _f$cleanupApplying = Field(
    'cleanupApplying',
    _$cleanupApplying,
    opt: true,
    def: false,
  );
  static List<RunPendingGateRef> _$pendingGates(RunSummary v) => v.pendingGates;
  static const Field<RunSummary, List<RunPendingGateRef>> _f$pendingGates =
      Field(
        'pendingGates',
        _$pendingGates,
        opt: true,
        def: const <RunPendingGateRef>[],
      );

  @override
  final MappableFields<RunSummary> fields = const {
    #id: _f$id,
    #objective: _f$objective,
    #status: _f$status,
    #bucket: _f$bucket,
    #workspaceId: _f$workspaceId,
    #workspaceName: _f$workspaceName,
    #projectId: _f$projectId,
    #projectName: _f$projectName,
    #createdAt: _f$createdAt,
    #lastActivityAt: _f$lastActivityAt,
    #completedAt: _f$completedAt,
    #planGatePending: _f$planGatePending,
    #isolation: _f$isolation,
    #approvalRequired: _f$approvalRequired,
    #planRevision: _f$planRevision,
    #attentionReason: _f$attentionReason,
    #coordinatorState: _f$coordinatorState,
    #pausedBy: _f$pausedBy,
    #controlSequence: _f$controlSequence,
    #pendingGateKinds: _f$pendingGateKinds,
    #taskCount: _f$taskCount,
    #completedCount: _f$completedCount,
    #runningCount: _f$runningCount,
    #failedCount: _f$failedCount,
    #stalledCount: _f$stalledCount,
    #blockedCount: _f$blockedCount,
    #pendingGateCount: _f$pendingGateCount,
    #cleanupAttention: _f$cleanupAttention,
    #cleanupApplying: _f$cleanupApplying,
    #pendingGates: _f$pendingGates,
  };

  static RunSummary _instantiate(DecodingData data) {
    return RunSummary(
      id: data.dec(_f$id),
      objective: data.dec(_f$objective),
      status: data.dec(_f$status),
      bucket: data.dec(_f$bucket),
      workspaceId: data.dec(_f$workspaceId),
      workspaceName: data.dec(_f$workspaceName),
      projectId: data.dec(_f$projectId),
      projectName: data.dec(_f$projectName),
      createdAt: data.dec(_f$createdAt),
      lastActivityAt: data.dec(_f$lastActivityAt),
      completedAt: data.dec(_f$completedAt),
      planGatePending: data.dec(_f$planGatePending),
      isolation: data.dec(_f$isolation),
      approvalRequired: data.dec(_f$approvalRequired),
      planRevision: data.dec(_f$planRevision),
      attentionReason: data.dec(_f$attentionReason),
      coordinatorState: data.dec(_f$coordinatorState),
      pausedBy: data.dec(_f$pausedBy),
      controlSequence: data.dec(_f$controlSequence),
      pendingGateKinds: data.dec(_f$pendingGateKinds),
      taskCount: data.dec(_f$taskCount),
      completedCount: data.dec(_f$completedCount),
      runningCount: data.dec(_f$runningCount),
      failedCount: data.dec(_f$failedCount),
      stalledCount: data.dec(_f$stalledCount),
      blockedCount: data.dec(_f$blockedCount),
      pendingGateCount: data.dec(_f$pendingGateCount),
      cleanupAttention: data.dec(_f$cleanupAttention),
      cleanupApplying: data.dec(_f$cleanupApplying),
      pendingGates: data.dec(_f$pendingGates),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static RunSummary fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<RunSummary>(map);
  }

  static RunSummary fromJson(String json) {
    return ensureInitialized().decodeJson<RunSummary>(json);
  }
}

mixin RunSummaryMappable {
  String toJson() {
    return RunSummaryMapper.ensureInitialized().encodeJson<RunSummary>(
      this as RunSummary,
    );
  }

  Map<String, dynamic> toMap() {
    return RunSummaryMapper.ensureInitialized().encodeMap<RunSummary>(
      this as RunSummary,
    );
  }

  RunSummaryCopyWith<RunSummary, RunSummary, RunSummary> get copyWith =>
      _RunSummaryCopyWithImpl<RunSummary, RunSummary>(
        this as RunSummary,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return RunSummaryMapper.ensureInitialized().stringifyValue(
      this as RunSummary,
    );
  }

  @override
  bool operator ==(Object other) {
    return RunSummaryMapper.ensureInitialized().equalsValue(
      this as RunSummary,
      other,
    );
  }

  @override
  int get hashCode {
    return RunSummaryMapper.ensureInitialized().hashValue(this as RunSummary);
  }
}

extension RunSummaryValueCopy<$R, $Out>
    on ObjectCopyWith<$R, RunSummary, $Out> {
  RunSummaryCopyWith<$R, RunSummary, $Out> get $asRunSummary =>
      $base.as((v, t, t2) => _RunSummaryCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class RunSummaryCopyWith<$R, $In extends RunSummary, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>>
  get pendingGateKinds;
  ListCopyWith<
    $R,
    RunPendingGateRef,
    RunPendingGateRefCopyWith<$R, RunPendingGateRef, RunPendingGateRef>
  >
  get pendingGates;
  $R call({
    String? id,
    String? objective,
    String? status,
    RunBucket? bucket,
    String? workspaceId,
    String? workspaceName,
    String? projectId,
    String? projectName,
    String? createdAt,
    String? lastActivityAt,
    String? completedAt,
    bool? planGatePending,
    String? isolation,
    bool? approvalRequired,
    int? planRevision,
    String? attentionReason,
    String? coordinatorState,
    String? pausedBy,
    int? controlSequence,
    List<String>? pendingGateKinds,
    int? taskCount,
    int? completedCount,
    int? runningCount,
    int? failedCount,
    int? stalledCount,
    int? blockedCount,
    int? pendingGateCount,
    bool? cleanupAttention,
    bool? cleanupApplying,
    List<RunPendingGateRef>? pendingGates,
  });
  RunSummaryCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _RunSummaryCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, RunSummary, $Out>
    implements RunSummaryCopyWith<$R, RunSummary, $Out> {
  _RunSummaryCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<RunSummary> $mapper =
      RunSummaryMapper.ensureInitialized();
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>>
  get pendingGateKinds => ListCopyWith(
    $value.pendingGateKinds,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(pendingGateKinds: v),
  );
  @override
  ListCopyWith<
    $R,
    RunPendingGateRef,
    RunPendingGateRefCopyWith<$R, RunPendingGateRef, RunPendingGateRef>
  >
  get pendingGates => ListCopyWith(
    $value.pendingGates,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(pendingGates: v),
  );
  @override
  $R call({
    String? id,
    String? objective,
    String? status,
    RunBucket? bucket,
    String? workspaceId,
    Object? workspaceName = $none,
    Object? projectId = $none,
    Object? projectName = $none,
    String? createdAt,
    String? lastActivityAt,
    Object? completedAt = $none,
    bool? planGatePending,
    String? isolation,
    bool? approvalRequired,
    Object? planRevision = $none,
    Object? attentionReason = $none,
    String? coordinatorState,
    Object? pausedBy = $none,
    int? controlSequence,
    List<String>? pendingGateKinds,
    int? taskCount,
    int? completedCount,
    int? runningCount,
    int? failedCount,
    int? stalledCount,
    int? blockedCount,
    int? pendingGateCount,
    bool? cleanupAttention,
    bool? cleanupApplying,
    List<RunPendingGateRef>? pendingGates,
  }) => $apply(
    FieldCopyWithData({
      if (id != null) #id: id,
      if (objective != null) #objective: objective,
      if (status != null) #status: status,
      if (bucket != null) #bucket: bucket,
      if (workspaceId != null) #workspaceId: workspaceId,
      if (workspaceName != $none) #workspaceName: workspaceName,
      if (projectId != $none) #projectId: projectId,
      if (projectName != $none) #projectName: projectName,
      if (createdAt != null) #createdAt: createdAt,
      if (lastActivityAt != null) #lastActivityAt: lastActivityAt,
      if (completedAt != $none) #completedAt: completedAt,
      if (planGatePending != null) #planGatePending: planGatePending,
      if (isolation != null) #isolation: isolation,
      if (approvalRequired != null) #approvalRequired: approvalRequired,
      if (planRevision != $none) #planRevision: planRevision,
      if (attentionReason != $none) #attentionReason: attentionReason,
      if (coordinatorState != null) #coordinatorState: coordinatorState,
      if (pausedBy != $none) #pausedBy: pausedBy,
      if (controlSequence != null) #controlSequence: controlSequence,
      if (pendingGateKinds != null) #pendingGateKinds: pendingGateKinds,
      if (taskCount != null) #taskCount: taskCount,
      if (completedCount != null) #completedCount: completedCount,
      if (runningCount != null) #runningCount: runningCount,
      if (failedCount != null) #failedCount: failedCount,
      if (stalledCount != null) #stalledCount: stalledCount,
      if (blockedCount != null) #blockedCount: blockedCount,
      if (pendingGateCount != null) #pendingGateCount: pendingGateCount,
      if (cleanupAttention != null) #cleanupAttention: cleanupAttention,
      if (cleanupApplying != null) #cleanupApplying: cleanupApplying,
      if (pendingGates != null) #pendingGates: pendingGates,
    }),
  );
  @override
  RunSummary $make(CopyWithData data) => RunSummary(
    id: data.get(#id, or: $value.id),
    objective: data.get(#objective, or: $value.objective),
    status: data.get(#status, or: $value.status),
    bucket: data.get(#bucket, or: $value.bucket),
    workspaceId: data.get(#workspaceId, or: $value.workspaceId),
    workspaceName: data.get(#workspaceName, or: $value.workspaceName),
    projectId: data.get(#projectId, or: $value.projectId),
    projectName: data.get(#projectName, or: $value.projectName),
    createdAt: data.get(#createdAt, or: $value.createdAt),
    lastActivityAt: data.get(#lastActivityAt, or: $value.lastActivityAt),
    completedAt: data.get(#completedAt, or: $value.completedAt),
    planGatePending: data.get(#planGatePending, or: $value.planGatePending),
    isolation: data.get(#isolation, or: $value.isolation),
    approvalRequired: data.get(#approvalRequired, or: $value.approvalRequired),
    planRevision: data.get(#planRevision, or: $value.planRevision),
    attentionReason: data.get(#attentionReason, or: $value.attentionReason),
    coordinatorState: data.get(#coordinatorState, or: $value.coordinatorState),
    pausedBy: data.get(#pausedBy, or: $value.pausedBy),
    controlSequence: data.get(#controlSequence, or: $value.controlSequence),
    pendingGateKinds: data.get(#pendingGateKinds, or: $value.pendingGateKinds),
    taskCount: data.get(#taskCount, or: $value.taskCount),
    completedCount: data.get(#completedCount, or: $value.completedCount),
    runningCount: data.get(#runningCount, or: $value.runningCount),
    failedCount: data.get(#failedCount, or: $value.failedCount),
    stalledCount: data.get(#stalledCount, or: $value.stalledCount),
    blockedCount: data.get(#blockedCount, or: $value.blockedCount),
    pendingGateCount: data.get(#pendingGateCount, or: $value.pendingGateCount),
    cleanupAttention: data.get(#cleanupAttention, or: $value.cleanupAttention),
    cleanupApplying: data.get(#cleanupApplying, or: $value.cleanupApplying),
    pendingGates: data.get(#pendingGates, or: $value.pendingGates),
  );

  @override
  RunSummaryCopyWith<$R2, RunSummary, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _RunSummaryCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class RunBoardPageMapper extends ClassMapperBase<RunBoardPage> {
  RunBoardPageMapper._();

  static RunBoardPageMapper? _instance;
  static RunBoardPageMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RunBoardPageMapper._());
      RunBoardCountsMapper.ensureInitialized();
      RunSummaryMapper.ensureInitialized();
      RunBoardCursorMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'RunBoardPage';

  static int _$revision(RunBoardPage v) => v.revision;
  static const Field<RunBoardPage, int> _f$revision = Field(
    'revision',
    _$revision,
  );
  static RunBoardCounts _$counts(RunBoardPage v) => v.counts;
  static const Field<RunBoardPage, RunBoardCounts> _f$counts = Field(
    'counts',
    _$counts,
    opt: true,
    def: const RunBoardCounts(),
  );
  static List<RunSummary> _$items(RunBoardPage v) => v.items;
  static const Field<RunBoardPage, List<RunSummary>> _f$items = Field(
    'items',
    _$items,
    opt: true,
    def: const <RunSummary>[],
  );
  static RunBoardCursor? _$nextCursor(RunBoardPage v) => v.nextCursor;
  static const Field<RunBoardPage, RunBoardCursor> _f$nextCursor = Field(
    'nextCursor',
    _$nextCursor,
    opt: true,
  );

  @override
  final MappableFields<RunBoardPage> fields = const {
    #revision: _f$revision,
    #counts: _f$counts,
    #items: _f$items,
    #nextCursor: _f$nextCursor,
  };

  static RunBoardPage _instantiate(DecodingData data) {
    return RunBoardPage(
      revision: data.dec(_f$revision),
      counts: data.dec(_f$counts),
      items: data.dec(_f$items),
      nextCursor: data.dec(_f$nextCursor),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static RunBoardPage fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<RunBoardPage>(map);
  }

  static RunBoardPage fromJson(String json) {
    return ensureInitialized().decodeJson<RunBoardPage>(json);
  }
}

mixin RunBoardPageMappable {
  String toJson() {
    return RunBoardPageMapper.ensureInitialized().encodeJson<RunBoardPage>(
      this as RunBoardPage,
    );
  }

  Map<String, dynamic> toMap() {
    return RunBoardPageMapper.ensureInitialized().encodeMap<RunBoardPage>(
      this as RunBoardPage,
    );
  }

  RunBoardPageCopyWith<RunBoardPage, RunBoardPage, RunBoardPage> get copyWith =>
      _RunBoardPageCopyWithImpl<RunBoardPage, RunBoardPage>(
        this as RunBoardPage,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return RunBoardPageMapper.ensureInitialized().stringifyValue(
      this as RunBoardPage,
    );
  }

  @override
  bool operator ==(Object other) {
    return RunBoardPageMapper.ensureInitialized().equalsValue(
      this as RunBoardPage,
      other,
    );
  }

  @override
  int get hashCode {
    return RunBoardPageMapper.ensureInitialized().hashValue(
      this as RunBoardPage,
    );
  }
}

extension RunBoardPageValueCopy<$R, $Out>
    on ObjectCopyWith<$R, RunBoardPage, $Out> {
  RunBoardPageCopyWith<$R, RunBoardPage, $Out> get $asRunBoardPage =>
      $base.as((v, t, t2) => _RunBoardPageCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class RunBoardPageCopyWith<$R, $In extends RunBoardPage, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  RunBoardCountsCopyWith<$R, RunBoardCounts, RunBoardCounts> get counts;
  ListCopyWith<$R, RunSummary, RunSummaryCopyWith<$R, RunSummary, RunSummary>>
  get items;
  RunBoardCursorCopyWith<$R, RunBoardCursor, RunBoardCursor>? get nextCursor;
  $R call({
    int? revision,
    RunBoardCounts? counts,
    List<RunSummary>? items,
    RunBoardCursor? nextCursor,
  });
  RunBoardPageCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _RunBoardPageCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, RunBoardPage, $Out>
    implements RunBoardPageCopyWith<$R, RunBoardPage, $Out> {
  _RunBoardPageCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<RunBoardPage> $mapper =
      RunBoardPageMapper.ensureInitialized();
  @override
  RunBoardCountsCopyWith<$R, RunBoardCounts, RunBoardCounts> get counts =>
      $value.counts.copyWith.$chain((v) => call(counts: v));
  @override
  ListCopyWith<$R, RunSummary, RunSummaryCopyWith<$R, RunSummary, RunSummary>>
  get items => ListCopyWith(
    $value.items,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(items: v),
  );
  @override
  RunBoardCursorCopyWith<$R, RunBoardCursor, RunBoardCursor>? get nextCursor =>
      $value.nextCursor?.copyWith.$chain((v) => call(nextCursor: v));
  @override
  $R call({
    int? revision,
    RunBoardCounts? counts,
    List<RunSummary>? items,
    Object? nextCursor = $none,
  }) => $apply(
    FieldCopyWithData({
      if (revision != null) #revision: revision,
      if (counts != null) #counts: counts,
      if (items != null) #items: items,
      if (nextCursor != $none) #nextCursor: nextCursor,
    }),
  );
  @override
  RunBoardPage $make(CopyWithData data) => RunBoardPage(
    revision: data.get(#revision, or: $value.revision),
    counts: data.get(#counts, or: $value.counts),
    items: data.get(#items, or: $value.items),
    nextCursor: data.get(#nextCursor, or: $value.nextCursor),
  );

  @override
  RunBoardPageCopyWith<$R2, RunBoardPage, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _RunBoardPageCopyWithImpl<$R2, $Out2>($value, $cast, t);
}
