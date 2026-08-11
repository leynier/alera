// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'ai_dictation_settings.dart';

class AiDictationProviderPolicyMapper
    extends EnumMapper<AiDictationProviderPolicy> {
  AiDictationProviderPolicyMapper._();

  static AiDictationProviderPolicyMapper? _instance;
  static AiDictationProviderPolicyMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = AiDictationProviderPolicyMapper._(),
      );
    }
    return _instance!;
  }

  static AiDictationProviderPolicy fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  AiDictationProviderPolicy decode(dynamic value) {
    switch (value) {
      case r'localOnly':
        return AiDictationProviderPolicy.localOnly;
      case r'localPreferred':
        return AiDictationProviderPolicy.localPreferred;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(AiDictationProviderPolicy self) {
    switch (self) {
      case AiDictationProviderPolicy.localOnly:
        return r'localOnly';
      case AiDictationProviderPolicy.localPreferred:
        return r'localPreferred';
    }
  }
}
extension AiDictationProviderPolicyMapperExtension
    on AiDictationProviderPolicy {
  String toValue() {
    AiDictationProviderPolicyMapper.ensureInitialized();
    return MapperContainer.globals.toValue<AiDictationProviderPolicy>(this)
        as String;
  }
}

class AiDictationSettingsMapper extends ClassMapperBase<AiDictationSettings> {
  AiDictationSettingsMapper._();

  static AiDictationSettingsMapper? _instance;
  static AiDictationSettingsMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = AiDictationSettingsMapper._());
      AiDictationProviderPolicyMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'AiDictationSettings';

  static bool _$enabled(AiDictationSettings v) => v.enabled;
  static const Field<AiDictationSettings, bool> _f$enabled = Field(
    'enabled',
    _$enabled,
    opt: true,
    def: false,
  );
  static AiDictationProviderPolicy _$providerPolicy(AiDictationSettings v) =>
      v.providerPolicy;
  static const Field<AiDictationSettings, AiDictationProviderPolicy>
  _f$providerPolicy = Field(
    'providerPolicy',
    _$providerPolicy,
    opt: true,
    def: AiDictationProviderPolicy.localPreferred,
  );
  static String? _$language(AiDictationSettings v) => v.language;
  static const Field<AiDictationSettings, String> _f$language = Field(
    'language',
    _$language,
    opt: true,
  );
  static String _$localModelId(AiDictationSettings v) => v.localModelId;
  static const Field<AiDictationSettings, String> _f$localModelId = Field(
    'localModelId',
    _$localModelId,
    opt: true,
    def: 'whisper-cpp-base',
  );
  static String? _$remoteBaseUrl(AiDictationSettings v) => v.remoteBaseUrl;
  static const Field<AiDictationSettings, String> _f$remoteBaseUrl = Field(
    'remoteBaseUrl',
    _$remoteBaseUrl,
    opt: true,
  );
  static String? _$remoteModel(AiDictationSettings v) => v.remoteModel;
  static const Field<AiDictationSettings, String> _f$remoteModel = Field(
    'remoteModel',
    _$remoteModel,
    opt: true,
  );
  static int _$timeoutSeconds(AiDictationSettings v) => v.timeoutSeconds;
  static const Field<AiDictationSettings, int> _f$timeoutSeconds = Field(
    'timeoutSeconds',
    _$timeoutSeconds,
    opt: true,
    def: 60,
  );
  static int? _$remoteConsentVersion(AiDictationSettings v) =>
      v.remoteConsentVersion;
  static const Field<AiDictationSettings, int> _f$remoteConsentVersion = Field(
    'remoteConsentVersion',
    _$remoteConsentVersion,
    opt: true,
  );

  @override
  final MappableFields<AiDictationSettings> fields = const {
    #enabled: _f$enabled,
    #providerPolicy: _f$providerPolicy,
    #language: _f$language,
    #localModelId: _f$localModelId,
    #remoteBaseUrl: _f$remoteBaseUrl,
    #remoteModel: _f$remoteModel,
    #timeoutSeconds: _f$timeoutSeconds,
    #remoteConsentVersion: _f$remoteConsentVersion,
  };

  static AiDictationSettings _instantiate(DecodingData data) {
    return AiDictationSettings(
      enabled: data.dec(_f$enabled),
      providerPolicy: data.dec(_f$providerPolicy),
      language: data.dec(_f$language),
      localModelId: data.dec(_f$localModelId),
      remoteBaseUrl: data.dec(_f$remoteBaseUrl),
      remoteModel: data.dec(_f$remoteModel),
      timeoutSeconds: data.dec(_f$timeoutSeconds),
      remoteConsentVersion: data.dec(_f$remoteConsentVersion),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static AiDictationSettings fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<AiDictationSettings>(map);
  }

  static AiDictationSettings fromJson(String json) {
    return ensureInitialized().decodeJson<AiDictationSettings>(json);
  }
}

mixin AiDictationSettingsMappable {
  String toJson() {
    return AiDictationSettingsMapper.ensureInitialized()
        .encodeJson<AiDictationSettings>(this as AiDictationSettings);
  }

  Map<String, dynamic> toMap() {
    return AiDictationSettingsMapper.ensureInitialized()
        .encodeMap<AiDictationSettings>(this as AiDictationSettings);
  }

  AiDictationSettingsCopyWith<
    AiDictationSettings,
    AiDictationSettings,
    AiDictationSettings
  >
  get copyWith =>
      _AiDictationSettingsCopyWithImpl<
        AiDictationSettings,
        AiDictationSettings
      >(this as AiDictationSettings, $identity, $identity);
  @override
  String toString() {
    return AiDictationSettingsMapper.ensureInitialized().stringifyValue(
      this as AiDictationSettings,
    );
  }

  @override
  bool operator ==(Object other) {
    return AiDictationSettingsMapper.ensureInitialized().equalsValue(
      this as AiDictationSettings,
      other,
    );
  }

  @override
  int get hashCode {
    return AiDictationSettingsMapper.ensureInitialized().hashValue(
      this as AiDictationSettings,
    );
  }
}

extension AiDictationSettingsValueCopy<$R, $Out>
    on ObjectCopyWith<$R, AiDictationSettings, $Out> {
  AiDictationSettingsCopyWith<$R, AiDictationSettings, $Out>
  get $asAiDictationSettings => $base.as(
    (v, t, t2) => _AiDictationSettingsCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class AiDictationSettingsCopyWith<
  $R,
  $In extends AiDictationSettings,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    bool? enabled,
    AiDictationProviderPolicy? providerPolicy,
    String? language,
    String? localModelId,
    String? remoteBaseUrl,
    String? remoteModel,
    int? timeoutSeconds,
    int? remoteConsentVersion,
  });
  AiDictationSettingsCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _AiDictationSettingsCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, AiDictationSettings, $Out>
    implements AiDictationSettingsCopyWith<$R, AiDictationSettings, $Out> {
  _AiDictationSettingsCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<AiDictationSettings> $mapper =
      AiDictationSettingsMapper.ensureInitialized();
  @override
  $R call({
    bool? enabled,
    AiDictationProviderPolicy? providerPolicy,
    Object? language = $none,
    String? localModelId,
    Object? remoteBaseUrl = $none,
    Object? remoteModel = $none,
    int? timeoutSeconds,
    Object? remoteConsentVersion = $none,
  }) => $apply(
    FieldCopyWithData({
      if (enabled != null) #enabled: enabled,
      if (providerPolicy != null) #providerPolicy: providerPolicy,
      if (language != $none) #language: language,
      if (localModelId != null) #localModelId: localModelId,
      if (remoteBaseUrl != $none) #remoteBaseUrl: remoteBaseUrl,
      if (remoteModel != $none) #remoteModel: remoteModel,
      if (timeoutSeconds != null) #timeoutSeconds: timeoutSeconds,
      if (remoteConsentVersion != $none)
        #remoteConsentVersion: remoteConsentVersion,
    }),
  );
  @override
  AiDictationSettings $make(CopyWithData data) => AiDictationSettings(
    enabled: data.get(#enabled, or: $value.enabled),
    providerPolicy: data.get(#providerPolicy, or: $value.providerPolicy),
    language: data.get(#language, or: $value.language),
    localModelId: data.get(#localModelId, or: $value.localModelId),
    remoteBaseUrl: data.get(#remoteBaseUrl, or: $value.remoteBaseUrl),
    remoteModel: data.get(#remoteModel, or: $value.remoteModel),
    timeoutSeconds: data.get(#timeoutSeconds, or: $value.timeoutSeconds),
    remoteConsentVersion: data.get(
      #remoteConsentVersion,
      or: $value.remoteConsentVersion,
    ),
  );

  @override
  AiDictationSettingsCopyWith<$R2, AiDictationSettings, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _AiDictationSettingsCopyWithImpl<$R2, $Out2>($value, $cast, t);
}
