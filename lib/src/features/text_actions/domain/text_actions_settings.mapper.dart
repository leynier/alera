// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'text_actions_settings.dart';

class TextActionMapper extends ClassMapperBase<TextAction> {
  TextActionMapper._();

  static TextActionMapper? _instance;
  static TextActionMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = TextActionMapper._());
      AiTextGenerationAgentMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'TextAction';

  static String _$id(TextAction v) => v.id;
  static const Field<TextAction, String> _f$id = Field('id', _$id);
  static String _$name(TextAction v) => v.name;
  static const Field<TextAction, String> _f$name = Field('name', _$name);
  static String _$prompt(TextAction v) => v.prompt;
  static const Field<TextAction, String> _f$prompt = Field('prompt', _$prompt);
  static bool _$enabled(TextAction v) => v.enabled;
  static const Field<TextAction, bool> _f$enabled = Field(
    'enabled',
    _$enabled,
    opt: true,
    def: true,
  );
  static AiTextGenerationAgent? _$agentOverride(TextAction v) =>
      v.agentOverride;
  static const Field<TextAction, AiTextGenerationAgent> _f$agentOverride =
      Field('agentOverride', _$agentOverride, opt: true);
  static String? _$modelOverride(TextAction v) => v.modelOverride;
  static const Field<TextAction, String> _f$modelOverride = Field(
    'modelOverride',
    _$modelOverride,
    opt: true,
  );
  static Map<String, String> _$reasoningByModel(TextAction v) =>
      v.reasoningByModel;
  static const Field<TextAction, Map<String, String>> _f$reasoningByModel =
      Field(
        'reasoningByModel',
        _$reasoningByModel,
        opt: true,
        def: const <String, String>{},
      );

  @override
  final MappableFields<TextAction> fields = const {
    #id: _f$id,
    #name: _f$name,
    #prompt: _f$prompt,
    #enabled: _f$enabled,
    #agentOverride: _f$agentOverride,
    #modelOverride: _f$modelOverride,
    #reasoningByModel: _f$reasoningByModel,
  };

  static TextAction _instantiate(DecodingData data) {
    return TextAction(
      id: data.dec(_f$id),
      name: data.dec(_f$name),
      prompt: data.dec(_f$prompt),
      enabled: data.dec(_f$enabled),
      agentOverride: data.dec(_f$agentOverride),
      modelOverride: data.dec(_f$modelOverride),
      reasoningByModel: data.dec(_f$reasoningByModel),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static TextAction fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<TextAction>(map);
  }

  static TextAction fromJson(String json) {
    return ensureInitialized().decodeJson<TextAction>(json);
  }
}
mixin TextActionMappable {
  String toJson() {
    return TextActionMapper.ensureInitialized().encodeJson<TextAction>(
      this as TextAction,
    );
  }

  Map<String, dynamic> toMap() {
    return TextActionMapper.ensureInitialized().encodeMap<TextAction>(
      this as TextAction,
    );
  }

  TextActionCopyWith<TextAction, TextAction, TextAction> get copyWith =>
      _TextActionCopyWithImpl<TextAction, TextAction>(
        this as TextAction,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return TextActionMapper.ensureInitialized().stringifyValue(
      this as TextAction,
    );
  }

  @override
  bool operator ==(Object other) {
    return TextActionMapper.ensureInitialized().equalsValue(
      this as TextAction,
      other,
    );
  }

  @override
  int get hashCode {
    return TextActionMapper.ensureInitialized().hashValue(this as TextAction);
  }
}

extension TextActionValueCopy<$R, $Out>
    on ObjectCopyWith<$R, TextAction, $Out> {
  TextActionCopyWith<$R, TextAction, $Out> get $asTextAction =>
      $base.as((v, t, t2) => _TextActionCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class TextActionCopyWith<$R, $In extends TextAction, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  MapCopyWith<$R, String, String, ObjectCopyWith<$R, String, String>>
  get reasoningByModel;
  $R call({
    String? id,
    String? name,
    String? prompt,
    bool? enabled,
    AiTextGenerationAgent? agentOverride,
    String? modelOverride,
    Map<String, String>? reasoningByModel,
  });
  TextActionCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _TextActionCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, TextAction, $Out>
    implements TextActionCopyWith<$R, TextAction, $Out> {
  _TextActionCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<TextAction> $mapper =
      TextActionMapper.ensureInitialized();
  @override
  MapCopyWith<$R, String, String, ObjectCopyWith<$R, String, String>>
  get reasoningByModel => MapCopyWith(
    $value.reasoningByModel,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(reasoningByModel: v),
  );
  @override
  $R call({
    String? id,
    String? name,
    String? prompt,
    bool? enabled,
    Object? agentOverride = $none,
    Object? modelOverride = $none,
    Map<String, String>? reasoningByModel,
  }) => $apply(
    FieldCopyWithData({
      if (id != null) #id: id,
      if (name != null) #name: name,
      if (prompt != null) #prompt: prompt,
      if (enabled != null) #enabled: enabled,
      if (agentOverride != $none) #agentOverride: agentOverride,
      if (modelOverride != $none) #modelOverride: modelOverride,
      if (reasoningByModel != null) #reasoningByModel: reasoningByModel,
    }),
  );
  @override
  TextAction $make(CopyWithData data) => TextAction(
    id: data.get(#id, or: $value.id),
    name: data.get(#name, or: $value.name),
    prompt: data.get(#prompt, or: $value.prompt),
    enabled: data.get(#enabled, or: $value.enabled),
    agentOverride: data.get(#agentOverride, or: $value.agentOverride),
    modelOverride: data.get(#modelOverride, or: $value.modelOverride),
    reasoningByModel: data.get(#reasoningByModel, or: $value.reasoningByModel),
  );

  @override
  TextActionCopyWith<$R2, TextAction, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _TextActionCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class TextActionsSettingsMapper extends ClassMapperBase<TextActionsSettings> {
  TextActionsSettingsMapper._();

  static TextActionsSettingsMapper? _instance;
  static TextActionsSettingsMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = TextActionsSettingsMapper._());
      TextActionMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'TextActionsSettings';

  static List<TextAction> _$actions(TextActionsSettings v) => v.actions;
  static const Field<TextActionsSettings, List<TextAction>> _f$actions = Field(
    'actions',
    _$actions,
    opt: true,
    def: const <TextAction>[],
  );

  @override
  final MappableFields<TextActionsSettings> fields = const {
    #actions: _f$actions,
  };

  static TextActionsSettings _instantiate(DecodingData data) {
    return TextActionsSettings(actions: data.dec(_f$actions));
  }

  @override
  final Function instantiate = _instantiate;

  static TextActionsSettings fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<TextActionsSettings>(map);
  }

  static TextActionsSettings fromJson(String json) {
    return ensureInitialized().decodeJson<TextActionsSettings>(json);
  }
}

mixin TextActionsSettingsMappable {
  String toJson() {
    return TextActionsSettingsMapper.ensureInitialized()
        .encodeJson<TextActionsSettings>(this as TextActionsSettings);
  }

  Map<String, dynamic> toMap() {
    return TextActionsSettingsMapper.ensureInitialized()
        .encodeMap<TextActionsSettings>(this as TextActionsSettings);
  }

  TextActionsSettingsCopyWith<
    TextActionsSettings,
    TextActionsSettings,
    TextActionsSettings
  >
  get copyWith =>
      _TextActionsSettingsCopyWithImpl<
        TextActionsSettings,
        TextActionsSettings
      >(this as TextActionsSettings, $identity, $identity);
  @override
  String toString() {
    return TextActionsSettingsMapper.ensureInitialized().stringifyValue(
      this as TextActionsSettings,
    );
  }

  @override
  bool operator ==(Object other) {
    return TextActionsSettingsMapper.ensureInitialized().equalsValue(
      this as TextActionsSettings,
      other,
    );
  }

  @override
  int get hashCode {
    return TextActionsSettingsMapper.ensureInitialized().hashValue(
      this as TextActionsSettings,
    );
  }
}

extension TextActionsSettingsValueCopy<$R, $Out>
    on ObjectCopyWith<$R, TextActionsSettings, $Out> {
  TextActionsSettingsCopyWith<$R, TextActionsSettings, $Out>
  get $asTextActionsSettings => $base.as(
    (v, t, t2) => _TextActionsSettingsCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class TextActionsSettingsCopyWith<
  $R,
  $In extends TextActionsSettings,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, TextAction, TextActionCopyWith<$R, TextAction, TextAction>>
  get actions;
  $R call({List<TextAction>? actions});
  TextActionsSettingsCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _TextActionsSettingsCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, TextActionsSettings, $Out>
    implements TextActionsSettingsCopyWith<$R, TextActionsSettings, $Out> {
  _TextActionsSettingsCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<TextActionsSettings> $mapper =
      TextActionsSettingsMapper.ensureInitialized();
  @override
  ListCopyWith<$R, TextAction, TextActionCopyWith<$R, TextAction, TextAction>>
  get actions => ListCopyWith(
    $value.actions,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(actions: v),
  );
  @override
  $R call({List<TextAction>? actions}) =>
      $apply(FieldCopyWithData({if (actions != null) #actions: actions}));
  @override
  TextActionsSettings $make(CopyWithData data) =>
      TextActionsSettings(actions: data.get(#actions, or: $value.actions));

  @override
  TextActionsSettingsCopyWith<$R2, TextActionsSettings, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _TextActionsSettingsCopyWithImpl<$R2, $Out2>($value, $cast, t);
}
