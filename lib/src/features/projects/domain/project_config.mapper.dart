// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'project_config.dart';

class ProjectConfigMapper extends ClassMapperBase<ProjectConfig> {
  ProjectConfigMapper._();

  static ProjectConfigMapper? _instance;
  static ProjectConfigMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ProjectConfigMapper._());
      WorktreeSetupConfigMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ProjectConfig';

  static WorktreeSetupConfig _$worktree(ProjectConfig v) => v.worktree;
  static const Field<ProjectConfig, WorktreeSetupConfig> _f$worktree = Field(
    'worktree',
    _$worktree,
    opt: true,
    def: WorktreeSetupConfig.defaults,
  );

  @override
  final MappableFields<ProjectConfig> fields = const {#worktree: _f$worktree};

  static ProjectConfig _instantiate(DecodingData data) {
    return ProjectConfig(worktree: data.dec(_f$worktree));
  }

  @override
  final Function instantiate = _instantiate;

  static ProjectConfig fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ProjectConfig>(map);
  }

  static ProjectConfig fromJson(String json) {
    return ensureInitialized().decodeJson<ProjectConfig>(json);
  }
}

mixin ProjectConfigMappable {
  String toJson() {
    return ProjectConfigMapper.ensureInitialized().encodeJson<ProjectConfig>(
      this as ProjectConfig,
    );
  }

  Map<String, dynamic> toMap() {
    return ProjectConfigMapper.ensureInitialized().encodeMap<ProjectConfig>(
      this as ProjectConfig,
    );
  }

  ProjectConfigCopyWith<ProjectConfig, ProjectConfig, ProjectConfig>
  get copyWith => _ProjectConfigCopyWithImpl<ProjectConfig, ProjectConfig>(
    this as ProjectConfig,
    $identity,
    $identity,
  );
  @override
  String toString() {
    return ProjectConfigMapper.ensureInitialized().stringifyValue(
      this as ProjectConfig,
    );
  }

  @override
  bool operator ==(Object other) {
    return ProjectConfigMapper.ensureInitialized().equalsValue(
      this as ProjectConfig,
      other,
    );
  }

  @override
  int get hashCode {
    return ProjectConfigMapper.ensureInitialized().hashValue(
      this as ProjectConfig,
    );
  }
}

extension ProjectConfigValueCopy<$R, $Out>
    on ObjectCopyWith<$R, ProjectConfig, $Out> {
  ProjectConfigCopyWith<$R, ProjectConfig, $Out> get $asProjectConfig =>
      $base.as((v, t, t2) => _ProjectConfigCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class ProjectConfigCopyWith<$R, $In extends ProjectConfig, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  WorktreeSetupConfigCopyWith<$R, WorktreeSetupConfig, WorktreeSetupConfig>
  get worktree;
  $R call({WorktreeSetupConfig? worktree});
  ProjectConfigCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _ProjectConfigCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, ProjectConfig, $Out>
    implements ProjectConfigCopyWith<$R, ProjectConfig, $Out> {
  _ProjectConfigCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<ProjectConfig> $mapper =
      ProjectConfigMapper.ensureInitialized();
  @override
  WorktreeSetupConfigCopyWith<$R, WorktreeSetupConfig, WorktreeSetupConfig>
  get worktree => $value.worktree.copyWith.$chain((v) => call(worktree: v));
  @override
  $R call({WorktreeSetupConfig? worktree}) =>
      $apply(FieldCopyWithData({if (worktree != null) #worktree: worktree}));
  @override
  ProjectConfig $make(CopyWithData data) =>
      ProjectConfig(worktree: data.get(#worktree, or: $value.worktree));

  @override
  ProjectConfigCopyWith<$R2, ProjectConfig, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _ProjectConfigCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class WorktreeSetupConfigMapper extends ClassMapperBase<WorktreeSetupConfig> {
  WorktreeSetupConfigMapper._();

  static WorktreeSetupConfigMapper? _instance;
  static WorktreeSetupConfigMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = WorktreeSetupConfigMapper._());
      WorktreeCopyRuleMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'WorktreeSetupConfig';

  static List<WorktreeCopyRule> _$copy(WorktreeSetupConfig v) => v.copy;
  static const Field<WorktreeSetupConfig, List<WorktreeCopyRule>> _f$copy =
      Field('copy', _$copy, opt: true, def: const <WorktreeCopyRule>[]);
  static List<String> _$setup(WorktreeSetupConfig v) => v.setup;
  static const Field<WorktreeSetupConfig, List<String>> _f$setup = Field(
    'setup',
    _$setup,
    opt: true,
    def: const <String>[],
  );

  @override
  final MappableFields<WorktreeSetupConfig> fields = const {
    #copy: _f$copy,
    #setup: _f$setup,
  };

  static WorktreeSetupConfig _instantiate(DecodingData data) {
    return WorktreeSetupConfig(
      copy: data.dec(_f$copy),
      setup: data.dec(_f$setup),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static WorktreeSetupConfig fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<WorktreeSetupConfig>(map);
  }

  static WorktreeSetupConfig fromJson(String json) {
    return ensureInitialized().decodeJson<WorktreeSetupConfig>(json);
  }
}

mixin WorktreeSetupConfigMappable {
  String toJson() {
    return WorktreeSetupConfigMapper.ensureInitialized()
        .encodeJson<WorktreeSetupConfig>(this as WorktreeSetupConfig);
  }

  Map<String, dynamic> toMap() {
    return WorktreeSetupConfigMapper.ensureInitialized()
        .encodeMap<WorktreeSetupConfig>(this as WorktreeSetupConfig);
  }

  WorktreeSetupConfigCopyWith<
    WorktreeSetupConfig,
    WorktreeSetupConfig,
    WorktreeSetupConfig
  >
  get copyWith =>
      _WorktreeSetupConfigCopyWithImpl<
        WorktreeSetupConfig,
        WorktreeSetupConfig
      >(this as WorktreeSetupConfig, $identity, $identity);
  @override
  String toString() {
    return WorktreeSetupConfigMapper.ensureInitialized().stringifyValue(
      this as WorktreeSetupConfig,
    );
  }

  @override
  bool operator ==(Object other) {
    return WorktreeSetupConfigMapper.ensureInitialized().equalsValue(
      this as WorktreeSetupConfig,
      other,
    );
  }

  @override
  int get hashCode {
    return WorktreeSetupConfigMapper.ensureInitialized().hashValue(
      this as WorktreeSetupConfig,
    );
  }
}

extension WorktreeSetupConfigValueCopy<$R, $Out>
    on ObjectCopyWith<$R, WorktreeSetupConfig, $Out> {
  WorktreeSetupConfigCopyWith<$R, WorktreeSetupConfig, $Out>
  get $asWorktreeSetupConfig => $base.as(
    (v, t, t2) => _WorktreeSetupConfigCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class WorktreeSetupConfigCopyWith<
  $R,
  $In extends WorktreeSetupConfig,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<
    $R,
    WorktreeCopyRule,
    WorktreeCopyRuleCopyWith<$R, WorktreeCopyRule, WorktreeCopyRule>
  >
  get copy;
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get setup;
  $R call({List<WorktreeCopyRule>? copy, List<String>? setup});
  WorktreeSetupConfigCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _WorktreeSetupConfigCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, WorktreeSetupConfig, $Out>
    implements WorktreeSetupConfigCopyWith<$R, WorktreeSetupConfig, $Out> {
  _WorktreeSetupConfigCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<WorktreeSetupConfig> $mapper =
      WorktreeSetupConfigMapper.ensureInitialized();
  @override
  ListCopyWith<
    $R,
    WorktreeCopyRule,
    WorktreeCopyRuleCopyWith<$R, WorktreeCopyRule, WorktreeCopyRule>
  >
  get copy => ListCopyWith(
    $value.copy,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(copy: v),
  );
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get setup =>
      ListCopyWith(
        $value.setup,
        (v, t) => ObjectCopyWith(v, $identity, t),
        (v) => call(setup: v),
      );
  @override
  $R call({List<WorktreeCopyRule>? copy, List<String>? setup}) => $apply(
    FieldCopyWithData({
      if (copy != null) #copy: copy,
      if (setup != null) #setup: setup,
    }),
  );
  @override
  WorktreeSetupConfig $make(CopyWithData data) => WorktreeSetupConfig(
    copy: data.get(#copy, or: $value.copy),
    setup: data.get(#setup, or: $value.setup),
  );

  @override
  WorktreeSetupConfigCopyWith<$R2, WorktreeSetupConfig, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _WorktreeSetupConfigCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class WorktreeCopyRuleMapper extends ClassMapperBase<WorktreeCopyRule> {
  WorktreeCopyRuleMapper._();

  static WorktreeCopyRuleMapper? _instance;
  static WorktreeCopyRuleMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = WorktreeCopyRuleMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'WorktreeCopyRule';

  static String _$from(WorktreeCopyRule v) => v.from;
  static const Field<WorktreeCopyRule, String> _f$from = Field('from', _$from);
  static String? _$to(WorktreeCopyRule v) => v.to;
  static const Field<WorktreeCopyRule, String> _f$to = Field(
    'to',
    _$to,
    opt: true,
  );
  static bool _$overwrite(WorktreeCopyRule v) => v.overwrite;
  static const Field<WorktreeCopyRule, bool> _f$overwrite = Field(
    'overwrite',
    _$overwrite,
    opt: true,
    def: false,
  );

  @override
  final MappableFields<WorktreeCopyRule> fields = const {
    #from: _f$from,
    #to: _f$to,
    #overwrite: _f$overwrite,
  };

  static WorktreeCopyRule _instantiate(DecodingData data) {
    return WorktreeCopyRule(
      from: data.dec(_f$from),
      to: data.dec(_f$to),
      overwrite: data.dec(_f$overwrite),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static WorktreeCopyRule fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<WorktreeCopyRule>(map);
  }

  static WorktreeCopyRule fromJson(String json) {
    return ensureInitialized().decodeJson<WorktreeCopyRule>(json);
  }
}

mixin WorktreeCopyRuleMappable {
  String toJson() {
    return WorktreeCopyRuleMapper.ensureInitialized()
        .encodeJson<WorktreeCopyRule>(this as WorktreeCopyRule);
  }

  Map<String, dynamic> toMap() {
    return WorktreeCopyRuleMapper.ensureInitialized()
        .encodeMap<WorktreeCopyRule>(this as WorktreeCopyRule);
  }

  WorktreeCopyRuleCopyWith<WorktreeCopyRule, WorktreeCopyRule, WorktreeCopyRule>
  get copyWith =>
      _WorktreeCopyRuleCopyWithImpl<WorktreeCopyRule, WorktreeCopyRule>(
        this as WorktreeCopyRule,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return WorktreeCopyRuleMapper.ensureInitialized().stringifyValue(
      this as WorktreeCopyRule,
    );
  }

  @override
  bool operator ==(Object other) {
    return WorktreeCopyRuleMapper.ensureInitialized().equalsValue(
      this as WorktreeCopyRule,
      other,
    );
  }

  @override
  int get hashCode {
    return WorktreeCopyRuleMapper.ensureInitialized().hashValue(
      this as WorktreeCopyRule,
    );
  }
}

extension WorktreeCopyRuleValueCopy<$R, $Out>
    on ObjectCopyWith<$R, WorktreeCopyRule, $Out> {
  WorktreeCopyRuleCopyWith<$R, WorktreeCopyRule, $Out>
  get $asWorktreeCopyRule =>
      $base.as((v, t, t2) => _WorktreeCopyRuleCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class WorktreeCopyRuleCopyWith<$R, $In extends WorktreeCopyRule, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({String? from, String? to, bool? overwrite});
  WorktreeCopyRuleCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _WorktreeCopyRuleCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, WorktreeCopyRule, $Out>
    implements WorktreeCopyRuleCopyWith<$R, WorktreeCopyRule, $Out> {
  _WorktreeCopyRuleCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<WorktreeCopyRule> $mapper =
      WorktreeCopyRuleMapper.ensureInitialized();
  @override
  $R call({String? from, Object? to = $none, bool? overwrite}) => $apply(
    FieldCopyWithData({
      if (from != null) #from: from,
      if (to != $none) #to: to,
      if (overwrite != null) #overwrite: overwrite,
    }),
  );
  @override
  WorktreeCopyRule $make(CopyWithData data) => WorktreeCopyRule(
    from: data.get(#from, or: $value.from),
    to: data.get(#to, or: $value.to),
    overwrite: data.get(#overwrite, or: $value.overwrite),
  );

  @override
  WorktreeCopyRuleCopyWith<$R2, WorktreeCopyRule, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _WorktreeCopyRuleCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

