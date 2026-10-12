// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'run_snapshot.dart';

class RunTaskAttemptMapper extends ClassMapperBase<RunTaskAttempt> {
  RunTaskAttemptMapper._();

  static RunTaskAttemptMapper? _instance;
  static RunTaskAttemptMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RunTaskAttemptMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'RunTaskAttempt';

  static String _$workspaceId(RunTaskAttempt v) => v.workspaceId;
  static const Field<RunTaskAttempt, String> _f$workspaceId = Field(
    'workspaceId',
    _$workspaceId,
  );
  static int _$attempt(RunTaskAttempt v) => v.attempt;
  static const Field<RunTaskAttempt, int> _f$attempt = Field(
    'attempt',
    _$attempt,
    opt: true,
    def: 1,
  );
  static String? _$branch(RunTaskAttempt v) => v.branch;
  static const Field<RunTaskAttempt, String> _f$branch = Field(
    'branch',
    _$branch,
    opt: true,
  );
  static String? _$baseSha(RunTaskAttempt v) => v.baseSha;
  static const Field<RunTaskAttempt, String> _f$baseSha = Field(
    'baseSha',
    _$baseSha,
    opt: true,
  );
  static String _$phase(RunTaskAttempt v) => v.phase;
  static const Field<RunTaskAttempt, String> _f$phase = Field(
    'phase',
    _$phase,
    opt: true,
    def: '',
  );

  @override
  final MappableFields<RunTaskAttempt> fields = const {
    #workspaceId: _f$workspaceId,
    #attempt: _f$attempt,
    #branch: _f$branch,
    #baseSha: _f$baseSha,
    #phase: _f$phase,
  };

  static RunTaskAttempt _instantiate(DecodingData data) {
    return RunTaskAttempt(
      workspaceId: data.dec(_f$workspaceId),
      attempt: data.dec(_f$attempt),
      branch: data.dec(_f$branch),
      baseSha: data.dec(_f$baseSha),
      phase: data.dec(_f$phase),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static RunTaskAttempt fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<RunTaskAttempt>(map);
  }

  static RunTaskAttempt fromJson(String json) {
    return ensureInitialized().decodeJson<RunTaskAttempt>(json);
  }
}

mixin RunTaskAttemptMappable {
  String toJson() {
    return RunTaskAttemptMapper.ensureInitialized().encodeJson<RunTaskAttempt>(
      this as RunTaskAttempt,
    );
  }

  Map<String, dynamic> toMap() {
    return RunTaskAttemptMapper.ensureInitialized().encodeMap<RunTaskAttempt>(
      this as RunTaskAttempt,
    );
  }

  RunTaskAttemptCopyWith<RunTaskAttempt, RunTaskAttempt, RunTaskAttempt>
  get copyWith => _RunTaskAttemptCopyWithImpl<RunTaskAttempt, RunTaskAttempt>(
    this as RunTaskAttempt,
    $identity,
    $identity,
  );
  @override
  String toString() {
    return RunTaskAttemptMapper.ensureInitialized().stringifyValue(
      this as RunTaskAttempt,
    );
  }

  @override
  bool operator ==(Object other) {
    return RunTaskAttemptMapper.ensureInitialized().equalsValue(
      this as RunTaskAttempt,
      other,
    );
  }

  @override
  int get hashCode {
    return RunTaskAttemptMapper.ensureInitialized().hashValue(
      this as RunTaskAttempt,
    );
  }
}

extension RunTaskAttemptValueCopy<$R, $Out>
    on ObjectCopyWith<$R, RunTaskAttempt, $Out> {
  RunTaskAttemptCopyWith<$R, RunTaskAttempt, $Out> get $asRunTaskAttempt =>
      $base.as((v, t, t2) => _RunTaskAttemptCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class RunTaskAttemptCopyWith<$R, $In extends RunTaskAttempt, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    String? workspaceId,
    int? attempt,
    String? branch,
    String? baseSha,
    String? phase,
  });
  RunTaskAttemptCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _RunTaskAttemptCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, RunTaskAttempt, $Out>
    implements RunTaskAttemptCopyWith<$R, RunTaskAttempt, $Out> {
  _RunTaskAttemptCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<RunTaskAttempt> $mapper =
      RunTaskAttemptMapper.ensureInitialized();
  @override
  $R call({
    String? workspaceId,
    int? attempt,
    Object? branch = $none,
    Object? baseSha = $none,
    String? phase,
  }) => $apply(
    FieldCopyWithData({
      if (workspaceId != null) #workspaceId: workspaceId,
      if (attempt != null) #attempt: attempt,
      if (branch != $none) #branch: branch,
      if (baseSha != $none) #baseSha: baseSha,
      if (phase != null) #phase: phase,
    }),
  );
  @override
  RunTaskAttempt $make(CopyWithData data) => RunTaskAttempt(
    workspaceId: data.get(#workspaceId, or: $value.workspaceId),
    attempt: data.get(#attempt, or: $value.attempt),
    branch: data.get(#branch, or: $value.branch),
    baseSha: data.get(#baseSha, or: $value.baseSha),
    phase: data.get(#phase, or: $value.phase),
  );

  @override
  RunTaskAttemptCopyWith<$R2, RunTaskAttempt, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _RunTaskAttemptCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class RunTaskIntegrationMapper extends ClassMapperBase<RunTaskIntegration> {
  RunTaskIntegrationMapper._();

  static RunTaskIntegrationMapper? _instance;
  static RunTaskIntegrationMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RunTaskIntegrationMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'RunTaskIntegration';

  static String _$state(RunTaskIntegration v) => v.state;
  static const Field<RunTaskIntegration, String> _f$state = Field(
    'state',
    _$state,
  );
  static String? _$sha(RunTaskIntegration v) => v.sha;
  static const Field<RunTaskIntegration, String> _f$sha = Field(
    'sha',
    _$sha,
    opt: true,
  );

  @override
  final MappableFields<RunTaskIntegration> fields = const {
    #state: _f$state,
    #sha: _f$sha,
  };

  static RunTaskIntegration _instantiate(DecodingData data) {
    return RunTaskIntegration(state: data.dec(_f$state), sha: data.dec(_f$sha));
  }

  @override
  final Function instantiate = _instantiate;

  static RunTaskIntegration fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<RunTaskIntegration>(map);
  }

  static RunTaskIntegration fromJson(String json) {
    return ensureInitialized().decodeJson<RunTaskIntegration>(json);
  }
}

mixin RunTaskIntegrationMappable {
  String toJson() {
    return RunTaskIntegrationMapper.ensureInitialized()
        .encodeJson<RunTaskIntegration>(this as RunTaskIntegration);
  }

  Map<String, dynamic> toMap() {
    return RunTaskIntegrationMapper.ensureInitialized()
        .encodeMap<RunTaskIntegration>(this as RunTaskIntegration);
  }

  RunTaskIntegrationCopyWith<
    RunTaskIntegration,
    RunTaskIntegration,
    RunTaskIntegration
  >
  get copyWith =>
      _RunTaskIntegrationCopyWithImpl<RunTaskIntegration, RunTaskIntegration>(
        this as RunTaskIntegration,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return RunTaskIntegrationMapper.ensureInitialized().stringifyValue(
      this as RunTaskIntegration,
    );
  }

  @override
  bool operator ==(Object other) {
    return RunTaskIntegrationMapper.ensureInitialized().equalsValue(
      this as RunTaskIntegration,
      other,
    );
  }

  @override
  int get hashCode {
    return RunTaskIntegrationMapper.ensureInitialized().hashValue(
      this as RunTaskIntegration,
    );
  }
}

extension RunTaskIntegrationValueCopy<$R, $Out>
    on ObjectCopyWith<$R, RunTaskIntegration, $Out> {
  RunTaskIntegrationCopyWith<$R, RunTaskIntegration, $Out>
  get $asRunTaskIntegration => $base.as(
    (v, t, t2) => _RunTaskIntegrationCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class RunTaskIntegrationCopyWith<
  $R,
  $In extends RunTaskIntegration,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({String? state, String? sha});
  RunTaskIntegrationCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _RunTaskIntegrationCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, RunTaskIntegration, $Out>
    implements RunTaskIntegrationCopyWith<$R, RunTaskIntegration, $Out> {
  _RunTaskIntegrationCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<RunTaskIntegration> $mapper =
      RunTaskIntegrationMapper.ensureInitialized();
  @override
  $R call({String? state, Object? sha = $none}) => $apply(
    FieldCopyWithData({
      if (state != null) #state: state,
      if (sha != $none) #sha: sha,
    }),
  );
  @override
  RunTaskIntegration $make(CopyWithData data) => RunTaskIntegration(
    state: data.get(#state, or: $value.state),
    sha: data.get(#sha, or: $value.sha),
  );

  @override
  RunTaskIntegrationCopyWith<$R2, RunTaskIntegration, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _RunTaskIntegrationCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class RunTaskMapper extends ClassMapperBase<RunTask> {
  RunTaskMapper._();

  static RunTaskMapper? _instance;
  static RunTaskMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RunTaskMapper._());
      RunTaskAttemptMapper.ensureInitialized();
      RunTaskIntegrationMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'RunTask';

  static String _$id(RunTask v) => v.id;
  static const Field<RunTask, String> _f$id = Field('id', _$id);
  static String? _$logicalId(RunTask v) => v.logicalId;
  static const Field<RunTask, String> _f$logicalId = Field(
    'logicalId',
    _$logicalId,
    opt: true,
  );
  static String _$title(RunTask v) => v.title;
  static const Field<RunTask, String> _f$title = Field('title', _$title);
  static String _$status(RunTask v) => v.status;
  static const Field<RunTask, String> _f$status = Field('status', _$status);
  static String? _$stageId(RunTask v) => v.stageId;
  static const Field<RunTask, String> _f$stageId = Field(
    'stageId',
    _$stageId,
    opt: true,
  );
  static String? _$roleId(RunTask v) => v.roleId;
  static const Field<RunTask, String> _f$roleId = Field(
    'roleId',
    _$roleId,
    opt: true,
  );
  static int? _$planRevision(RunTask v) => v.planRevision;
  static const Field<RunTask, int> _f$planRevision = Field(
    'planRevision',
    _$planRevision,
    opt: true,
  );
  static String _$workspaceId(RunTask v) => v.workspaceId;
  static const Field<RunTask, String> _f$workspaceId = Field(
    'workspaceId',
    _$workspaceId,
  );
  static List<String> _$dependencies(RunTask v) => v.dependencies;
  static const Field<RunTask, List<String>> _f$dependencies = Field(
    'dependencies',
    _$dependencies,
    opt: true,
    def: const <String>[],
  );
  static bool _$dependenciesTruncated(RunTask v) => v.dependenciesTruncated;
  static const Field<RunTask, bool> _f$dependenciesTruncated = Field(
    'dependenciesTruncated',
    _$dependenciesTruncated,
    opt: true,
    def: false,
  );
  static String? _$attemptState(RunTask v) => v.attemptState;
  static const Field<RunTask, String> _f$attemptState = Field(
    'attemptState',
    _$attemptState,
    opt: true,
  );
  static RunTaskAttempt? _$attempt(RunTask v) => v.attempt;
  static const Field<RunTask, RunTaskAttempt> _f$attempt = Field(
    'attempt',
    _$attempt,
    opt: true,
  );
  static RunTaskIntegration? _$integration(RunTask v) => v.integration;
  static const Field<RunTask, RunTaskIntegration> _f$integration = Field(
    'integration',
    _$integration,
    opt: true,
  );
  static String? _$profile(RunTask v) => v.profile;
  static const Field<RunTask, String> _f$profile = Field(
    'profile',
    _$profile,
    opt: true,
  );
  static String? _$assignee(RunTask v) => v.assignee;
  static const Field<RunTask, String> _f$assignee = Field(
    'assignee',
    _$assignee,
    opt: true,
  );
  static String? _$startedAt(RunTask v) => v.startedAt;
  static const Field<RunTask, String> _f$startedAt = Field(
    'startedAt',
    _$startedAt,
    opt: true,
  );
  static String? _$completedAt(RunTask v) => v.completedAt;
  static const Field<RunTask, String> _f$completedAt = Field(
    'completedAt',
    _$completedAt,
    opt: true,
  );
  static String? _$updatedAt(RunTask v) => v.updatedAt;
  static const Field<RunTask, String> _f$updatedAt = Field(
    'updatedAt',
    _$updatedAt,
    opt: true,
  );

  @override
  final MappableFields<RunTask> fields = const {
    #id: _f$id,
    #logicalId: _f$logicalId,
    #title: _f$title,
    #status: _f$status,
    #stageId: _f$stageId,
    #roleId: _f$roleId,
    #planRevision: _f$planRevision,
    #workspaceId: _f$workspaceId,
    #dependencies: _f$dependencies,
    #dependenciesTruncated: _f$dependenciesTruncated,
    #attemptState: _f$attemptState,
    #attempt: _f$attempt,
    #integration: _f$integration,
    #profile: _f$profile,
    #assignee: _f$assignee,
    #startedAt: _f$startedAt,
    #completedAt: _f$completedAt,
    #updatedAt: _f$updatedAt,
  };

  static RunTask _instantiate(DecodingData data) {
    return RunTask(
      id: data.dec(_f$id),
      logicalId: data.dec(_f$logicalId),
      title: data.dec(_f$title),
      status: data.dec(_f$status),
      stageId: data.dec(_f$stageId),
      roleId: data.dec(_f$roleId),
      planRevision: data.dec(_f$planRevision),
      workspaceId: data.dec(_f$workspaceId),
      dependencies: data.dec(_f$dependencies),
      dependenciesTruncated: data.dec(_f$dependenciesTruncated),
      attemptState: data.dec(_f$attemptState),
      attempt: data.dec(_f$attempt),
      integration: data.dec(_f$integration),
      profile: data.dec(_f$profile),
      assignee: data.dec(_f$assignee),
      startedAt: data.dec(_f$startedAt),
      completedAt: data.dec(_f$completedAt),
      updatedAt: data.dec(_f$updatedAt),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static RunTask fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<RunTask>(map);
  }

  static RunTask fromJson(String json) {
    return ensureInitialized().decodeJson<RunTask>(json);
  }
}

mixin RunTaskMappable {
  String toJson() {
    return RunTaskMapper.ensureInitialized().encodeJson<RunTask>(
      this as RunTask,
    );
  }

  Map<String, dynamic> toMap() {
    return RunTaskMapper.ensureInitialized().encodeMap<RunTask>(
      this as RunTask,
    );
  }

  RunTaskCopyWith<RunTask, RunTask, RunTask> get copyWith =>
      _RunTaskCopyWithImpl<RunTask, RunTask>(
        this as RunTask,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return RunTaskMapper.ensureInitialized().stringifyValue(this as RunTask);
  }

  @override
  bool operator ==(Object other) {
    return RunTaskMapper.ensureInitialized().equalsValue(
      this as RunTask,
      other,
    );
  }

  @override
  int get hashCode {
    return RunTaskMapper.ensureInitialized().hashValue(this as RunTask);
  }
}

extension RunTaskValueCopy<$R, $Out> on ObjectCopyWith<$R, RunTask, $Out> {
  RunTaskCopyWith<$R, RunTask, $Out> get $asRunTask =>
      $base.as((v, t, t2) => _RunTaskCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class RunTaskCopyWith<$R, $In extends RunTask, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get dependencies;
  RunTaskAttemptCopyWith<$R, RunTaskAttempt, RunTaskAttempt>? get attempt;
  RunTaskIntegrationCopyWith<$R, RunTaskIntegration, RunTaskIntegration>?
  get integration;
  $R call({
    String? id,
    String? logicalId,
    String? title,
    String? status,
    String? stageId,
    String? roleId,
    int? planRevision,
    String? workspaceId,
    List<String>? dependencies,
    bool? dependenciesTruncated,
    String? attemptState,
    RunTaskAttempt? attempt,
    RunTaskIntegration? integration,
    String? profile,
    String? assignee,
    String? startedAt,
    String? completedAt,
    String? updatedAt,
  });
  RunTaskCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _RunTaskCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, RunTask, $Out>
    implements RunTaskCopyWith<$R, RunTask, $Out> {
  _RunTaskCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<RunTask> $mapper =
      RunTaskMapper.ensureInitialized();
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>>
  get dependencies => ListCopyWith(
    $value.dependencies,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(dependencies: v),
  );
  @override
  RunTaskAttemptCopyWith<$R, RunTaskAttempt, RunTaskAttempt>? get attempt =>
      $value.attempt?.copyWith.$chain((v) => call(attempt: v));
  @override
  RunTaskIntegrationCopyWith<$R, RunTaskIntegration, RunTaskIntegration>?
  get integration =>
      $value.integration?.copyWith.$chain((v) => call(integration: v));
  @override
  $R call({
    String? id,
    Object? logicalId = $none,
    String? title,
    String? status,
    Object? stageId = $none,
    Object? roleId = $none,
    Object? planRevision = $none,
    String? workspaceId,
    List<String>? dependencies,
    bool? dependenciesTruncated,
    Object? attemptState = $none,
    Object? attempt = $none,
    Object? integration = $none,
    Object? profile = $none,
    Object? assignee = $none,
    Object? startedAt = $none,
    Object? completedAt = $none,
    Object? updatedAt = $none,
  }) => $apply(
    FieldCopyWithData({
      if (id != null) #id: id,
      if (logicalId != $none) #logicalId: logicalId,
      if (title != null) #title: title,
      if (status != null) #status: status,
      if (stageId != $none) #stageId: stageId,
      if (roleId != $none) #roleId: roleId,
      if (planRevision != $none) #planRevision: planRevision,
      if (workspaceId != null) #workspaceId: workspaceId,
      if (dependencies != null) #dependencies: dependencies,
      if (dependenciesTruncated != null)
        #dependenciesTruncated: dependenciesTruncated,
      if (attemptState != $none) #attemptState: attemptState,
      if (attempt != $none) #attempt: attempt,
      if (integration != $none) #integration: integration,
      if (profile != $none) #profile: profile,
      if (assignee != $none) #assignee: assignee,
      if (startedAt != $none) #startedAt: startedAt,
      if (completedAt != $none) #completedAt: completedAt,
      if (updatedAt != $none) #updatedAt: updatedAt,
    }),
  );
  @override
  RunTask $make(CopyWithData data) => RunTask(
    id: data.get(#id, or: $value.id),
    logicalId: data.get(#logicalId, or: $value.logicalId),
    title: data.get(#title, or: $value.title),
    status: data.get(#status, or: $value.status),
    stageId: data.get(#stageId, or: $value.stageId),
    roleId: data.get(#roleId, or: $value.roleId),
    planRevision: data.get(#planRevision, or: $value.planRevision),
    workspaceId: data.get(#workspaceId, or: $value.workspaceId),
    dependencies: data.get(#dependencies, or: $value.dependencies),
    dependenciesTruncated: data.get(
      #dependenciesTruncated,
      or: $value.dependenciesTruncated,
    ),
    attemptState: data.get(#attemptState, or: $value.attemptState),
    attempt: data.get(#attempt, or: $value.attempt),
    integration: data.get(#integration, or: $value.integration),
    profile: data.get(#profile, or: $value.profile),
    assignee: data.get(#assignee, or: $value.assignee),
    startedAt: data.get(#startedAt, or: $value.startedAt),
    completedAt: data.get(#completedAt, or: $value.completedAt),
    updatedAt: data.get(#updatedAt, or: $value.updatedAt),
  );

  @override
  RunTaskCopyWith<$R2, RunTask, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _RunTaskCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class RunPlanSummaryMapper extends ClassMapperBase<RunPlanSummary> {
  RunPlanSummaryMapper._();

  static RunPlanSummaryMapper? _instance;
  static RunPlanSummaryMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RunPlanSummaryMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'RunPlanSummary';

  static int _$revision(RunPlanSummary v) => v.revision;
  static const Field<RunPlanSummary, int> _f$revision = Field(
    'revision',
    _$revision,
  );
  static String _$digest(RunPlanSummary v) => v.digest;
  static const Field<RunPlanSummary, String> _f$digest = Field(
    'digest',
    _$digest,
    opt: true,
    def: '',
  );
  static int? _$previousRevision(RunPlanSummary v) => v.previousRevision;
  static const Field<RunPlanSummary, int> _f$previousRevision = Field(
    'previousRevision',
    _$previousRevision,
    opt: true,
  );
  static String? _$changeReason(RunPlanSummary v) => v.changeReason;
  static const Field<RunPlanSummary, String> _f$changeReason = Field(
    'changeReason',
    _$changeReason,
    opt: true,
  );
  static String _$state(RunPlanSummary v) => v.state;
  static const Field<RunPlanSummary, String> _f$state = Field(
    'state',
    _$state,
    opt: true,
    def: 'approved',
  );

  @override
  final MappableFields<RunPlanSummary> fields = const {
    #revision: _f$revision,
    #digest: _f$digest,
    #previousRevision: _f$previousRevision,
    #changeReason: _f$changeReason,
    #state: _f$state,
  };

  static RunPlanSummary _instantiate(DecodingData data) {
    return RunPlanSummary(
      revision: data.dec(_f$revision),
      digest: data.dec(_f$digest),
      previousRevision: data.dec(_f$previousRevision),
      changeReason: data.dec(_f$changeReason),
      state: data.dec(_f$state),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static RunPlanSummary fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<RunPlanSummary>(map);
  }

  static RunPlanSummary fromJson(String json) {
    return ensureInitialized().decodeJson<RunPlanSummary>(json);
  }
}

mixin RunPlanSummaryMappable {
  String toJson() {
    return RunPlanSummaryMapper.ensureInitialized().encodeJson<RunPlanSummary>(
      this as RunPlanSummary,
    );
  }

  Map<String, dynamic> toMap() {
    return RunPlanSummaryMapper.ensureInitialized().encodeMap<RunPlanSummary>(
      this as RunPlanSummary,
    );
  }

  RunPlanSummaryCopyWith<RunPlanSummary, RunPlanSummary, RunPlanSummary>
  get copyWith => _RunPlanSummaryCopyWithImpl<RunPlanSummary, RunPlanSummary>(
    this as RunPlanSummary,
    $identity,
    $identity,
  );
  @override
  String toString() {
    return RunPlanSummaryMapper.ensureInitialized().stringifyValue(
      this as RunPlanSummary,
    );
  }

  @override
  bool operator ==(Object other) {
    return RunPlanSummaryMapper.ensureInitialized().equalsValue(
      this as RunPlanSummary,
      other,
    );
  }

  @override
  int get hashCode {
    return RunPlanSummaryMapper.ensureInitialized().hashValue(
      this as RunPlanSummary,
    );
  }
}

extension RunPlanSummaryValueCopy<$R, $Out>
    on ObjectCopyWith<$R, RunPlanSummary, $Out> {
  RunPlanSummaryCopyWith<$R, RunPlanSummary, $Out> get $asRunPlanSummary =>
      $base.as((v, t, t2) => _RunPlanSummaryCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class RunPlanSummaryCopyWith<$R, $In extends RunPlanSummary, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    int? revision,
    String? digest,
    int? previousRevision,
    String? changeReason,
    String? state,
  });
  RunPlanSummaryCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _RunPlanSummaryCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, RunPlanSummary, $Out>
    implements RunPlanSummaryCopyWith<$R, RunPlanSummary, $Out> {
  _RunPlanSummaryCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<RunPlanSummary> $mapper =
      RunPlanSummaryMapper.ensureInitialized();
  @override
  $R call({
    int? revision,
    String? digest,
    Object? previousRevision = $none,
    Object? changeReason = $none,
    String? state,
  }) => $apply(
    FieldCopyWithData({
      if (revision != null) #revision: revision,
      if (digest != null) #digest: digest,
      if (previousRevision != $none) #previousRevision: previousRevision,
      if (changeReason != $none) #changeReason: changeReason,
      if (state != null) #state: state,
    }),
  );
  @override
  RunPlanSummary $make(CopyWithData data) => RunPlanSummary(
    revision: data.get(#revision, or: $value.revision),
    digest: data.get(#digest, or: $value.digest),
    previousRevision: data.get(#previousRevision, or: $value.previousRevision),
    changeReason: data.get(#changeReason, or: $value.changeReason),
    state: data.get(#state, or: $value.state),
  );

  @override
  RunPlanSummaryCopyWith<$R2, RunPlanSummary, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _RunPlanSummaryCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class RunCoordinatorSummaryMapper
    extends ClassMapperBase<RunCoordinatorSummary> {
  RunCoordinatorSummaryMapper._();

  static RunCoordinatorSummaryMapper? _instance;
  static RunCoordinatorSummaryMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RunCoordinatorSummaryMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'RunCoordinatorSummary';

  static String? _$handle(RunCoordinatorSummary v) => v.handle;
  static const Field<RunCoordinatorSummary, String> _f$handle = Field(
    'handle',
    _$handle,
    opt: true,
  );
  static String? _$tabId(RunCoordinatorSummary v) => v.tabId;
  static const Field<RunCoordinatorSummary, String> _f$tabId = Field(
    'tabId',
    _$tabId,
    opt: true,
  );
  static String? _$profileId(RunCoordinatorSummary v) => v.profileId;
  static const Field<RunCoordinatorSummary, String> _f$profileId = Field(
    'profileId',
    _$profileId,
    opt: true,
  );
  static String _$state(RunCoordinatorSummary v) => v.state;
  static const Field<RunCoordinatorSummary, String> _f$state = Field(
    'state',
    _$state,
    opt: true,
    def: 'none',
  );
  static String? _$error(RunCoordinatorSummary v) => v.error;
  static const Field<RunCoordinatorSummary, String> _f$error = Field(
    'error',
    _$error,
    opt: true,
  );

  @override
  final MappableFields<RunCoordinatorSummary> fields = const {
    #handle: _f$handle,
    #tabId: _f$tabId,
    #profileId: _f$profileId,
    #state: _f$state,
    #error: _f$error,
  };

  static RunCoordinatorSummary _instantiate(DecodingData data) {
    return RunCoordinatorSummary(
      handle: data.dec(_f$handle),
      tabId: data.dec(_f$tabId),
      profileId: data.dec(_f$profileId),
      state: data.dec(_f$state),
      error: data.dec(_f$error),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static RunCoordinatorSummary fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<RunCoordinatorSummary>(map);
  }

  static RunCoordinatorSummary fromJson(String json) {
    return ensureInitialized().decodeJson<RunCoordinatorSummary>(json);
  }
}

mixin RunCoordinatorSummaryMappable {
  String toJson() {
    return RunCoordinatorSummaryMapper.ensureInitialized()
        .encodeJson<RunCoordinatorSummary>(this as RunCoordinatorSummary);
  }

  Map<String, dynamic> toMap() {
    return RunCoordinatorSummaryMapper.ensureInitialized()
        .encodeMap<RunCoordinatorSummary>(this as RunCoordinatorSummary);
  }

  RunCoordinatorSummaryCopyWith<
    RunCoordinatorSummary,
    RunCoordinatorSummary,
    RunCoordinatorSummary
  >
  get copyWith =>
      _RunCoordinatorSummaryCopyWithImpl<
        RunCoordinatorSummary,
        RunCoordinatorSummary
      >(this as RunCoordinatorSummary, $identity, $identity);
  @override
  String toString() {
    return RunCoordinatorSummaryMapper.ensureInitialized().stringifyValue(
      this as RunCoordinatorSummary,
    );
  }

  @override
  bool operator ==(Object other) {
    return RunCoordinatorSummaryMapper.ensureInitialized().equalsValue(
      this as RunCoordinatorSummary,
      other,
    );
  }

  @override
  int get hashCode {
    return RunCoordinatorSummaryMapper.ensureInitialized().hashValue(
      this as RunCoordinatorSummary,
    );
  }
}

extension RunCoordinatorSummaryValueCopy<$R, $Out>
    on ObjectCopyWith<$R, RunCoordinatorSummary, $Out> {
  RunCoordinatorSummaryCopyWith<$R, RunCoordinatorSummary, $Out>
  get $asRunCoordinatorSummary => $base.as(
    (v, t, t2) => _RunCoordinatorSummaryCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class RunCoordinatorSummaryCopyWith<
  $R,
  $In extends RunCoordinatorSummary,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    String? handle,
    String? tabId,
    String? profileId,
    String? state,
    String? error,
  });
  RunCoordinatorSummaryCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _RunCoordinatorSummaryCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, RunCoordinatorSummary, $Out>
    implements RunCoordinatorSummaryCopyWith<$R, RunCoordinatorSummary, $Out> {
  _RunCoordinatorSummaryCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<RunCoordinatorSummary> $mapper =
      RunCoordinatorSummaryMapper.ensureInitialized();
  @override
  $R call({
    Object? handle = $none,
    Object? tabId = $none,
    Object? profileId = $none,
    String? state,
    Object? error = $none,
  }) => $apply(
    FieldCopyWithData({
      if (handle != $none) #handle: handle,
      if (tabId != $none) #tabId: tabId,
      if (profileId != $none) #profileId: profileId,
      if (state != null) #state: state,
      if (error != $none) #error: error,
    }),
  );
  @override
  RunCoordinatorSummary $make(CopyWithData data) => RunCoordinatorSummary(
    handle: data.get(#handle, or: $value.handle),
    tabId: data.get(#tabId, or: $value.tabId),
    profileId: data.get(#profileId, or: $value.profileId),
    state: data.get(#state, or: $value.state),
    error: data.get(#error, or: $value.error),
  );

  @override
  RunCoordinatorSummaryCopyWith<$R2, RunCoordinatorSummary, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _RunCoordinatorSummaryCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class RunIntegrationSummaryMapper
    extends ClassMapperBase<RunIntegrationSummary> {
  RunIntegrationSummaryMapper._();

  static RunIntegrationSummaryMapper? _instance;
  static RunIntegrationSummaryMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RunIntegrationSummaryMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'RunIntegrationSummary';

  static String? _$workspaceId(RunIntegrationSummary v) => v.workspaceId;
  static const Field<RunIntegrationSummary, String> _f$workspaceId = Field(
    'workspaceId',
    _$workspaceId,
    opt: true,
  );
  static String? _$branch(RunIntegrationSummary v) => v.branch;
  static const Field<RunIntegrationSummary, String> _f$branch = Field(
    'branch',
    _$branch,
    opt: true,
  );
  static String? _$sha(RunIntegrationSummary v) => v.sha;
  static const Field<RunIntegrationSummary, String> _f$sha = Field(
    'sha',
    _$sha,
    opt: true,
  );

  @override
  final MappableFields<RunIntegrationSummary> fields = const {
    #workspaceId: _f$workspaceId,
    #branch: _f$branch,
    #sha: _f$sha,
  };

  static RunIntegrationSummary _instantiate(DecodingData data) {
    return RunIntegrationSummary(
      workspaceId: data.dec(_f$workspaceId),
      branch: data.dec(_f$branch),
      sha: data.dec(_f$sha),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static RunIntegrationSummary fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<RunIntegrationSummary>(map);
  }

  static RunIntegrationSummary fromJson(String json) {
    return ensureInitialized().decodeJson<RunIntegrationSummary>(json);
  }
}

mixin RunIntegrationSummaryMappable {
  String toJson() {
    return RunIntegrationSummaryMapper.ensureInitialized()
        .encodeJson<RunIntegrationSummary>(this as RunIntegrationSummary);
  }

  Map<String, dynamic> toMap() {
    return RunIntegrationSummaryMapper.ensureInitialized()
        .encodeMap<RunIntegrationSummary>(this as RunIntegrationSummary);
  }

  RunIntegrationSummaryCopyWith<
    RunIntegrationSummary,
    RunIntegrationSummary,
    RunIntegrationSummary
  >
  get copyWith =>
      _RunIntegrationSummaryCopyWithImpl<
        RunIntegrationSummary,
        RunIntegrationSummary
      >(this as RunIntegrationSummary, $identity, $identity);
  @override
  String toString() {
    return RunIntegrationSummaryMapper.ensureInitialized().stringifyValue(
      this as RunIntegrationSummary,
    );
  }

  @override
  bool operator ==(Object other) {
    return RunIntegrationSummaryMapper.ensureInitialized().equalsValue(
      this as RunIntegrationSummary,
      other,
    );
  }

  @override
  int get hashCode {
    return RunIntegrationSummaryMapper.ensureInitialized().hashValue(
      this as RunIntegrationSummary,
    );
  }
}

extension RunIntegrationSummaryValueCopy<$R, $Out>
    on ObjectCopyWith<$R, RunIntegrationSummary, $Out> {
  RunIntegrationSummaryCopyWith<$R, RunIntegrationSummary, $Out>
  get $asRunIntegrationSummary => $base.as(
    (v, t, t2) => _RunIntegrationSummaryCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class RunIntegrationSummaryCopyWith<
  $R,
  $In extends RunIntegrationSummary,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({String? workspaceId, String? branch, String? sha});
  RunIntegrationSummaryCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _RunIntegrationSummaryCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, RunIntegrationSummary, $Out>
    implements RunIntegrationSummaryCopyWith<$R, RunIntegrationSummary, $Out> {
  _RunIntegrationSummaryCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<RunIntegrationSummary> $mapper =
      RunIntegrationSummaryMapper.ensureInitialized();
  @override
  $R call({
    Object? workspaceId = $none,
    Object? branch = $none,
    Object? sha = $none,
  }) => $apply(
    FieldCopyWithData({
      if (workspaceId != $none) #workspaceId: workspaceId,
      if (branch != $none) #branch: branch,
      if (sha != $none) #sha: sha,
    }),
  );
  @override
  RunIntegrationSummary $make(CopyWithData data) => RunIntegrationSummary(
    workspaceId: data.get(#workspaceId, or: $value.workspaceId),
    branch: data.get(#branch, or: $value.branch),
    sha: data.get(#sha, or: $value.sha),
  );

  @override
  RunIntegrationSummaryCopyWith<$R2, RunIntegrationSummary, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _RunIntegrationSummaryCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class RunCleanupSummaryMapper extends ClassMapperBase<RunCleanupSummary> {
  RunCleanupSummaryMapper._();

  static RunCleanupSummaryMapper? _instance;
  static RunCleanupSummaryMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RunCleanupSummaryMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'RunCleanupSummary';

  static String _$id(RunCleanupSummary v) => v.id;
  static const Field<RunCleanupSummary, String> _f$id = Field('id', _$id);
  static String _$state(RunCleanupSummary v) => v.state;
  static const Field<RunCleanupSummary, String> _f$state = Field(
    'state',
    _$state,
  );
  static String? _$error(RunCleanupSummary v) => v.error;
  static const Field<RunCleanupSummary, String> _f$error = Field(
    'error',
    _$error,
    opt: true,
  );
  static bool _$abandoned(RunCleanupSummary v) => v.abandoned;
  static const Field<RunCleanupSummary, bool> _f$abandoned = Field(
    'abandoned',
    _$abandoned,
    opt: true,
    def: false,
  );

  @override
  final MappableFields<RunCleanupSummary> fields = const {
    #id: _f$id,
    #state: _f$state,
    #error: _f$error,
    #abandoned: _f$abandoned,
  };

  static RunCleanupSummary _instantiate(DecodingData data) {
    return RunCleanupSummary(
      id: data.dec(_f$id),
      state: data.dec(_f$state),
      error: data.dec(_f$error),
      abandoned: data.dec(_f$abandoned),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static RunCleanupSummary fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<RunCleanupSummary>(map);
  }

  static RunCleanupSummary fromJson(String json) {
    return ensureInitialized().decodeJson<RunCleanupSummary>(json);
  }
}

mixin RunCleanupSummaryMappable {
  String toJson() {
    return RunCleanupSummaryMapper.ensureInitialized()
        .encodeJson<RunCleanupSummary>(this as RunCleanupSummary);
  }

  Map<String, dynamic> toMap() {
    return RunCleanupSummaryMapper.ensureInitialized()
        .encodeMap<RunCleanupSummary>(this as RunCleanupSummary);
  }

  RunCleanupSummaryCopyWith<
    RunCleanupSummary,
    RunCleanupSummary,
    RunCleanupSummary
  >
  get copyWith =>
      _RunCleanupSummaryCopyWithImpl<RunCleanupSummary, RunCleanupSummary>(
        this as RunCleanupSummary,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return RunCleanupSummaryMapper.ensureInitialized().stringifyValue(
      this as RunCleanupSummary,
    );
  }

  @override
  bool operator ==(Object other) {
    return RunCleanupSummaryMapper.ensureInitialized().equalsValue(
      this as RunCleanupSummary,
      other,
    );
  }

  @override
  int get hashCode {
    return RunCleanupSummaryMapper.ensureInitialized().hashValue(
      this as RunCleanupSummary,
    );
  }
}

extension RunCleanupSummaryValueCopy<$R, $Out>
    on ObjectCopyWith<$R, RunCleanupSummary, $Out> {
  RunCleanupSummaryCopyWith<$R, RunCleanupSummary, $Out>
  get $asRunCleanupSummary => $base.as(
    (v, t, t2) => _RunCleanupSummaryCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class RunCleanupSummaryCopyWith<
  $R,
  $In extends RunCleanupSummary,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({String? id, String? state, String? error, bool? abandoned});
  RunCleanupSummaryCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _RunCleanupSummaryCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, RunCleanupSummary, $Out>
    implements RunCleanupSummaryCopyWith<$R, RunCleanupSummary, $Out> {
  _RunCleanupSummaryCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<RunCleanupSummary> $mapper =
      RunCleanupSummaryMapper.ensureInitialized();
  @override
  $R call({
    String? id,
    String? state,
    Object? error = $none,
    bool? abandoned,
  }) => $apply(
    FieldCopyWithData({
      if (id != null) #id: id,
      if (state != null) #state: state,
      if (error != $none) #error: error,
      if (abandoned != null) #abandoned: abandoned,
    }),
  );
  @override
  RunCleanupSummary $make(CopyWithData data) => RunCleanupSummary(
    id: data.get(#id, or: $value.id),
    state: data.get(#state, or: $value.state),
    error: data.get(#error, or: $value.error),
    abandoned: data.get(#abandoned, or: $value.abandoned),
  );

  @override
  RunCleanupSummaryCopyWith<$R2, RunCleanupSummary, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _RunCleanupSummaryCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class RunSnapshotMapper extends ClassMapperBase<RunSnapshot> {
  RunSnapshotMapper._();

  static RunSnapshotMapper? _instance;
  static RunSnapshotMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RunSnapshotMapper._());
      RunSummaryMapper.ensureInitialized();
      RunPlanSummaryMapper.ensureInitialized();
      RunCoordinatorSummaryMapper.ensureInitialized();
      RunIntegrationSummaryMapper.ensureInitialized();
      RunGateMapper.ensureInitialized();
      RunCleanupSummaryMapper.ensureInitialized();
      RunTaskMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'RunSnapshot';

  static int _$revision(RunSnapshot v) => v.revision;
  static const Field<RunSnapshot, int> _f$revision = Field(
    'revision',
    _$revision,
  );
  static RunSummary _$run(RunSnapshot v) => v.run;
  static const Field<RunSnapshot, RunSummary> _f$run = Field('run', _$run);
  static String _$objective(RunSnapshot v) => v.objective;
  static const Field<RunSnapshot, String> _f$objective = Field(
    'objective',
    _$objective,
    opt: true,
    def: '',
  );
  static bool _$objectiveTruncated(RunSnapshot v) => v.objectiveTruncated;
  static const Field<RunSnapshot, bool> _f$objectiveTruncated = Field(
    'objectiveTruncated',
    _$objectiveTruncated,
    opt: true,
    def: false,
  );
  static int _$controlSequence(RunSnapshot v) => v.controlSequence;
  static const Field<RunSnapshot, int> _f$controlSequence = Field(
    'controlSequence',
    _$controlSequence,
    opt: true,
    def: 0,
  );
  static String _$stallPolicy(RunSnapshot v) => v.stallPolicy;
  static const Field<RunSnapshot, String> _f$stallPolicy = Field(
    'stallPolicy',
    _$stallPolicy,
    opt: true,
    def: 'ask',
  );
  static int _$maxConcurrent(RunSnapshot v) => v.maxConcurrent;
  static const Field<RunSnapshot, int> _f$maxConcurrent = Field(
    'maxConcurrent',
    _$maxConcurrent,
    opt: true,
    def: 1,
  );
  static String? _$stopReason(RunSnapshot v) => v.stopReason;
  static const Field<RunSnapshot, String> _f$stopReason = Field(
    'stopReason',
    _$stopReason,
    opt: true,
  );
  static Map<String, Object?>? _$recipeSource(RunSnapshot v) => v.recipeSource;
  static const Field<RunSnapshot, Map<String, Object?>> _f$recipeSource = Field(
    'recipeSource',
    _$recipeSource,
    opt: true,
  );
  static String? _$sourceSha(RunSnapshot v) => v.sourceSha;
  static const Field<RunSnapshot, String> _f$sourceSha = Field(
    'sourceSha',
    _$sourceSha,
    opt: true,
  );
  static RunPlanSummary? _$plan(RunSnapshot v) => v.plan;
  static const Field<RunSnapshot, RunPlanSummary> _f$plan = Field(
    'plan',
    _$plan,
    opt: true,
  );
  static RunCoordinatorSummary _$coordinator(RunSnapshot v) => v.coordinator;
  static const Field<RunSnapshot, RunCoordinatorSummary> _f$coordinator = Field(
    'coordinator',
    _$coordinator,
    opt: true,
    def: const RunCoordinatorSummary(),
  );
  static RunIntegrationSummary? _$integration(RunSnapshot v) => v.integration;
  static const Field<RunSnapshot, RunIntegrationSummary> _f$integration = Field(
    'integration',
    _$integration,
    opt: true,
  );
  static List<RunGate> _$pendingGates(RunSnapshot v) => v.pendingGates;
  static const Field<RunSnapshot, List<RunGate>> _f$pendingGates = Field(
    'pendingGates',
    _$pendingGates,
    opt: true,
    def: const <RunGate>[],
  );
  static RunCleanupSummary? _$cleanup(RunSnapshot v) => v.cleanup;
  static const Field<RunSnapshot, RunCleanupSummary> _f$cleanup = Field(
    'cleanup',
    _$cleanup,
    opt: true,
  );
  static int? _$resourceCount(RunSnapshot v) => v.resourceCount;
  static const Field<RunSnapshot, int> _f$resourceCount = Field(
    'resourceCount',
    _$resourceCount,
    opt: true,
  );
  static List<RunTask> _$tasks(RunSnapshot v) => v.tasks;
  static const Field<RunSnapshot, List<RunTask>> _f$tasks = Field(
    'tasks',
    _$tasks,
    opt: true,
    def: const <RunTask>[],
  );
  static String? _$nextTaskId(RunSnapshot v) => v.nextTaskId;
  static const Field<RunSnapshot, String> _f$nextTaskId = Field(
    'nextTaskId',
    _$nextTaskId,
    opt: true,
  );

  @override
  final MappableFields<RunSnapshot> fields = const {
    #revision: _f$revision,
    #run: _f$run,
    #objective: _f$objective,
    #objectiveTruncated: _f$objectiveTruncated,
    #controlSequence: _f$controlSequence,
    #stallPolicy: _f$stallPolicy,
    #maxConcurrent: _f$maxConcurrent,
    #stopReason: _f$stopReason,
    #recipeSource: _f$recipeSource,
    #sourceSha: _f$sourceSha,
    #plan: _f$plan,
    #coordinator: _f$coordinator,
    #integration: _f$integration,
    #pendingGates: _f$pendingGates,
    #cleanup: _f$cleanup,
    #resourceCount: _f$resourceCount,
    #tasks: _f$tasks,
    #nextTaskId: _f$nextTaskId,
  };

  static RunSnapshot _instantiate(DecodingData data) {
    return RunSnapshot(
      revision: data.dec(_f$revision),
      run: data.dec(_f$run),
      objective: data.dec(_f$objective),
      objectiveTruncated: data.dec(_f$objectiveTruncated),
      controlSequence: data.dec(_f$controlSequence),
      stallPolicy: data.dec(_f$stallPolicy),
      maxConcurrent: data.dec(_f$maxConcurrent),
      stopReason: data.dec(_f$stopReason),
      recipeSource: data.dec(_f$recipeSource),
      sourceSha: data.dec(_f$sourceSha),
      plan: data.dec(_f$plan),
      coordinator: data.dec(_f$coordinator),
      integration: data.dec(_f$integration),
      pendingGates: data.dec(_f$pendingGates),
      cleanup: data.dec(_f$cleanup),
      resourceCount: data.dec(_f$resourceCount),
      tasks: data.dec(_f$tasks),
      nextTaskId: data.dec(_f$nextTaskId),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static RunSnapshot fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<RunSnapshot>(map);
  }

  static RunSnapshot fromJson(String json) {
    return ensureInitialized().decodeJson<RunSnapshot>(json);
  }
}

mixin RunSnapshotMappable {
  String toJson() {
    return RunSnapshotMapper.ensureInitialized().encodeJson<RunSnapshot>(
      this as RunSnapshot,
    );
  }

  Map<String, dynamic> toMap() {
    return RunSnapshotMapper.ensureInitialized().encodeMap<RunSnapshot>(
      this as RunSnapshot,
    );
  }

  RunSnapshotCopyWith<RunSnapshot, RunSnapshot, RunSnapshot> get copyWith =>
      _RunSnapshotCopyWithImpl<RunSnapshot, RunSnapshot>(
        this as RunSnapshot,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return RunSnapshotMapper.ensureInitialized().stringifyValue(
      this as RunSnapshot,
    );
  }

  @override
  bool operator ==(Object other) {
    return RunSnapshotMapper.ensureInitialized().equalsValue(
      this as RunSnapshot,
      other,
    );
  }

  @override
  int get hashCode {
    return RunSnapshotMapper.ensureInitialized().hashValue(this as RunSnapshot);
  }
}

extension RunSnapshotValueCopy<$R, $Out>
    on ObjectCopyWith<$R, RunSnapshot, $Out> {
  RunSnapshotCopyWith<$R, RunSnapshot, $Out> get $asRunSnapshot =>
      $base.as((v, t, t2) => _RunSnapshotCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class RunSnapshotCopyWith<$R, $In extends RunSnapshot, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  RunSummaryCopyWith<$R, RunSummary, RunSummary> get run;
  MapCopyWith<$R, String, Object?, ObjectCopyWith<$R, Object?, Object?>?>?
  get recipeSource;
  RunPlanSummaryCopyWith<$R, RunPlanSummary, RunPlanSummary>? get plan;
  RunCoordinatorSummaryCopyWith<
    $R,
    RunCoordinatorSummary,
    RunCoordinatorSummary
  >
  get coordinator;
  RunIntegrationSummaryCopyWith<
    $R,
    RunIntegrationSummary,
    RunIntegrationSummary
  >?
  get integration;
  ListCopyWith<$R, RunGate, RunGateCopyWith<$R, RunGate, RunGate>>
  get pendingGates;
  RunCleanupSummaryCopyWith<$R, RunCleanupSummary, RunCleanupSummary>?
  get cleanup;
  ListCopyWith<$R, RunTask, RunTaskCopyWith<$R, RunTask, RunTask>> get tasks;
  $R call({
    int? revision,
    RunSummary? run,
    String? objective,
    bool? objectiveTruncated,
    int? controlSequence,
    String? stallPolicy,
    int? maxConcurrent,
    String? stopReason,
    Map<String, Object?>? recipeSource,
    String? sourceSha,
    RunPlanSummary? plan,
    RunCoordinatorSummary? coordinator,
    RunIntegrationSummary? integration,
    List<RunGate>? pendingGates,
    RunCleanupSummary? cleanup,
    int? resourceCount,
    List<RunTask>? tasks,
    String? nextTaskId,
  });
  RunSnapshotCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _RunSnapshotCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, RunSnapshot, $Out>
    implements RunSnapshotCopyWith<$R, RunSnapshot, $Out> {
  _RunSnapshotCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<RunSnapshot> $mapper =
      RunSnapshotMapper.ensureInitialized();
  @override
  RunSummaryCopyWith<$R, RunSummary, RunSummary> get run =>
      $value.run.copyWith.$chain((v) => call(run: v));
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
  RunPlanSummaryCopyWith<$R, RunPlanSummary, RunPlanSummary>? get plan =>
      $value.plan?.copyWith.$chain((v) => call(plan: v));
  @override
  RunCoordinatorSummaryCopyWith<
    $R,
    RunCoordinatorSummary,
    RunCoordinatorSummary
  >
  get coordinator =>
      $value.coordinator.copyWith.$chain((v) => call(coordinator: v));
  @override
  RunIntegrationSummaryCopyWith<
    $R,
    RunIntegrationSummary,
    RunIntegrationSummary
  >?
  get integration =>
      $value.integration?.copyWith.$chain((v) => call(integration: v));
  @override
  ListCopyWith<$R, RunGate, RunGateCopyWith<$R, RunGate, RunGate>>
  get pendingGates => ListCopyWith(
    $value.pendingGates,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(pendingGates: v),
  );
  @override
  RunCleanupSummaryCopyWith<$R, RunCleanupSummary, RunCleanupSummary>?
  get cleanup => $value.cleanup?.copyWith.$chain((v) => call(cleanup: v));
  @override
  ListCopyWith<$R, RunTask, RunTaskCopyWith<$R, RunTask, RunTask>> get tasks =>
      ListCopyWith(
        $value.tasks,
        (v, t) => v.copyWith.$chain(t),
        (v) => call(tasks: v),
      );
  @override
  $R call({
    int? revision,
    RunSummary? run,
    String? objective,
    bool? objectiveTruncated,
    int? controlSequence,
    String? stallPolicy,
    int? maxConcurrent,
    Object? stopReason = $none,
    Object? recipeSource = $none,
    Object? sourceSha = $none,
    Object? plan = $none,
    RunCoordinatorSummary? coordinator,
    Object? integration = $none,
    List<RunGate>? pendingGates,
    Object? cleanup = $none,
    Object? resourceCount = $none,
    List<RunTask>? tasks,
    Object? nextTaskId = $none,
  }) => $apply(
    FieldCopyWithData({
      if (revision != null) #revision: revision,
      if (run != null) #run: run,
      if (objective != null) #objective: objective,
      if (objectiveTruncated != null) #objectiveTruncated: objectiveTruncated,
      if (controlSequence != null) #controlSequence: controlSequence,
      if (stallPolicy != null) #stallPolicy: stallPolicy,
      if (maxConcurrent != null) #maxConcurrent: maxConcurrent,
      if (stopReason != $none) #stopReason: stopReason,
      if (recipeSource != $none) #recipeSource: recipeSource,
      if (sourceSha != $none) #sourceSha: sourceSha,
      if (plan != $none) #plan: plan,
      if (coordinator != null) #coordinator: coordinator,
      if (integration != $none) #integration: integration,
      if (pendingGates != null) #pendingGates: pendingGates,
      if (cleanup != $none) #cleanup: cleanup,
      if (resourceCount != $none) #resourceCount: resourceCount,
      if (tasks != null) #tasks: tasks,
      if (nextTaskId != $none) #nextTaskId: nextTaskId,
    }),
  );
  @override
  RunSnapshot $make(CopyWithData data) => RunSnapshot(
    revision: data.get(#revision, or: $value.revision),
    run: data.get(#run, or: $value.run),
    objective: data.get(#objective, or: $value.objective),
    objectiveTruncated: data.get(
      #objectiveTruncated,
      or: $value.objectiveTruncated,
    ),
    controlSequence: data.get(#controlSequence, or: $value.controlSequence),
    stallPolicy: data.get(#stallPolicy, or: $value.stallPolicy),
    maxConcurrent: data.get(#maxConcurrent, or: $value.maxConcurrent),
    stopReason: data.get(#stopReason, or: $value.stopReason),
    recipeSource: data.get(#recipeSource, or: $value.recipeSource),
    sourceSha: data.get(#sourceSha, or: $value.sourceSha),
    plan: data.get(#plan, or: $value.plan),
    coordinator: data.get(#coordinator, or: $value.coordinator),
    integration: data.get(#integration, or: $value.integration),
    pendingGates: data.get(#pendingGates, or: $value.pendingGates),
    cleanup: data.get(#cleanup, or: $value.cleanup),
    resourceCount: data.get(#resourceCount, or: $value.resourceCount),
    tasks: data.get(#tasks, or: $value.tasks),
    nextTaskId: data.get(#nextTaskId, or: $value.nextTaskId),
  );

  @override
  RunSnapshotCopyWith<$R2, RunSnapshot, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _RunSnapshotCopyWithImpl<$R2, $Out2>($value, $cast, t);
}
