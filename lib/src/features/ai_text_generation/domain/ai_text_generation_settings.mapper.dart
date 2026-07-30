// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'ai_text_generation_settings.dart';

class AiTextGenerationOperationMapper
    extends EnumMapper<AiTextGenerationOperation> {
  AiTextGenerationOperationMapper._();

  static AiTextGenerationOperationMapper? _instance;
  static AiTextGenerationOperationMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = AiTextGenerationOperationMapper._(),
      );
    }
    return _instance!;
  }

  static AiTextGenerationOperation fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  AiTextGenerationOperation decode(dynamic value) {
    switch (value) {
      case r'commitMessage':
        return AiTextGenerationOperation.commitMessage;
      case r'pullRequestDetails':
        return AiTextGenerationOperation.pullRequestDetails;
      case r'branchName':
        return AiTextGenerationOperation.branchName;
      case r'workspaceIdentity':
        return AiTextGenerationOperation.workspaceIdentity;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(AiTextGenerationOperation self) {
    switch (self) {
      case AiTextGenerationOperation.commitMessage:
        return r'commitMessage';
      case AiTextGenerationOperation.pullRequestDetails:
        return r'pullRequestDetails';
      case AiTextGenerationOperation.branchName:
        return r'branchName';
      case AiTextGenerationOperation.workspaceIdentity:
        return r'workspaceIdentity';
    }
  }
}

extension AiTextGenerationOperationMapperExtension
    on AiTextGenerationOperation {
  String toValue() {
    AiTextGenerationOperationMapper.ensureInitialized();
    return MapperContainer.globals.toValue<AiTextGenerationOperation>(this)
        as String;
  }
}

class AiTextGenerationAgentMapper extends EnumMapper<AiTextGenerationAgent> {
  AiTextGenerationAgentMapper._();

  static AiTextGenerationAgentMapper? _instance;
  static AiTextGenerationAgentMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = AiTextGenerationAgentMapper._());
    }
    return _instance!;
  }

  static AiTextGenerationAgent fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  AiTextGenerationAgent decode(dynamic value) {
    switch (value) {
      case r'codex':
        return AiTextGenerationAgent.codex;
      case r'claude':
        return AiTextGenerationAgent.claude;
      case r'copilot':
        return AiTextGenerationAgent.copilot;
      case r'cursor':
        return AiTextGenerationAgent.cursor;
      case r'agy':
        return AiTextGenerationAgent.agy;
      case r'opencode':
        return AiTextGenerationAgent.opencode;
      case r'pi':
        return AiTextGenerationAgent.pi;
      case r'amp':
        return AiTextGenerationAgent.amp;
      case r'grok':
        return AiTextGenerationAgent.grok;
      case r'custom':
        return AiTextGenerationAgent.custom;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(AiTextGenerationAgent self) {
    switch (self) {
      case AiTextGenerationAgent.codex:
        return r'codex';
      case AiTextGenerationAgent.claude:
        return r'claude';
      case AiTextGenerationAgent.copilot:
        return r'copilot';
      case AiTextGenerationAgent.cursor:
        return r'cursor';
      case AiTextGenerationAgent.agy:
        return r'agy';
      case AiTextGenerationAgent.opencode:
        return r'opencode';
      case AiTextGenerationAgent.pi:
        return r'pi';
      case AiTextGenerationAgent.amp:
        return r'amp';
      case AiTextGenerationAgent.grok:
        return r'grok';
      case AiTextGenerationAgent.custom:
        return r'custom';
    }
  }
}

extension AiTextGenerationAgentMapperExtension on AiTextGenerationAgent {
  String toValue() {
    AiTextGenerationAgentMapper.ensureInitialized();
    return MapperContainer.globals.toValue<AiTextGenerationAgent>(this)
        as String;
  }
}

class AiTextDiscoveredThinkingLevelMapper
    extends ClassMapperBase<AiTextDiscoveredThinkingLevel> {
  AiTextDiscoveredThinkingLevelMapper._();

  static AiTextDiscoveredThinkingLevelMapper? _instance;
  static AiTextDiscoveredThinkingLevelMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = AiTextDiscoveredThinkingLevelMapper._(),
      );
    }
    return _instance!;
  }

  @override
  final String id = 'AiTextDiscoveredThinkingLevel';

  static String _$id(AiTextDiscoveredThinkingLevel v) => v.id;
  static const Field<AiTextDiscoveredThinkingLevel, String> _f$id = Field(
    'id',
    _$id,
  );
  static String _$label(AiTextDiscoveredThinkingLevel v) => v.label;
  static const Field<AiTextDiscoveredThinkingLevel, String> _f$label = Field(
    'label',
    _$label,
  );

  @override
  final MappableFields<AiTextDiscoveredThinkingLevel> fields = const {
    #id: _f$id,
    #label: _f$label,
  };

  static AiTextDiscoveredThinkingLevel _instantiate(DecodingData data) {
    return AiTextDiscoveredThinkingLevel(
      id: data.dec(_f$id),
      label: data.dec(_f$label),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static AiTextDiscoveredThinkingLevel fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<AiTextDiscoveredThinkingLevel>(map);
  }

  static AiTextDiscoveredThinkingLevel fromJson(String json) {
    return ensureInitialized().decodeJson<AiTextDiscoveredThinkingLevel>(json);
  }
}

mixin AiTextDiscoveredThinkingLevelMappable {
  String toJson() {
    return AiTextDiscoveredThinkingLevelMapper.ensureInitialized()
        .encodeJson<AiTextDiscoveredThinkingLevel>(
          this as AiTextDiscoveredThinkingLevel,
        );
  }

  Map<String, dynamic> toMap() {
    return AiTextDiscoveredThinkingLevelMapper.ensureInitialized()
        .encodeMap<AiTextDiscoveredThinkingLevel>(
          this as AiTextDiscoveredThinkingLevel,
        );
  }

  AiTextDiscoveredThinkingLevelCopyWith<
    AiTextDiscoveredThinkingLevel,
    AiTextDiscoveredThinkingLevel,
    AiTextDiscoveredThinkingLevel
  >
  get copyWith =>
      _AiTextDiscoveredThinkingLevelCopyWithImpl<
        AiTextDiscoveredThinkingLevel,
        AiTextDiscoveredThinkingLevel
      >(this as AiTextDiscoveredThinkingLevel, $identity, $identity);
  @override
  String toString() {
    return AiTextDiscoveredThinkingLevelMapper.ensureInitialized()
        .stringifyValue(this as AiTextDiscoveredThinkingLevel);
  }

  @override
  bool operator ==(Object other) {
    return AiTextDiscoveredThinkingLevelMapper.ensureInitialized().equalsValue(
      this as AiTextDiscoveredThinkingLevel,
      other,
    );
  }

  @override
  int get hashCode {
    return AiTextDiscoveredThinkingLevelMapper.ensureInitialized().hashValue(
      this as AiTextDiscoveredThinkingLevel,
    );
  }
}

extension AiTextDiscoveredThinkingLevelValueCopy<$R, $Out>
    on ObjectCopyWith<$R, AiTextDiscoveredThinkingLevel, $Out> {
  AiTextDiscoveredThinkingLevelCopyWith<$R, AiTextDiscoveredThinkingLevel, $Out>
  get $asAiTextDiscoveredThinkingLevel => $base.as(
    (v, t, t2) =>
        _AiTextDiscoveredThinkingLevelCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class AiTextDiscoveredThinkingLevelCopyWith<
  $R,
  $In extends AiTextDiscoveredThinkingLevel,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({String? id, String? label});
  AiTextDiscoveredThinkingLevelCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _AiTextDiscoveredThinkingLevelCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, AiTextDiscoveredThinkingLevel, $Out>
    implements
        AiTextDiscoveredThinkingLevelCopyWith<
          $R,
          AiTextDiscoveredThinkingLevel,
          $Out
        > {
  _AiTextDiscoveredThinkingLevelCopyWithImpl(
    super.value,
    super.then,
    super.then2,
  );

  @override
  late final ClassMapperBase<AiTextDiscoveredThinkingLevel> $mapper =
      AiTextDiscoveredThinkingLevelMapper.ensureInitialized();
  @override
  $R call({String? id, String? label}) => $apply(
    FieldCopyWithData({
      if (id != null) #id: id,
      if (label != null) #label: label,
    }),
  );
  @override
  AiTextDiscoveredThinkingLevel $make(CopyWithData data) =>
      AiTextDiscoveredThinkingLevel(
        id: data.get(#id, or: $value.id),
        label: data.get(#label, or: $value.label),
      );

  @override
  AiTextDiscoveredThinkingLevelCopyWith<
    $R2,
    AiTextDiscoveredThinkingLevel,
    $Out2
  >
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _AiTextDiscoveredThinkingLevelCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class AiTextDiscoveredModelMapper
    extends ClassMapperBase<AiTextDiscoveredModel> {
  AiTextDiscoveredModelMapper._();

  static AiTextDiscoveredModelMapper? _instance;
  static AiTextDiscoveredModelMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = AiTextDiscoveredModelMapper._());
      AiTextDiscoveredThinkingLevelMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'AiTextDiscoveredModel';

  static String _$id(AiTextDiscoveredModel v) => v.id;
  static const Field<AiTextDiscoveredModel, String> _f$id = Field('id', _$id);
  static String _$label(AiTextDiscoveredModel v) => v.label;
  static const Field<AiTextDiscoveredModel, String> _f$label = Field(
    'label',
    _$label,
  );
  static List<AiTextDiscoveredThinkingLevel> _$thinkingLevels(
    AiTextDiscoveredModel v,
  ) => v.thinkingLevels;
  static const Field<AiTextDiscoveredModel, List<AiTextDiscoveredThinkingLevel>>
  _f$thinkingLevels = Field(
    'thinkingLevels',
    _$thinkingLevels,
    opt: true,
    def: const <AiTextDiscoveredThinkingLevel>[],
  );
  static String? _$defaultThinkingLevel(AiTextDiscoveredModel v) =>
      v.defaultThinkingLevel;
  static const Field<AiTextDiscoveredModel, String> _f$defaultThinkingLevel =
      Field('defaultThinkingLevel', _$defaultThinkingLevel, opt: true);

  @override
  final MappableFields<AiTextDiscoveredModel> fields = const {
    #id: _f$id,
    #label: _f$label,
    #thinkingLevels: _f$thinkingLevels,
    #defaultThinkingLevel: _f$defaultThinkingLevel,
  };

  static AiTextDiscoveredModel _instantiate(DecodingData data) {
    return AiTextDiscoveredModel(
      id: data.dec(_f$id),
      label: data.dec(_f$label),
      thinkingLevels: data.dec(_f$thinkingLevels),
      defaultThinkingLevel: data.dec(_f$defaultThinkingLevel),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static AiTextDiscoveredModel fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<AiTextDiscoveredModel>(map);
  }

  static AiTextDiscoveredModel fromJson(String json) {
    return ensureInitialized().decodeJson<AiTextDiscoveredModel>(json);
  }
}

mixin AiTextDiscoveredModelMappable {
  String toJson() {
    return AiTextDiscoveredModelMapper.ensureInitialized()
        .encodeJson<AiTextDiscoveredModel>(this as AiTextDiscoveredModel);
  }

  Map<String, dynamic> toMap() {
    return AiTextDiscoveredModelMapper.ensureInitialized()
        .encodeMap<AiTextDiscoveredModel>(this as AiTextDiscoveredModel);
  }

  AiTextDiscoveredModelCopyWith<
    AiTextDiscoveredModel,
    AiTextDiscoveredModel,
    AiTextDiscoveredModel
  >
  get copyWith =>
      _AiTextDiscoveredModelCopyWithImpl<
        AiTextDiscoveredModel,
        AiTextDiscoveredModel
      >(this as AiTextDiscoveredModel, $identity, $identity);
  @override
  String toString() {
    return AiTextDiscoveredModelMapper.ensureInitialized().stringifyValue(
      this as AiTextDiscoveredModel,
    );
  }

  @override
  bool operator ==(Object other) {
    return AiTextDiscoveredModelMapper.ensureInitialized().equalsValue(
      this as AiTextDiscoveredModel,
      other,
    );
  }

  @override
  int get hashCode {
    return AiTextDiscoveredModelMapper.ensureInitialized().hashValue(
      this as AiTextDiscoveredModel,
    );
  }
}

extension AiTextDiscoveredModelValueCopy<$R, $Out>
    on ObjectCopyWith<$R, AiTextDiscoveredModel, $Out> {
  AiTextDiscoveredModelCopyWith<$R, AiTextDiscoveredModel, $Out>
  get $asAiTextDiscoveredModel => $base.as(
    (v, t, t2) => _AiTextDiscoveredModelCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class AiTextDiscoveredModelCopyWith<
  $R,
  $In extends AiTextDiscoveredModel,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<
    $R,
    AiTextDiscoveredThinkingLevel,
    AiTextDiscoveredThinkingLevelCopyWith<
      $R,
      AiTextDiscoveredThinkingLevel,
      AiTextDiscoveredThinkingLevel
    >
  >
  get thinkingLevels;
  $R call({
    String? id,
    String? label,
    List<AiTextDiscoveredThinkingLevel>? thinkingLevels,
    String? defaultThinkingLevel,
  });
  AiTextDiscoveredModelCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _AiTextDiscoveredModelCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, AiTextDiscoveredModel, $Out>
    implements AiTextDiscoveredModelCopyWith<$R, AiTextDiscoveredModel, $Out> {
  _AiTextDiscoveredModelCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<AiTextDiscoveredModel> $mapper =
      AiTextDiscoveredModelMapper.ensureInitialized();
  @override
  ListCopyWith<
    $R,
    AiTextDiscoveredThinkingLevel,
    AiTextDiscoveredThinkingLevelCopyWith<
      $R,
      AiTextDiscoveredThinkingLevel,
      AiTextDiscoveredThinkingLevel
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
    List<AiTextDiscoveredThinkingLevel>? thinkingLevels,
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
  AiTextDiscoveredModel $make(CopyWithData data) => AiTextDiscoveredModel(
    id: data.get(#id, or: $value.id),
    label: data.get(#label, or: $value.label),
    thinkingLevels: data.get(#thinkingLevels, or: $value.thinkingLevels),
    defaultThinkingLevel: data.get(
      #defaultThinkingLevel,
      or: $value.defaultThinkingLevel,
    ),
  );

  @override
  AiTextDiscoveredModelCopyWith<$R2, AiTextDiscoveredModel, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _AiTextDiscoveredModelCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class AiTextGenerationSettingsMapper
    extends ClassMapperBase<AiTextGenerationSettings> {
  AiTextGenerationSettingsMapper._();

  static AiTextGenerationSettingsMapper? _instance;
  static AiTextGenerationSettingsMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = AiTextGenerationSettingsMapper._(),
      );
      AiTextGenerationAgentMapper.ensureInitialized();
      AiTextDiscoveredModelMapper.ensureInitialized();
      AiTextGenerationOperationMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'AiTextGenerationSettings';

  static bool _$enabled(AiTextGenerationSettings v) => v.enabled;
  static const Field<AiTextGenerationSettings, bool> _f$enabled = Field(
    'enabled',
    _$enabled,
    opt: true,
    def: true,
  );
  static AiTextGenerationAgent _$agent(AiTextGenerationSettings v) => v.agent;
  static const Field<AiTextGenerationSettings, AiTextGenerationAgent> _f$agent =
      Field('agent', _$agent, opt: true, def: AiTextGenerationAgent.codex);
  static Map<AiTextGenerationAgent, String> _$selectedModelByAgent(
    AiTextGenerationSettings v,
  ) => v.selectedModelByAgent;
  static const Field<
    AiTextGenerationSettings,
    Map<AiTextGenerationAgent, String>
  >
  _f$selectedModelByAgent = Field(
    'selectedModelByAgent',
    _$selectedModelByAgent,
    opt: true,
    def: const <AiTextGenerationAgent, String>{},
  );
  static Map<String, String> _$selectedThinkingByModel(
    AiTextGenerationSettings v,
  ) => v.selectedThinkingByModel;
  static const Field<AiTextGenerationSettings, Map<String, String>>
  _f$selectedThinkingByModel = Field(
    'selectedThinkingByModel',
    _$selectedThinkingByModel,
    opt: true,
    def: const <String, String>{},
  );
  static Map<AiTextGenerationAgent, List<AiTextDiscoveredModel>>
  _$discoveredModelsByAgent(AiTextGenerationSettings v) =>
      v.discoveredModelsByAgent;
  static const Field<
    AiTextGenerationSettings,
    Map<AiTextGenerationAgent, List<AiTextDiscoveredModel>>
  >
  _f$discoveredModelsByAgent = Field(
    'discoveredModelsByAgent',
    _$discoveredModelsByAgent,
    opt: true,
    def: const <AiTextGenerationAgent, List<AiTextDiscoveredModel>>{},
  );
  static Map<AiTextGenerationAgent, String> _$discoveredDefaultModelByAgent(
    AiTextGenerationSettings v,
  ) => v.discoveredDefaultModelByAgent;
  static const Field<
    AiTextGenerationSettings,
    Map<AiTextGenerationAgent, String>
  >
  _f$discoveredDefaultModelByAgent = Field(
    'discoveredDefaultModelByAgent',
    _$discoveredDefaultModelByAgent,
    opt: true,
    def: const <AiTextGenerationAgent, String>{},
  );
  static String _$customCommand(AiTextGenerationSettings v) => v.customCommand;
  static const Field<AiTextGenerationSettings, String> _f$customCommand = Field(
    'customCommand',
    _$customCommand,
    opt: true,
    def: '',
  );
  static Map<AiTextGenerationOperation, String> _$instructionsByOperation(
    AiTextGenerationSettings v,
  ) => v.instructionsByOperation;
  static const Field<
    AiTextGenerationSettings,
    Map<AiTextGenerationOperation, String>
  >
  _f$instructionsByOperation = Field(
    'instructionsByOperation',
    _$instructionsByOperation,
    opt: true,
    def: const <AiTextGenerationOperation, String>{},
  );
  static int _$timeoutSeconds(AiTextGenerationSettings v) => v.timeoutSeconds;
  static const Field<AiTextGenerationSettings, int> _f$timeoutSeconds = Field(
    'timeoutSeconds',
    _$timeoutSeconds,
    opt: true,
    def: 120,
  );

  @override
  final MappableFields<AiTextGenerationSettings> fields = const {
    #enabled: _f$enabled,
    #agent: _f$agent,
    #selectedModelByAgent: _f$selectedModelByAgent,
    #selectedThinkingByModel: _f$selectedThinkingByModel,
    #discoveredModelsByAgent: _f$discoveredModelsByAgent,
    #discoveredDefaultModelByAgent: _f$discoveredDefaultModelByAgent,
    #customCommand: _f$customCommand,
    #instructionsByOperation: _f$instructionsByOperation,
    #timeoutSeconds: _f$timeoutSeconds,
  };

  static AiTextGenerationSettings _instantiate(DecodingData data) {
    return AiTextGenerationSettings(
      enabled: data.dec(_f$enabled),
      agent: data.dec(_f$agent),
      selectedModelByAgent: data.dec(_f$selectedModelByAgent),
      selectedThinkingByModel: data.dec(_f$selectedThinkingByModel),
      discoveredModelsByAgent: data.dec(_f$discoveredModelsByAgent),
      discoveredDefaultModelByAgent: data.dec(_f$discoveredDefaultModelByAgent),
      customCommand: data.dec(_f$customCommand),
      instructionsByOperation: data.dec(_f$instructionsByOperation),
      timeoutSeconds: data.dec(_f$timeoutSeconds),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static AiTextGenerationSettings fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<AiTextGenerationSettings>(map);
  }

  static AiTextGenerationSettings fromJson(String json) {
    return ensureInitialized().decodeJson<AiTextGenerationSettings>(json);
  }
}

mixin AiTextGenerationSettingsMappable {
  String toJson() {
    return AiTextGenerationSettingsMapper.ensureInitialized()
        .encodeJson<AiTextGenerationSettings>(this as AiTextGenerationSettings);
  }

  Map<String, dynamic> toMap() {
    return AiTextGenerationSettingsMapper.ensureInitialized()
        .encodeMap<AiTextGenerationSettings>(this as AiTextGenerationSettings);
  }

  AiTextGenerationSettingsCopyWith<
    AiTextGenerationSettings,
    AiTextGenerationSettings,
    AiTextGenerationSettings
  >
  get copyWith =>
      _AiTextGenerationSettingsCopyWithImpl<
        AiTextGenerationSettings,
        AiTextGenerationSettings
      >(this as AiTextGenerationSettings, $identity, $identity);
  @override
  String toString() {
    return AiTextGenerationSettingsMapper.ensureInitialized().stringifyValue(
      this as AiTextGenerationSettings,
    );
  }

  @override
  bool operator ==(Object other) {
    return AiTextGenerationSettingsMapper.ensureInitialized().equalsValue(
      this as AiTextGenerationSettings,
      other,
    );
  }

  @override
  int get hashCode {
    return AiTextGenerationSettingsMapper.ensureInitialized().hashValue(
      this as AiTextGenerationSettings,
    );
  }
}

extension AiTextGenerationSettingsValueCopy<$R, $Out>
    on ObjectCopyWith<$R, AiTextGenerationSettings, $Out> {
  AiTextGenerationSettingsCopyWith<$R, AiTextGenerationSettings, $Out>
  get $asAiTextGenerationSettings => $base.as(
    (v, t, t2) => _AiTextGenerationSettingsCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class AiTextGenerationSettingsCopyWith<
  $R,
  $In extends AiTextGenerationSettings,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  MapCopyWith<
    $R,
    AiTextGenerationAgent,
    String,
    ObjectCopyWith<$R, String, String>
  >
  get selectedModelByAgent;
  MapCopyWith<$R, String, String, ObjectCopyWith<$R, String, String>>
  get selectedThinkingByModel;
  MapCopyWith<
    $R,
    AiTextGenerationAgent,
    List<AiTextDiscoveredModel>,
    ObjectCopyWith<$R, List<AiTextDiscoveredModel>, List<AiTextDiscoveredModel>>
  >
  get discoveredModelsByAgent;
  MapCopyWith<
    $R,
    AiTextGenerationAgent,
    String,
    ObjectCopyWith<$R, String, String>
  >
  get discoveredDefaultModelByAgent;
  MapCopyWith<
    $R,
    AiTextGenerationOperation,
    String,
    ObjectCopyWith<$R, String, String>
  >
  get instructionsByOperation;
  $R call({
    bool? enabled,
    AiTextGenerationAgent? agent,
    Map<AiTextGenerationAgent, String>? selectedModelByAgent,
    Map<String, String>? selectedThinkingByModel,
    Map<AiTextGenerationAgent, List<AiTextDiscoveredModel>>?
    discoveredModelsByAgent,
    Map<AiTextGenerationAgent, String>? discoveredDefaultModelByAgent,
    String? customCommand,
    Map<AiTextGenerationOperation, String>? instructionsByOperation,
    int? timeoutSeconds,
  });
  AiTextGenerationSettingsCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _AiTextGenerationSettingsCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, AiTextGenerationSettings, $Out>
    implements
        AiTextGenerationSettingsCopyWith<$R, AiTextGenerationSettings, $Out> {
  _AiTextGenerationSettingsCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<AiTextGenerationSettings> $mapper =
      AiTextGenerationSettingsMapper.ensureInitialized();
  @override
  MapCopyWith<
    $R,
    AiTextGenerationAgent,
    String,
    ObjectCopyWith<$R, String, String>
  >
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
    AiTextGenerationAgent,
    List<AiTextDiscoveredModel>,
    ObjectCopyWith<$R, List<AiTextDiscoveredModel>, List<AiTextDiscoveredModel>>
  >
  get discoveredModelsByAgent => MapCopyWith(
    $value.discoveredModelsByAgent,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(discoveredModelsByAgent: v),
  );
  @override
  MapCopyWith<
    $R,
    AiTextGenerationAgent,
    String,
    ObjectCopyWith<$R, String, String>
  >
  get discoveredDefaultModelByAgent => MapCopyWith(
    $value.discoveredDefaultModelByAgent,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(discoveredDefaultModelByAgent: v),
  );
  @override
  MapCopyWith<
    $R,
    AiTextGenerationOperation,
    String,
    ObjectCopyWith<$R, String, String>
  >
  get instructionsByOperation => MapCopyWith(
    $value.instructionsByOperation,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(instructionsByOperation: v),
  );
  @override
  $R call({
    bool? enabled,
    AiTextGenerationAgent? agent,
    Map<AiTextGenerationAgent, String>? selectedModelByAgent,
    Map<String, String>? selectedThinkingByModel,
    Map<AiTextGenerationAgent, List<AiTextDiscoveredModel>>?
    discoveredModelsByAgent,
    Map<AiTextGenerationAgent, String>? discoveredDefaultModelByAgent,
    String? customCommand,
    Map<AiTextGenerationOperation, String>? instructionsByOperation,
    int? timeoutSeconds,
  }) => $apply(
    FieldCopyWithData({
      if (enabled != null) #enabled: enabled,
      if (agent != null) #agent: agent,
      if (selectedModelByAgent != null)
        #selectedModelByAgent: selectedModelByAgent,
      if (selectedThinkingByModel != null)
        #selectedThinkingByModel: selectedThinkingByModel,
      if (discoveredModelsByAgent != null)
        #discoveredModelsByAgent: discoveredModelsByAgent,
      if (discoveredDefaultModelByAgent != null)
        #discoveredDefaultModelByAgent: discoveredDefaultModelByAgent,
      if (customCommand != null) #customCommand: customCommand,
      if (instructionsByOperation != null)
        #instructionsByOperation: instructionsByOperation,
      if (timeoutSeconds != null) #timeoutSeconds: timeoutSeconds,
    }),
  );
  @override
  AiTextGenerationSettings $make(CopyWithData data) => AiTextGenerationSettings(
    enabled: data.get(#enabled, or: $value.enabled),
    agent: data.get(#agent, or: $value.agent),
    selectedModelByAgent: data.get(
      #selectedModelByAgent,
      or: $value.selectedModelByAgent,
    ),
    selectedThinkingByModel: data.get(
      #selectedThinkingByModel,
      or: $value.selectedThinkingByModel,
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
    timeoutSeconds: data.get(#timeoutSeconds, or: $value.timeoutSeconds),
  );

  @override
  AiTextGenerationSettingsCopyWith<$R2, AiTextGenerationSettings, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _AiTextGenerationSettingsCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

