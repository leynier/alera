// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'linked_review.dart';

class LinkedReviewMapper extends ClassMapperBase<LinkedReview> {
  LinkedReviewMapper._();

  static LinkedReviewMapper? _instance;
  static LinkedReviewMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = LinkedReviewMapper._());
      GitHostingProviderMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'LinkedReview';

  static String _$workspaceId(LinkedReview v) => v.workspaceId;
  static const Field<LinkedReview, String> _f$workspaceId = Field(
    'workspaceId',
    _$workspaceId,
  );
  static DateTime _$linkedAt(LinkedReview v) => v.linkedAt;
  static const Field<LinkedReview, DateTime> _f$linkedAt = Field(
    'linkedAt',
    _$linkedAt,
  );
  static bool _$dismissed(LinkedReview v) => v.dismissed;
  static const Field<LinkedReview, bool> _f$dismissed = Field(
    'dismissed',
    _$dismissed,
    opt: true,
    def: false,
  );
  static GitHostingProvider? _$provider(LinkedReview v) => v.provider;
  static const Field<LinkedReview, GitHostingProvider> _f$provider = Field(
    'provider',
    _$provider,
    opt: true,
  );
  static int? _$number(LinkedReview v) => v.number;
  static const Field<LinkedReview, int> _f$number = Field(
    'number',
    _$number,
    opt: true,
  );
  static String? _$url(LinkedReview v) => v.url;
  static const Field<LinkedReview, String> _f$url = Field(
    'url',
    _$url,
    opt: true,
  );

  @override
  final MappableFields<LinkedReview> fields = const {
    #workspaceId: _f$workspaceId,
    #linkedAt: _f$linkedAt,
    #dismissed: _f$dismissed,
    #provider: _f$provider,
    #number: _f$number,
    #url: _f$url,
  };

  static LinkedReview _instantiate(DecodingData data) {
    return LinkedReview(
      workspaceId: data.dec(_f$workspaceId),
      linkedAt: data.dec(_f$linkedAt),
      dismissed: data.dec(_f$dismissed),
      provider: data.dec(_f$provider),
      number: data.dec(_f$number),
      url: data.dec(_f$url),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static LinkedReview fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<LinkedReview>(map);
  }

  static LinkedReview fromJson(String json) {
    return ensureInitialized().decodeJson<LinkedReview>(json);
  }
}

mixin LinkedReviewMappable {
  String toJson() {
    return LinkedReviewMapper.ensureInitialized().encodeJson<LinkedReview>(
      this as LinkedReview,
    );
  }

  Map<String, dynamic> toMap() {
    return LinkedReviewMapper.ensureInitialized().encodeMap<LinkedReview>(
      this as LinkedReview,
    );
  }

  LinkedReviewCopyWith<LinkedReview, LinkedReview, LinkedReview> get copyWith =>
      _LinkedReviewCopyWithImpl<LinkedReview, LinkedReview>(
        this as LinkedReview,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return LinkedReviewMapper.ensureInitialized().stringifyValue(
      this as LinkedReview,
    );
  }

  @override
  bool operator ==(Object other) {
    return LinkedReviewMapper.ensureInitialized().equalsValue(
      this as LinkedReview,
      other,
    );
  }

  @override
  int get hashCode {
    return LinkedReviewMapper.ensureInitialized().hashValue(
      this as LinkedReview,
    );
  }
}

extension LinkedReviewValueCopy<$R, $Out>
    on ObjectCopyWith<$R, LinkedReview, $Out> {
  LinkedReviewCopyWith<$R, LinkedReview, $Out> get $asLinkedReview =>
      $base.as((v, t, t2) => _LinkedReviewCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class LinkedReviewCopyWith<$R, $In extends LinkedReview, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    String? workspaceId,
    DateTime? linkedAt,
    bool? dismissed,
    GitHostingProvider? provider,
    int? number,
    String? url,
  });
  LinkedReviewCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _LinkedReviewCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, LinkedReview, $Out>
    implements LinkedReviewCopyWith<$R, LinkedReview, $Out> {
  _LinkedReviewCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<LinkedReview> $mapper =
      LinkedReviewMapper.ensureInitialized();
  @override
  $R call({
    String? workspaceId,
    DateTime? linkedAt,
    bool? dismissed,
    Object? provider = $none,
    Object? number = $none,
    Object? url = $none,
  }) => $apply(
    FieldCopyWithData({
      if (workspaceId != null) #workspaceId: workspaceId,
      if (linkedAt != null) #linkedAt: linkedAt,
      if (dismissed != null) #dismissed: dismissed,
      if (provider != $none) #provider: provider,
      if (number != $none) #number: number,
      if (url != $none) #url: url,
    }),
  );
  @override
  LinkedReview $make(CopyWithData data) => LinkedReview(
    workspaceId: data.get(#workspaceId, or: $value.workspaceId),
    linkedAt: data.get(#linkedAt, or: $value.linkedAt),
    dismissed: data.get(#dismissed, or: $value.dismissed),
    provider: data.get(#provider, or: $value.provider),
    number: data.get(#number, or: $value.number),
    url: data.get(#url, or: $value.url),
  );

  @override
  LinkedReviewCopyWith<$R2, LinkedReview, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _LinkedReviewCopyWithImpl<$R2, $Out2>($value, $cast, t);
}
