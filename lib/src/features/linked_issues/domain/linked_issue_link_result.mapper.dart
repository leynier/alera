// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'linked_issue_link_result.dart';

class IssueFetchFailureMapper extends ClassMapperBase<IssueFetchFailure> {
  IssueFetchFailureMapper._();

  static IssueFetchFailureMapper? _instance;
  static IssueFetchFailureMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = IssueFetchFailureMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'IssueFetchFailure';

  static String _$code(IssueFetchFailure v) => v.code;
  static const Field<IssueFetchFailure, String> _f$code = Field('code', _$code);
  static String _$message(IssueFetchFailure v) => v.message;
  static const Field<IssueFetchFailure, String> _f$message = Field(
    'message',
    _$message,
  );

  @override
  final MappableFields<IssueFetchFailure> fields = const {
    #code: _f$code,
    #message: _f$message,
  };

  static IssueFetchFailure _instantiate(DecodingData data) {
    return IssueFetchFailure(
      code: data.dec(_f$code),
      message: data.dec(_f$message),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static IssueFetchFailure fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<IssueFetchFailure>(map);
  }

  static IssueFetchFailure fromJson(String json) {
    return ensureInitialized().decodeJson<IssueFetchFailure>(json);
  }
}

mixin IssueFetchFailureMappable {
  String toJson() {
    return IssueFetchFailureMapper.ensureInitialized()
        .encodeJson<IssueFetchFailure>(this as IssueFetchFailure);
  }

  Map<String, dynamic> toMap() {
    return IssueFetchFailureMapper.ensureInitialized()
        .encodeMap<IssueFetchFailure>(this as IssueFetchFailure);
  }

  IssueFetchFailureCopyWith<
    IssueFetchFailure,
    IssueFetchFailure,
    IssueFetchFailure
  >
  get copyWith =>
      _IssueFetchFailureCopyWithImpl<IssueFetchFailure, IssueFetchFailure>(
        this as IssueFetchFailure,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return IssueFetchFailureMapper.ensureInitialized().stringifyValue(
      this as IssueFetchFailure,
    );
  }

  @override
  bool operator ==(Object other) {
    return IssueFetchFailureMapper.ensureInitialized().equalsValue(
      this as IssueFetchFailure,
      other,
    );
  }

  @override
  int get hashCode {
    return IssueFetchFailureMapper.ensureInitialized().hashValue(
      this as IssueFetchFailure,
    );
  }
}

extension IssueFetchFailureValueCopy<$R, $Out>
    on ObjectCopyWith<$R, IssueFetchFailure, $Out> {
  IssueFetchFailureCopyWith<$R, IssueFetchFailure, $Out>
  get $asIssueFetchFailure => $base.as(
    (v, t, t2) => _IssueFetchFailureCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class IssueFetchFailureCopyWith<
  $R,
  $In extends IssueFetchFailure,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({String? code, String? message});
  IssueFetchFailureCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _IssueFetchFailureCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, IssueFetchFailure, $Out>
    implements IssueFetchFailureCopyWith<$R, IssueFetchFailure, $Out> {
  _IssueFetchFailureCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<IssueFetchFailure> $mapper =
      IssueFetchFailureMapper.ensureInitialized();
  @override
  $R call({String? code, String? message}) => $apply(
    FieldCopyWithData({
      if (code != null) #code: code,
      if (message != null) #message: message,
    }),
  );
  @override
  IssueFetchFailure $make(CopyWithData data) => IssueFetchFailure(
    code: data.get(#code, or: $value.code),
    message: data.get(#message, or: $value.message),
  );

  @override
  IssueFetchFailureCopyWith<$R2, IssueFetchFailure, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _IssueFetchFailureCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class LinkedIssueLinkResultMapper
    extends ClassMapperBase<LinkedIssueLinkResult> {
  LinkedIssueLinkResultMapper._();

  static LinkedIssueLinkResultMapper? _instance;
  static LinkedIssueLinkResultMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = LinkedIssueLinkResultMapper._());
      LinkedIssueMapper.ensureInitialized();
      IssueDetailsMapper.ensureInitialized();
      IssueFetchFailureMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'LinkedIssueLinkResult';

  static LinkedIssue _$linkedIssue(LinkedIssueLinkResult v) => v.linkedIssue;
  static const Field<LinkedIssueLinkResult, LinkedIssue> _f$linkedIssue = Field(
    'linkedIssue',
    _$linkedIssue,
  );
  static IssueDetails? _$issue(LinkedIssueLinkResult v) => v.issue;
  static const Field<LinkedIssueLinkResult, IssueDetails> _f$issue = Field(
    'issue',
    _$issue,
    opt: true,
  );
  static IssueFetchFailure? _$fetchError(LinkedIssueLinkResult v) =>
      v.fetchError;
  static const Field<LinkedIssueLinkResult, IssueFetchFailure> _f$fetchError =
      Field('fetchError', _$fetchError, opt: true);

  @override
  final MappableFields<LinkedIssueLinkResult> fields = const {
    #linkedIssue: _f$linkedIssue,
    #issue: _f$issue,
    #fetchError: _f$fetchError,
  };

  static LinkedIssueLinkResult _instantiate(DecodingData data) {
    return LinkedIssueLinkResult(
      linkedIssue: data.dec(_f$linkedIssue),
      issue: data.dec(_f$issue),
      fetchError: data.dec(_f$fetchError),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static LinkedIssueLinkResult fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<LinkedIssueLinkResult>(map);
  }

  static LinkedIssueLinkResult fromJson(String json) {
    return ensureInitialized().decodeJson<LinkedIssueLinkResult>(json);
  }
}

mixin LinkedIssueLinkResultMappable {
  String toJson() {
    return LinkedIssueLinkResultMapper.ensureInitialized()
        .encodeJson<LinkedIssueLinkResult>(this as LinkedIssueLinkResult);
  }

  Map<String, dynamic> toMap() {
    return LinkedIssueLinkResultMapper.ensureInitialized()
        .encodeMap<LinkedIssueLinkResult>(this as LinkedIssueLinkResult);
  }

  LinkedIssueLinkResultCopyWith<
    LinkedIssueLinkResult,
    LinkedIssueLinkResult,
    LinkedIssueLinkResult
  >
  get copyWith =>
      _LinkedIssueLinkResultCopyWithImpl<
        LinkedIssueLinkResult,
        LinkedIssueLinkResult
      >(this as LinkedIssueLinkResult, $identity, $identity);
  @override
  String toString() {
    return LinkedIssueLinkResultMapper.ensureInitialized().stringifyValue(
      this as LinkedIssueLinkResult,
    );
  }

  @override
  bool operator ==(Object other) {
    return LinkedIssueLinkResultMapper.ensureInitialized().equalsValue(
      this as LinkedIssueLinkResult,
      other,
    );
  }

  @override
  int get hashCode {
    return LinkedIssueLinkResultMapper.ensureInitialized().hashValue(
      this as LinkedIssueLinkResult,
    );
  }
}

extension LinkedIssueLinkResultValueCopy<$R, $Out>
    on ObjectCopyWith<$R, LinkedIssueLinkResult, $Out> {
  LinkedIssueLinkResultCopyWith<$R, LinkedIssueLinkResult, $Out>
  get $asLinkedIssueLinkResult => $base.as(
    (v, t, t2) => _LinkedIssueLinkResultCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class LinkedIssueLinkResultCopyWith<
  $R,
  $In extends LinkedIssueLinkResult,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  LinkedIssueCopyWith<$R, LinkedIssue, LinkedIssue> get linkedIssue;
  IssueDetailsCopyWith<$R, IssueDetails, IssueDetails>? get issue;
  IssueFetchFailureCopyWith<$R, IssueFetchFailure, IssueFetchFailure>?
  get fetchError;
  $R call({
    LinkedIssue? linkedIssue,
    IssueDetails? issue,
    IssueFetchFailure? fetchError,
  });
  LinkedIssueLinkResultCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _LinkedIssueLinkResultCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, LinkedIssueLinkResult, $Out>
    implements LinkedIssueLinkResultCopyWith<$R, LinkedIssueLinkResult, $Out> {
  _LinkedIssueLinkResultCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<LinkedIssueLinkResult> $mapper =
      LinkedIssueLinkResultMapper.ensureInitialized();
  @override
  LinkedIssueCopyWith<$R, LinkedIssue, LinkedIssue> get linkedIssue =>
      $value.linkedIssue.copyWith.$chain((v) => call(linkedIssue: v));
  @override
  IssueDetailsCopyWith<$R, IssueDetails, IssueDetails>? get issue =>
      $value.issue?.copyWith.$chain((v) => call(issue: v));
  @override
  IssueFetchFailureCopyWith<$R, IssueFetchFailure, IssueFetchFailure>?
  get fetchError =>
      $value.fetchError?.copyWith.$chain((v) => call(fetchError: v));
  @override
  $R call({
    LinkedIssue? linkedIssue,
    Object? issue = $none,
    Object? fetchError = $none,
  }) => $apply(
    FieldCopyWithData({
      if (linkedIssue != null) #linkedIssue: linkedIssue,
      if (issue != $none) #issue: issue,
      if (fetchError != $none) #fetchError: fetchError,
    }),
  );
  @override
  LinkedIssueLinkResult $make(CopyWithData data) => LinkedIssueLinkResult(
    linkedIssue: data.get(#linkedIssue, or: $value.linkedIssue),
    issue: data.get(#issue, or: $value.issue),
    fetchError: data.get(#fetchError, or: $value.fetchError),
  );

  @override
  LinkedIssueLinkResultCopyWith<$R2, LinkedIssueLinkResult, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _LinkedIssueLinkResultCopyWithImpl<$R2, $Out2>($value, $cast, t);
}
