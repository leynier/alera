// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'run_gate.dart';

class RunGateKindMapper extends EnumMapper<RunGateKind> {
  RunGateKindMapper._();

  static RunGateKindMapper? _instance;
  static RunGateKindMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RunGateKindMapper._());
    }
    return _instance!;
  }

  static RunGateKind fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  RunGateKind decode(dynamic value) {
    switch (value) {
      case r'decision':
        return RunGateKind.decision;
      case r'stall':
        return RunGateKind.stall;
      case r'plan':
        return RunGateKind.plan;
      case r'stage':
        return RunGateKind.stage;
      default:
        return RunGateKind.values[0];
    }
  }

  @override
  dynamic encode(RunGateKind self) {
    switch (self) {
      case RunGateKind.decision:
        return r'decision';
      case RunGateKind.stall:
        return r'stall';
      case RunGateKind.plan:
        return r'plan';
      case RunGateKind.stage:
        return r'stage';
    }
  }
}

extension RunGateKindMapperExtension on RunGateKind {
  String toValue() {
    RunGateKindMapper.ensureInitialized();
    return MapperContainer.globals.toValue<RunGateKind>(this) as String;
  }
}

class RunGateStatusMapper extends EnumMapper<RunGateStatus> {
  RunGateStatusMapper._();

  static RunGateStatusMapper? _instance;
  static RunGateStatusMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RunGateStatusMapper._());
    }
    return _instance!;
  }

  static RunGateStatus fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  RunGateStatus decode(dynamic value) {
    switch (value) {
      case r'pending':
        return RunGateStatus.pending;
      case r'resolved':
        return RunGateStatus.resolved;
      case r'timeout':
        return RunGateStatus.timeout;
      case r'invalidated':
        return RunGateStatus.invalidated;
      default:
        return RunGateStatus.values[3];
    }
  }

  @override
  dynamic encode(RunGateStatus self) {
    switch (self) {
      case RunGateStatus.pending:
        return r'pending';
      case RunGateStatus.resolved:
        return r'resolved';
      case RunGateStatus.timeout:
        return r'timeout';
      case RunGateStatus.invalidated:
        return r'invalidated';
    }
  }
}

extension RunGateStatusMapperExtension on RunGateStatus {
  String toValue() {
    RunGateStatusMapper.ensureInitialized();
    return MapperContainer.globals.toValue<RunGateStatus>(this) as String;
  }
}

class RunGateMapper extends ClassMapperBase<RunGate> {
  RunGateMapper._();

  static RunGateMapper? _instance;
  static RunGateMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RunGateMapper._());
      RunGateKindMapper.ensureInitialized();
      RunGateStatusMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'RunGate';

  static String _$id(RunGate v) => v.id;
  static const Field<RunGate, String> _f$id = Field('id', _$id);
  static String? _$runId(RunGate v) => v.runId;
  static const Field<RunGate, String> _f$runId = Field(
    'runId',
    _$runId,
    opt: true,
  );
  static String? _$taskId(RunGate v) => v.taskId;
  static const Field<RunGate, String> _f$taskId = Field(
    'taskId',
    _$taskId,
    opt: true,
  );
  static RunGateKind _$kind(RunGate v) => v.kind;
  static const Field<RunGate, RunGateKind> _f$kind = Field('kind', _$kind);
  static String _$scope(RunGate v) => v.scope;
  static const Field<RunGate, String> _f$scope = Field(
    'scope',
    _$scope,
    opt: true,
    def: '',
  );
  static String _$question(RunGate v) => v.question;
  static const Field<RunGate, String> _f$question = Field(
    'question',
    _$question,
    opt: true,
    def: '',
  );
  static List<String> _$options(RunGate v) => v.options;
  static const Field<RunGate, List<String>> _f$options = Field(
    'options',
    _$options,
    opt: true,
    def: const <String>[],
  );
  static RunGateStatus _$status(RunGate v) => v.status;
  static const Field<RunGate, RunGateStatus> _f$status = Field(
    'status',
    _$status,
  );
  static bool _$due(RunGate v) => v.due;
  static const Field<RunGate, bool> _f$due = Field(
    'due',
    _$due,
    opt: true,
    def: false,
  );
  static String? _$resolution(RunGate v) => v.resolution;
  static const Field<RunGate, String> _f$resolution = Field(
    'resolution',
    _$resolution,
    opt: true,
  );
  static String? _$reason(RunGate v) => v.reason;
  static const Field<RunGate, String> _f$reason = Field(
    'reason',
    _$reason,
    opt: true,
  );
  static int? _$planRevision(RunGate v) => v.planRevision;
  static const Field<RunGate, int> _f$planRevision = Field(
    'planRevision',
    _$planRevision,
    opt: true,
  );
  static String? _$evidenceDigest(RunGate v) => v.evidenceDigest;
  static const Field<RunGate, String> _f$evidenceDigest = Field(
    'evidenceDigest',
    _$evidenceDigest,
    opt: true,
  );
  static String? _$integrationSha(RunGate v) => v.integrationSha;
  static const Field<RunGate, String> _f$integrationSha = Field(
    'integrationSha',
    _$integrationSha,
    opt: true,
  );
  static String? _$actorKind(RunGate v) => v.actorKind;
  static const Field<RunGate, String> _f$actorKind = Field(
    'actorKind',
    _$actorKind,
    opt: true,
  );
  static String? _$actorId(RunGate v) => v.actorId;
  static const Field<RunGate, String> _f$actorId = Field(
    'actorId',
    _$actorId,
    opt: true,
  );
  static String _$createdAt(RunGate v) => v.createdAt;
  static const Field<RunGate, String> _f$createdAt = Field(
    'createdAt',
    _$createdAt,
  );
  static String? _$resolvedAt(RunGate v) => v.resolvedAt;
  static const Field<RunGate, String> _f$resolvedAt = Field(
    'resolvedAt',
    _$resolvedAt,
    opt: true,
  );

  @override
  final MappableFields<RunGate> fields = const {
    #id: _f$id,
    #runId: _f$runId,
    #taskId: _f$taskId,
    #kind: _f$kind,
    #scope: _f$scope,
    #question: _f$question,
    #options: _f$options,
    #status: _f$status,
    #due: _f$due,
    #resolution: _f$resolution,
    #reason: _f$reason,
    #planRevision: _f$planRevision,
    #evidenceDigest: _f$evidenceDigest,
    #integrationSha: _f$integrationSha,
    #actorKind: _f$actorKind,
    #actorId: _f$actorId,
    #createdAt: _f$createdAt,
    #resolvedAt: _f$resolvedAt,
  };

  static RunGate _instantiate(DecodingData data) {
    return RunGate(
      id: data.dec(_f$id),
      runId: data.dec(_f$runId),
      taskId: data.dec(_f$taskId),
      kind: data.dec(_f$kind),
      scope: data.dec(_f$scope),
      question: data.dec(_f$question),
      options: data.dec(_f$options),
      status: data.dec(_f$status),
      due: data.dec(_f$due),
      resolution: data.dec(_f$resolution),
      reason: data.dec(_f$reason),
      planRevision: data.dec(_f$planRevision),
      evidenceDigest: data.dec(_f$evidenceDigest),
      integrationSha: data.dec(_f$integrationSha),
      actorKind: data.dec(_f$actorKind),
      actorId: data.dec(_f$actorId),
      createdAt: data.dec(_f$createdAt),
      resolvedAt: data.dec(_f$resolvedAt),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static RunGate fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<RunGate>(map);
  }

  static RunGate fromJson(String json) {
    return ensureInitialized().decodeJson<RunGate>(json);
  }
}

mixin RunGateMappable {
  String toJson() {
    return RunGateMapper.ensureInitialized().encodeJson<RunGate>(
      this as RunGate,
    );
  }

  Map<String, dynamic> toMap() {
    return RunGateMapper.ensureInitialized().encodeMap<RunGate>(
      this as RunGate,
    );
  }

  RunGateCopyWith<RunGate, RunGate, RunGate> get copyWith =>
      _RunGateCopyWithImpl<RunGate, RunGate>(
        this as RunGate,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return RunGateMapper.ensureInitialized().stringifyValue(this as RunGate);
  }

  @override
  bool operator ==(Object other) {
    return RunGateMapper.ensureInitialized().equalsValue(
      this as RunGate,
      other,
    );
  }

  @override
  int get hashCode {
    return RunGateMapper.ensureInitialized().hashValue(this as RunGate);
  }
}

extension RunGateValueCopy<$R, $Out> on ObjectCopyWith<$R, RunGate, $Out> {
  RunGateCopyWith<$R, RunGate, $Out> get $asRunGate =>
      $base.as((v, t, t2) => _RunGateCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class RunGateCopyWith<$R, $In extends RunGate, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get options;
  $R call({
    String? id,
    String? runId,
    String? taskId,
    RunGateKind? kind,
    String? scope,
    String? question,
    List<String>? options,
    RunGateStatus? status,
    bool? due,
    String? resolution,
    String? reason,
    int? planRevision,
    String? evidenceDigest,
    String? integrationSha,
    String? actorKind,
    String? actorId,
    String? createdAt,
    String? resolvedAt,
  });
  RunGateCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _RunGateCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, RunGate, $Out>
    implements RunGateCopyWith<$R, RunGate, $Out> {
  _RunGateCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<RunGate> $mapper =
      RunGateMapper.ensureInitialized();
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get options =>
      ListCopyWith(
        $value.options,
        (v, t) => ObjectCopyWith(v, $identity, t),
        (v) => call(options: v),
      );
  @override
  $R call({
    String? id,
    Object? runId = $none,
    Object? taskId = $none,
    RunGateKind? kind,
    String? scope,
    String? question,
    List<String>? options,
    RunGateStatus? status,
    bool? due,
    Object? resolution = $none,
    Object? reason = $none,
    Object? planRevision = $none,
    Object? evidenceDigest = $none,
    Object? integrationSha = $none,
    Object? actorKind = $none,
    Object? actorId = $none,
    String? createdAt,
    Object? resolvedAt = $none,
  }) => $apply(
    FieldCopyWithData({
      if (id != null) #id: id,
      if (runId != $none) #runId: runId,
      if (taskId != $none) #taskId: taskId,
      if (kind != null) #kind: kind,
      if (scope != null) #scope: scope,
      if (question != null) #question: question,
      if (options != null) #options: options,
      if (status != null) #status: status,
      if (due != null) #due: due,
      if (resolution != $none) #resolution: resolution,
      if (reason != $none) #reason: reason,
      if (planRevision != $none) #planRevision: planRevision,
      if (evidenceDigest != $none) #evidenceDigest: evidenceDigest,
      if (integrationSha != $none) #integrationSha: integrationSha,
      if (actorKind != $none) #actorKind: actorKind,
      if (actorId != $none) #actorId: actorId,
      if (createdAt != null) #createdAt: createdAt,
      if (resolvedAt != $none) #resolvedAt: resolvedAt,
    }),
  );
  @override
  RunGate $make(CopyWithData data) => RunGate(
    id: data.get(#id, or: $value.id),
    runId: data.get(#runId, or: $value.runId),
    taskId: data.get(#taskId, or: $value.taskId),
    kind: data.get(#kind, or: $value.kind),
    scope: data.get(#scope, or: $value.scope),
    question: data.get(#question, or: $value.question),
    options: data.get(#options, or: $value.options),
    status: data.get(#status, or: $value.status),
    due: data.get(#due, or: $value.due),
    resolution: data.get(#resolution, or: $value.resolution),
    reason: data.get(#reason, or: $value.reason),
    planRevision: data.get(#planRevision, or: $value.planRevision),
    evidenceDigest: data.get(#evidenceDigest, or: $value.evidenceDigest),
    integrationSha: data.get(#integrationSha, or: $value.integrationSha),
    actorKind: data.get(#actorKind, or: $value.actorKind),
    actorId: data.get(#actorId, or: $value.actorId),
    createdAt: data.get(#createdAt, or: $value.createdAt),
    resolvedAt: data.get(#resolvedAt, or: $value.resolvedAt),
  );

  @override
  RunGateCopyWith<$R2, RunGate, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _RunGateCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class RunGateEvidenceTaskMapper extends ClassMapperBase<RunGateEvidenceTask> {
  RunGateEvidenceTaskMapper._();

  static RunGateEvidenceTaskMapper? _instance;
  static RunGateEvidenceTaskMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RunGateEvidenceTaskMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'RunGateEvidenceTask';

  static String _$taskId(RunGateEvidenceTask v) => v.taskId;
  static const Field<RunGateEvidenceTask, String> _f$taskId = Field(
    'taskId',
    _$taskId,
  );
  static String? _$logicalId(RunGateEvidenceTask v) => v.logicalId;
  static const Field<RunGateEvidenceTask, String> _f$logicalId = Field(
    'logicalId',
    _$logicalId,
    opt: true,
  );
  static String _$title(RunGateEvidenceTask v) => v.title;
  static const Field<RunGateEvidenceTask, String> _f$title = Field(
    'title',
    _$title,
  );
  static String? _$stageId(RunGateEvidenceTask v) => v.stageId;
  static const Field<RunGateEvidenceTask, String> _f$stageId = Field(
    'stageId',
    _$stageId,
    opt: true,
  );
  static String _$status(RunGateEvidenceTask v) => v.status;
  static const Field<RunGateEvidenceTask, String> _f$status = Field(
    'status',
    _$status,
  );
  static String? _$resultPreview(RunGateEvidenceTask v) => v.resultPreview;
  static const Field<RunGateEvidenceTask, String> _f$resultPreview = Field(
    'resultPreview',
    _$resultPreview,
    opt: true,
  );
  static bool _$resultTruncated(RunGateEvidenceTask v) => v.resultTruncated;
  static const Field<RunGateEvidenceTask, bool> _f$resultTruncated = Field(
    'resultTruncated',
    _$resultTruncated,
    opt: true,
    def: false,
  );
  static String? _$resultDigest(RunGateEvidenceTask v) => v.resultDigest;
  static const Field<RunGateEvidenceTask, String> _f$resultDigest = Field(
    'resultDigest',
    _$resultDigest,
    opt: true,
  );
  static String? _$artifactDigest(RunGateEvidenceTask v) => v.artifactDigest;
  static const Field<RunGateEvidenceTask, String> _f$artifactDigest = Field(
    'artifactDigest',
    _$artifactDigest,
    opt: true,
  );
  static String? _$integrationSha(RunGateEvidenceTask v) => v.integrationSha;
  static const Field<RunGateEvidenceTask, String> _f$integrationSha = Field(
    'integrationSha',
    _$integrationSha,
    opt: true,
  );
  static String? _$integrationState(RunGateEvidenceTask v) =>
      v.integrationState;
  static const Field<RunGateEvidenceTask, String> _f$integrationState = Field(
    'integrationState',
    _$integrationState,
    opt: true,
  );
  static List<String> _$conflictPaths(RunGateEvidenceTask v) => v.conflictPaths;
  static const Field<RunGateEvidenceTask, List<String>> _f$conflictPaths =
      Field('conflictPaths', _$conflictPaths, opt: true, def: const <String>[]);
  static String? _$assignee(RunGateEvidenceTask v) => v.assignee;
  static const Field<RunGateEvidenceTask, String> _f$assignee = Field(
    'assignee',
    _$assignee,
    opt: true,
  );

  @override
  final MappableFields<RunGateEvidenceTask> fields = const {
    #taskId: _f$taskId,
    #logicalId: _f$logicalId,
    #title: _f$title,
    #stageId: _f$stageId,
    #status: _f$status,
    #resultPreview: _f$resultPreview,
    #resultTruncated: _f$resultTruncated,
    #resultDigest: _f$resultDigest,
    #artifactDigest: _f$artifactDigest,
    #integrationSha: _f$integrationSha,
    #integrationState: _f$integrationState,
    #conflictPaths: _f$conflictPaths,
    #assignee: _f$assignee,
  };

  static RunGateEvidenceTask _instantiate(DecodingData data) {
    return RunGateEvidenceTask(
      taskId: data.dec(_f$taskId),
      logicalId: data.dec(_f$logicalId),
      title: data.dec(_f$title),
      stageId: data.dec(_f$stageId),
      status: data.dec(_f$status),
      resultPreview: data.dec(_f$resultPreview),
      resultTruncated: data.dec(_f$resultTruncated),
      resultDigest: data.dec(_f$resultDigest),
      artifactDigest: data.dec(_f$artifactDigest),
      integrationSha: data.dec(_f$integrationSha),
      integrationState: data.dec(_f$integrationState),
      conflictPaths: data.dec(_f$conflictPaths),
      assignee: data.dec(_f$assignee),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static RunGateEvidenceTask fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<RunGateEvidenceTask>(map);
  }

  static RunGateEvidenceTask fromJson(String json) {
    return ensureInitialized().decodeJson<RunGateEvidenceTask>(json);
  }
}

mixin RunGateEvidenceTaskMappable {
  String toJson() {
    return RunGateEvidenceTaskMapper.ensureInitialized()
        .encodeJson<RunGateEvidenceTask>(this as RunGateEvidenceTask);
  }

  Map<String, dynamic> toMap() {
    return RunGateEvidenceTaskMapper.ensureInitialized()
        .encodeMap<RunGateEvidenceTask>(this as RunGateEvidenceTask);
  }

  RunGateEvidenceTaskCopyWith<
    RunGateEvidenceTask,
    RunGateEvidenceTask,
    RunGateEvidenceTask
  >
  get copyWith =>
      _RunGateEvidenceTaskCopyWithImpl<
        RunGateEvidenceTask,
        RunGateEvidenceTask
      >(this as RunGateEvidenceTask, $identity, $identity);
  @override
  String toString() {
    return RunGateEvidenceTaskMapper.ensureInitialized().stringifyValue(
      this as RunGateEvidenceTask,
    );
  }

  @override
  bool operator ==(Object other) {
    return RunGateEvidenceTaskMapper.ensureInitialized().equalsValue(
      this as RunGateEvidenceTask,
      other,
    );
  }

  @override
  int get hashCode {
    return RunGateEvidenceTaskMapper.ensureInitialized().hashValue(
      this as RunGateEvidenceTask,
    );
  }
}

extension RunGateEvidenceTaskValueCopy<$R, $Out>
    on ObjectCopyWith<$R, RunGateEvidenceTask, $Out> {
  RunGateEvidenceTaskCopyWith<$R, RunGateEvidenceTask, $Out>
  get $asRunGateEvidenceTask => $base.as(
    (v, t, t2) => _RunGateEvidenceTaskCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class RunGateEvidenceTaskCopyWith<
  $R,
  $In extends RunGateEvidenceTask,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>>
  get conflictPaths;
  $R call({
    String? taskId,
    String? logicalId,
    String? title,
    String? stageId,
    String? status,
    String? resultPreview,
    bool? resultTruncated,
    String? resultDigest,
    String? artifactDigest,
    String? integrationSha,
    String? integrationState,
    List<String>? conflictPaths,
    String? assignee,
  });
  RunGateEvidenceTaskCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _RunGateEvidenceTaskCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, RunGateEvidenceTask, $Out>
    implements RunGateEvidenceTaskCopyWith<$R, RunGateEvidenceTask, $Out> {
  _RunGateEvidenceTaskCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<RunGateEvidenceTask> $mapper =
      RunGateEvidenceTaskMapper.ensureInitialized();
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>>
  get conflictPaths => ListCopyWith(
    $value.conflictPaths,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(conflictPaths: v),
  );
  @override
  $R call({
    String? taskId,
    Object? logicalId = $none,
    String? title,
    Object? stageId = $none,
    String? status,
    Object? resultPreview = $none,
    bool? resultTruncated,
    Object? resultDigest = $none,
    Object? artifactDigest = $none,
    Object? integrationSha = $none,
    Object? integrationState = $none,
    List<String>? conflictPaths,
    Object? assignee = $none,
  }) => $apply(
    FieldCopyWithData({
      if (taskId != null) #taskId: taskId,
      if (logicalId != $none) #logicalId: logicalId,
      if (title != null) #title: title,
      if (stageId != $none) #stageId: stageId,
      if (status != null) #status: status,
      if (resultPreview != $none) #resultPreview: resultPreview,
      if (resultTruncated != null) #resultTruncated: resultTruncated,
      if (resultDigest != $none) #resultDigest: resultDigest,
      if (artifactDigest != $none) #artifactDigest: artifactDigest,
      if (integrationSha != $none) #integrationSha: integrationSha,
      if (integrationState != $none) #integrationState: integrationState,
      if (conflictPaths != null) #conflictPaths: conflictPaths,
      if (assignee != $none) #assignee: assignee,
    }),
  );
  @override
  RunGateEvidenceTask $make(CopyWithData data) => RunGateEvidenceTask(
    taskId: data.get(#taskId, or: $value.taskId),
    logicalId: data.get(#logicalId, or: $value.logicalId),
    title: data.get(#title, or: $value.title),
    stageId: data.get(#stageId, or: $value.stageId),
    status: data.get(#status, or: $value.status),
    resultPreview: data.get(#resultPreview, or: $value.resultPreview),
    resultTruncated: data.get(#resultTruncated, or: $value.resultTruncated),
    resultDigest: data.get(#resultDigest, or: $value.resultDigest),
    artifactDigest: data.get(#artifactDigest, or: $value.artifactDigest),
    integrationSha: data.get(#integrationSha, or: $value.integrationSha),
    integrationState: data.get(#integrationState, or: $value.integrationState),
    conflictPaths: data.get(#conflictPaths, or: $value.conflictPaths),
    assignee: data.get(#assignee, or: $value.assignee),
  );

  @override
  RunGateEvidenceTaskCopyWith<$R2, RunGateEvidenceTask, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _RunGateEvidenceTaskCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class RunGateDetailMapper extends ClassMapperBase<RunGateDetail> {
  RunGateDetailMapper._();

  static RunGateDetailMapper? _instance;
  static RunGateDetailMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RunGateDetailMapper._());
      RunGateMapper.ensureInitialized();
      RunPlanViewMapper.ensureInitialized();
      RunGateEvidenceTaskMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'RunGateDetail';

  static RunGate _$gate(RunGateDetail v) => v.gate;
  static const Field<RunGateDetail, RunGate> _f$gate = Field('gate', _$gate);
  static RunPlanView? _$plan(RunGateDetail v) => v.plan;
  static const Field<RunGateDetail, RunPlanView> _f$plan = Field(
    'plan',
    _$plan,
    opt: true,
  );
  static List<RunGateEvidenceTask> _$tasks(RunGateDetail v) => v.tasks;
  static const Field<RunGateDetail, List<RunGateEvidenceTask>> _f$tasks = Field(
    'tasks',
    _$tasks,
    opt: true,
    def: const <RunGateEvidenceTask>[],
  );

  @override
  final MappableFields<RunGateDetail> fields = const {
    #gate: _f$gate,
    #plan: _f$plan,
    #tasks: _f$tasks,
  };

  static RunGateDetail _instantiate(DecodingData data) {
    return RunGateDetail(
      gate: data.dec(_f$gate),
      plan: data.dec(_f$plan),
      tasks: data.dec(_f$tasks),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static RunGateDetail fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<RunGateDetail>(map);
  }

  static RunGateDetail fromJson(String json) {
    return ensureInitialized().decodeJson<RunGateDetail>(json);
  }
}

mixin RunGateDetailMappable {
  String toJson() {
    return RunGateDetailMapper.ensureInitialized().encodeJson<RunGateDetail>(
      this as RunGateDetail,
    );
  }

  Map<String, dynamic> toMap() {
    return RunGateDetailMapper.ensureInitialized().encodeMap<RunGateDetail>(
      this as RunGateDetail,
    );
  }

  RunGateDetailCopyWith<RunGateDetail, RunGateDetail, RunGateDetail>
  get copyWith => _RunGateDetailCopyWithImpl<RunGateDetail, RunGateDetail>(
    this as RunGateDetail,
    $identity,
    $identity,
  );
  @override
  String toString() {
    return RunGateDetailMapper.ensureInitialized().stringifyValue(
      this as RunGateDetail,
    );
  }

  @override
  bool operator ==(Object other) {
    return RunGateDetailMapper.ensureInitialized().equalsValue(
      this as RunGateDetail,
      other,
    );
  }

  @override
  int get hashCode {
    return RunGateDetailMapper.ensureInitialized().hashValue(
      this as RunGateDetail,
    );
  }
}

extension RunGateDetailValueCopy<$R, $Out>
    on ObjectCopyWith<$R, RunGateDetail, $Out> {
  RunGateDetailCopyWith<$R, RunGateDetail, $Out> get $asRunGateDetail =>
      $base.as((v, t, t2) => _RunGateDetailCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class RunGateDetailCopyWith<$R, $In extends RunGateDetail, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  RunGateCopyWith<$R, RunGate, RunGate> get gate;
  RunPlanViewCopyWith<$R, RunPlanView, RunPlanView>? get plan;
  ListCopyWith<
    $R,
    RunGateEvidenceTask,
    RunGateEvidenceTaskCopyWith<$R, RunGateEvidenceTask, RunGateEvidenceTask>
  >
  get tasks;
  $R call({RunGate? gate, RunPlanView? plan, List<RunGateEvidenceTask>? tasks});
  RunGateDetailCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _RunGateDetailCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, RunGateDetail, $Out>
    implements RunGateDetailCopyWith<$R, RunGateDetail, $Out> {
  _RunGateDetailCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<RunGateDetail> $mapper =
      RunGateDetailMapper.ensureInitialized();
  @override
  RunGateCopyWith<$R, RunGate, RunGate> get gate =>
      $value.gate.copyWith.$chain((v) => call(gate: v));
  @override
  RunPlanViewCopyWith<$R, RunPlanView, RunPlanView>? get plan =>
      $value.plan?.copyWith.$chain((v) => call(plan: v));
  @override
  ListCopyWith<
    $R,
    RunGateEvidenceTask,
    RunGateEvidenceTaskCopyWith<$R, RunGateEvidenceTask, RunGateEvidenceTask>
  >
  get tasks => ListCopyWith(
    $value.tasks,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(tasks: v),
  );
  @override
  $R call({
    RunGate? gate,
    Object? plan = $none,
    List<RunGateEvidenceTask>? tasks,
  }) => $apply(
    FieldCopyWithData({
      if (gate != null) #gate: gate,
      if (plan != $none) #plan: plan,
      if (tasks != null) #tasks: tasks,
    }),
  );
  @override
  RunGateDetail $make(CopyWithData data) => RunGateDetail(
    gate: data.get(#gate, or: $value.gate),
    plan: data.get(#plan, or: $value.plan),
    tasks: data.get(#tasks, or: $value.tasks),
  );

  @override
  RunGateDetailCopyWith<$R2, RunGateDetail, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _RunGateDetailCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class RunGateReceiptMapper extends ClassMapperBase<RunGateReceipt> {
  RunGateReceiptMapper._();

  static RunGateReceiptMapper? _instance;
  static RunGateReceiptMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RunGateReceiptMapper._());
      RunGateMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'RunGateReceipt';

  static String _$requestId(RunGateReceipt v) => v.requestId;
  static const Field<RunGateReceipt, String> _f$requestId = Field(
    'requestId',
    _$requestId,
  );
  static RunGate _$gate(RunGateReceipt v) => v.gate;
  static const Field<RunGateReceipt, RunGate> _f$gate = Field('gate', _$gate);
  static String? _$runId(RunGateReceipt v) => v.runId;
  static const Field<RunGateReceipt, String> _f$runId = Field(
    'runId',
    _$runId,
    opt: true,
  );
  static String? _$runStatus(RunGateReceipt v) => v.runStatus;
  static const Field<RunGateReceipt, String> _f$runStatus = Field(
    'runStatus',
    _$runStatus,
    opt: true,
  );
  static int? _$planRevision(RunGateReceipt v) => v.planRevision;
  static const Field<RunGateReceipt, int> _f$planRevision = Field(
    'planRevision',
    _$planRevision,
    opt: true,
  );
  static bool _$changesRequested(RunGateReceipt v) => v.changesRequested;
  static const Field<RunGateReceipt, bool> _f$changesRequested = Field(
    'changesRequested',
    _$changesRequested,
    opt: true,
    def: false,
  );
  static String _$coordinatorAction(RunGateReceipt v) => v.coordinatorAction;
  static const Field<RunGateReceipt, String> _f$coordinatorAction = Field(
    'coordinatorAction',
    _$coordinatorAction,
    opt: true,
    def: 'none',
  );

  @override
  final MappableFields<RunGateReceipt> fields = const {
    #requestId: _f$requestId,
    #gate: _f$gate,
    #runId: _f$runId,
    #runStatus: _f$runStatus,
    #planRevision: _f$planRevision,
    #changesRequested: _f$changesRequested,
    #coordinatorAction: _f$coordinatorAction,
  };

  static RunGateReceipt _instantiate(DecodingData data) {
    return RunGateReceipt(
      requestId: data.dec(_f$requestId),
      gate: data.dec(_f$gate),
      runId: data.dec(_f$runId),
      runStatus: data.dec(_f$runStatus),
      planRevision: data.dec(_f$planRevision),
      changesRequested: data.dec(_f$changesRequested),
      coordinatorAction: data.dec(_f$coordinatorAction),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static RunGateReceipt fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<RunGateReceipt>(map);
  }

  static RunGateReceipt fromJson(String json) {
    return ensureInitialized().decodeJson<RunGateReceipt>(json);
  }
}

mixin RunGateReceiptMappable {
  String toJson() {
    return RunGateReceiptMapper.ensureInitialized().encodeJson<RunGateReceipt>(
      this as RunGateReceipt,
    );
  }

  Map<String, dynamic> toMap() {
    return RunGateReceiptMapper.ensureInitialized().encodeMap<RunGateReceipt>(
      this as RunGateReceipt,
    );
  }

  RunGateReceiptCopyWith<RunGateReceipt, RunGateReceipt, RunGateReceipt>
  get copyWith => _RunGateReceiptCopyWithImpl<RunGateReceipt, RunGateReceipt>(
    this as RunGateReceipt,
    $identity,
    $identity,
  );
  @override
  String toString() {
    return RunGateReceiptMapper.ensureInitialized().stringifyValue(
      this as RunGateReceipt,
    );
  }

  @override
  bool operator ==(Object other) {
    return RunGateReceiptMapper.ensureInitialized().equalsValue(
      this as RunGateReceipt,
      other,
    );
  }

  @override
  int get hashCode {
    return RunGateReceiptMapper.ensureInitialized().hashValue(
      this as RunGateReceipt,
    );
  }
}

extension RunGateReceiptValueCopy<$R, $Out>
    on ObjectCopyWith<$R, RunGateReceipt, $Out> {
  RunGateReceiptCopyWith<$R, RunGateReceipt, $Out> get $asRunGateReceipt =>
      $base.as((v, t, t2) => _RunGateReceiptCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class RunGateReceiptCopyWith<$R, $In extends RunGateReceipt, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  RunGateCopyWith<$R, RunGate, RunGate> get gate;
  $R call({
    String? requestId,
    RunGate? gate,
    String? runId,
    String? runStatus,
    int? planRevision,
    bool? changesRequested,
    String? coordinatorAction,
  });
  RunGateReceiptCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _RunGateReceiptCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, RunGateReceipt, $Out>
    implements RunGateReceiptCopyWith<$R, RunGateReceipt, $Out> {
  _RunGateReceiptCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<RunGateReceipt> $mapper =
      RunGateReceiptMapper.ensureInitialized();
  @override
  RunGateCopyWith<$R, RunGate, RunGate> get gate =>
      $value.gate.copyWith.$chain((v) => call(gate: v));
  @override
  $R call({
    String? requestId,
    RunGate? gate,
    Object? runId = $none,
    Object? runStatus = $none,
    Object? planRevision = $none,
    bool? changesRequested,
    String? coordinatorAction,
  }) => $apply(
    FieldCopyWithData({
      if (requestId != null) #requestId: requestId,
      if (gate != null) #gate: gate,
      if (runId != $none) #runId: runId,
      if (runStatus != $none) #runStatus: runStatus,
      if (planRevision != $none) #planRevision: planRevision,
      if (changesRequested != null) #changesRequested: changesRequested,
      if (coordinatorAction != null) #coordinatorAction: coordinatorAction,
    }),
  );
  @override
  RunGateReceipt $make(CopyWithData data) => RunGateReceipt(
    requestId: data.get(#requestId, or: $value.requestId),
    gate: data.get(#gate, or: $value.gate),
    runId: data.get(#runId, or: $value.runId),
    runStatus: data.get(#runStatus, or: $value.runStatus),
    planRevision: data.get(#planRevision, or: $value.planRevision),
    changesRequested: data.get(#changesRequested, or: $value.changesRequested),
    coordinatorAction: data.get(
      #coordinatorAction,
      or: $value.coordinatorAction,
    ),
  );

  @override
  RunGateReceiptCopyWith<$R2, RunGateReceipt, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _RunGateReceiptCopyWithImpl<$R2, $Out2>($value, $cast, t);
}
