// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'hosted_review.dart';

class HostedReviewStateMapper extends EnumMapper<HostedReviewState> {
  HostedReviewStateMapper._();

  static HostedReviewStateMapper? _instance;
  static HostedReviewStateMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = HostedReviewStateMapper._());
    }
    return _instance!;
  }

  static HostedReviewState fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  HostedReviewState decode(dynamic value) {
    switch (value) {
      case r'open':
        return HostedReviewState.open;
      case r'draft':
        return HostedReviewState.draft;
      case r'merged':
        return HostedReviewState.merged;
      case r'closed':
        return HostedReviewState.closed;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(HostedReviewState self) {
    switch (self) {
      case HostedReviewState.open:
        return r'open';
      case HostedReviewState.draft:
        return r'draft';
      case HostedReviewState.merged:
        return r'merged';
      case HostedReviewState.closed:
        return r'closed';
    }
  }
}

extension HostedReviewStateMapperExtension on HostedReviewState {
  String toValue() {
    HostedReviewStateMapper.ensureInitialized();
    return MapperContainer.globals.toValue<HostedReviewState>(this) as String;
  }
}

class HostedReviewMergeableMapper extends EnumMapper<HostedReviewMergeable> {
  HostedReviewMergeableMapper._();

  static HostedReviewMergeableMapper? _instance;
  static HostedReviewMergeableMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = HostedReviewMergeableMapper._());
    }
    return _instance!;
  }

  static HostedReviewMergeable fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  HostedReviewMergeable decode(dynamic value) {
    switch (value) {
      case r'mergeable':
        return HostedReviewMergeable.mergeable;
      case r'conflicting':
        return HostedReviewMergeable.conflicting;
      case r'unknown':
        return HostedReviewMergeable.unknown;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(HostedReviewMergeable self) {
    switch (self) {
      case HostedReviewMergeable.mergeable:
        return r'mergeable';
      case HostedReviewMergeable.conflicting:
        return r'conflicting';
      case HostedReviewMergeable.unknown:
        return r'unknown';
    }
  }
}

extension HostedReviewMergeableMapperExtension on HostedReviewMergeable {
  String toValue() {
    HostedReviewMergeableMapper.ensureInitialized();
    return MapperContainer.globals.toValue<HostedReviewMergeable>(this)
        as String;
  }
}

class HostedReviewMapper extends ClassMapperBase<HostedReview> {
  HostedReviewMapper._();

  static HostedReviewMapper? _instance;
  static HostedReviewMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = HostedReviewMapper._());
      GitHostingProviderMapper.ensureInitialized();
      HostedReviewStateMapper.ensureInitialized();
      HostedReviewMergeableMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'HostedReview';

  static GitHostingProvider _$provider(HostedReview v) => v.provider;
  static const Field<HostedReview, GitHostingProvider> _f$provider = Field(
    'provider',
    _$provider,
  );
  static int _$number(HostedReview v) => v.number;
  static const Field<HostedReview, int> _f$number = Field('number', _$number);
  static String _$title(HostedReview v) => v.title;
  static const Field<HostedReview, String> _f$title = Field('title', _$title);
  static HostedReviewState _$state(HostedReview v) => v.state;
  static const Field<HostedReview, HostedReviewState> _f$state = Field(
    'state',
    _$state,
  );
  static String _$url(HostedReview v) => v.url;
  static const Field<HostedReview, String> _f$url = Field('url', _$url);
  static DateTime? _$createdAt(HostedReview v) => v.createdAt;
  static const Field<HostedReview, DateTime> _f$createdAt = Field(
    'createdAt',
    _$createdAt,
    opt: true,
  );
  static String? _$author(HostedReview v) => v.author;
  static const Field<HostedReview, String> _f$author = Field(
    'author',
    _$author,
    opt: true,
  );
  static String? _$baseBranch(HostedReview v) => v.baseBranch;
  static const Field<HostedReview, String> _f$baseBranch = Field(
    'baseBranch',
    _$baseBranch,
    opt: true,
  );
  static String? _$headBranch(HostedReview v) => v.headBranch;
  static const Field<HostedReview, String> _f$headBranch = Field(
    'headBranch',
    _$headBranch,
    opt: true,
  );
  static String? _$headSha(HostedReview v) => v.headSha;
  static const Field<HostedReview, String> _f$headSha = Field(
    'headSha',
    _$headSha,
    opt: true,
  );
  static String? _$comparisonBaseSha(HostedReview v) => v.comparisonBaseSha;
  static const Field<HostedReview, String> _f$comparisonBaseSha = Field(
    'comparisonBaseSha',
    _$comparisonBaseSha,
    opt: true,
  );
  static String? _$mergeCommitSha(HostedReview v) => v.mergeCommitSha;
  static const Field<HostedReview, String> _f$mergeCommitSha = Field(
    'mergeCommitSha',
    _$mergeCommitSha,
    opt: true,
  );
  static HostedReviewMergeable _$mergeable(HostedReview v) => v.mergeable;
  static const Field<HostedReview, HostedReviewMergeable> _f$mergeable = Field(
    'mergeable',
    _$mergeable,
    opt: true,
    def: HostedReviewMergeable.unknown,
  );

  @override
  final MappableFields<HostedReview> fields = const {
    #provider: _f$provider,
    #number: _f$number,
    #title: _f$title,
    #state: _f$state,
    #url: _f$url,
    #createdAt: _f$createdAt,
    #author: _f$author,
    #baseBranch: _f$baseBranch,
    #headBranch: _f$headBranch,
    #headSha: _f$headSha,
    #comparisonBaseSha: _f$comparisonBaseSha,
    #mergeCommitSha: _f$mergeCommitSha,
    #mergeable: _f$mergeable,
  };

  static HostedReview _instantiate(DecodingData data) {
    return HostedReview(
      provider: data.dec(_f$provider),
      number: data.dec(_f$number),
      title: data.dec(_f$title),
      state: data.dec(_f$state),
      url: data.dec(_f$url),
      createdAt: data.dec(_f$createdAt),
      author: data.dec(_f$author),
      baseBranch: data.dec(_f$baseBranch),
      headBranch: data.dec(_f$headBranch),
      headSha: data.dec(_f$headSha),
      comparisonBaseSha: data.dec(_f$comparisonBaseSha),
      mergeCommitSha: data.dec(_f$mergeCommitSha),
      mergeable: data.dec(_f$mergeable),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static HostedReview fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<HostedReview>(map);
  }

  static HostedReview fromJson(String json) {
    return ensureInitialized().decodeJson<HostedReview>(json);
  }
}

mixin HostedReviewMappable {
  String toJson() {
    return HostedReviewMapper.ensureInitialized().encodeJson<HostedReview>(
      this as HostedReview,
    );
  }

  Map<String, dynamic> toMap() {
    return HostedReviewMapper.ensureInitialized().encodeMap<HostedReview>(
      this as HostedReview,
    );
  }

  HostedReviewCopyWith<HostedReview, HostedReview, HostedReview> get copyWith =>
      _HostedReviewCopyWithImpl<HostedReview, HostedReview>(
        this as HostedReview,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return HostedReviewMapper.ensureInitialized().stringifyValue(
      this as HostedReview,
    );
  }

  @override
  bool operator ==(Object other) {
    return HostedReviewMapper.ensureInitialized().equalsValue(
      this as HostedReview,
      other,
    );
  }

  @override
  int get hashCode {
    return HostedReviewMapper.ensureInitialized().hashValue(
      this as HostedReview,
    );
  }
}

extension HostedReviewValueCopy<$R, $Out>
    on ObjectCopyWith<$R, HostedReview, $Out> {
  HostedReviewCopyWith<$R, HostedReview, $Out> get $asHostedReview =>
      $base.as((v, t, t2) => _HostedReviewCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class HostedReviewCopyWith<$R, $In extends HostedReview, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    GitHostingProvider? provider,
    int? number,
    String? title,
    HostedReviewState? state,
    String? url,
    DateTime? createdAt,
    String? author,
    String? baseBranch,
    String? headBranch,
    String? headSha,
    String? comparisonBaseSha,
    String? mergeCommitSha,
    HostedReviewMergeable? mergeable,
  });
  HostedReviewCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _HostedReviewCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, HostedReview, $Out>
    implements HostedReviewCopyWith<$R, HostedReview, $Out> {
  _HostedReviewCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<HostedReview> $mapper =
      HostedReviewMapper.ensureInitialized();
  @override
  $R call({
    GitHostingProvider? provider,
    int? number,
    String? title,
    HostedReviewState? state,
    String? url,
    Object? createdAt = $none,
    Object? author = $none,
    Object? baseBranch = $none,
    Object? headBranch = $none,
    Object? headSha = $none,
    Object? comparisonBaseSha = $none,
    Object? mergeCommitSha = $none,
    HostedReviewMergeable? mergeable,
  }) => $apply(
    FieldCopyWithData({
      if (provider != null) #provider: provider,
      if (number != null) #number: number,
      if (title != null) #title: title,
      if (state != null) #state: state,
      if (url != null) #url: url,
      if (createdAt != $none) #createdAt: createdAt,
      if (author != $none) #author: author,
      if (baseBranch != $none) #baseBranch: baseBranch,
      if (headBranch != $none) #headBranch: headBranch,
      if (headSha != $none) #headSha: headSha,
      if (comparisonBaseSha != $none) #comparisonBaseSha: comparisonBaseSha,
      if (mergeCommitSha != $none) #mergeCommitSha: mergeCommitSha,
      if (mergeable != null) #mergeable: mergeable,
    }),
  );
  @override
  HostedReview $make(CopyWithData data) => HostedReview(
    provider: data.get(#provider, or: $value.provider),
    number: data.get(#number, or: $value.number),
    title: data.get(#title, or: $value.title),
    state: data.get(#state, or: $value.state),
    url: data.get(#url, or: $value.url),
    createdAt: data.get(#createdAt, or: $value.createdAt),
    author: data.get(#author, or: $value.author),
    baseBranch: data.get(#baseBranch, or: $value.baseBranch),
    headBranch: data.get(#headBranch, or: $value.headBranch),
    headSha: data.get(#headSha, or: $value.headSha),
    comparisonBaseSha: data.get(
      #comparisonBaseSha,
      or: $value.comparisonBaseSha,
    ),
    mergeCommitSha: data.get(#mergeCommitSha, or: $value.mergeCommitSha),
    mergeable: data.get(#mergeable, or: $value.mergeable),
  );

  @override
  HostedReviewCopyWith<$R2, HostedReview, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _HostedReviewCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

