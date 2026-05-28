// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'alera_settings.dart';

class TerminalCursorShapeMapper extends EnumMapper<TerminalCursorShape> {
  TerminalCursorShapeMapper._();

  static TerminalCursorShapeMapper? _instance;
  static TerminalCursorShapeMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = TerminalCursorShapeMapper._());
    }
    return _instance!;
  }

  static TerminalCursorShape fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  TerminalCursorShape decode(dynamic value) {
    switch (value) {
      case r'block':
        return TerminalCursorShape.block;
      case r'bar':
        return TerminalCursorShape.bar;
      case r'underline':
        return TerminalCursorShape.underline;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(TerminalCursorShape self) {
    switch (self) {
      case TerminalCursorShape.block:
        return r'block';
      case TerminalCursorShape.bar:
        return r'bar';
      case TerminalCursorShape.underline:
        return r'underline';
    }
  }
}

extension TerminalCursorShapeMapperExtension on TerminalCursorShape {
  String toValue() {
    TerminalCursorShapeMapper.ensureInitialized();
    return MapperContainer.globals.toValue<TerminalCursorShape>(this) as String;
  }
}

class TerminalColorOverridesMapper
    extends ClassMapperBase<TerminalColorOverrides> {
  TerminalColorOverridesMapper._();

  static TerminalColorOverridesMapper? _instance;
  static TerminalColorOverridesMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = TerminalColorOverridesMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'TerminalColorOverrides';

  static String? _$foreground(TerminalColorOverrides v) => v.foreground;
  static const Field<TerminalColorOverrides, String> _f$foreground = Field(
    'foreground',
    _$foreground,
    opt: true,
  );
  static String? _$background(TerminalColorOverrides v) => v.background;
  static const Field<TerminalColorOverrides, String> _f$background = Field(
    'background',
    _$background,
    opt: true,
  );
  static String? _$cursor(TerminalColorOverrides v) => v.cursor;
  static const Field<TerminalColorOverrides, String> _f$cursor = Field(
    'cursor',
    _$cursor,
    opt: true,
  );
  static String? _$selection(TerminalColorOverrides v) => v.selection;
  static const Field<TerminalColorOverrides, String> _f$selection = Field(
    'selection',
    _$selection,
    opt: true,
  );

  @override
  final MappableFields<TerminalColorOverrides> fields = const {
    #foreground: _f$foreground,
    #background: _f$background,
    #cursor: _f$cursor,
    #selection: _f$selection,
  };

  static TerminalColorOverrides _instantiate(DecodingData data) {
    return TerminalColorOverrides(
      foreground: data.dec(_f$foreground),
      background: data.dec(_f$background),
      cursor: data.dec(_f$cursor),
      selection: data.dec(_f$selection),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static TerminalColorOverrides fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<TerminalColorOverrides>(map);
  }

  static TerminalColorOverrides fromJson(String json) {
    return ensureInitialized().decodeJson<TerminalColorOverrides>(json);
  }
}

mixin TerminalColorOverridesMappable {
  String toJson() {
    return TerminalColorOverridesMapper.ensureInitialized()
        .encodeJson<TerminalColorOverrides>(this as TerminalColorOverrides);
  }

  Map<String, dynamic> toMap() {
    return TerminalColorOverridesMapper.ensureInitialized()
        .encodeMap<TerminalColorOverrides>(this as TerminalColorOverrides);
  }

  TerminalColorOverridesCopyWith<
    TerminalColorOverrides,
    TerminalColorOverrides,
    TerminalColorOverrides
  >
  get copyWith =>
      _TerminalColorOverridesCopyWithImpl<
        TerminalColorOverrides,
        TerminalColorOverrides
      >(this as TerminalColorOverrides, $identity, $identity);
  @override
  String toString() {
    return TerminalColorOverridesMapper.ensureInitialized().stringifyValue(
      this as TerminalColorOverrides,
    );
  }

  @override
  bool operator ==(Object other) {
    return TerminalColorOverridesMapper.ensureInitialized().equalsValue(
      this as TerminalColorOverrides,
      other,
    );
  }

  @override
  int get hashCode {
    return TerminalColorOverridesMapper.ensureInitialized().hashValue(
      this as TerminalColorOverrides,
    );
  }
}

extension TerminalColorOverridesValueCopy<$R, $Out>
    on ObjectCopyWith<$R, TerminalColorOverrides, $Out> {
  TerminalColorOverridesCopyWith<$R, TerminalColorOverrides, $Out>
  get $asTerminalColorOverrides => $base.as(
    (v, t, t2) => _TerminalColorOverridesCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class TerminalColorOverridesCopyWith<
  $R,
  $In extends TerminalColorOverrides,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    String? foreground,
    String? background,
    String? cursor,
    String? selection,
  });
  TerminalColorOverridesCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _TerminalColorOverridesCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, TerminalColorOverrides, $Out>
    implements
        TerminalColorOverridesCopyWith<$R, TerminalColorOverrides, $Out> {
  _TerminalColorOverridesCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<TerminalColorOverrides> $mapper =
      TerminalColorOverridesMapper.ensureInitialized();
  @override
  $R call({
    Object? foreground = $none,
    Object? background = $none,
    Object? cursor = $none,
    Object? selection = $none,
  }) => $apply(
    FieldCopyWithData({
      if (foreground != $none) #foreground: foreground,
      if (background != $none) #background: background,
      if (cursor != $none) #cursor: cursor,
      if (selection != $none) #selection: selection,
    }),
  );
  @override
  TerminalColorOverrides $make(CopyWithData data) => TerminalColorOverrides(
    foreground: data.get(#foreground, or: $value.foreground),
    background: data.get(#background, or: $value.background),
    cursor: data.get(#cursor, or: $value.cursor),
    selection: data.get(#selection, or: $value.selection),
  );

  @override
  TerminalColorOverridesCopyWith<$R2, TerminalColorOverrides, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _TerminalColorOverridesCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class TerminalSettingsMapper extends ClassMapperBase<TerminalSettings> {
  TerminalSettingsMapper._();

  static TerminalSettingsMapper? _instance;
  static TerminalSettingsMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = TerminalSettingsMapper._());
      TerminalCursorShapeMapper.ensureInitialized();
      TerminalColorOverridesMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'TerminalSettings';

  static String _$fontFamily(TerminalSettings v) => v.fontFamily;
  static const Field<TerminalSettings, String> _f$fontFamily = Field(
    'fontFamily',
    _$fontFamily,
  );
  static double _$fontSize(TerminalSettings v) => v.fontSize;
  static const Field<TerminalSettings, double> _f$fontSize = Field(
    'fontSize',
    _$fontSize,
  );
  static int _$fontWeight(TerminalSettings v) => v.fontWeight;
  static const Field<TerminalSettings, int> _f$fontWeight = Field(
    'fontWeight',
    _$fontWeight,
    opt: true,
    def: 400,
  );
  static double _$lineHeight(TerminalSettings v) => v.lineHeight;
  static const Field<TerminalSettings, double> _f$lineHeight = Field(
    'lineHeight',
    _$lineHeight,
  );
  static double _$paddingX(TerminalSettings v) => v.paddingX;
  static const Field<TerminalSettings, double> _f$paddingX = Field(
    'paddingX',
    _$paddingX,
    opt: true,
    def: AleraTokens.space12,
  );
  static double _$paddingY(TerminalSettings v) => v.paddingY;
  static const Field<TerminalSettings, double> _f$paddingY = Field(
    'paddingY',
    _$paddingY,
    opt: true,
    def: AleraTokens.space12,
  );
  static TerminalCursorShape _$cursorShape(TerminalSettings v) => v.cursorShape;
  static const Field<TerminalSettings, TerminalCursorShape> _f$cursorShape =
      Field('cursorShape', _$cursorShape);
  static bool _$cursorBlink(TerminalSettings v) => v.cursorBlink;
  static const Field<TerminalSettings, bool> _f$cursorBlink = Field(
    'cursorBlink',
    _$cursorBlink,
    opt: true,
    def: false,
  );
  static double _$cursorOpacity(TerminalSettings v) => v.cursorOpacity;
  static const Field<TerminalSettings, double> _f$cursorOpacity = Field(
    'cursorOpacity',
    _$cursorOpacity,
    opt: true,
    def: 1,
  );
  static String _$themeName(TerminalSettings v) => v.themeName;
  static const Field<TerminalSettings, String> _f$themeName = Field(
    'themeName',
    _$themeName,
    opt: true,
    def: TerminalThemeNames.aleraDark,
  );
  static double _$backgroundOpacity(TerminalSettings v) => v.backgroundOpacity;
  static const Field<TerminalSettings, double> _f$backgroundOpacity = Field(
    'backgroundOpacity',
    _$backgroundOpacity,
    opt: true,
    def: 1,
  );
  static String? _$wordSeparators(TerminalSettings v) => v.wordSeparators;
  static const Field<TerminalSettings, String> _f$wordSeparators = Field(
    'wordSeparators',
    _$wordSeparators,
    opt: true,
  );
  static TerminalColorOverrides _$colorOverrides(TerminalSettings v) =>
      v.colorOverrides;
  static const Field<TerminalSettings, TerminalColorOverrides>
  _f$colorOverrides = Field(
    'colorOverrides',
    _$colorOverrides,
    opt: true,
    def: const TerminalColorOverrides(),
  );
  static int _$scrollbackLines(TerminalSettings v) => v.scrollbackLines;
  static const Field<TerminalSettings, int> _f$scrollbackLines = Field(
    'scrollbackLines',
    _$scrollbackLines,
  );
  static int _$hostEmptyShutdownDelaySeconds(TerminalSettings v) =>
      v.hostEmptyShutdownDelaySeconds;
  static const Field<TerminalSettings, int> _f$hostEmptyShutdownDelaySeconds =
      Field(
        'hostEmptyShutdownDelaySeconds',
        _$hostEmptyShutdownDelaySeconds,
        opt: true,
        def: 30,
      );
  static int _$hostDetachedSessionShutdownDelaySeconds(TerminalSettings v) =>
      v.hostDetachedSessionShutdownDelaySeconds;
  static const Field<TerminalSettings, int>
  _f$hostDetachedSessionShutdownDelaySeconds = Field(
    'hostDetachedSessionShutdownDelaySeconds',
    _$hostDetachedSessionShutdownDelaySeconds,
    opt: true,
    def: 60 * 60,
  );
  static int _$hostScrollbackBytes(TerminalSettings v) => v.hostScrollbackBytes;
  static const Field<TerminalSettings, int> _f$hostScrollbackBytes = Field(
    'hostScrollbackBytes',
    _$hostScrollbackBytes,
    opt: true,
    def: 10 * 1000 * 1000,
  );

  @override
  final MappableFields<TerminalSettings> fields = const {
    #fontFamily: _f$fontFamily,
    #fontSize: _f$fontSize,
    #fontWeight: _f$fontWeight,
    #lineHeight: _f$lineHeight,
    #paddingX: _f$paddingX,
    #paddingY: _f$paddingY,
    #cursorShape: _f$cursorShape,
    #cursorBlink: _f$cursorBlink,
    #cursorOpacity: _f$cursorOpacity,
    #themeName: _f$themeName,
    #backgroundOpacity: _f$backgroundOpacity,
    #wordSeparators: _f$wordSeparators,
    #colorOverrides: _f$colorOverrides,
    #scrollbackLines: _f$scrollbackLines,
    #hostEmptyShutdownDelaySeconds: _f$hostEmptyShutdownDelaySeconds,
    #hostDetachedSessionShutdownDelaySeconds:
        _f$hostDetachedSessionShutdownDelaySeconds,
    #hostScrollbackBytes: _f$hostScrollbackBytes,
  };

  static TerminalSettings _instantiate(DecodingData data) {
    return TerminalSettings(
      fontFamily: data.dec(_f$fontFamily),
      fontSize: data.dec(_f$fontSize),
      fontWeight: data.dec(_f$fontWeight),
      lineHeight: data.dec(_f$lineHeight),
      paddingX: data.dec(_f$paddingX),
      paddingY: data.dec(_f$paddingY),
      cursorShape: data.dec(_f$cursorShape),
      cursorBlink: data.dec(_f$cursorBlink),
      cursorOpacity: data.dec(_f$cursorOpacity),
      themeName: data.dec(_f$themeName),
      backgroundOpacity: data.dec(_f$backgroundOpacity),
      wordSeparators: data.dec(_f$wordSeparators),
      colorOverrides: data.dec(_f$colorOverrides),
      scrollbackLines: data.dec(_f$scrollbackLines),
      hostEmptyShutdownDelaySeconds: data.dec(_f$hostEmptyShutdownDelaySeconds),
      hostDetachedSessionShutdownDelaySeconds: data.dec(
        _f$hostDetachedSessionShutdownDelaySeconds,
      ),
      hostScrollbackBytes: data.dec(_f$hostScrollbackBytes),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static TerminalSettings fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<TerminalSettings>(map);
  }

  static TerminalSettings fromJson(String json) {
    return ensureInitialized().decodeJson<TerminalSettings>(json);
  }
}

mixin TerminalSettingsMappable {
  String toJson() {
    return TerminalSettingsMapper.ensureInitialized()
        .encodeJson<TerminalSettings>(this as TerminalSettings);
  }

  Map<String, dynamic> toMap() {
    return TerminalSettingsMapper.ensureInitialized()
        .encodeMap<TerminalSettings>(this as TerminalSettings);
  }

  TerminalSettingsCopyWith<TerminalSettings, TerminalSettings, TerminalSettings>
  get copyWith =>
      _TerminalSettingsCopyWithImpl<TerminalSettings, TerminalSettings>(
        this as TerminalSettings,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return TerminalSettingsMapper.ensureInitialized().stringifyValue(
      this as TerminalSettings,
    );
  }

  @override
  bool operator ==(Object other) {
    return TerminalSettingsMapper.ensureInitialized().equalsValue(
      this as TerminalSettings,
      other,
    );
  }

  @override
  int get hashCode {
    return TerminalSettingsMapper.ensureInitialized().hashValue(
      this as TerminalSettings,
    );
  }
}

extension TerminalSettingsValueCopy<$R, $Out>
    on ObjectCopyWith<$R, TerminalSettings, $Out> {
  TerminalSettingsCopyWith<$R, TerminalSettings, $Out>
  get $asTerminalSettings =>
      $base.as((v, t, t2) => _TerminalSettingsCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class TerminalSettingsCopyWith<$R, $In extends TerminalSettings, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  TerminalColorOverridesCopyWith<
    $R,
    TerminalColorOverrides,
    TerminalColorOverrides
  >
  get colorOverrides;
  $R call({
    String? fontFamily,
    double? fontSize,
    int? fontWeight,
    double? lineHeight,
    double? paddingX,
    double? paddingY,
    TerminalCursorShape? cursorShape,
    bool? cursorBlink,
    double? cursorOpacity,
    String? themeName,
    double? backgroundOpacity,
    String? wordSeparators,
    TerminalColorOverrides? colorOverrides,
    int? scrollbackLines,
    int? hostEmptyShutdownDelaySeconds,
    int? hostDetachedSessionShutdownDelaySeconds,
    int? hostScrollbackBytes,
  });
  TerminalSettingsCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _TerminalSettingsCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, TerminalSettings, $Out>
    implements TerminalSettingsCopyWith<$R, TerminalSettings, $Out> {
  _TerminalSettingsCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<TerminalSettings> $mapper =
      TerminalSettingsMapper.ensureInitialized();
  @override
  TerminalColorOverridesCopyWith<
    $R,
    TerminalColorOverrides,
    TerminalColorOverrides
  >
  get colorOverrides =>
      $value.colorOverrides.copyWith.$chain((v) => call(colorOverrides: v));
  @override
  $R call({
    String? fontFamily,
    double? fontSize,
    int? fontWeight,
    double? lineHeight,
    double? paddingX,
    double? paddingY,
    TerminalCursorShape? cursorShape,
    bool? cursorBlink,
    double? cursorOpacity,
    String? themeName,
    double? backgroundOpacity,
    Object? wordSeparators = $none,
    TerminalColorOverrides? colorOverrides,
    int? scrollbackLines,
    int? hostEmptyShutdownDelaySeconds,
    int? hostDetachedSessionShutdownDelaySeconds,
    int? hostScrollbackBytes,
  }) => $apply(
    FieldCopyWithData({
      if (fontFamily != null) #fontFamily: fontFamily,
      if (fontSize != null) #fontSize: fontSize,
      if (fontWeight != null) #fontWeight: fontWeight,
      if (lineHeight != null) #lineHeight: lineHeight,
      if (paddingX != null) #paddingX: paddingX,
      if (paddingY != null) #paddingY: paddingY,
      if (cursorShape != null) #cursorShape: cursorShape,
      if (cursorBlink != null) #cursorBlink: cursorBlink,
      if (cursorOpacity != null) #cursorOpacity: cursorOpacity,
      if (themeName != null) #themeName: themeName,
      if (backgroundOpacity != null) #backgroundOpacity: backgroundOpacity,
      if (wordSeparators != $none) #wordSeparators: wordSeparators,
      if (colorOverrides != null) #colorOverrides: colorOverrides,
      if (scrollbackLines != null) #scrollbackLines: scrollbackLines,
      if (hostEmptyShutdownDelaySeconds != null)
        #hostEmptyShutdownDelaySeconds: hostEmptyShutdownDelaySeconds,
      if (hostDetachedSessionShutdownDelaySeconds != null)
        #hostDetachedSessionShutdownDelaySeconds:
            hostDetachedSessionShutdownDelaySeconds,
      if (hostScrollbackBytes != null)
        #hostScrollbackBytes: hostScrollbackBytes,
    }),
  );
  @override
  TerminalSettings $make(CopyWithData data) => TerminalSettings(
    fontFamily: data.get(#fontFamily, or: $value.fontFamily),
    fontSize: data.get(#fontSize, or: $value.fontSize),
    fontWeight: data.get(#fontWeight, or: $value.fontWeight),
    lineHeight: data.get(#lineHeight, or: $value.lineHeight),
    paddingX: data.get(#paddingX, or: $value.paddingX),
    paddingY: data.get(#paddingY, or: $value.paddingY),
    cursorShape: data.get(#cursorShape, or: $value.cursorShape),
    cursorBlink: data.get(#cursorBlink, or: $value.cursorBlink),
    cursorOpacity: data.get(#cursorOpacity, or: $value.cursorOpacity),
    themeName: data.get(#themeName, or: $value.themeName),
    backgroundOpacity: data.get(
      #backgroundOpacity,
      or: $value.backgroundOpacity,
    ),
    wordSeparators: data.get(#wordSeparators, or: $value.wordSeparators),
    colorOverrides: data.get(#colorOverrides, or: $value.colorOverrides),
    scrollbackLines: data.get(#scrollbackLines, or: $value.scrollbackLines),
    hostEmptyShutdownDelaySeconds: data.get(
      #hostEmptyShutdownDelaySeconds,
      or: $value.hostEmptyShutdownDelaySeconds,
    ),
    hostDetachedSessionShutdownDelaySeconds: data.get(
      #hostDetachedSessionShutdownDelaySeconds,
      or: $value.hostDetachedSessionShutdownDelaySeconds,
    ),
    hostScrollbackBytes: data.get(
      #hostScrollbackBytes,
      or: $value.hostScrollbackBytes,
    ),
  );

  @override
  TerminalSettingsCopyWith<$R2, TerminalSettings, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _TerminalSettingsCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class AgentStatusHookSettingsMapper
    extends ClassMapperBase<AgentStatusHookSettings> {
  AgentStatusHookSettingsMapper._();

  static AgentStatusHookSettingsMapper? _instance;
  static AgentStatusHookSettingsMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = AgentStatusHookSettingsMapper._(),
      );
    }
    return _instance!;
  }

  @override
  final String id = 'AgentStatusHookSettings';

  static bool _$codex(AgentStatusHookSettings v) => v.codex;
  static const Field<AgentStatusHookSettings, bool> _f$codex = Field(
    'codex',
    _$codex,
    opt: true,
    def: false,
  );
  static bool _$claude(AgentStatusHookSettings v) => v.claude;
  static const Field<AgentStatusHookSettings, bool> _f$claude = Field(
    'claude',
    _$claude,
    opt: true,
    def: false,
  );
  static bool _$copilot(AgentStatusHookSettings v) => v.copilot;
  static const Field<AgentStatusHookSettings, bool> _f$copilot = Field(
    'copilot',
    _$copilot,
    opt: true,
    def: false,
  );
  static bool _$cursor(AgentStatusHookSettings v) => v.cursor;
  static const Field<AgentStatusHookSettings, bool> _f$cursor = Field(
    'cursor',
    _$cursor,
    opt: true,
    def: false,
  );
  static bool _$agy(AgentStatusHookSettings v) => v.agy;
  static const Field<AgentStatusHookSettings, bool> _f$agy = Field(
    'agy',
    _$agy,
    opt: true,
    def: false,
  );
  static bool _$opencode(AgentStatusHookSettings v) => v.opencode;
  static const Field<AgentStatusHookSettings, bool> _f$opencode = Field(
    'opencode',
    _$opencode,
    opt: true,
    def: false,
  );
  static bool _$pi(AgentStatusHookSettings v) => v.pi;
  static const Field<AgentStatusHookSettings, bool> _f$pi = Field(
    'pi',
    _$pi,
    opt: true,
    def: false,
  );
  static bool _$amp(AgentStatusHookSettings v) => v.amp;
  static const Field<AgentStatusHookSettings, bool> _f$amp = Field(
    'amp',
    _$amp,
    opt: true,
    def: false,
  );

  @override
  final MappableFields<AgentStatusHookSettings> fields = const {
    #codex: _f$codex,
    #claude: _f$claude,
    #copilot: _f$copilot,
    #cursor: _f$cursor,
    #agy: _f$agy,
    #opencode: _f$opencode,
    #pi: _f$pi,
    #amp: _f$amp,
  };

  static AgentStatusHookSettings _instantiate(DecodingData data) {
    return AgentStatusHookSettings(
      codex: data.dec(_f$codex),
      claude: data.dec(_f$claude),
      copilot: data.dec(_f$copilot),
      cursor: data.dec(_f$cursor),
      agy: data.dec(_f$agy),
      opencode: data.dec(_f$opencode),
      pi: data.dec(_f$pi),
      amp: data.dec(_f$amp),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static AgentStatusHookSettings fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<AgentStatusHookSettings>(map);
  }

  static AgentStatusHookSettings fromJson(String json) {
    return ensureInitialized().decodeJson<AgentStatusHookSettings>(json);
  }
}

mixin AgentStatusHookSettingsMappable {
  String toJson() {
    return AgentStatusHookSettingsMapper.ensureInitialized()
        .encodeJson<AgentStatusHookSettings>(this as AgentStatusHookSettings);
  }

  Map<String, dynamic> toMap() {
    return AgentStatusHookSettingsMapper.ensureInitialized()
        .encodeMap<AgentStatusHookSettings>(this as AgentStatusHookSettings);
  }

  AgentStatusHookSettingsCopyWith<
    AgentStatusHookSettings,
    AgentStatusHookSettings,
    AgentStatusHookSettings
  >
  get copyWith =>
      _AgentStatusHookSettingsCopyWithImpl<
        AgentStatusHookSettings,
        AgentStatusHookSettings
      >(this as AgentStatusHookSettings, $identity, $identity);
  @override
  String toString() {
    return AgentStatusHookSettingsMapper.ensureInitialized().stringifyValue(
      this as AgentStatusHookSettings,
    );
  }

  @override
  bool operator ==(Object other) {
    return AgentStatusHookSettingsMapper.ensureInitialized().equalsValue(
      this as AgentStatusHookSettings,
      other,
    );
  }

  @override
  int get hashCode {
    return AgentStatusHookSettingsMapper.ensureInitialized().hashValue(
      this as AgentStatusHookSettings,
    );
  }
}

extension AgentStatusHookSettingsValueCopy<$R, $Out>
    on ObjectCopyWith<$R, AgentStatusHookSettings, $Out> {
  AgentStatusHookSettingsCopyWith<$R, AgentStatusHookSettings, $Out>
  get $asAgentStatusHookSettings => $base.as(
    (v, t, t2) => _AgentStatusHookSettingsCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class AgentStatusHookSettingsCopyWith<
  $R,
  $In extends AgentStatusHookSettings,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    bool? codex,
    bool? claude,
    bool? copilot,
    bool? cursor,
    bool? agy,
    bool? opencode,
    bool? pi,
    bool? amp,
  });
  AgentStatusHookSettingsCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _AgentStatusHookSettingsCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, AgentStatusHookSettings, $Out>
    implements
        AgentStatusHookSettingsCopyWith<$R, AgentStatusHookSettings, $Out> {
  _AgentStatusHookSettingsCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<AgentStatusHookSettings> $mapper =
      AgentStatusHookSettingsMapper.ensureInitialized();
  @override
  $R call({
    bool? codex,
    bool? claude,
    bool? copilot,
    bool? cursor,
    bool? agy,
    bool? opencode,
    bool? pi,
    bool? amp,
  }) => $apply(
    FieldCopyWithData({
      if (codex != null) #codex: codex,
      if (claude != null) #claude: claude,
      if (copilot != null) #copilot: copilot,
      if (cursor != null) #cursor: cursor,
      if (agy != null) #agy: agy,
      if (opencode != null) #opencode: opencode,
      if (pi != null) #pi: pi,
      if (amp != null) #amp: amp,
    }),
  );
  @override
  AgentStatusHookSettings $make(CopyWithData data) => AgentStatusHookSettings(
    codex: data.get(#codex, or: $value.codex),
    claude: data.get(#claude, or: $value.claude),
    copilot: data.get(#copilot, or: $value.copilot),
    cursor: data.get(#cursor, or: $value.cursor),
    agy: data.get(#agy, or: $value.agy),
    opencode: data.get(#opencode, or: $value.opencode),
    pi: data.get(#pi, or: $value.pi),
    amp: data.get(#amp, or: $value.amp),
  );

  @override
  AgentStatusHookSettingsCopyWith<$R2, AgentStatusHookSettings, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _AgentStatusHookSettingsCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class GeneralSettingsMapper extends ClassMapperBase<GeneralSettings> {
  GeneralSettingsMapper._();

  static GeneralSettingsMapper? _instance;
  static GeneralSettingsMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = GeneralSettingsMapper._());
      AgentStatusHookSettingsMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'GeneralSettings';

  static String? _$workspaceDirectory(GeneralSettings v) =>
      v.workspaceDirectory;
  static const Field<GeneralSettings, String> _f$workspaceDirectory = Field(
    'workspaceDirectory',
    _$workspaceDirectory,
    opt: true,
  );
  static bool _$starClicked(GeneralSettings v) => v.starClicked;
  static const Field<GeneralSettings, bool> _f$starClicked = Field(
    'starClicked',
    _$starClicked,
    opt: true,
    def: false,
  );
  static bool _$confirmProjectRemoval(GeneralSettings v) =>
      v.confirmProjectRemoval;
  static const Field<GeneralSettings, bool> _f$confirmProjectRemoval = Field(
    'confirmProjectRemoval',
    _$confirmProjectRemoval,
    opt: true,
    def: true,
  );
  static bool _$confirmWorkspaceRemoval(GeneralSettings v) =>
      v.confirmWorkspaceRemoval;
  static const Field<GeneralSettings, bool> _f$confirmWorkspaceRemoval = Field(
    'confirmWorkspaceRemoval',
    _$confirmWorkspaceRemoval,
    opt: true,
    def: true,
  );
  static AgentStatusHookSettings _$agentStatusHooks(GeneralSettings v) =>
      v.agentStatusHooks;
  static const Field<GeneralSettings, AgentStatusHookSettings>
  _f$agentStatusHooks = Field(
    'agentStatusHooks',
    _$agentStatusHooks,
    opt: true,
    def: AgentStatusHookSettings.defaults,
  );
  static bool _$agentStatusNotificationsEnabled(GeneralSettings v) =>
      v.agentStatusNotificationsEnabled;
  static const Field<GeneralSettings, bool> _f$agentStatusNotificationsEnabled =
      Field(
        'agentStatusNotificationsEnabled',
        _$agentStatusNotificationsEnabled,
        opt: true,
        def: false,
      );
  static bool _$keepComputerAwakeWhileAgentsWork(GeneralSettings v) =>
      v.keepComputerAwakeWhileAgentsWork;
  static const Field<GeneralSettings, bool>
  _f$keepComputerAwakeWhileAgentsWork = Field(
    'keepComputerAwakeWhileAgentsWork',
    _$keepComputerAwakeWhileAgentsWork,
    opt: true,
    def: false,
  );

  @override
  final MappableFields<GeneralSettings> fields = const {
    #workspaceDirectory: _f$workspaceDirectory,
    #starClicked: _f$starClicked,
    #confirmProjectRemoval: _f$confirmProjectRemoval,
    #confirmWorkspaceRemoval: _f$confirmWorkspaceRemoval,
    #agentStatusHooks: _f$agentStatusHooks,
    #agentStatusNotificationsEnabled: _f$agentStatusNotificationsEnabled,
    #keepComputerAwakeWhileAgentsWork: _f$keepComputerAwakeWhileAgentsWork,
  };

  static GeneralSettings _instantiate(DecodingData data) {
    return GeneralSettings(
      workspaceDirectory: data.dec(_f$workspaceDirectory),
      starClicked: data.dec(_f$starClicked),
      confirmProjectRemoval: data.dec(_f$confirmProjectRemoval),
      confirmWorkspaceRemoval: data.dec(_f$confirmWorkspaceRemoval),
      agentStatusHooks: data.dec(_f$agentStatusHooks),
      agentStatusNotificationsEnabled: data.dec(
        _f$agentStatusNotificationsEnabled,
      ),
      keepComputerAwakeWhileAgentsWork: data.dec(
        _f$keepComputerAwakeWhileAgentsWork,
      ),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static GeneralSettings fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<GeneralSettings>(map);
  }

  static GeneralSettings fromJson(String json) {
    return ensureInitialized().decodeJson<GeneralSettings>(json);
  }
}

mixin GeneralSettingsMappable {
  String toJson() {
    return GeneralSettingsMapper.ensureInitialized()
        .encodeJson<GeneralSettings>(this as GeneralSettings);
  }

  Map<String, dynamic> toMap() {
    return GeneralSettingsMapper.ensureInitialized().encodeMap<GeneralSettings>(
      this as GeneralSettings,
    );
  }

  GeneralSettingsCopyWith<GeneralSettings, GeneralSettings, GeneralSettings>
  get copyWith =>
      _GeneralSettingsCopyWithImpl<GeneralSettings, GeneralSettings>(
        this as GeneralSettings,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return GeneralSettingsMapper.ensureInitialized().stringifyValue(
      this as GeneralSettings,
    );
  }

  @override
  bool operator ==(Object other) {
    return GeneralSettingsMapper.ensureInitialized().equalsValue(
      this as GeneralSettings,
      other,
    );
  }

  @override
  int get hashCode {
    return GeneralSettingsMapper.ensureInitialized().hashValue(
      this as GeneralSettings,
    );
  }
}

extension GeneralSettingsValueCopy<$R, $Out>
    on ObjectCopyWith<$R, GeneralSettings, $Out> {
  GeneralSettingsCopyWith<$R, GeneralSettings, $Out> get $asGeneralSettings =>
      $base.as((v, t, t2) => _GeneralSettingsCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class GeneralSettingsCopyWith<$R, $In extends GeneralSettings, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  AgentStatusHookSettingsCopyWith<
    $R,
    AgentStatusHookSettings,
    AgentStatusHookSettings
  >
  get agentStatusHooks;
  $R call({
    String? workspaceDirectory,
    bool? starClicked,
    bool? confirmProjectRemoval,
    bool? confirmWorkspaceRemoval,
    AgentStatusHookSettings? agentStatusHooks,
    bool? agentStatusNotificationsEnabled,
    bool? keepComputerAwakeWhileAgentsWork,
  });
  GeneralSettingsCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _GeneralSettingsCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, GeneralSettings, $Out>
    implements GeneralSettingsCopyWith<$R, GeneralSettings, $Out> {
  _GeneralSettingsCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<GeneralSettings> $mapper =
      GeneralSettingsMapper.ensureInitialized();
  @override
  AgentStatusHookSettingsCopyWith<
    $R,
    AgentStatusHookSettings,
    AgentStatusHookSettings
  >
  get agentStatusHooks =>
      $value.agentStatusHooks.copyWith.$chain((v) => call(agentStatusHooks: v));
  @override
  $R call({
    Object? workspaceDirectory = $none,
    bool? starClicked,
    bool? confirmProjectRemoval,
    bool? confirmWorkspaceRemoval,
    AgentStatusHookSettings? agentStatusHooks,
    bool? agentStatusNotificationsEnabled,
    bool? keepComputerAwakeWhileAgentsWork,
  }) => $apply(
    FieldCopyWithData({
      if (workspaceDirectory != $none) #workspaceDirectory: workspaceDirectory,
      if (starClicked != null) #starClicked: starClicked,
      if (confirmProjectRemoval != null)
        #confirmProjectRemoval: confirmProjectRemoval,
      if (confirmWorkspaceRemoval != null)
        #confirmWorkspaceRemoval: confirmWorkspaceRemoval,
      if (agentStatusHooks != null) #agentStatusHooks: agentStatusHooks,
      if (agentStatusNotificationsEnabled != null)
        #agentStatusNotificationsEnabled: agentStatusNotificationsEnabled,
      if (keepComputerAwakeWhileAgentsWork != null)
        #keepComputerAwakeWhileAgentsWork: keepComputerAwakeWhileAgentsWork,
    }),
  );
  @override
  GeneralSettings $make(CopyWithData data) => GeneralSettings(
    workspaceDirectory: data.get(
      #workspaceDirectory,
      or: $value.workspaceDirectory,
    ),
    starClicked: data.get(#starClicked, or: $value.starClicked),
    confirmProjectRemoval: data.get(
      #confirmProjectRemoval,
      or: $value.confirmProjectRemoval,
    ),
    confirmWorkspaceRemoval: data.get(
      #confirmWorkspaceRemoval,
      or: $value.confirmWorkspaceRemoval,
    ),
    agentStatusHooks: data.get(#agentStatusHooks, or: $value.agentStatusHooks),
    agentStatusNotificationsEnabled: data.get(
      #agentStatusNotificationsEnabled,
      or: $value.agentStatusNotificationsEnabled,
    ),
    keepComputerAwakeWhileAgentsWork: data.get(
      #keepComputerAwakeWhileAgentsWork,
      or: $value.keepComputerAwakeWhileAgentsWork,
    ),
  );

  @override
  GeneralSettingsCopyWith<$R2, GeneralSettings, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _GeneralSettingsCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class AleraSettingsMapper extends ClassMapperBase<AleraSettings> {
  AleraSettingsMapper._();

  static AleraSettingsMapper? _instance;
  static AleraSettingsMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = AleraSettingsMapper._());
      GeneralSettingsMapper.ensureInitialized();
      TerminalSettingsMapper.ensureInitialized();
      KeyboardShortcutSettingsMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'AleraSettings';

  static GeneralSettings _$general(AleraSettings v) => v.general;
  static const Field<AleraSettings, GeneralSettings> _f$general = Field(
    'general',
    _$general,
  );
  static TerminalSettings _$terminal(AleraSettings v) => v.terminal;
  static const Field<AleraSettings, TerminalSettings> _f$terminal = Field(
    'terminal',
    _$terminal,
  );
  static KeyboardShortcutSettings _$keyboard(AleraSettings v) => v.keyboard;
  static const Field<AleraSettings, KeyboardShortcutSettings> _f$keyboard =
      Field('keyboard', _$keyboard);

  @override
  final MappableFields<AleraSettings> fields = const {
    #general: _f$general,
    #terminal: _f$terminal,
    #keyboard: _f$keyboard,
  };

  static AleraSettings _instantiate(DecodingData data) {
    return AleraSettings(
      general: data.dec(_f$general),
      terminal: data.dec(_f$terminal),
      keyboard: data.dec(_f$keyboard),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static AleraSettings fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<AleraSettings>(map);
  }

  static AleraSettings fromJson(String json) {
    return ensureInitialized().decodeJson<AleraSettings>(json);
  }
}

mixin AleraSettingsMappable {
  String toJson() {
    return AleraSettingsMapper.ensureInitialized().encodeJson<AleraSettings>(
      this as AleraSettings,
    );
  }

  Map<String, dynamic> toMap() {
    return AleraSettingsMapper.ensureInitialized().encodeMap<AleraSettings>(
      this as AleraSettings,
    );
  }

  AleraSettingsCopyWith<AleraSettings, AleraSettings, AleraSettings>
  get copyWith => _AleraSettingsCopyWithImpl<AleraSettings, AleraSettings>(
    this as AleraSettings,
    $identity,
    $identity,
  );
  @override
  String toString() {
    return AleraSettingsMapper.ensureInitialized().stringifyValue(
      this as AleraSettings,
    );
  }

  @override
  bool operator ==(Object other) {
    return AleraSettingsMapper.ensureInitialized().equalsValue(
      this as AleraSettings,
      other,
    );
  }

  @override
  int get hashCode {
    return AleraSettingsMapper.ensureInitialized().hashValue(
      this as AleraSettings,
    );
  }
}

extension AleraSettingsValueCopy<$R, $Out>
    on ObjectCopyWith<$R, AleraSettings, $Out> {
  AleraSettingsCopyWith<$R, AleraSettings, $Out> get $asAleraSettings =>
      $base.as((v, t, t2) => _AleraSettingsCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class AleraSettingsCopyWith<$R, $In extends AleraSettings, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  GeneralSettingsCopyWith<$R, GeneralSettings, GeneralSettings> get general;
  TerminalSettingsCopyWith<$R, TerminalSettings, TerminalSettings> get terminal;
  KeyboardShortcutSettingsCopyWith<
    $R,
    KeyboardShortcutSettings,
    KeyboardShortcutSettings
  >
  get keyboard;
  $R call({
    GeneralSettings? general,
    TerminalSettings? terminal,
    KeyboardShortcutSettings? keyboard,
  });
  AleraSettingsCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _AleraSettingsCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, AleraSettings, $Out>
    implements AleraSettingsCopyWith<$R, AleraSettings, $Out> {
  _AleraSettingsCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<AleraSettings> $mapper =
      AleraSettingsMapper.ensureInitialized();
  @override
  GeneralSettingsCopyWith<$R, GeneralSettings, GeneralSettings> get general =>
      $value.general.copyWith.$chain((v) => call(general: v));
  @override
  TerminalSettingsCopyWith<$R, TerminalSettings, TerminalSettings>
  get terminal => $value.terminal.copyWith.$chain((v) => call(terminal: v));
  @override
  KeyboardShortcutSettingsCopyWith<
    $R,
    KeyboardShortcutSettings,
    KeyboardShortcutSettings
  >
  get keyboard => $value.keyboard.copyWith.$chain((v) => call(keyboard: v));
  @override
  $R call({
    GeneralSettings? general,
    TerminalSettings? terminal,
    KeyboardShortcutSettings? keyboard,
  }) => $apply(
    FieldCopyWithData({
      if (general != null) #general: general,
      if (terminal != null) #terminal: terminal,
      if (keyboard != null) #keyboard: keyboard,
    }),
  );
  @override
  AleraSettings $make(CopyWithData data) => AleraSettings(
    general: data.get(#general, or: $value.general),
    terminal: data.get(#terminal, or: $value.terminal),
    keyboard: data.get(#keyboard, or: $value.keyboard),
  );

  @override
  AleraSettingsCopyWith<$R2, AleraSettings, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _AleraSettingsCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

