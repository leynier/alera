// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'review_check.dart';

class ReviewCheckStatusMapper extends EnumMapper<ReviewCheckStatus> {
  ReviewCheckStatusMapper._();

  static ReviewCheckStatusMapper? _instance;
  static ReviewCheckStatusMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ReviewCheckStatusMapper._());
    }
    return _instance!;
  }

  static ReviewCheckStatus fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  ReviewCheckStatus decode(dynamic value) {
    switch (value) {
      case r'queued':
        return ReviewCheckStatus.queued;
      case r'inProgress':
        return ReviewCheckStatus.inProgress;
      case r'completed':
        return ReviewCheckStatus.completed;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(ReviewCheckStatus self) {
    switch (self) {
      case ReviewCheckStatus.queued:
        return r'queued';
      case ReviewCheckStatus.inProgress:
        return r'inProgress';
      case ReviewCheckStatus.completed:
        return r'completed';
    }
  }
}

extension ReviewCheckStatusMapperExtension on ReviewCheckStatus {
  String toValue() {
    ReviewCheckStatusMapper.ensureInitialized();
    return MapperContainer.globals.toValue<ReviewCheckStatus>(this) as String;
  }
}

class ReviewCheckConclusionMapper extends EnumMapper<ReviewCheckConclusion> {
  ReviewCheckConclusionMapper._();

  static ReviewCheckConclusionMapper? _instance;
  static ReviewCheckConclusionMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ReviewCheckConclusionMapper._());
    }
    return _instance!;
  }

  static ReviewCheckConclusion fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  ReviewCheckConclusion decode(dynamic value) {
    switch (value) {
      case r'success':
        return ReviewCheckConclusion.success;
      case r'failure':
        return ReviewCheckConclusion.failure;
      case r'cancelled':
        return ReviewCheckConclusion.cancelled;
      case r'timedOut':
        return ReviewCheckConclusion.timedOut;
      case r'actionRequired':
        return ReviewCheckConclusion.actionRequired;
      case r'neutral':
        return ReviewCheckConclusion.neutral;
      case r'skipped':
        return ReviewCheckConclusion.skipped;
      case r'pending':
        return ReviewCheckConclusion.pending;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(ReviewCheckConclusion self) {
    switch (self) {
      case ReviewCheckConclusion.success:
        return r'success';
      case ReviewCheckConclusion.failure:
        return r'failure';
      case ReviewCheckConclusion.cancelled:
        return r'cancelled';
      case ReviewCheckConclusion.timedOut:
        return r'timedOut';
      case ReviewCheckConclusion.actionRequired:
        return r'actionRequired';
      case ReviewCheckConclusion.neutral:
        return r'neutral';
      case ReviewCheckConclusion.skipped:
        return r'skipped';
      case ReviewCheckConclusion.pending:
        return r'pending';
    }
  }
}

extension ReviewCheckConclusionMapperExtension on ReviewCheckConclusion {
  String toValue() {
    ReviewCheckConclusionMapper.ensureInitialized();
    return MapperContainer.globals.toValue<ReviewCheckConclusion>(this)
        as String;
  }
}

class ReviewChecksRollupMapper extends EnumMapper<ReviewChecksRollup> {
  ReviewChecksRollupMapper._();

  static ReviewChecksRollupMapper? _instance;
  static ReviewChecksRollupMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ReviewChecksRollupMapper._());
    }
    return _instance!;
  }

  static ReviewChecksRollup fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  ReviewChecksRollup decode(dynamic value) {
    switch (value) {
      case r'none':
        return ReviewChecksRollup.none;
      case r'pending':
        return ReviewChecksRollup.pending;
      case r'success':
        return ReviewChecksRollup.success;
      case r'failure':
        return ReviewChecksRollup.failure;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(ReviewChecksRollup self) {
    switch (self) {
      case ReviewChecksRollup.none:
        return r'none';
      case ReviewChecksRollup.pending:
        return r'pending';
      case ReviewChecksRollup.success:
        return r'success';
      case ReviewChecksRollup.failure:
        return r'failure';
    }
  }
}

extension ReviewChecksRollupMapperExtension on ReviewChecksRollup {
  String toValue() {
    ReviewChecksRollupMapper.ensureInitialized();
    return MapperContainer.globals.toValue<ReviewChecksRollup>(this) as String;
  }
}

class ReviewCheckMapper extends ClassMapperBase<ReviewCheck> {
  ReviewCheckMapper._();

  static ReviewCheckMapper? _instance;
  static ReviewCheckMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ReviewCheckMapper._());
      ReviewCheckStatusMapper.ensureInitialized();
      ReviewCheckConclusionMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ReviewCheck';

  static String _$name(ReviewCheck v) => v.name;
  static const Field<ReviewCheck, String> _f$name = Field('name', _$name);
  static ReviewCheckStatus _$status(ReviewCheck v) => v.status;
  static const Field<ReviewCheck, ReviewCheckStatus> _f$status = Field(
    'status',
    _$status,
  );
  static ReviewCheckConclusion _$conclusion(ReviewCheck v) => v.conclusion;
  static const Field<ReviewCheck, ReviewCheckConclusion> _f$conclusion = Field(
    'conclusion',
    _$conclusion,
  );
  static String? _$url(ReviewCheck v) => v.url;
  static const Field<ReviewCheck, String> _f$url = Field(
    'url',
    _$url,
    opt: true,
  );

  @override
  final MappableFields<ReviewCheck> fields = const {
    #name: _f$name,
    #status: _f$status,
    #conclusion: _f$conclusion,
    #url: _f$url,
  };

  static ReviewCheck _instantiate(DecodingData data) {
    return ReviewCheck(
      name: data.dec(_f$name),
      status: data.dec(_f$status),
      conclusion: data.dec(_f$conclusion),
      url: data.dec(_f$url),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ReviewCheck fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ReviewCheck>(map);
  }

  static ReviewCheck fromJson(String json) {
    return ensureInitialized().decodeJson<ReviewCheck>(json);
  }
}

mixin ReviewCheckMappable {
  String toJson() {
    return ReviewCheckMapper.ensureInitialized().encodeJson<ReviewCheck>(
      this as ReviewCheck,
    );
  }

  Map<String, dynamic> toMap() {
    return ReviewCheckMapper.ensureInitialized().encodeMap<ReviewCheck>(
      this as ReviewCheck,
    );
  }

  ReviewCheckCopyWith<ReviewCheck, ReviewCheck, ReviewCheck> get copyWith =>
      _ReviewCheckCopyWithImpl<ReviewCheck, ReviewCheck>(
        this as ReviewCheck,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return ReviewCheckMapper.ensureInitialized().stringifyValue(
      this as ReviewCheck,
    );
  }

  @override
  bool operator ==(Object other) {
    return ReviewCheckMapper.ensureInitialized().equalsValue(
      this as ReviewCheck,
      other,
    );
  }

  @override
  int get hashCode {
    return ReviewCheckMapper.ensureInitialized().hashValue(this as ReviewCheck);
  }
}

extension ReviewCheckValueCopy<$R, $Out>
    on ObjectCopyWith<$R, ReviewCheck, $Out> {
  ReviewCheckCopyWith<$R, ReviewCheck, $Out> get $asReviewCheck =>
      $base.as((v, t, t2) => _ReviewCheckCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class ReviewCheckCopyWith<$R, $In extends ReviewCheck, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    String? name,
    ReviewCheckStatus? status,
    ReviewCheckConclusion? conclusion,
    String? url,
  });
  ReviewCheckCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _ReviewCheckCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, ReviewCheck, $Out>
    implements ReviewCheckCopyWith<$R, ReviewCheck, $Out> {
  _ReviewCheckCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<ReviewCheck> $mapper =
      ReviewCheckMapper.ensureInitialized();
  @override
  $R call({
    String? name,
    ReviewCheckStatus? status,
    ReviewCheckConclusion? conclusion,
    Object? url = $none,
  }) => $apply(
    FieldCopyWithData({
      if (name != null) #name: name,
      if (status != null) #status: status,
      if (conclusion != null) #conclusion: conclusion,
      if (url != $none) #url: url,
    }),
  );
  @override
  ReviewCheck $make(CopyWithData data) => ReviewCheck(
    name: data.get(#name, or: $value.name),
    status: data.get(#status, or: $value.status),
    conclusion: data.get(#conclusion, or: $value.conclusion),
    url: data.get(#url, or: $value.url),
  );

  @override
  ReviewCheckCopyWith<$R2, ReviewCheck, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _ReviewCheckCopyWithImpl<$R2, $Out2>($value, $cast, t);
}
