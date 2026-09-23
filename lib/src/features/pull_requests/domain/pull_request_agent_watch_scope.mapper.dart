// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'pull_request_agent_watch_scope.dart';

class PullRequestAgentWatchScopeMapper
    extends ClassMapperBase<PullRequestAgentWatchScope> {
  PullRequestAgentWatchScopeMapper._();

  static PullRequestAgentWatchScopeMapper? _instance;
  static PullRequestAgentWatchScopeMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = PullRequestAgentWatchScopeMapper._(),
      );
    }
    return _instance!;
  }

  @override
  final String id = 'PullRequestAgentWatchScope';

  static bool _$checks(PullRequestAgentWatchScope v) => v.checks;
  static const Field<PullRequestAgentWatchScope, bool> _f$checks = Field(
    'checks',
    _$checks,
    opt: true,
    def: true,
  );
  static bool _$comments(PullRequestAgentWatchScope v) => v.comments;
  static const Field<PullRequestAgentWatchScope, bool> _f$comments = Field(
    'comments',
    _$comments,
    opt: true,
    def: true,
  );
  static bool _$conflicts(PullRequestAgentWatchScope v) => v.conflicts;
  static const Field<PullRequestAgentWatchScope, bool> _f$conflicts = Field(
    'conflicts',
    _$conflicts,
    opt: true,
    def: true,
  );

  @override
  final MappableFields<PullRequestAgentWatchScope> fields = const {
    #checks: _f$checks,
    #comments: _f$comments,
    #conflicts: _f$conflicts,
  };

  static PullRequestAgentWatchScope _instantiate(DecodingData data) {
    return PullRequestAgentWatchScope(
      checks: data.dec(_f$checks),
      comments: data.dec(_f$comments),
      conflicts: data.dec(_f$conflicts),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static PullRequestAgentWatchScope fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<PullRequestAgentWatchScope>(map);
  }

  static PullRequestAgentWatchScope fromJson(String json) {
    return ensureInitialized().decodeJson<PullRequestAgentWatchScope>(json);
  }
}

mixin PullRequestAgentWatchScopeMappable {
  String toJson() {
    return PullRequestAgentWatchScopeMapper.ensureInitialized()
        .encodeJson<PullRequestAgentWatchScope>(
          this as PullRequestAgentWatchScope,
        );
  }

  Map<String, dynamic> toMap() {
    return PullRequestAgentWatchScopeMapper.ensureInitialized()
        .encodeMap<PullRequestAgentWatchScope>(
          this as PullRequestAgentWatchScope,
        );
  }

  PullRequestAgentWatchScopeCopyWith<
    PullRequestAgentWatchScope,
    PullRequestAgentWatchScope,
    PullRequestAgentWatchScope
  >
  get copyWith =>
      _PullRequestAgentWatchScopeCopyWithImpl<
        PullRequestAgentWatchScope,
        PullRequestAgentWatchScope
      >(this as PullRequestAgentWatchScope, $identity, $identity);
  @override
  String toString() {
    return PullRequestAgentWatchScopeMapper.ensureInitialized().stringifyValue(
      this as PullRequestAgentWatchScope,
    );
  }

  @override
  bool operator ==(Object other) {
    return PullRequestAgentWatchScopeMapper.ensureInitialized().equalsValue(
      this as PullRequestAgentWatchScope,
      other,
    );
  }

  @override
  int get hashCode {
    return PullRequestAgentWatchScopeMapper.ensureInitialized().hashValue(
      this as PullRequestAgentWatchScope,
    );
  }
}

extension PullRequestAgentWatchScopeValueCopy<$R, $Out>
    on ObjectCopyWith<$R, PullRequestAgentWatchScope, $Out> {
  PullRequestAgentWatchScopeCopyWith<$R, PullRequestAgentWatchScope, $Out>
  get $asPullRequestAgentWatchScope => $base.as(
    (v, t, t2) => _PullRequestAgentWatchScopeCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class PullRequestAgentWatchScopeCopyWith<
  $R,
  $In extends PullRequestAgentWatchScope,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({bool? checks, bool? comments, bool? conflicts});
  PullRequestAgentWatchScopeCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _PullRequestAgentWatchScopeCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, PullRequestAgentWatchScope, $Out>
    implements
        PullRequestAgentWatchScopeCopyWith<
          $R,
          PullRequestAgentWatchScope,
          $Out
        > {
  _PullRequestAgentWatchScopeCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<PullRequestAgentWatchScope> $mapper =
      PullRequestAgentWatchScopeMapper.ensureInitialized();
  @override
  $R call({bool? checks, bool? comments, bool? conflicts}) => $apply(
    FieldCopyWithData({
      if (checks != null) #checks: checks,
      if (comments != null) #comments: comments,
      if (conflicts != null) #conflicts: conflicts,
    }),
  );
  @override
  PullRequestAgentWatchScope $make(CopyWithData data) =>
      PullRequestAgentWatchScope(
        checks: data.get(#checks, or: $value.checks),
        comments: data.get(#comments, or: $value.comments),
        conflicts: data.get(#conflicts, or: $value.conflicts),
      );

  @override
  PullRequestAgentWatchScopeCopyWith<$R2, PullRequestAgentWatchScope, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _PullRequestAgentWatchScopeCopyWithImpl<$R2, $Out2>($value, $cast, t);
}
