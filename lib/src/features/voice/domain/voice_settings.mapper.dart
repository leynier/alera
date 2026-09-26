// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'voice_settings.dart';

class VoicePipelineMapper extends EnumMapper<VoicePipeline> {
  VoicePipelineMapper._();

  static VoicePipelineMapper? _instance;
  static VoicePipelineMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = VoicePipelineMapper._());
    }
    return _instance!;
  }

  static VoicePipeline fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  VoicePipeline decode(dynamic value) {
    switch (value) {
      case r'chained':
        return VoicePipeline.chained;
      case r'realtime':
        return VoicePipeline.realtime;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(VoicePipeline self) {
    switch (self) {
      case VoicePipeline.chained:
        return r'chained';
      case VoicePipeline.realtime:
        return r'realtime';
    }
  }
}

extension VoicePipelineMapperExtension on VoicePipeline {
  String toValue() {
    VoicePipelineMapper.ensureInitialized();
    return MapperContainer.globals.toValue<VoicePipeline>(this) as String;
  }
}

class VoiceSttProviderMapper extends EnumMapper<VoiceSttProvider> {
  VoiceSttProviderMapper._();

  static VoiceSttProviderMapper? _instance;
  static VoiceSttProviderMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = VoiceSttProviderMapper._());
    }
    return _instance!;
  }

  static VoiceSttProvider fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  VoiceSttProvider decode(dynamic value) {
    switch (value) {
      case r'localWhisper':
        return VoiceSttProvider.localWhisper;
      case r'geminiTranscribeLive':
        return VoiceSttProvider.geminiTranscribeLive;
      case r'openAiCompatible':
        return VoiceSttProvider.openAiCompatible;
      case r'codexRealtime':
        return VoiceSttProvider.codexRealtime;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(VoiceSttProvider self) {
    switch (self) {
      case VoiceSttProvider.localWhisper:
        return r'localWhisper';
      case VoiceSttProvider.geminiTranscribeLive:
        return r'geminiTranscribeLive';
      case VoiceSttProvider.openAiCompatible:
        return r'openAiCompatible';
      case VoiceSttProvider.codexRealtime:
        return r'codexRealtime';
    }
  }
}

extension VoiceSttProviderMapperExtension on VoiceSttProvider {
  String toValue() {
    VoiceSttProviderMapper.ensureInitialized();
    return MapperContainer.globals.toValue<VoiceSttProvider>(this) as String;
  }
}

class VoiceTtsProviderMapper extends EnumMapper<VoiceTtsProvider> {
  VoiceTtsProviderMapper._();

  static VoiceTtsProviderMapper? _instance;
  static VoiceTtsProviderMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = VoiceTtsProviderMapper._());
    }
    return _instance!;
  }

  static VoiceTtsProvider fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  VoiceTtsProvider decode(dynamic value) {
    switch (value) {
      case r'geminiFlashTts':
        return VoiceTtsProvider.geminiFlashTts;
      case r'openAiTts':
        return VoiceTtsProvider.openAiTts;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(VoiceTtsProvider self) {
    switch (self) {
      case VoiceTtsProvider.geminiFlashTts:
        return r'geminiFlashTts';
      case VoiceTtsProvider.openAiTts:
        return r'openAiTts';
    }
  }
}

extension VoiceTtsProviderMapperExtension on VoiceTtsProvider {
  String toValue() {
    VoiceTtsProviderMapper.ensureInitialized();
    return MapperContainer.globals.toValue<VoiceTtsProvider>(this) as String;
  }
}

class VoiceRealtimeProviderMapper extends EnumMapper<VoiceRealtimeProvider> {
  VoiceRealtimeProviderMapper._();

  static VoiceRealtimeProviderMapper? _instance;
  static VoiceRealtimeProviderMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = VoiceRealtimeProviderMapper._());
    }
    return _instance!;
  }

  static VoiceRealtimeProvider fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  VoiceRealtimeProvider decode(dynamic value) {
    switch (value) {
      case r'geminiFlashLive':
        return VoiceRealtimeProvider.geminiFlashLive;
      case r'gptRealtimeMini':
        return VoiceRealtimeProvider.gptRealtimeMini;
      case r'gptRealtime':
        return VoiceRealtimeProvider.gptRealtime;
      case r'gptLive1':
        return VoiceRealtimeProvider.gptLive1;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(VoiceRealtimeProvider self) {
    switch (self) {
      case VoiceRealtimeProvider.geminiFlashLive:
        return r'geminiFlashLive';
      case VoiceRealtimeProvider.gptRealtimeMini:
        return r'gptRealtimeMini';
      case VoiceRealtimeProvider.gptRealtime:
        return r'gptRealtime';
      case VoiceRealtimeProvider.gptLive1:
        return r'gptLive1';
    }
  }
}

extension VoiceRealtimeProviderMapperExtension on VoiceRealtimeProvider {
  String toValue() {
    VoiceRealtimeProviderMapper.ensureInitialized();
    return MapperContainer.globals.toValue<VoiceRealtimeProvider>(this)
        as String;
  }
}

class VoiceSettingsMapper extends ClassMapperBase<VoiceSettings> {
  VoiceSettingsMapper._();

  static VoiceSettingsMapper? _instance;
  static VoiceSettingsMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = VoiceSettingsMapper._());
      VoicePipelineMapper.ensureInitialized();
      VoiceSttProviderMapper.ensureInitialized();
      VoiceTtsProviderMapper.ensureInitialized();
      VoiceRealtimeProviderMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'VoiceSettings';

  static String? _$homeAgentProfileId(VoiceSettings v) => v.homeAgentProfileId;
  static const Field<VoiceSettings, String> _f$homeAgentProfileId = Field(
    'homeAgentProfileId',
    _$homeAgentProfileId,
    opt: true,
  );
  static VoicePipeline _$pipeline(VoiceSettings v) => v.pipeline;
  static const Field<VoiceSettings, VoicePipeline> _f$pipeline = Field(
    'pipeline',
    _$pipeline,
    opt: true,
    def: VoicePipeline.chained,
  );
  static VoiceSttProvider _$sttProvider(VoiceSettings v) => v.sttProvider;
  static const Field<VoiceSettings, VoiceSttProvider> _f$sttProvider = Field(
    'sttProvider',
    _$sttProvider,
    opt: true,
    def: VoiceSttProvider.localWhisper,
  );
  static VoiceTtsProvider _$ttsProvider(VoiceSettings v) => v.ttsProvider;
  static const Field<VoiceSettings, VoiceTtsProvider> _f$ttsProvider = Field(
    'ttsProvider',
    _$ttsProvider,
    opt: true,
    def: VoiceTtsProvider.geminiFlashTts,
  );
  static VoiceRealtimeProvider _$realtimeProvider(VoiceSettings v) =>
      v.realtimeProvider;
  static const Field<VoiceSettings, VoiceRealtimeProvider> _f$realtimeProvider =
      Field(
        'realtimeProvider',
        _$realtimeProvider,
        opt: true,
        def: VoiceRealtimeProvider.geminiFlashLive,
      );
  static String? _$ttsVoice(VoiceSettings v) => v.ttsVoice;
  static const Field<VoiceSettings, String> _f$ttsVoice = Field(
    'ttsVoice',
    _$ttsVoice,
    opt: true,
  );
  static bool _$ackWhileThinking(VoiceSettings v) => v.ackWhileThinking;
  static const Field<VoiceSettings, bool> _f$ackWhileThinking = Field(
    'ackWhileThinking',
    _$ackWhileThinking,
    opt: true,
    def: false,
  );

  @override
  final MappableFields<VoiceSettings> fields = const {
    #homeAgentProfileId: _f$homeAgentProfileId,
    #pipeline: _f$pipeline,
    #sttProvider: _f$sttProvider,
    #ttsProvider: _f$ttsProvider,
    #realtimeProvider: _f$realtimeProvider,
    #ttsVoice: _f$ttsVoice,
    #ackWhileThinking: _f$ackWhileThinking,
  };

  static VoiceSettings _instantiate(DecodingData data) {
    return VoiceSettings(
      homeAgentProfileId: data.dec(_f$homeAgentProfileId),
      pipeline: data.dec(_f$pipeline),
      sttProvider: data.dec(_f$sttProvider),
      ttsProvider: data.dec(_f$ttsProvider),
      realtimeProvider: data.dec(_f$realtimeProvider),
      ttsVoice: data.dec(_f$ttsVoice),
      ackWhileThinking: data.dec(_f$ackWhileThinking),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static VoiceSettings fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<VoiceSettings>(map);
  }

  static VoiceSettings fromJson(String json) {
    return ensureInitialized().decodeJson<VoiceSettings>(json);
  }
}

mixin VoiceSettingsMappable {
  String toJson() {
    return VoiceSettingsMapper.ensureInitialized().encodeJson<VoiceSettings>(
      this as VoiceSettings,
    );
  }

  Map<String, dynamic> toMap() {
    return VoiceSettingsMapper.ensureInitialized().encodeMap<VoiceSettings>(
      this as VoiceSettings,
    );
  }

  VoiceSettingsCopyWith<VoiceSettings, VoiceSettings, VoiceSettings>
  get copyWith => _VoiceSettingsCopyWithImpl<VoiceSettings, VoiceSettings>(
    this as VoiceSettings,
    $identity,
    $identity,
  );
  @override
  String toString() {
    return VoiceSettingsMapper.ensureInitialized().stringifyValue(
      this as VoiceSettings,
    );
  }

  @override
  bool operator ==(Object other) {
    return VoiceSettingsMapper.ensureInitialized().equalsValue(
      this as VoiceSettings,
      other,
    );
  }

  @override
  int get hashCode {
    return VoiceSettingsMapper.ensureInitialized().hashValue(
      this as VoiceSettings,
    );
  }
}

extension VoiceSettingsValueCopy<$R, $Out>
    on ObjectCopyWith<$R, VoiceSettings, $Out> {
  VoiceSettingsCopyWith<$R, VoiceSettings, $Out> get $asVoiceSettings =>
      $base.as((v, t, t2) => _VoiceSettingsCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class VoiceSettingsCopyWith<$R, $In extends VoiceSettings, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    String? homeAgentProfileId,
    VoicePipeline? pipeline,
    VoiceSttProvider? sttProvider,
    VoiceTtsProvider? ttsProvider,
    VoiceRealtimeProvider? realtimeProvider,
    String? ttsVoice,
    bool? ackWhileThinking,
  });
  VoiceSettingsCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _VoiceSettingsCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, VoiceSettings, $Out>
    implements VoiceSettingsCopyWith<$R, VoiceSettings, $Out> {
  _VoiceSettingsCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<VoiceSettings> $mapper =
      VoiceSettingsMapper.ensureInitialized();
  @override
  $R call({
    Object? homeAgentProfileId = $none,
    VoicePipeline? pipeline,
    VoiceSttProvider? sttProvider,
    VoiceTtsProvider? ttsProvider,
    VoiceRealtimeProvider? realtimeProvider,
    Object? ttsVoice = $none,
    bool? ackWhileThinking,
  }) => $apply(
    FieldCopyWithData({
      if (homeAgentProfileId != $none) #homeAgentProfileId: homeAgentProfileId,
      if (pipeline != null) #pipeline: pipeline,
      if (sttProvider != null) #sttProvider: sttProvider,
      if (ttsProvider != null) #ttsProvider: ttsProvider,
      if (realtimeProvider != null) #realtimeProvider: realtimeProvider,
      if (ttsVoice != $none) #ttsVoice: ttsVoice,
      if (ackWhileThinking != null) #ackWhileThinking: ackWhileThinking,
    }),
  );
  @override
  VoiceSettings $make(CopyWithData data) => VoiceSettings(
    homeAgentProfileId: data.get(
      #homeAgentProfileId,
      or: $value.homeAgentProfileId,
    ),
    pipeline: data.get(#pipeline, or: $value.pipeline),
    sttProvider: data.get(#sttProvider, or: $value.sttProvider),
    ttsProvider: data.get(#ttsProvider, or: $value.ttsProvider),
    realtimeProvider: data.get(#realtimeProvider, or: $value.realtimeProvider),
    ttsVoice: data.get(#ttsVoice, or: $value.ttsVoice),
    ackWhileThinking: data.get(#ackWhileThinking, or: $value.ackWhileThinking),
  );

  @override
  VoiceSettingsCopyWith<$R2, VoiceSettings, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _VoiceSettingsCopyWithImpl<$R2, $Out2>($value, $cast, t);
}
