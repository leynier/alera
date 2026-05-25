// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'keyboard_shortcut_settings.dart';

class KeyboardShortcutSettingsMapper
    extends ClassMapperBase<KeyboardShortcutSettings> {
  KeyboardShortcutSettingsMapper._();

  static KeyboardShortcutSettingsMapper? _instance;
  static KeyboardShortcutSettingsMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = KeyboardShortcutSettingsMapper._(),
      );
      KeyboardActionIdMapper.ensureInitialized();
      TerminalShortcutPolicyMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'KeyboardShortcutSettings';

  static Map<KeyboardActionId, List<String>> _$overrides(
    KeyboardShortcutSettings v,
  ) => v.overrides;
  static const Field<
    KeyboardShortcutSettings,
    Map<KeyboardActionId, List<String>>
  >
  _f$overrides = Field(
    'overrides',
    _$overrides,
    opt: true,
    def: const <KeyboardActionId, List<String>>{},
  );
  static TerminalShortcutPolicy _$terminalPolicy(KeyboardShortcutSettings v) =>
      v.terminalPolicy;
  static const Field<KeyboardShortcutSettings, TerminalShortcutPolicy>
  _f$terminalPolicy = Field(
    'terminalPolicy',
    _$terminalPolicy,
    opt: true,
    def: TerminalShortcutPolicy.appFirst,
  );

  @override
  final MappableFields<KeyboardShortcutSettings> fields = const {
    #overrides: _f$overrides,
    #terminalPolicy: _f$terminalPolicy,
  };

  static KeyboardShortcutSettings _instantiate(DecodingData data) {
    return KeyboardShortcutSettings(
      overrides: data.dec(_f$overrides),
      terminalPolicy: data.dec(_f$terminalPolicy),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static KeyboardShortcutSettings fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<KeyboardShortcutSettings>(map);
  }

  static KeyboardShortcutSettings fromJson(String json) {
    return ensureInitialized().decodeJson<KeyboardShortcutSettings>(json);
  }
}

mixin KeyboardShortcutSettingsMappable {
  String toJson() {
    return KeyboardShortcutSettingsMapper.ensureInitialized()
        .encodeJson<KeyboardShortcutSettings>(this as KeyboardShortcutSettings);
  }

  Map<String, dynamic> toMap() {
    return KeyboardShortcutSettingsMapper.ensureInitialized()
        .encodeMap<KeyboardShortcutSettings>(this as KeyboardShortcutSettings);
  }

  KeyboardShortcutSettingsCopyWith<
    KeyboardShortcutSettings,
    KeyboardShortcutSettings,
    KeyboardShortcutSettings
  >
  get copyWith =>
      _KeyboardShortcutSettingsCopyWithImpl<
        KeyboardShortcutSettings,
        KeyboardShortcutSettings
      >(this as KeyboardShortcutSettings, $identity, $identity);
  @override
  String toString() {
    return KeyboardShortcutSettingsMapper.ensureInitialized().stringifyValue(
      this as KeyboardShortcutSettings,
    );
  }

  @override
  bool operator ==(Object other) {
    return KeyboardShortcutSettingsMapper.ensureInitialized().equalsValue(
      this as KeyboardShortcutSettings,
      other,
    );
  }

  @override
  int get hashCode {
    return KeyboardShortcutSettingsMapper.ensureInitialized().hashValue(
      this as KeyboardShortcutSettings,
    );
  }
}

extension KeyboardShortcutSettingsValueCopy<$R, $Out>
    on ObjectCopyWith<$R, KeyboardShortcutSettings, $Out> {
  KeyboardShortcutSettingsCopyWith<$R, KeyboardShortcutSettings, $Out>
  get $asKeyboardShortcutSettings => $base.as(
    (v, t, t2) => _KeyboardShortcutSettingsCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class KeyboardShortcutSettingsCopyWith<
  $R,
  $In extends KeyboardShortcutSettings,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  MapCopyWith<
    $R,
    KeyboardActionId,
    List<String>,
    ObjectCopyWith<$R, List<String>, List<String>>
  >
  get overrides;
  $R call({
    Map<KeyboardActionId, List<String>>? overrides,
    TerminalShortcutPolicy? terminalPolicy,
  });
  KeyboardShortcutSettingsCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _KeyboardShortcutSettingsCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, KeyboardShortcutSettings, $Out>
    implements
        KeyboardShortcutSettingsCopyWith<$R, KeyboardShortcutSettings, $Out> {
  _KeyboardShortcutSettingsCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<KeyboardShortcutSettings> $mapper =
      KeyboardShortcutSettingsMapper.ensureInitialized();
  @override
  MapCopyWith<
    $R,
    KeyboardActionId,
    List<String>,
    ObjectCopyWith<$R, List<String>, List<String>>
  >
  get overrides => MapCopyWith(
    $value.overrides,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(overrides: v),
  );
  @override
  $R call({
    Map<KeyboardActionId, List<String>>? overrides,
    TerminalShortcutPolicy? terminalPolicy,
  }) => $apply(
    FieldCopyWithData({
      if (overrides != null) #overrides: overrides,
      if (terminalPolicy != null) #terminalPolicy: terminalPolicy,
    }),
  );
  @override
  KeyboardShortcutSettings $make(CopyWithData data) => KeyboardShortcutSettings(
    overrides: data.get(#overrides, or: $value.overrides),
    terminalPolicy: data.get(#terminalPolicy, or: $value.terminalPolicy),
  );

  @override
  KeyboardShortcutSettingsCopyWith<$R2, KeyboardShortcutSettings, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _KeyboardShortcutSettingsCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

