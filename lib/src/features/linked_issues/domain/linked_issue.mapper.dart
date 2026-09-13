// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'linked_issue.dart';

class LinkedIssueMapper extends ClassMapperBase<LinkedIssue> {
  LinkedIssueMapper._();

  static LinkedIssueMapper? _instance;
  static LinkedIssueMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = LinkedIssueMapper._());
      GitHostingProviderMapper.ensureInitialized();
      IssueStateMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'LinkedIssue';

  static String _$workspaceId(LinkedIssue v) => v.workspaceId;
  static const Field<LinkedIssue, String> _f$workspaceId = Field(
    'workspaceId',
    _$workspaceId,
  );
  static String _$url(LinkedIssue v) => v.url;
  static const Field<LinkedIssue, String> _f$url = Field('url', _$url);
  static DateTime _$linkedAt(LinkedIssue v) => v.linkedAt;
  static const Field<LinkedIssue, DateTime> _f$linkedAt = Field(
    'linkedAt',
    _$linkedAt,
  );
  static GitHostingProvider? _$provider(LinkedIssue v) => v.provider;
  static const Field<LinkedIssue, GitHostingProvider> _f$provider = Field(
    'provider',
    _$provider,
    opt: true,
  );
  static String? _$repository(LinkedIssue v) => v.repository;
  static const Field<LinkedIssue, String> _f$repository = Field(
    'repository',
    _$repository,
    opt: true,
  );
  static int? _$number(LinkedIssue v) => v.number;
  static const Field<LinkedIssue, int> _f$number = Field(
    'number',
    _$number,
    opt: true,
  );
  static String? _$title(LinkedIssue v) => v.title;
  static const Field<LinkedIssue, String> _f$title = Field(
    'title',
    _$title,
    opt: true,
  );
  static IssueState? _$state(LinkedIssue v) => v.state;
  static const Field<LinkedIssue, IssueState> _f$state = Field(
    'state',
    _$state,
    opt: true,
  );
  static String? _$stateLabel(LinkedIssue v) => v.stateLabel;
  static const Field<LinkedIssue, String> _f$stateLabel = Field(
    'stateLabel',
    _$stateLabel,
    opt: true,
  );
  static DateTime? _$fetchedAt(LinkedIssue v) => v.fetchedAt;
  static const Field<LinkedIssue, DateTime> _f$fetchedAt = Field(
    'fetchedAt',
    _$fetchedAt,
    opt: true,
  );
  static String? _$fetchError(LinkedIssue v) => v.fetchError;
  static const Field<LinkedIssue, String> _f$fetchError = Field(
    'fetchError',
    _$fetchError,
    opt: true,
  );

  @override
  final MappableFields<LinkedIssue> fields = const {
    #workspaceId: _f$workspaceId,
    #url: _f$url,
    #linkedAt: _f$linkedAt,
    #provider: _f$provider,
    #repository: _f$repository,
    #number: _f$number,
    #title: _f$title,
    #state: _f$state,
    #stateLabel: _f$stateLabel,
    #fetchedAt: _f$fetchedAt,
    #fetchError: _f$fetchError,
  };

  static LinkedIssue _instantiate(DecodingData data) {
    return LinkedIssue(
      workspaceId: data.dec(_f$workspaceId),
      url: data.dec(_f$url),
      linkedAt: data.dec(_f$linkedAt),
      provider: data.dec(_f$provider),
      repository: data.dec(_f$repository),
      number: data.dec(_f$number),
      title: data.dec(_f$title),
      state: data.dec(_f$state),
      stateLabel: data.dec(_f$stateLabel),
      fetchedAt: data.dec(_f$fetchedAt),
      fetchError: data.dec(_f$fetchError),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static LinkedIssue fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<LinkedIssue>(map);
  }

  static LinkedIssue fromJson(String json) {
    return ensureInitialized().decodeJson<LinkedIssue>(json);
  }
}

mixin LinkedIssueMappable {
  String toJson() {
    return LinkedIssueMapper.ensureInitialized().encodeJson<LinkedIssue>(
      this as LinkedIssue,
    );
  }

  Map<String, dynamic> toMap() {
    return LinkedIssueMapper.ensureInitialized().encodeMap<LinkedIssue>(
      this as LinkedIssue,
    );
  }

  LinkedIssueCopyWith<LinkedIssue, LinkedIssue, LinkedIssue> get copyWith =>
      _LinkedIssueCopyWithImpl<LinkedIssue, LinkedIssue>(
        this as LinkedIssue,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return LinkedIssueMapper.ensureInitialized().stringifyValue(
      this as LinkedIssue,
    );
  }

  @override
  bool operator ==(Object other) {
    return LinkedIssueMapper.ensureInitialized().equalsValue(
      this as LinkedIssue,
      other,
    );
  }

  @override
  int get hashCode {
    return LinkedIssueMapper.ensureInitialized().hashValue(this as LinkedIssue);
  }
}

extension LinkedIssueValueCopy<$R, $Out>
    on ObjectCopyWith<$R, LinkedIssue, $Out> {
  LinkedIssueCopyWith<$R, LinkedIssue, $Out> get $asLinkedIssue =>
      $base.as((v, t, t2) => _LinkedIssueCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class LinkedIssueCopyWith<$R, $In extends LinkedIssue, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    String? workspaceId,
    String? url,
    DateTime? linkedAt,
    GitHostingProvider? provider,
    String? repository,
    int? number,
    String? title,
    IssueState? state,
    String? stateLabel,
    DateTime? fetchedAt,
    String? fetchError,
  });
  LinkedIssueCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _LinkedIssueCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, LinkedIssue, $Out>
    implements LinkedIssueCopyWith<$R, LinkedIssue, $Out> {
  _LinkedIssueCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<LinkedIssue> $mapper =
      LinkedIssueMapper.ensureInitialized();
  @override
  $R call({
    String? workspaceId,
    String? url,
    DateTime? linkedAt,
    Object? provider = $none,
    Object? repository = $none,
    Object? number = $none,
    Object? title = $none,
    Object? state = $none,
    Object? stateLabel = $none,
    Object? fetchedAt = $none,
    Object? fetchError = $none,
  }) => $apply(
    FieldCopyWithData({
      if (workspaceId != null) #workspaceId: workspaceId,
      if (url != null) #url: url,
      if (linkedAt != null) #linkedAt: linkedAt,
      if (provider != $none) #provider: provider,
      if (repository != $none) #repository: repository,
      if (number != $none) #number: number,
      if (title != $none) #title: title,
      if (state != $none) #state: state,
      if (stateLabel != $none) #stateLabel: stateLabel,
      if (fetchedAt != $none) #fetchedAt: fetchedAt,
      if (fetchError != $none) #fetchError: fetchError,
    }),
  );
  @override
  LinkedIssue $make(CopyWithData data) => LinkedIssue(
    workspaceId: data.get(#workspaceId, or: $value.workspaceId),
    url: data.get(#url, or: $value.url),
    linkedAt: data.get(#linkedAt, or: $value.linkedAt),
    provider: data.get(#provider, or: $value.provider),
    repository: data.get(#repository, or: $value.repository),
    number: data.get(#number, or: $value.number),
    title: data.get(#title, or: $value.title),
    state: data.get(#state, or: $value.state),
    stateLabel: data.get(#stateLabel, or: $value.stateLabel),
    fetchedAt: data.get(#fetchedAt, or: $value.fetchedAt),
    fetchError: data.get(#fetchError, or: $value.fetchError),
  );

  @override
  LinkedIssueCopyWith<$R2, LinkedIssue, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _LinkedIssueCopyWithImpl<$R2, $Out2>($value, $cast, t);
}
