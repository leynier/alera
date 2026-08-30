// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'ai_assist_settings.dart';

class AiAssistOperationMapper extends EnumMapper<AiAssistOperation> {
  AiAssistOperationMapper._();

  static AiAssistOperationMapper? _instance;
  static AiAssistOperationMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = AiAssistOperationMapper._());
    }
    return _instance!;
  }

  static AiAssistOperation fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  AiAssistOperation decode(dynamic value) {
    switch (value) {
      case r'commitMessage':
        return AiAssistOperation.commitMessage;
      case r'pullRequestDetails':
        return AiAssistOperation.pullRequestDetails;
      case r'branchName':
        return AiAssistOperation.branchName;
      case r'readingDiff':
        return AiAssistOperation.readingDiff;
      case r'workspaceIdentity':
        return AiAssistOperation.workspaceIdentity;
      case r'agentTitle':
        return AiAssistOperation.agentTitle;
      case r'speechMessage':
        return AiAssistOperation.speechMessage;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(AiAssistOperation self) {
    switch (self) {
      case AiAssistOperation.commitMessage:
        return r'commitMessage';
      case AiAssistOperation.pullRequestDetails:
        return r'pullRequestDetails';
      case AiAssistOperation.branchName:
        return r'branchName';
      case AiAssistOperation.readingDiff:
        return r'readingDiff';
      case AiAssistOperation.workspaceIdentity:
        return r'workspaceIdentity';
      case AiAssistOperation.agentTitle:
        return r'agentTitle';
      case AiAssistOperation.speechMessage:
        return r'speechMessage';
    }
  }
}

extension AiAssistOperationMapperExtension on AiAssistOperation {
  String toValue() {
    AiAssistOperationMapper.ensureInitialized();
    return MapperContainer.globals.toValue<AiAssistOperation>(this) as String;
  }
}

class AiAssistAgentMapper extends EnumMapper<AiAssistAgent> {
  AiAssistAgentMapper._();

  static AiAssistAgentMapper? _instance;
  static AiAssistAgentMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = AiAssistAgentMapper._());
    }
    return _instance!;
  }

  static AiAssistAgent fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  AiAssistAgent decode(dynamic value) {
    switch (value) {
      case r'codex':
        return AiAssistAgent.codex;
      case r'claude':
        return AiAssistAgent.claude;
      case r'copilot':
        return AiAssistAgent.copilot;
      case r'cursor':
        return AiAssistAgent.cursor;
      case r'agy':
        return AiAssistAgent.agy;
      case r'opencode':
        return AiAssistAgent.opencode;
      case r'opencode2':
        return AiAssistAgent.opencode2;
      case r'pi':
        return AiAssistAgent.pi;
      case r'amp':
        return AiAssistAgent.amp;
      case r'grok':
        return AiAssistAgent.grok;
      case r'fx':
        return AiAssistAgent.fx;
      case r'custom':
        return AiAssistAgent.custom;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(AiAssistAgent self) {
    switch (self) {
      case AiAssistAgent.codex:
        return r'codex';
      case AiAssistAgent.claude:
        return r'claude';
      case AiAssistAgent.copilot:
        return r'copilot';
      case AiAssistAgent.cursor:
        return r'cursor';
      case AiAssistAgent.agy:
        return r'agy';
      case AiAssistAgent.opencode:
        return r'opencode';
      case AiAssistAgent.opencode2:
        return r'opencode2';
      case AiAssistAgent.pi:
        return r'pi';
      case AiAssistAgent.amp:
        return r'amp';
      case AiAssistAgent.grok:
        return r'grok';
      case AiAssistAgent.fx:
        return r'fx';
      case AiAssistAgent.custom:
        return r'custom';
    }
  }
}

extension AiAssistAgentMapperExtension on AiAssistAgent {
  String toValue() {
    AiAssistAgentMapper.ensureInitialized();
    return MapperContainer.globals.toValue<AiAssistAgent>(this) as String;
  }
}

class AiAssistDiscoveredThinkingLevelMapper
    extends ClassMapperBase<AiAssistDiscoveredThinkingLevel> {
  AiAssistDiscoveredThinkingLevelMapper._();

  static AiAssistDiscoveredThinkingLevelMapper? _instance;
  static AiAssistDiscoveredThinkingLevelMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = AiAssistDiscoveredThinkingLevelMapper._(),
      );
    }
    return _instance!;
  }

  @override
  final String id = 'AiAssistDiscoveredThinkingLevel';

  static String _$id(AiAssistDiscoveredThinkingLevel v) => v.id;
  static const Field<AiAssistDiscoveredThinkingLevel, String> _f$id = Field(
    'id',
    _$id,
  );
  static String _$label(AiAssistDiscoveredThinkingLevel v) => v.label;
  static const Field<AiAssistDiscoveredThinkingLevel, String> _f$label = Field(
    'label',
    _$label,
  );

  @override
  final MappableFields<AiAssistDiscoveredThinkingLevel> fields = const {
    #id: _f$id,
    #label: _f$label,
  };

  static AiAssistDiscoveredThinkingLevel _instantiate(DecodingData data) {
    return AiAssistDiscoveredThinkingLevel(
      id: data.dec(_f$id),
      label: data.dec(_f$label),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static AiAssistDiscoveredThinkingLevel fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<AiAssistDiscoveredThinkingLevel>(map);
  }

  static AiAssistDiscoveredThinkingLevel fromJson(String json) {
    return ensureInitialized().decodeJson<AiAssistDiscoveredThinkingLevel>(
      json,
    );
  }
}

mixin AiAssistDiscoveredThinkingLevelMappable {
  String toJson() {
    return AiAssistDiscoveredThinkingLevelMapper.ensureInitialized()
        .encodeJson<AiAssistDiscoveredThinkingLevel>(
          this as AiAssistDiscoveredThinkingLevel,
        );
  }

  Map<String, dynamic> toMap() {
    return AiAssistDiscoveredThinkingLevelMapper.ensureInitialized()
        .encodeMap<AiAssistDiscoveredThinkingLevel>(
          this as AiAssistDiscoveredThinkingLevel,
        );
  }

  AiAssistDiscoveredThinkingLevelCopyWith<
    AiAssistDiscoveredThinkingLevel,
    AiAssistDiscoveredThinkingLevel,
    AiAssistDiscoveredThinkingLevel
  >
  get copyWith =>
      _AiAssistDiscoveredThinkingLevelCopyWithImpl<
        AiAssistDiscoveredThinkingLevel,
        AiAssistDiscoveredThinkingLevel
      >(this as AiAssistDiscoveredThinkingLevel, $identity, $identity);
  @override
  String toString() {
    return AiAssistDiscoveredThinkingLevelMapper.ensureInitialized()
        .stringifyValue(this as AiAssistDiscoveredThinkingLevel);
  }

  @override
  bool operator ==(Object other) {
    return AiAssistDiscoveredThinkingLevelMapper.ensureInitialized()
        .equalsValue(this as AiAssistDiscoveredThinkingLevel, other);
  }

  @override
  int get hashCode {
    return AiAssistDiscoveredThinkingLevelMapper.ensureInitialized().hashValue(
      this as AiAssistDiscoveredThinkingLevel,
    );
  }
}

extension AiAssistDiscoveredThinkingLevelValueCopy<$R, $Out>
    on ObjectCopyWith<$R, AiAssistDiscoveredThinkingLevel, $Out> {
  AiAssistDiscoveredThinkingLevelCopyWith<
    $R,
    AiAssistDiscoveredThinkingLevel,
    $Out
  >
  get $asAiAssistDiscoveredThinkingLevel => $base.as(
    (v, t, t2) =>
        _AiAssistDiscoveredThinkingLevelCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class AiAssistDiscoveredThinkingLevelCopyWith<
  $R,
  $In extends AiAssistDiscoveredThinkingLevel,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({String? id, String? label});
  AiAssistDiscoveredThinkingLevelCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _AiAssistDiscoveredThinkingLevelCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, AiAssistDiscoveredThinkingLevel, $Out>
    implements
        AiAssistDiscoveredThinkingLevelCopyWith<
          $R,
          AiAssistDiscoveredThinkingLevel,
          $Out
        > {
  _AiAssistDiscoveredThinkingLevelCopyWithImpl(
    super.value,
    super.then,
    super.then2,
  );

  @override
  late final ClassMapperBase<AiAssistDiscoveredThinkingLevel> $mapper =
      AiAssistDiscoveredThinkingLevelMapper.ensureInitialized();
  @override
  $R call({String? id, String? label}) => $apply(
    FieldCopyWithData({
      if (id != null) #id: id,
      if (label != null) #label: label,
    }),
  );
  @override
  AiAssistDiscoveredThinkingLevel $make(CopyWithData data) =>
      AiAssistDiscoveredThinkingLevel(
        id: data.get(#id, or: $value.id),
        label: data.get(#label, or: $value.label),
      );

  @override
  AiAssistDiscoveredThinkingLevelCopyWith<
    $R2,
    AiAssistDiscoveredThinkingLevel,
    $Out2
  >
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _AiAssistDiscoveredThinkingLevelCopyWithImpl<$R2, $Out2>(
        $value,
        $cast,
        t,
      );
}

class AiAssistDiscoveredModelMapper
    extends ClassMapperBase<AiAssistDiscoveredModel> {
  AiAssistDiscoveredModelMapper._();

  static AiAssistDiscoveredModelMapper? _instance;
  static AiAssistDiscoveredModelMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = AiAssistDiscoveredModelMapper._(),
      );
      AiAssistDiscoveredThinkingLevelMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'AiAssistDiscoveredModel';

  static String _$id(AiAssistDiscoveredModel v) => v.id;
  static const Field<AiAssistDiscoveredModel, String> _f$id = Field('id', _$id);
  static String _$label(AiAssistDiscoveredModel v) => v.label;
  static const Field<AiAssistDiscoveredModel, String> _f$label = Field(
    'label',
    _$label,
  );
  static List<AiAssistDiscoveredThinkingLevel> _$thinkingLevels(
    AiAssistDiscoveredModel v,
  ) => v.thinkingLevels;
  static const Field<
    AiAssistDiscoveredModel,
    List<AiAssistDiscoveredThinkingLevel>
  >
  _f$thinkingLevels = Field(
    'thinkingLevels',
    _$thinkingLevels,
    opt: true,
    def: const <AiAssistDiscoveredThinkingLevel>[],
  );
  static String? _$defaultThinkingLevel(AiAssistDiscoveredModel v) =>
      v.defaultThinkingLevel;
  static const Field<AiAssistDiscoveredModel, String> _f$defaultThinkingLevel =
      Field('defaultThinkingLevel', _$defaultThinkingLevel, opt: true);

  @override
  final MappableFields<AiAssistDiscoveredModel> fields = const {
    #id: _f$id,
    #label: _f$label,
    #thinkingLevels: _f$thinkingLevels,
    #defaultThinkingLevel: _f$defaultThinkingLevel,
  };

  static AiAssistDiscoveredModel _instantiate(DecodingData data) {
    return AiAssistDiscoveredModel(
      id: data.dec(_f$id),
      label: data.dec(_f$label),
      thinkingLevels: data.dec(_f$thinkingLevels),
      defaultThinkingLevel: data.dec(_f$defaultThinkingLevel),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static AiAssistDiscoveredModel fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<AiAssistDiscoveredModel>(map);
  }

  static AiAssistDiscoveredModel fromJson(String json) {
    return ensureInitialized().decodeJson<AiAssistDiscoveredModel>(json);
  }
}

mixin AiAssistDiscoveredModelMappable {
  String toJson() {
    return AiAssistDiscoveredModelMapper.ensureInitialized()
        .encodeJson<AiAssistDiscoveredModel>(this as AiAssistDiscoveredModel);
  }

  Map<String, dynamic> toMap() {
    return AiAssistDiscoveredModelMapper.ensureInitialized()
        .encodeMap<AiAssistDiscoveredModel>(this as AiAssistDiscoveredModel);
  }

  AiAssistDiscoveredModelCopyWith<
    AiAssistDiscoveredModel,
    AiAssistDiscoveredModel,
    AiAssistDiscoveredModel
  >
  get copyWith =>
      _AiAssistDiscoveredModelCopyWithImpl<
        AiAssistDiscoveredModel,
        AiAssistDiscoveredModel
      >(this as AiAssistDiscoveredModel, $identity, $identity);
  @override
  String toString() {
    return AiAssistDiscoveredModelMapper.ensureInitialized().stringifyValue(
      this as AiAssistDiscoveredModel,
    );
  }

  @override
  bool operator ==(Object other) {
    return AiAssistDiscoveredModelMapper.ensureInitialized().equalsValue(
      this as AiAssistDiscoveredModel,
      other,
    );
  }

  @override
  int get hashCode {
    return AiAssistDiscoveredModelMapper.ensureInitialized().hashValue(
      this as AiAssistDiscoveredModel,
    );
  }
}

extension AiAssistDiscoveredModelValueCopy<$R, $Out>
    on ObjectCopyWith<$R, AiAssistDiscoveredModel, $Out> {
  AiAssistDiscoveredModelCopyWith<$R, AiAssistDiscoveredModel, $Out>
  get $asAiAssistDiscoveredModel => $base.as(
    (v, t, t2) => _AiAssistDiscoveredModelCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class AiAssistDiscoveredModelCopyWith<
  $R,
  $In extends AiAssistDiscoveredModel,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<
    $R,
    AiAssistDiscoveredThinkingLevel,
    AiAssistDiscoveredThinkingLevelCopyWith<
      $R,
      AiAssistDiscoveredThinkingLevel,
      AiAssistDiscoveredThinkingLevel
    >
  >
  get thinkingLevels;
  $R call({
    String? id,
    String? label,
    List<AiAssistDiscoveredThinkingLevel>? thinkingLevels,
    String? defaultThinkingLevel,
  });
  AiAssistDiscoveredModelCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _AiAssistDiscoveredModelCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, AiAssistDiscoveredModel, $Out>
    implements
        AiAssistDiscoveredModelCopyWith<$R, AiAssistDiscoveredModel, $Out> {
  _AiAssistDiscoveredModelCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<AiAssistDiscoveredModel> $mapper =
      AiAssistDiscoveredModelMapper.ensureInitialized();
  @override
  ListCopyWith<
    $R,
    AiAssistDiscoveredThinkingLevel,
    AiAssistDiscoveredThinkingLevelCopyWith<
      $R,
      AiAssistDiscoveredThinkingLevel,
      AiAssistDiscoveredThinkingLevel
    >
  >
  get thinkingLevels => ListCopyWith(
    $value.thinkingLevels,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(thinkingLevels: v),
  );
  @override
  $R call({
    String? id,
    String? label,
    List<AiAssistDiscoveredThinkingLevel>? thinkingLevels,
    Object? defaultThinkingLevel = $none,
  }) => $apply(
    FieldCopyWithData({
      if (id != null) #id: id,
      if (label != null) #label: label,
      if (thinkingLevels != null) #thinkingLevels: thinkingLevels,
      if (defaultThinkingLevel != $none)
        #defaultThinkingLevel: defaultThinkingLevel,
    }),
  );
  @override
  AiAssistDiscoveredModel $make(CopyWithData data) => AiAssistDiscoveredModel(
    id: data.get(#id, or: $value.id),
    label: data.get(#label, or: $value.label),
    thinkingLevels: data.get(#thinkingLevels, or: $value.thinkingLevels),
    defaultThinkingLevel: data.get(
      #defaultThinkingLevel,
      or: $value.defaultThinkingLevel,
    ),
  );

  @override
  AiAssistDiscoveredModelCopyWith<$R2, AiAssistDiscoveredModel, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _AiAssistDiscoveredModelCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class AiAssistPromptSettingsMapper
    extends ClassMapperBase<AiAssistPromptSettings> {
  AiAssistPromptSettingsMapper._();

  static AiAssistPromptSettingsMapper? _instance;
  static AiAssistPromptSettingsMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = AiAssistPromptSettingsMapper._());
      AiAssistAgentMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'AiAssistPromptSettings';

  static AiAssistAgent? _$agent(AiAssistPromptSettings v) => v.agent;
  static const Field<AiAssistPromptSettings, AiAssistAgent> _f$agent = Field(
    'agent',
    _$agent,
    opt: true,
  );
  static String? _$model(AiAssistPromptSettings v) => v.model;
  static const Field<AiAssistPromptSettings, String> _f$model = Field(
    'model',
    _$model,
    opt: true,
  );

  @override
  final MappableFields<AiAssistPromptSettings> fields = const {
    #agent: _f$agent,
    #model: _f$model,
  };

  static AiAssistPromptSettings _instantiate(DecodingData data) {
    return AiAssistPromptSettings(
      agent: data.dec(_f$agent),
      model: data.dec(_f$model),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static AiAssistPromptSettings fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<AiAssistPromptSettings>(map);
  }

  static AiAssistPromptSettings fromJson(String json) {
    return ensureInitialized().decodeJson<AiAssistPromptSettings>(json);
  }
}

mixin AiAssistPromptSettingsMappable {
  String toJson() {
    return AiAssistPromptSettingsMapper.ensureInitialized()
        .encodeJson<AiAssistPromptSettings>(this as AiAssistPromptSettings);
  }

  Map<String, dynamic> toMap() {
    return AiAssistPromptSettingsMapper.ensureInitialized()
        .encodeMap<AiAssistPromptSettings>(this as AiAssistPromptSettings);
  }

  AiAssistPromptSettingsCopyWith<
    AiAssistPromptSettings,
    AiAssistPromptSettings,
    AiAssistPromptSettings
  >
  get copyWith =>
      _AiAssistPromptSettingsCopyWithImpl<
        AiAssistPromptSettings,
        AiAssistPromptSettings
      >(this as AiAssistPromptSettings, $identity, $identity);
  @override
  String toString() {
    return AiAssistPromptSettingsMapper.ensureInitialized().stringifyValue(
      this as AiAssistPromptSettings,
    );
  }

  @override
  bool operator ==(Object other) {
    return AiAssistPromptSettingsMapper.ensureInitialized().equalsValue(
      this as AiAssistPromptSettings,
      other,
    );
  }

  @override
  int get hashCode {
    return AiAssistPromptSettingsMapper.ensureInitialized().hashValue(
      this as AiAssistPromptSettings,
    );
  }
}

extension AiAssistPromptSettingsValueCopy<$R, $Out>
    on ObjectCopyWith<$R, AiAssistPromptSettings, $Out> {
  AiAssistPromptSettingsCopyWith<$R, AiAssistPromptSettings, $Out>
  get $asAiAssistPromptSettings => $base.as(
    (v, t, t2) => _AiAssistPromptSettingsCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class AiAssistPromptSettingsCopyWith<
  $R,
  $In extends AiAssistPromptSettings,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({AiAssistAgent? agent, String? model});
  AiAssistPromptSettingsCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _AiAssistPromptSettingsCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, AiAssistPromptSettings, $Out>
    implements
        AiAssistPromptSettingsCopyWith<$R, AiAssistPromptSettings, $Out> {
  _AiAssistPromptSettingsCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<AiAssistPromptSettings> $mapper =
      AiAssistPromptSettingsMapper.ensureInitialized();
  @override
  $R call({Object? agent = $none, Object? model = $none}) => $apply(
    FieldCopyWithData({
      if (agent != $none) #agent: agent,
      if (model != $none) #model: model,
    }),
  );
  @override
  AiAssistPromptSettings $make(CopyWithData data) => AiAssistPromptSettings(
    agent: data.get(#agent, or: $value.agent),
    model: data.get(#model, or: $value.model),
  );

  @override
  AiAssistPromptSettingsCopyWith<$R2, AiAssistPromptSettings, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _AiAssistPromptSettingsCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class AiAssistSettingsMapper extends ClassMapperBase<AiAssistSettings> {
  AiAssistSettingsMapper._();

  static AiAssistSettingsMapper? _instance;
  static AiAssistSettingsMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = AiAssistSettingsMapper._());
      AiAssistAgentMapper.ensureInitialized();
      AiAssistOperationMapper.ensureInitialized();
      AiAssistDiscoveredModelMapper.ensureInitialized();
      AiAssistPromptSettingsMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'AiAssistSettings';

  static bool _$enabled(AiAssistSettings v) => v.enabled;
  static const Field<AiAssistSettings, bool> _f$enabled = Field(
    'enabled',
    _$enabled,
    opt: true,
    def: true,
  );
  static bool _$autoGenerateAgentTitles(AiAssistSettings v) =>
      v.autoGenerateAgentTitles;
  static const Field<AiAssistSettings, bool> _f$autoGenerateAgentTitles = Field(
    'autoGenerateAgentTitles',
    _$autoGenerateAgentTitles,
    opt: true,
    def: true,
  );
  static AiAssistAgent _$agent(AiAssistSettings v) => v.agent;
  static const Field<AiAssistSettings, AiAssistAgent> _f$agent = Field(
    'agent',
    _$agent,
    opt: true,
    def: AiAssistAgent.codex,
  );
  static Map<AiAssistAgent, String> _$selectedModelByAgent(
    AiAssistSettings v,
  ) => v.selectedModelByAgent;
  static const Field<AiAssistSettings, Map<AiAssistAgent, String>>
  _f$selectedModelByAgent = Field(
    'selectedModelByAgent',
    _$selectedModelByAgent,
    opt: true,
    def: const <AiAssistAgent, String>{},
  );
  static Map<String, String> _$selectedThinkingByModel(AiAssistSettings v) =>
      v.selectedThinkingByModel;
  static const Field<AiAssistSettings, Map<String, String>>
  _f$selectedThinkingByModel = Field(
    'selectedThinkingByModel',
    _$selectedThinkingByModel,
    opt: true,
    def: const <String, String>{},
  );
  static Map<AiAssistOperation, Map<String, String>>
  _$selectedThinkingByOperation(AiAssistSettings v) =>
      v.selectedThinkingByOperation;
  static const Field<
    AiAssistSettings,
    Map<AiAssistOperation, Map<String, String>>
  >
  _f$selectedThinkingByOperation = Field(
    'selectedThinkingByOperation',
    _$selectedThinkingByOperation,
    opt: true,
    def: const <AiAssistOperation, Map<String, String>>{},
  );
  static Map<AiAssistAgent, List<AiAssistDiscoveredModel>>
  _$discoveredModelsByAgent(AiAssistSettings v) => v.discoveredModelsByAgent;
  static const Field<
    AiAssistSettings,
    Map<AiAssistAgent, List<AiAssistDiscoveredModel>>
  >
  _f$discoveredModelsByAgent = Field(
    'discoveredModelsByAgent',
    _$discoveredModelsByAgent,
    opt: true,
    def: const <AiAssistAgent, List<AiAssistDiscoveredModel>>{},
  );
  static Map<AiAssistAgent, String> _$discoveredDefaultModelByAgent(
    AiAssistSettings v,
  ) => v.discoveredDefaultModelByAgent;
  static const Field<AiAssistSettings, Map<AiAssistAgent, String>>
  _f$discoveredDefaultModelByAgent = Field(
    'discoveredDefaultModelByAgent',
    _$discoveredDefaultModelByAgent,
    opt: true,
    def: const <AiAssistAgent, String>{},
  );
  static String _$customCommand(AiAssistSettings v) => v.customCommand;
  static const Field<AiAssistSettings, String> _f$customCommand = Field(
    'customCommand',
    _$customCommand,
    opt: true,
    def: '',
  );
  static Map<AiAssistOperation, String> _$instructionsByOperation(
    AiAssistSettings v,
  ) => v.instructionsByOperation;
  static const Field<AiAssistSettings, Map<AiAssistOperation, String>>
  _f$instructionsByOperation = Field(
    'instructionsByOperation',
    _$instructionsByOperation,
    opt: true,
    def: const <AiAssistOperation, String>{},
  );
  static Map<AiAssistOperation, AiAssistPromptSettings>
  _$promptSettingsByOperation(AiAssistSettings v) =>
      v.promptSettingsByOperation;
  static const Field<
    AiAssistSettings,
    Map<AiAssistOperation, AiAssistPromptSettings>
  >
  _f$promptSettingsByOperation = Field(
    'promptSettingsByOperation',
    _$promptSettingsByOperation,
    opt: true,
    def: const <AiAssistOperation, AiAssistPromptSettings>{},
  );
  static int _$timeoutSeconds(AiAssistSettings v) => v.timeoutSeconds;
  static const Field<AiAssistSettings, int> _f$timeoutSeconds = Field(
    'timeoutSeconds',
    _$timeoutSeconds,
    opt: true,
    def: 120,
  );

  @override
  final MappableFields<AiAssistSettings> fields = const {
    #enabled: _f$enabled,
    #autoGenerateAgentTitles: _f$autoGenerateAgentTitles,
    #agent: _f$agent,
    #selectedModelByAgent: _f$selectedModelByAgent,
    #selectedThinkingByModel: _f$selectedThinkingByModel,
    #selectedThinkingByOperation: _f$selectedThinkingByOperation,
    #discoveredModelsByAgent: _f$discoveredModelsByAgent,
    #discoveredDefaultModelByAgent: _f$discoveredDefaultModelByAgent,
    #customCommand: _f$customCommand,
    #instructionsByOperation: _f$instructionsByOperation,
    #promptSettingsByOperation: _f$promptSettingsByOperation,
    #timeoutSeconds: _f$timeoutSeconds,
  };

  static AiAssistSettings _instantiate(DecodingData data) {
    return AiAssistSettings(
      enabled: data.dec(_f$enabled),
      autoGenerateAgentTitles: data.dec(_f$autoGenerateAgentTitles),
      agent: data.dec(_f$agent),
      selectedModelByAgent: data.dec(_f$selectedModelByAgent),
      selectedThinkingByModel: data.dec(_f$selectedThinkingByModel),
      selectedThinkingByOperation: data.dec(_f$selectedThinkingByOperation),
      discoveredModelsByAgent: data.dec(_f$discoveredModelsByAgent),
      discoveredDefaultModelByAgent: data.dec(_f$discoveredDefaultModelByAgent),
      customCommand: data.dec(_f$customCommand),
      instructionsByOperation: data.dec(_f$instructionsByOperation),
      promptSettingsByOperation: data.dec(_f$promptSettingsByOperation),
      timeoutSeconds: data.dec(_f$timeoutSeconds),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static AiAssistSettings fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<AiAssistSettings>(map);
  }

  static AiAssistSettings fromJson(String json) {
    return ensureInitialized().decodeJson<AiAssistSettings>(json);
  }
}

mixin AiAssistSettingsMappable {
  String toJson() {
    return AiAssistSettingsMapper.ensureInitialized()
        .encodeJson<AiAssistSettings>(this as AiAssistSettings);
  }

  Map<String, dynamic> toMap() {
    return AiAssistSettingsMapper.ensureInitialized()
        .encodeMap<AiAssistSettings>(this as AiAssistSettings);
  }

  AiAssistSettingsCopyWith<AiAssistSettings, AiAssistSettings, AiAssistSettings>
  get copyWith =>
      _AiAssistSettingsCopyWithImpl<AiAssistSettings, AiAssistSettings>(
        this as AiAssistSettings,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return AiAssistSettingsMapper.ensureInitialized().stringifyValue(
      this as AiAssistSettings,
    );
  }

  @override
  bool operator ==(Object other) {
    return AiAssistSettingsMapper.ensureInitialized().equalsValue(
      this as AiAssistSettings,
      other,
    );
  }

  @override
  int get hashCode {
    return AiAssistSettingsMapper.ensureInitialized().hashValue(
      this as AiAssistSettings,
    );
  }
}

extension AiAssistSettingsValueCopy<$R, $Out>
    on ObjectCopyWith<$R, AiAssistSettings, $Out> {
  AiAssistSettingsCopyWith<$R, AiAssistSettings, $Out>
  get $asAiAssistSettings =>
      $base.as((v, t, t2) => _AiAssistSettingsCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class AiAssistSettingsCopyWith<$R, $In extends AiAssistSettings, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  MapCopyWith<$R, AiAssistAgent, String, ObjectCopyWith<$R, String, String>>
  get selectedModelByAgent;
  MapCopyWith<$R, String, String, ObjectCopyWith<$R, String, String>>
  get selectedThinkingByModel;
  MapCopyWith<
    $R,
    AiAssistOperation,
    Map<String, String>,
    ObjectCopyWith<$R, Map<String, String>, Map<String, String>>
  >
  get selectedThinkingByOperation;
  MapCopyWith<
    $R,
    AiAssistAgent,
    List<AiAssistDiscoveredModel>,
    ObjectCopyWith<
      $R,
      List<AiAssistDiscoveredModel>,
      List<AiAssistDiscoveredModel>
    >
  >
  get discoveredModelsByAgent;
  MapCopyWith<$R, AiAssistAgent, String, ObjectCopyWith<$R, String, String>>
  get discoveredDefaultModelByAgent;
  MapCopyWith<$R, AiAssistOperation, String, ObjectCopyWith<$R, String, String>>
  get instructionsByOperation;
  MapCopyWith<
    $R,
    AiAssistOperation,
    AiAssistPromptSettings,
    AiAssistPromptSettingsCopyWith<
      $R,
      AiAssistPromptSettings,
      AiAssistPromptSettings
    >
  >
  get promptSettingsByOperation;
  $R call({
    bool? enabled,
    bool? autoGenerateAgentTitles,
    AiAssistAgent? agent,
    Map<AiAssistAgent, String>? selectedModelByAgent,
    Map<String, String>? selectedThinkingByModel,
    Map<AiAssistOperation, Map<String, String>>? selectedThinkingByOperation,
    Map<AiAssistAgent, List<AiAssistDiscoveredModel>>? discoveredModelsByAgent,
    Map<AiAssistAgent, String>? discoveredDefaultModelByAgent,
    String? customCommand,
    Map<AiAssistOperation, String>? instructionsByOperation,
    Map<AiAssistOperation, AiAssistPromptSettings>? promptSettingsByOperation,
    int? timeoutSeconds,
  });
  AiAssistSettingsCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _AiAssistSettingsCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, AiAssistSettings, $Out>
    implements AiAssistSettingsCopyWith<$R, AiAssistSettings, $Out> {
  _AiAssistSettingsCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<AiAssistSettings> $mapper =
      AiAssistSettingsMapper.ensureInitialized();
  @override
  MapCopyWith<$R, AiAssistAgent, String, ObjectCopyWith<$R, String, String>>
  get selectedModelByAgent => MapCopyWith(
    $value.selectedModelByAgent,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(selectedModelByAgent: v),
  );
  @override
  MapCopyWith<$R, String, String, ObjectCopyWith<$R, String, String>>
  get selectedThinkingByModel => MapCopyWith(
    $value.selectedThinkingByModel,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(selectedThinkingByModel: v),
  );
  @override
  MapCopyWith<
    $R,
    AiAssistOperation,
    Map<String, String>,
    ObjectCopyWith<$R, Map<String, String>, Map<String, String>>
  >
  get selectedThinkingByOperation => MapCopyWith(
    $value.selectedThinkingByOperation,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(selectedThinkingByOperation: v),
  );
  @override
  MapCopyWith<
    $R,
    AiAssistAgent,
    List<AiAssistDiscoveredModel>,
    ObjectCopyWith<
      $R,
      List<AiAssistDiscoveredModel>,
      List<AiAssistDiscoveredModel>
    >
  >
  get discoveredModelsByAgent => MapCopyWith(
    $value.discoveredModelsByAgent,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(discoveredModelsByAgent: v),
  );
  @override
  MapCopyWith<$R, AiAssistAgent, String, ObjectCopyWith<$R, String, String>>
  get discoveredDefaultModelByAgent => MapCopyWith(
    $value.discoveredDefaultModelByAgent,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(discoveredDefaultModelByAgent: v),
  );
  @override
  MapCopyWith<$R, AiAssistOperation, String, ObjectCopyWith<$R, String, String>>
  get instructionsByOperation => MapCopyWith(
    $value.instructionsByOperation,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(instructionsByOperation: v),
  );
  @override
  MapCopyWith<
    $R,
    AiAssistOperation,
    AiAssistPromptSettings,
    AiAssistPromptSettingsCopyWith<
      $R,
      AiAssistPromptSettings,
      AiAssistPromptSettings
    >
  >
  get promptSettingsByOperation => MapCopyWith(
    $value.promptSettingsByOperation,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(promptSettingsByOperation: v),
  );
  @override
  $R call({
    bool? enabled,
    bool? autoGenerateAgentTitles,
    AiAssistAgent? agent,
    Map<AiAssistAgent, String>? selectedModelByAgent,
    Map<String, String>? selectedThinkingByModel,
    Map<AiAssistOperation, Map<String, String>>? selectedThinkingByOperation,
    Map<AiAssistAgent, List<AiAssistDiscoveredModel>>? discoveredModelsByAgent,
    Map<AiAssistAgent, String>? discoveredDefaultModelByAgent,
    String? customCommand,
    Map<AiAssistOperation, String>? instructionsByOperation,
    Map<AiAssistOperation, AiAssistPromptSettings>? promptSettingsByOperation,
    int? timeoutSeconds,
  }) => $apply(
    FieldCopyWithData({
      if (enabled != null) #enabled: enabled,
      if (autoGenerateAgentTitles != null)
        #autoGenerateAgentTitles: autoGenerateAgentTitles,
      if (agent != null) #agent: agent,
      if (selectedModelByAgent != null)
        #selectedModelByAgent: selectedModelByAgent,
      if (selectedThinkingByModel != null)
        #selectedThinkingByModel: selectedThinkingByModel,
      if (selectedThinkingByOperation != null)
        #selectedThinkingByOperation: selectedThinkingByOperation,
      if (discoveredModelsByAgent != null)
        #discoveredModelsByAgent: discoveredModelsByAgent,
      if (discoveredDefaultModelByAgent != null)
        #discoveredDefaultModelByAgent: discoveredDefaultModelByAgent,
      if (customCommand != null) #customCommand: customCommand,
      if (instructionsByOperation != null)
        #instructionsByOperation: instructionsByOperation,
      if (promptSettingsByOperation != null)
        #promptSettingsByOperation: promptSettingsByOperation,
      if (timeoutSeconds != null) #timeoutSeconds: timeoutSeconds,
    }),
  );
  @override
  AiAssistSettings $make(CopyWithData data) => AiAssistSettings(
    enabled: data.get(#enabled, or: $value.enabled),
    autoGenerateAgentTitles: data.get(
      #autoGenerateAgentTitles,
      or: $value.autoGenerateAgentTitles,
    ),
    agent: data.get(#agent, or: $value.agent),
    selectedModelByAgent: data.get(
      #selectedModelByAgent,
      or: $value.selectedModelByAgent,
    ),
    selectedThinkingByModel: data.get(
      #selectedThinkingByModel,
      or: $value.selectedThinkingByModel,
    ),
    selectedThinkingByOperation: data.get(
      #selectedThinkingByOperation,
      or: $value.selectedThinkingByOperation,
    ),
    discoveredModelsByAgent: data.get(
      #discoveredModelsByAgent,
      or: $value.discoveredModelsByAgent,
    ),
    discoveredDefaultModelByAgent: data.get(
      #discoveredDefaultModelByAgent,
      or: $value.discoveredDefaultModelByAgent,
    ),
    customCommand: data.get(#customCommand, or: $value.customCommand),
    instructionsByOperation: data.get(
      #instructionsByOperation,
      or: $value.instructionsByOperation,
    ),
    promptSettingsByOperation: data.get(
      #promptSettingsByOperation,
      or: $value.promptSettingsByOperation,
    ),
    timeoutSeconds: data.get(#timeoutSeconds, or: $value.timeoutSeconds),
  );

  @override
  AiAssistSettingsCopyWith<$R2, AiAssistSettings, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _AiAssistSettingsCopyWithImpl<$R2, $Out2>($value, $cast, t);
}
