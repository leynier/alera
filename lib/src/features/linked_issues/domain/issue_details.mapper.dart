// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'issue_details.dart';

class IssueDetailsMapper extends ClassMapperBase<IssueDetails> {
  IssueDetailsMapper._();

  static IssueDetailsMapper? _instance;
  static IssueDetailsMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = IssueDetailsMapper._());
      GitHostingProviderMapper.ensureInitialized();
      IssueStateMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'IssueDetails';

  static GitHostingProvider _$provider(IssueDetails v) => v.provider;
  static const Field<IssueDetails, GitHostingProvider> _f$provider = Field(
    'provider',
    _$provider,
  );
  static String _$url(IssueDetails v) => v.url;
  static const Field<IssueDetails, String> _f$url = Field('url', _$url);
  static int _$number(IssueDetails v) => v.number;
  static const Field<IssueDetails, int> _f$number = Field('number', _$number);
  static String _$title(IssueDetails v) => v.title;
  static const Field<IssueDetails, String> _f$title = Field('title', _$title);
  static IssueState _$state(IssueDetails v) => v.state;
  static const Field<IssueDetails, IssueState> _f$state = Field(
    'state',
    _$state,
  );
  static String? _$repository(IssueDetails v) => v.repository;
  static const Field<IssueDetails, String> _f$repository = Field(
    'repository',
    _$repository,
    opt: true,
  );
  static String? _$stateLabel(IssueDetails v) => v.stateLabel;
  static const Field<IssueDetails, String> _f$stateLabel = Field(
    'stateLabel',
    _$stateLabel,
    opt: true,
  );
  static String? _$body(IssueDetails v) => v.body;
  static const Field<IssueDetails, String> _f$body = Field(
    'body',
    _$body,
    opt: true,
  );
  static List<String> _$labels(IssueDetails v) => v.labels;
  static const Field<IssueDetails, List<String>> _f$labels = Field(
    'labels',
    _$labels,
    opt: true,
    def: const <String>[],
  );
  static List<String> _$assignees(IssueDetails v) => v.assignees;
  static const Field<IssueDetails, List<String>> _f$assignees = Field(
    'assignees',
    _$assignees,
    opt: true,
    def: const <String>[],
  );
  static String? _$author(IssueDetails v) => v.author;
  static const Field<IssueDetails, String> _f$author = Field(
    'author',
    _$author,
    opt: true,
  );
  static String? _$createdAt(IssueDetails v) => v.createdAt;
  static const Field<IssueDetails, String> _f$createdAt = Field(
    'createdAt',
    _$createdAt,
    opt: true,
  );
  static String? _$updatedAt(IssueDetails v) => v.updatedAt;
  static const Field<IssueDetails, String> _f$updatedAt = Field(
    'updatedAt',
    _$updatedAt,
    opt: true,
  );

  @override
  final MappableFields<IssueDetails> fields = const {
    #provider: _f$provider,
    #url: _f$url,
    #number: _f$number,
    #title: _f$title,
    #state: _f$state,
    #repository: _f$repository,
    #stateLabel: _f$stateLabel,
    #body: _f$body,
    #labels: _f$labels,
    #assignees: _f$assignees,
    #author: _f$author,
    #createdAt: _f$createdAt,
    #updatedAt: _f$updatedAt,
  };

  static IssueDetails _instantiate(DecodingData data) {
    return IssueDetails(
      provider: data.dec(_f$provider),
      url: data.dec(_f$url),
      number: data.dec(_f$number),
      title: data.dec(_f$title),
      state: data.dec(_f$state),
      repository: data.dec(_f$repository),
      stateLabel: data.dec(_f$stateLabel),
      body: data.dec(_f$body),
      labels: data.dec(_f$labels),
      assignees: data.dec(_f$assignees),
      author: data.dec(_f$author),
      createdAt: data.dec(_f$createdAt),
      updatedAt: data.dec(_f$updatedAt),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static IssueDetails fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<IssueDetails>(map);
  }

  static IssueDetails fromJson(String json) {
    return ensureInitialized().decodeJson<IssueDetails>(json);
  }
}

mixin IssueDetailsMappable {
  String toJson() {
    return IssueDetailsMapper.ensureInitialized().encodeJson<IssueDetails>(
      this as IssueDetails,
    );
  }

  Map<String, dynamic> toMap() {
    return IssueDetailsMapper.ensureInitialized().encodeMap<IssueDetails>(
      this as IssueDetails,
    );
  }

  IssueDetailsCopyWith<IssueDetails, IssueDetails, IssueDetails> get copyWith =>
      _IssueDetailsCopyWithImpl<IssueDetails, IssueDetails>(
        this as IssueDetails,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return IssueDetailsMapper.ensureInitialized().stringifyValue(
      this as IssueDetails,
    );
  }

  @override
  bool operator ==(Object other) {
    return IssueDetailsMapper.ensureInitialized().equalsValue(
      this as IssueDetails,
      other,
    );
  }

  @override
  int get hashCode {
    return IssueDetailsMapper.ensureInitialized().hashValue(
      this as IssueDetails,
    );
  }
}

extension IssueDetailsValueCopy<$R, $Out>
    on ObjectCopyWith<$R, IssueDetails, $Out> {
  IssueDetailsCopyWith<$R, IssueDetails, $Out> get $asIssueDetails =>
      $base.as((v, t, t2) => _IssueDetailsCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class IssueDetailsCopyWith<$R, $In extends IssueDetails, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get labels;
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get assignees;
  $R call({
    GitHostingProvider? provider,
    String? url,
    int? number,
    String? title,
    IssueState? state,
    String? repository,
    String? stateLabel,
    String? body,
    List<String>? labels,
    List<String>? assignees,
    String? author,
    String? createdAt,
    String? updatedAt,
  });
  IssueDetailsCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _IssueDetailsCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, IssueDetails, $Out>
    implements IssueDetailsCopyWith<$R, IssueDetails, $Out> {
  _IssueDetailsCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<IssueDetails> $mapper =
      IssueDetailsMapper.ensureInitialized();
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get labels =>
      ListCopyWith(
        $value.labels,
        (v, t) => ObjectCopyWith(v, $identity, t),
        (v) => call(labels: v),
      );
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get assignees =>
      ListCopyWith(
        $value.assignees,
        (v, t) => ObjectCopyWith(v, $identity, t),
        (v) => call(assignees: v),
      );
  @override
  $R call({
    GitHostingProvider? provider,
    String? url,
    int? number,
    String? title,
    IssueState? state,
    Object? repository = $none,
    Object? stateLabel = $none,
    Object? body = $none,
    List<String>? labels,
    List<String>? assignees,
    Object? author = $none,
    Object? createdAt = $none,
    Object? updatedAt = $none,
  }) => $apply(
    FieldCopyWithData({
      if (provider != null) #provider: provider,
      if (url != null) #url: url,
      if (number != null) #number: number,
      if (title != null) #title: title,
      if (state != null) #state: state,
      if (repository != $none) #repository: repository,
      if (stateLabel != $none) #stateLabel: stateLabel,
      if (body != $none) #body: body,
      if (labels != null) #labels: labels,
      if (assignees != null) #assignees: assignees,
      if (author != $none) #author: author,
      if (createdAt != $none) #createdAt: createdAt,
      if (updatedAt != $none) #updatedAt: updatedAt,
    }),
  );
  @override
  IssueDetails $make(CopyWithData data) => IssueDetails(
    provider: data.get(#provider, or: $value.provider),
    url: data.get(#url, or: $value.url),
    number: data.get(#number, or: $value.number),
    title: data.get(#title, or: $value.title),
    state: data.get(#state, or: $value.state),
    repository: data.get(#repository, or: $value.repository),
    stateLabel: data.get(#stateLabel, or: $value.stateLabel),
    body: data.get(#body, or: $value.body),
    labels: data.get(#labels, or: $value.labels),
    assignees: data.get(#assignees, or: $value.assignees),
    author: data.get(#author, or: $value.author),
    createdAt: data.get(#createdAt, or: $value.createdAt),
    updatedAt: data.get(#updatedAt, or: $value.updatedAt),
  );

  @override
  IssueDetailsCopyWith<$R2, IssueDetails, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _IssueDetailsCopyWithImpl<$R2, $Out2>($value, $cast, t);
}
