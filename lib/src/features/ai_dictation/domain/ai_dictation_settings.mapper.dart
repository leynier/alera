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

class AiDictationFallbackProviderMapper
    extends EnumMapper<AiDictationFallbackProvider> {
  AiDictationFallbackProviderMapper._();

  static AiDictationFallbackProviderMapper? _instance;
  static AiDictationFallbackProviderMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = AiDictationFallbackProviderMapper._(),
      );
    }
    return _instance!;
  }

  static AiDictationFallbackProvider fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  AiDictationFallbackProvider decode(dynamic value) {
    switch (value) {
      case r'openAiCompatible':
        return AiDictationFallbackProvider.openAiCompatible;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(AiDictationFallbackProvider self) {
    switch (self) {
      case AiDictationFallbackProvider.openAiCompatible:
        return r'openAiCompatible';
    }
  }
}

extension AiDictationFallbackProviderMapperExtension
    on AiDictationFallbackProvider {
  String toValue() {
    AiDictationFallbackProviderMapper.ensureInitialized();
    return MapperContainer.globals.toValue<AiDictationFallbackProvider>(this)
        as String;
  }
}

class AiDictationTranscriptionEngineMapper
    extends EnumMapper<AiDictationTranscriptionEngine> {
  AiDictationTranscriptionEngineMapper._();

  static AiDictationTranscriptionEngineMapper? _instance;
  static AiDictationTranscriptionEngineMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = AiDictationTranscriptionEngineMapper._(),
      );
    }
    return _instance!;
  }

  static AiDictationTranscriptionEngine fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  AiDictationTranscriptionEngine decode(dynamic value) {
    switch (value) {
      case r'localWhisper':
        return AiDictationTranscriptionEngine.localWhisper;
      case r'systemOnDevice':
        return AiDictationTranscriptionEngine.systemOnDevice;
      case r'systemRecognition':
        return AiDictationTranscriptionEngine.systemRecognition;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(AiDictationTranscriptionEngine self) {
    switch (self) {
      case AiDictationTranscriptionEngine.localWhisper:
        return r'localWhisper';
      case AiDictationTranscriptionEngine.systemOnDevice:
        return r'systemOnDevice';
      case AiDictationTranscriptionEngine.systemRecognition:
        return r'systemRecognition';
    }
  }
}

extension AiDictationTranscriptionEngineMapperExtension
    on AiDictationTranscriptionEngine {
  String toValue() {
    AiDictationTranscriptionEngineMapper.ensureInitialized();
    return MapperContainer.globals.toValue<AiDictationTranscriptionEngine>(this)
        as String;
  }
}

class AiDictationRewriteModeMapper extends EnumMapper<AiDictationRewriteMode> {
  AiDictationRewriteModeMapper._();

  static AiDictationRewriteModeMapper? _instance;
  static AiDictationRewriteModeMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = AiDictationRewriteModeMapper._());
    }
    return _instance!;
  }

  static AiDictationRewriteMode fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  AiDictationRewriteMode decode(dynamic value) {
    switch (value) {
      case r'off':
        return AiDictationRewriteMode.off;
      case r'cleanUp':
        return AiDictationRewriteMode.cleanUp;
      case r'summarize':
        return AiDictationRewriteMode.summarize;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(AiDictationRewriteMode self) {
    switch (self) {
      case AiDictationRewriteMode.off:
        return r'off';
      case AiDictationRewriteMode.cleanUp:
        return r'cleanUp';
      case AiDictationRewriteMode.summarize:
        return r'summarize';
    }
  }
}

extension AiDictationRewriteModeMapperExtension on AiDictationRewriteMode {
  String toValue() {
    AiDictationRewriteModeMapper.ensureInitialized();
    return MapperContainer.globals.toValue<AiDictationRewriteMode>(this)
        as String;
  }
}

class AiDictationSettingsMapper extends ClassMapperBase<AiDictationSettings> {
  AiDictationSettingsMapper._();

  static AiDictationSettingsMapper? _instance;
  static AiDictationSettingsMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = AiDictationSettingsMapper._());
      AiDictationTranscriptionEngineMapper.ensureInitialized();
      AiDictationRewriteModeMapper.ensureInitialized();
      AiDictationProviderPolicyMapper.ensureInitialized();
      AiDictationFallbackProviderMapper.ensureInitialized();
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
  static AiDictationTranscriptionEngine _$transcriptionEngine(
    AiDictationSettings v,
  ) => v.transcriptionEngine;
  static const Field<AiDictationSettings, AiDictationTranscriptionEngine>
  _f$transcriptionEngine = Field(
    'transcriptionEngine',
    _$transcriptionEngine,
    opt: true,
    def: AiDictationTranscriptionEngine.localWhisper,
  );
  static AiDictationRewriteMode _$rewriteMode(AiDictationSettings v) =>
      v.rewriteMode;
  static const Field<AiDictationSettings, AiDictationRewriteMode>
  _f$rewriteMode = Field(
    'rewriteMode',
    _$rewriteMode,
    opt: true,
    def: AiDictationRewriteMode.off,
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
  static bool _$hostFallbackEnabled(AiDictationSettings v) =>
      v.hostFallbackEnabled;
  static const Field<AiDictationSettings, bool> _f$hostFallbackEnabled = Field(
    'hostFallbackEnabled',
    _$hostFallbackEnabled,
    opt: true,
    def: true,
  );
  static bool _$providerFallbackEnabled(AiDictationSettings v) =>
      v.providerFallbackEnabled;
  static const Field<AiDictationSettings, bool> _f$providerFallbackEnabled =
      Field(
        'providerFallbackEnabled',
        _$providerFallbackEnabled,
        opt: true,
        def: false,
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
  static AiDictationFallbackProvider _$remoteProvider(AiDictationSettings v) =>
      v.remoteProvider;
  static const Field<AiDictationSettings, AiDictationFallbackProvider>
  _f$remoteProvider = Field(
    'remoteProvider',
    _$remoteProvider,
    opt: true,
    def: AiDictationFallbackProvider.openAiCompatible,
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
  static int? _$systemRecognitionConsentVersion(AiDictationSettings v) =>
      v.systemRecognitionConsentVersion;
  static const Field<AiDictationSettings, int>
  _f$systemRecognitionConsentVersion = Field(
    'systemRecognitionConsentVersion',
    _$systemRecognitionConsentVersion,
    opt: true,
  );

  @override
  final MappableFields<AiDictationSettings> fields = const {
    #enabled: _f$enabled,
    #transcriptionEngine: _f$transcriptionEngine,
    #rewriteMode: _f$rewriteMode,
    #providerPolicy: _f$providerPolicy,
    #language: _f$language,
    #localModelId: _f$localModelId,
    #hostFallbackEnabled: _f$hostFallbackEnabled,
    #providerFallbackEnabled: _f$providerFallbackEnabled,
    #remoteBaseUrl: _f$remoteBaseUrl,
    #remoteModel: _f$remoteModel,
    #remoteProvider: _f$remoteProvider,
    #timeoutSeconds: _f$timeoutSeconds,
    #remoteConsentVersion: _f$remoteConsentVersion,
    #systemRecognitionConsentVersion: _f$systemRecognitionConsentVersion,
  };

  static AiDictationSettings _instantiate(DecodingData data) {
    return AiDictationSettings(
      enabled: data.dec(_f$enabled),
      transcriptionEngine: data.dec(_f$transcriptionEngine),
      rewriteMode: data.dec(_f$rewriteMode),
      providerPolicy: data.dec(_f$providerPolicy),
      language: data.dec(_f$language),
      localModelId: data.dec(_f$localModelId),
      hostFallbackEnabled: data.dec(_f$hostFallbackEnabled),
      providerFallbackEnabled: data.dec(_f$providerFallbackEnabled),
      remoteBaseUrl: data.dec(_f$remoteBaseUrl),
      remoteModel: data.dec(_f$remoteModel),
      remoteProvider: data.dec(_f$remoteProvider),
      timeoutSeconds: data.dec(_f$timeoutSeconds),
      remoteConsentVersion: data.dec(_f$remoteConsentVersion),
      systemRecognitionConsentVersion: data.dec(
        _f$systemRecognitionConsentVersion,
      ),
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
    AiDictationTranscriptionEngine? transcriptionEngine,
    AiDictationRewriteMode? rewriteMode,
    AiDictationProviderPolicy? providerPolicy,
    String? language,
    String? localModelId,
    bool? hostFallbackEnabled,
    bool? providerFallbackEnabled,
    String? remoteBaseUrl,
    String? remoteModel,
    AiDictationFallbackProvider? remoteProvider,
    int? timeoutSeconds,
    int? remoteConsentVersion,
    int? systemRecognitionConsentVersion,
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
    AiDictationTranscriptionEngine? transcriptionEngine,
    AiDictationRewriteMode? rewriteMode,
    AiDictationProviderPolicy? providerPolicy,
    Object? language = $none,
    String? localModelId,
    bool? hostFallbackEnabled,
    bool? providerFallbackEnabled,
    Object? remoteBaseUrl = $none,
    Object? remoteModel = $none,
    AiDictationFallbackProvider? remoteProvider,
    int? timeoutSeconds,
    Object? remoteConsentVersion = $none,
    Object? systemRecognitionConsentVersion = $none,
  }) => $apply(
    FieldCopyWithData({
      if (enabled != null) #enabled: enabled,
      if (transcriptionEngine != null)
        #transcriptionEngine: transcriptionEngine,
      if (rewriteMode != null) #rewriteMode: rewriteMode,
      if (providerPolicy != null) #providerPolicy: providerPolicy,
      if (language != $none) #language: language,
      if (localModelId != null) #localModelId: localModelId,
      if (hostFallbackEnabled != null)
        #hostFallbackEnabled: hostFallbackEnabled,
      if (providerFallbackEnabled != null)
        #providerFallbackEnabled: providerFallbackEnabled,
      if (remoteBaseUrl != $none) #remoteBaseUrl: remoteBaseUrl,
      if (remoteModel != $none) #remoteModel: remoteModel,
      if (remoteProvider != null) #remoteProvider: remoteProvider,
      if (timeoutSeconds != null) #timeoutSeconds: timeoutSeconds,
      if (remoteConsentVersion != $none)
        #remoteConsentVersion: remoteConsentVersion,
      if (systemRecognitionConsentVersion != $none)
        #systemRecognitionConsentVersion: systemRecognitionConsentVersion,
    }),
  );
  @override
  AiDictationSettings $make(CopyWithData data) => AiDictationSettings(
    enabled: data.get(#enabled, or: $value.enabled),
    transcriptionEngine: data.get(
      #transcriptionEngine,
      or: $value.transcriptionEngine,
    ),
    rewriteMode: data.get(#rewriteMode, or: $value.rewriteMode),
    providerPolicy: data.get(#providerPolicy, or: $value.providerPolicy),
    language: data.get(#language, or: $value.language),
    localModelId: data.get(#localModelId, or: $value.localModelId),
    hostFallbackEnabled: data.get(
      #hostFallbackEnabled,
      or: $value.hostFallbackEnabled,
    ),
    providerFallbackEnabled: data.get(
      #providerFallbackEnabled,
      or: $value.providerFallbackEnabled,
    ),
    remoteBaseUrl: data.get(#remoteBaseUrl, or: $value.remoteBaseUrl),
    remoteModel: data.get(#remoteModel, or: $value.remoteModel),
    remoteProvider: data.get(#remoteProvider, or: $value.remoteProvider),
    timeoutSeconds: data.get(#timeoutSeconds, or: $value.timeoutSeconds),
    remoteConsentVersion: data.get(
      #remoteConsentVersion,
      or: $value.remoteConsentVersion,
    ),
    systemRecognitionConsentVersion: data.get(
      #systemRecognitionConsentVersion,
      or: $value.systemRecognitionConsentVersion,
    ),
  );

  @override
  AiDictationSettingsCopyWith<$R2, AiDictationSettings, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _AiDictationSettingsCopyWithImpl<$R2, $Out2>($value, $cast, t);
}
