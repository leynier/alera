// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'run_plan.dart';

class RunPlanStageMapper extends ClassMapperBase<RunPlanStage> {
  RunPlanStageMapper._();

  static RunPlanStageMapper? _instance;
  static RunPlanStageMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RunPlanStageMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'RunPlanStage';

  static String _$id(RunPlanStage v) => v.id;
  static const Field<RunPlanStage, String> _f$id = Field('id', _$id);
  static String _$title(RunPlanStage v) => v.title;
  static const Field<RunPlanStage, String> _f$title = Field(
    'title',
    _$title,
    opt: true,
    def: '',
  );
  static List<String> _$roleIds(RunPlanStage v) => v.roleIds;
  static const Field<RunPlanStage, List<String>> _f$roleIds = Field(
    'roleIds',
    _$roleIds,
    opt: true,
    def: const <String>[],
  );
  static List<String> _$dependsOn(RunPlanStage v) => v.dependsOn;
  static const Field<RunPlanStage, List<String>> _f$dependsOn = Field(
    'dependsOn',
    _$dependsOn,
    opt: true,
    def: const <String>[],
  );
  static String? _$profile(RunPlanStage v) => v.profile;
  static const Field<RunPlanStage, String> _f$profile = Field(
    'profile',
    _$profile,
    opt: true,
  );
  static List<String> _$fallbacks(RunPlanStage v) => v.fallbacks;
  static const Field<RunPlanStage, List<String>> _f$fallbacks = Field(
    'fallbacks',
    _$fallbacks,
    opt: true,
    def: const <String>[],
  );
  static bool _$gate(RunPlanStage v) => v.gate;
  static const Field<RunPlanStage, bool> _f$gate = Field(
    'gate',
    _$gate,
    opt: true,
    def: false,
  );
  static String? _$gateKind(RunPlanStage v) => v.gateKind;
  static const Field<RunPlanStage, String> _f$gateKind = Field(
    'gateKind',
    _$gateKind,
    opt: true,
  );

  @override
  final MappableFields<RunPlanStage> fields = const {
    #id: _f$id,
    #title: _f$title,
    #roleIds: _f$roleIds,
    #dependsOn: _f$dependsOn,
    #profile: _f$profile,
    #fallbacks: _f$fallbacks,
    #gate: _f$gate,
    #gateKind: _f$gateKind,
  };

  static RunPlanStage _instantiate(DecodingData data) {
    return RunPlanStage(
      id: data.dec(_f$id),
      title: data.dec(_f$title),
      roleIds: data.dec(_f$roleIds),
      dependsOn: data.dec(_f$dependsOn),
      profile: data.dec(_f$profile),
      fallbacks: data.dec(_f$fallbacks),
      gate: data.dec(_f$gate),
      gateKind: data.dec(_f$gateKind),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static RunPlanStage fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<RunPlanStage>(map);
  }

  static RunPlanStage fromJson(String json) {
    return ensureInitialized().decodeJson<RunPlanStage>(json);
  }
}

mixin RunPlanStageMappable {
  String toJson() {
    return RunPlanStageMapper.ensureInitialized().encodeJson<RunPlanStage>(
      this as RunPlanStage,
    );
  }

  Map<String, dynamic> toMap() {
    return RunPlanStageMapper.ensureInitialized().encodeMap<RunPlanStage>(
      this as RunPlanStage,
    );
  }

  RunPlanStageCopyWith<RunPlanStage, RunPlanStage, RunPlanStage> get copyWith =>
      _RunPlanStageCopyWithImpl<RunPlanStage, RunPlanStage>(
        this as RunPlanStage,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return RunPlanStageMapper.ensureInitialized().stringifyValue(
      this as RunPlanStage,
    );
  }

  @override
  bool operator ==(Object other) {
    return RunPlanStageMapper.ensureInitialized().equalsValue(
      this as RunPlanStage,
      other,
    );
  }

  @override
  int get hashCode {
    return RunPlanStageMapper.ensureInitialized().hashValue(
      this as RunPlanStage,
    );
  }
}

extension RunPlanStageValueCopy<$R, $Out>
    on ObjectCopyWith<$R, RunPlanStage, $Out> {
  RunPlanStageCopyWith<$R, RunPlanStage, $Out> get $asRunPlanStage =>
      $base.as((v, t, t2) => _RunPlanStageCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class RunPlanStageCopyWith<$R, $In extends RunPlanStage, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get roleIds;
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get dependsOn;
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get fallbacks;
  $R call({
    String? id,
    String? title,
    List<String>? roleIds,
    List<String>? dependsOn,
    String? profile,
    List<String>? fallbacks,
    bool? gate,
    String? gateKind,
  });
  RunPlanStageCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _RunPlanStageCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, RunPlanStage, $Out>
    implements RunPlanStageCopyWith<$R, RunPlanStage, $Out> {
  _RunPlanStageCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<RunPlanStage> $mapper =
      RunPlanStageMapper.ensureInitialized();
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get roleIds =>
      ListCopyWith(
        $value.roleIds,
        (v, t) => ObjectCopyWith(v, $identity, t),
        (v) => call(roleIds: v),
      );
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get dependsOn =>
      ListCopyWith(
        $value.dependsOn,
        (v, t) => ObjectCopyWith(v, $identity, t),
        (v) => call(dependsOn: v),
      );
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get fallbacks =>
      ListCopyWith(
        $value.fallbacks,
        (v, t) => ObjectCopyWith(v, $identity, t),
        (v) => call(fallbacks: v),
      );
  @override
  $R call({
    String? id,
    String? title,
    List<String>? roleIds,
    List<String>? dependsOn,
    Object? profile = $none,
    List<String>? fallbacks,
    bool? gate,
    Object? gateKind = $none,
  }) => $apply(
    FieldCopyWithData({
      if (id != null) #id: id,
      if (title != null) #title: title,
      if (roleIds != null) #roleIds: roleIds,
      if (dependsOn != null) #dependsOn: dependsOn,
      if (profile != $none) #profile: profile,
      if (fallbacks != null) #fallbacks: fallbacks,
      if (gate != null) #gate: gate,
      if (gateKind != $none) #gateKind: gateKind,
    }),
  );
  @override
  RunPlanStage $make(CopyWithData data) => RunPlanStage(
    id: data.get(#id, or: $value.id),
    title: data.get(#title, or: $value.title),
    roleIds: data.get(#roleIds, or: $value.roleIds),
    dependsOn: data.get(#dependsOn, or: $value.dependsOn),
    profile: data.get(#profile, or: $value.profile),
    fallbacks: data.get(#fallbacks, or: $value.fallbacks),
    gate: data.get(#gate, or: $value.gate),
    gateKind: data.get(#gateKind, or: $value.gateKind),
  );

  @override
  RunPlanStageCopyWith<$R2, RunPlanStage, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _RunPlanStageCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class RunPlanTaskMapper extends ClassMapperBase<RunPlanTask> {
  RunPlanTaskMapper._();

  static RunPlanTaskMapper? _instance;
  static RunPlanTaskMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RunPlanTaskMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'RunPlanTask';

  static String _$id(RunPlanTask v) => v.id;
  static const Field<RunPlanTask, String> _f$id = Field('id', _$id);
  static String? _$taskId(RunPlanTask v) => v.taskId;
  static const Field<RunPlanTask, String> _f$taskId = Field(
    'taskId',
    _$taskId,
    opt: true,
  );
  static String _$title(RunPlanTask v) => v.title;
  static const Field<RunPlanTask, String> _f$title = Field('title', _$title);
  static String _$spec(RunPlanTask v) => v.spec;
  static const Field<RunPlanTask, String> _f$spec = Field(
    'spec',
    _$spec,
    opt: true,
    def: '',
  );
  static String _$stageId(RunPlanTask v) => v.stageId;
  static const Field<RunPlanTask, String> _f$stageId = Field(
    'stageId',
    _$stageId,
  );
  static String? _$roleId(RunPlanTask v) => v.roleId;
  static const Field<RunPlanTask, String> _f$roleId = Field(
    'roleId',
    _$roleId,
    opt: true,
  );
  static List<String> _$dependsOn(RunPlanTask v) => v.dependsOn;
  static const Field<RunPlanTask, List<String>> _f$dependsOn = Field(
    'dependsOn',
    _$dependsOn,
    opt: true,
    def: const <String>[],
  );
  static Object? _$inputs(RunPlanTask v) => v.inputs;
  static const Field<RunPlanTask, Object> _f$inputs = Field(
    'inputs',
    _$inputs,
    opt: true,
  );
  static String? _$correctsTaskId(RunPlanTask v) => v.correctsTaskId;
  static const Field<RunPlanTask, String> _f$correctsTaskId = Field(
    'correctsTaskId',
    _$correctsTaskId,
    opt: true,
  );
  static String? _$profileId(RunPlanTask v) => v.profileId;
  static const Field<RunPlanTask, String> _f$profileId = Field(
    'profileId',
    _$profileId,
    opt: true,
  );
  static String? _$status(RunPlanTask v) => v.status;
  static const Field<RunPlanTask, String> _f$status = Field(
    'status',
    _$status,
    opt: true,
  );

  @override
  final MappableFields<RunPlanTask> fields = const {
    #id: _f$id,
    #taskId: _f$taskId,
    #title: _f$title,
    #spec: _f$spec,
    #stageId: _f$stageId,
    #roleId: _f$roleId,
    #dependsOn: _f$dependsOn,
    #inputs: _f$inputs,
    #correctsTaskId: _f$correctsTaskId,
    #profileId: _f$profileId,
    #status: _f$status,
  };

  static RunPlanTask _instantiate(DecodingData data) {
    return RunPlanTask(
      id: data.dec(_f$id),
      taskId: data.dec(_f$taskId),
      title: data.dec(_f$title),
      spec: data.dec(_f$spec),
      stageId: data.dec(_f$stageId),
      roleId: data.dec(_f$roleId),
      dependsOn: data.dec(_f$dependsOn),
      inputs: data.dec(_f$inputs),
      correctsTaskId: data.dec(_f$correctsTaskId),
      profileId: data.dec(_f$profileId),
      status: data.dec(_f$status),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static RunPlanTask fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<RunPlanTask>(map);
  }

  static RunPlanTask fromJson(String json) {
    return ensureInitialized().decodeJson<RunPlanTask>(json);
  }
}

mixin RunPlanTaskMappable {
  String toJson() {
    return RunPlanTaskMapper.ensureInitialized().encodeJson<RunPlanTask>(
      this as RunPlanTask,
    );
  }

  Map<String, dynamic> toMap() {
    return RunPlanTaskMapper.ensureInitialized().encodeMap<RunPlanTask>(
      this as RunPlanTask,
    );
  }

  RunPlanTaskCopyWith<RunPlanTask, RunPlanTask, RunPlanTask> get copyWith =>
      _RunPlanTaskCopyWithImpl<RunPlanTask, RunPlanTask>(
        this as RunPlanTask,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return RunPlanTaskMapper.ensureInitialized().stringifyValue(
      this as RunPlanTask,
    );
  }

  @override
  bool operator ==(Object other) {
    return RunPlanTaskMapper.ensureInitialized().equalsValue(
      this as RunPlanTask,
      other,
    );
  }

  @override
  int get hashCode {
    return RunPlanTaskMapper.ensureInitialized().hashValue(this as RunPlanTask);
  }
}

extension RunPlanTaskValueCopy<$R, $Out>
    on ObjectCopyWith<$R, RunPlanTask, $Out> {
  RunPlanTaskCopyWith<$R, RunPlanTask, $Out> get $asRunPlanTask =>
      $base.as((v, t, t2) => _RunPlanTaskCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class RunPlanTaskCopyWith<$R, $In extends RunPlanTask, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get dependsOn;
  $R call({
    String? id,
    String? taskId,
    String? title,
    String? spec,
    String? stageId,
    String? roleId,
    List<String>? dependsOn,
    Object? inputs,
    String? correctsTaskId,
    String? profileId,
    String? status,
  });
  RunPlanTaskCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _RunPlanTaskCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, RunPlanTask, $Out>
    implements RunPlanTaskCopyWith<$R, RunPlanTask, $Out> {
  _RunPlanTaskCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<RunPlanTask> $mapper =
      RunPlanTaskMapper.ensureInitialized();
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get dependsOn =>
      ListCopyWith(
        $value.dependsOn,
        (v, t) => ObjectCopyWith(v, $identity, t),
        (v) => call(dependsOn: v),
      );
  @override
  $R call({
    String? id,
    Object? taskId = $none,
    String? title,
    String? spec,
    String? stageId,
    Object? roleId = $none,
    List<String>? dependsOn,
    Object? inputs = $none,
    Object? correctsTaskId = $none,
    Object? profileId = $none,
    Object? status = $none,
  }) => $apply(
    FieldCopyWithData({
      if (id != null) #id: id,
      if (taskId != $none) #taskId: taskId,
      if (title != null) #title: title,
      if (spec != null) #spec: spec,
      if (stageId != null) #stageId: stageId,
      if (roleId != $none) #roleId: roleId,
      if (dependsOn != null) #dependsOn: dependsOn,
      if (inputs != $none) #inputs: inputs,
      if (correctsTaskId != $none) #correctsTaskId: correctsTaskId,
      if (profileId != $none) #profileId: profileId,
      if (status != $none) #status: status,
    }),
  );
  @override
  RunPlanTask $make(CopyWithData data) => RunPlanTask(
    id: data.get(#id, or: $value.id),
    taskId: data.get(#taskId, or: $value.taskId),
    title: data.get(#title, or: $value.title),
    spec: data.get(#spec, or: $value.spec),
    stageId: data.get(#stageId, or: $value.stageId),
    roleId: data.get(#roleId, or: $value.roleId),
    dependsOn: data.get(#dependsOn, or: $value.dependsOn),
    inputs: data.get(#inputs, or: $value.inputs),
    correctsTaskId: data.get(#correctsTaskId, or: $value.correctsTaskId),
    profileId: data.get(#profileId, or: $value.profileId),
    status: data.get(#status, or: $value.status),
  );

  @override
  RunPlanTaskCopyWith<$R2, RunPlanTask, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _RunPlanTaskCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class RunPlanViewMapper extends ClassMapperBase<RunPlanView> {
  RunPlanViewMapper._();

  static RunPlanViewMapper? _instance;
  static RunPlanViewMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RunPlanViewMapper._());
      RunPlanStageMapper.ensureInitialized();
      RunPlanTaskMapper.ensureInitialized();
      RunGateMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'RunPlanView';

  static String _$runId(RunPlanView v) => v.runId;
  static const Field<RunPlanView, String> _f$runId = Field('runId', _$runId);
  static int _$revision(RunPlanView v) => v.revision;
  static const Field<RunPlanView, int> _f$revision = Field(
    'revision',
    _$revision,
  );
  static int? _$currentRevision(RunPlanView v) => v.currentRevision;
  static const Field<RunPlanView, int> _f$currentRevision = Field(
    'currentRevision',
    _$currentRevision,
    opt: true,
  );
  static String _$isolation(RunPlanView v) => v.isolation;
  static const Field<RunPlanView, String> _f$isolation = Field(
    'isolation',
    _$isolation,
    opt: true,
    def: 'shared',
  );
  static String _$runStatus(RunPlanView v) => v.runStatus;
  static const Field<RunPlanView, String> _f$runStatus = Field(
    'runStatus',
    _$runStatus,
    opt: true,
    def: '',
  );
  static bool _$approvalRequired(RunPlanView v) => v.approvalRequired;
  static const Field<RunPlanView, bool> _f$approvalRequired = Field(
    'approvalRequired',
    _$approvalRequired,
    opt: true,
    def: false,
  );
  static String _$stallPolicy(RunPlanView v) => v.stallPolicy;
  static const Field<RunPlanView, String> _f$stallPolicy = Field(
    'stallPolicy',
    _$stallPolicy,
    opt: true,
    def: 'ask',
  );
  static int _$maxConcurrent(RunPlanView v) => v.maxConcurrent;
  static const Field<RunPlanView, int> _f$maxConcurrent = Field(
    'maxConcurrent',
    _$maxConcurrent,
    opt: true,
    def: 1,
  );
  static String _$objective(RunPlanView v) => v.objective;
  static const Field<RunPlanView, String> _f$objective = Field(
    'objective',
    _$objective,
    opt: true,
    def: '',
  );
  static String? _$sourceSha(RunPlanView v) => v.sourceSha;
  static const Field<RunPlanView, String> _f$sourceSha = Field(
    'sourceSha',
    _$sourceSha,
    opt: true,
  );
  static String _$digest(RunPlanView v) => v.digest;
  static const Field<RunPlanView, String> _f$digest = Field(
    'digest',
    _$digest,
    opt: true,
    def: '',
  );
  static int? _$previousRevision(RunPlanView v) => v.previousRevision;
  static const Field<RunPlanView, int> _f$previousRevision = Field(
    'previousRevision',
    _$previousRevision,
    opt: true,
  );
  static String? _$changeReason(RunPlanView v) => v.changeReason;
  static const Field<RunPlanView, String> _f$changeReason = Field(
    'changeReason',
    _$changeReason,
    opt: true,
  );
  static List<String> _$changeTaskIds(RunPlanView v) => v.changeTaskIds;
  static const Field<RunPlanView, List<String>> _f$changeTaskIds = Field(
    'changeTaskIds',
    _$changeTaskIds,
    opt: true,
    def: const <String>[],
  );
  static bool _$placeholder(RunPlanView v) => v.placeholder;
  static const Field<RunPlanView, bool> _f$placeholder = Field(
    'placeholder',
    _$placeholder,
    opt: true,
    def: false,
  );
  static Map<String, Object?>? _$recipe(RunPlanView v) => v.recipe;
  static const Field<RunPlanView, Map<String, Object?>> _f$recipe = Field(
    'recipe',
    _$recipe,
    opt: true,
  );
  static String? _$coordinatorProfileId(RunPlanView v) =>
      v.coordinatorProfileId;
  static const Field<RunPlanView, String> _f$coordinatorProfileId = Field(
    'coordinatorProfileId',
    _$coordinatorProfileId,
    opt: true,
  );
  static Map<String, String> _$roleProfiles(RunPlanView v) => v.roleProfiles;
  static const Field<RunPlanView, Map<String, String>> _f$roleProfiles = Field(
    'roleProfiles',
    _$roleProfiles,
    opt: true,
    def: const <String, String>{},
  );
  static List<RunPlanStage> _$stages(RunPlanView v) => v.stages;
  static const Field<RunPlanView, List<RunPlanStage>> _f$stages = Field(
    'stages',
    _$stages,
    opt: true,
    def: const <RunPlanStage>[],
  );
  static List<RunPlanTask> _$tasks(RunPlanView v) => v.tasks;
  static const Field<RunPlanView, List<RunPlanTask>> _f$tasks = Field(
    'tasks',
    _$tasks,
    opt: true,
    def: const <RunPlanTask>[],
  );
  static RunGate? _$planGate(RunPlanView v) => v.planGate;
  static const Field<RunPlanView, RunGate> _f$planGate = Field(
    'planGate',
    _$planGate,
    opt: true,
  );

  @override
  final MappableFields<RunPlanView> fields = const {
    #runId: _f$runId,
    #revision: _f$revision,
    #currentRevision: _f$currentRevision,
    #isolation: _f$isolation,
    #runStatus: _f$runStatus,
    #approvalRequired: _f$approvalRequired,
    #stallPolicy: _f$stallPolicy,
    #maxConcurrent: _f$maxConcurrent,
    #objective: _f$objective,
    #sourceSha: _f$sourceSha,
    #digest: _f$digest,
    #previousRevision: _f$previousRevision,
    #changeReason: _f$changeReason,
    #changeTaskIds: _f$changeTaskIds,
    #placeholder: _f$placeholder,
    #recipe: _f$recipe,
    #coordinatorProfileId: _f$coordinatorProfileId,
    #roleProfiles: _f$roleProfiles,
    #stages: _f$stages,
    #tasks: _f$tasks,
    #planGate: _f$planGate,
  };

  static RunPlanView _instantiate(DecodingData data) {
    return RunPlanView(
      runId: data.dec(_f$runId),
      revision: data.dec(_f$revision),
      currentRevision: data.dec(_f$currentRevision),
      isolation: data.dec(_f$isolation),
      runStatus: data.dec(_f$runStatus),
      approvalRequired: data.dec(_f$approvalRequired),
      stallPolicy: data.dec(_f$stallPolicy),
      maxConcurrent: data.dec(_f$maxConcurrent),
      objective: data.dec(_f$objective),
      sourceSha: data.dec(_f$sourceSha),
      digest: data.dec(_f$digest),
      previousRevision: data.dec(_f$previousRevision),
      changeReason: data.dec(_f$changeReason),
      changeTaskIds: data.dec(_f$changeTaskIds),
      placeholder: data.dec(_f$placeholder),
      recipe: data.dec(_f$recipe),
      coordinatorProfileId: data.dec(_f$coordinatorProfileId),
      roleProfiles: data.dec(_f$roleProfiles),
      stages: data.dec(_f$stages),
      tasks: data.dec(_f$tasks),
      planGate: data.dec(_f$planGate),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static RunPlanView fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<RunPlanView>(map);
  }

  static RunPlanView fromJson(String json) {
    return ensureInitialized().decodeJson<RunPlanView>(json);
  }
}

mixin RunPlanViewMappable {
  String toJson() {
    return RunPlanViewMapper.ensureInitialized().encodeJson<RunPlanView>(
      this as RunPlanView,
    );
  }

  Map<String, dynamic> toMap() {
    return RunPlanViewMapper.ensureInitialized().encodeMap<RunPlanView>(
      this as RunPlanView,
    );
  }

  RunPlanViewCopyWith<RunPlanView, RunPlanView, RunPlanView> get copyWith =>
      _RunPlanViewCopyWithImpl<RunPlanView, RunPlanView>(
        this as RunPlanView,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return RunPlanViewMapper.ensureInitialized().stringifyValue(
      this as RunPlanView,
    );
  }

  @override
  bool operator ==(Object other) {
    return RunPlanViewMapper.ensureInitialized().equalsValue(
      this as RunPlanView,
      other,
    );
  }

  @override
  int get hashCode {
    return RunPlanViewMapper.ensureInitialized().hashValue(this as RunPlanView);
  }
}

extension RunPlanViewValueCopy<$R, $Out>
    on ObjectCopyWith<$R, RunPlanView, $Out> {
  RunPlanViewCopyWith<$R, RunPlanView, $Out> get $asRunPlanView =>
      $base.as((v, t, t2) => _RunPlanViewCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class RunPlanViewCopyWith<$R, $In extends RunPlanView, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>>
  get changeTaskIds;
  MapCopyWith<$R, String, Object?, ObjectCopyWith<$R, Object?, Object?>?>?
  get recipe;
  MapCopyWith<$R, String, String, ObjectCopyWith<$R, String, String>>
  get roleProfiles;
  ListCopyWith<
    $R,
    RunPlanStage,
    RunPlanStageCopyWith<$R, RunPlanStage, RunPlanStage>
  >
  get stages;
  ListCopyWith<
    $R,
    RunPlanTask,
    RunPlanTaskCopyWith<$R, RunPlanTask, RunPlanTask>
  >
  get tasks;
  RunGateCopyWith<$R, RunGate, RunGate>? get planGate;
  $R call({
    String? runId,
    int? revision,
    int? currentRevision,
    String? isolation,
    String? runStatus,
    bool? approvalRequired,
    String? stallPolicy,
    int? maxConcurrent,
    String? objective,
    String? sourceSha,
    String? digest,
    int? previousRevision,
    String? changeReason,
    List<String>? changeTaskIds,
    bool? placeholder,
    Map<String, Object?>? recipe,
    String? coordinatorProfileId,
    Map<String, String>? roleProfiles,
    List<RunPlanStage>? stages,
    List<RunPlanTask>? tasks,
    RunGate? planGate,
  });
  RunPlanViewCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _RunPlanViewCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, RunPlanView, $Out>
    implements RunPlanViewCopyWith<$R, RunPlanView, $Out> {
  _RunPlanViewCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<RunPlanView> $mapper =
      RunPlanViewMapper.ensureInitialized();
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>>
  get changeTaskIds => ListCopyWith(
    $value.changeTaskIds,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(changeTaskIds: v),
  );
  @override
  MapCopyWith<$R, String, Object?, ObjectCopyWith<$R, Object?, Object?>?>?
  get recipe => $value.recipe != null
      ? MapCopyWith(
          $value.recipe!,
          (v, t) => ObjectCopyWith(v, $identity, t),
          (v) => call(recipe: v),
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
  ListCopyWith<
    $R,
    RunPlanStage,
    RunPlanStageCopyWith<$R, RunPlanStage, RunPlanStage>
  >
  get stages => ListCopyWith(
    $value.stages,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(stages: v),
  );
  @override
  ListCopyWith<
    $R,
    RunPlanTask,
    RunPlanTaskCopyWith<$R, RunPlanTask, RunPlanTask>
  >
  get tasks => ListCopyWith(
    $value.tasks,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(tasks: v),
  );
  @override
  RunGateCopyWith<$R, RunGate, RunGate>? get planGate =>
      $value.planGate?.copyWith.$chain((v) => call(planGate: v));
  @override
  $R call({
    String? runId,
    int? revision,
    Object? currentRevision = $none,
    String? isolation,
    String? runStatus,
    bool? approvalRequired,
    String? stallPolicy,
    int? maxConcurrent,
    String? objective,
    Object? sourceSha = $none,
    String? digest,
    Object? previousRevision = $none,
    Object? changeReason = $none,
    List<String>? changeTaskIds,
    bool? placeholder,
    Object? recipe = $none,
    Object? coordinatorProfileId = $none,
    Map<String, String>? roleProfiles,
    List<RunPlanStage>? stages,
    List<RunPlanTask>? tasks,
    Object? planGate = $none,
  }) => $apply(
    FieldCopyWithData({
      if (runId != null) #runId: runId,
      if (revision != null) #revision: revision,
      if (currentRevision != $none) #currentRevision: currentRevision,
      if (isolation != null) #isolation: isolation,
      if (runStatus != null) #runStatus: runStatus,
      if (approvalRequired != null) #approvalRequired: approvalRequired,
      if (stallPolicy != null) #stallPolicy: stallPolicy,
      if (maxConcurrent != null) #maxConcurrent: maxConcurrent,
      if (objective != null) #objective: objective,
      if (sourceSha != $none) #sourceSha: sourceSha,
      if (digest != null) #digest: digest,
      if (previousRevision != $none) #previousRevision: previousRevision,
      if (changeReason != $none) #changeReason: changeReason,
      if (changeTaskIds != null) #changeTaskIds: changeTaskIds,
      if (placeholder != null) #placeholder: placeholder,
      if (recipe != $none) #recipe: recipe,
      if (coordinatorProfileId != $none)
        #coordinatorProfileId: coordinatorProfileId,
      if (roleProfiles != null) #roleProfiles: roleProfiles,
      if (stages != null) #stages: stages,
      if (tasks != null) #tasks: tasks,
      if (planGate != $none) #planGate: planGate,
    }),
  );
  @override
  RunPlanView $make(CopyWithData data) => RunPlanView(
    runId: data.get(#runId, or: $value.runId),
    revision: data.get(#revision, or: $value.revision),
    currentRevision: data.get(#currentRevision, or: $value.currentRevision),
    isolation: data.get(#isolation, or: $value.isolation),
    runStatus: data.get(#runStatus, or: $value.runStatus),
    approvalRequired: data.get(#approvalRequired, or: $value.approvalRequired),
    stallPolicy: data.get(#stallPolicy, or: $value.stallPolicy),
    maxConcurrent: data.get(#maxConcurrent, or: $value.maxConcurrent),
    objective: data.get(#objective, or: $value.objective),
    sourceSha: data.get(#sourceSha, or: $value.sourceSha),
    digest: data.get(#digest, or: $value.digest),
    previousRevision: data.get(#previousRevision, or: $value.previousRevision),
    changeReason: data.get(#changeReason, or: $value.changeReason),
    changeTaskIds: data.get(#changeTaskIds, or: $value.changeTaskIds),
    placeholder: data.get(#placeholder, or: $value.placeholder),
    recipe: data.get(#recipe, or: $value.recipe),
    coordinatorProfileId: data.get(
      #coordinatorProfileId,
      or: $value.coordinatorProfileId,
    ),
    roleProfiles: data.get(#roleProfiles, or: $value.roleProfiles),
    stages: data.get(#stages, or: $value.stages),
    tasks: data.get(#tasks, or: $value.tasks),
    planGate: data.get(#planGate, or: $value.planGate),
  );

  @override
  RunPlanViewCopyWith<$R2, RunPlanView, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _RunPlanViewCopyWithImpl<$R2, $Out2>($value, $cast, t);
}
