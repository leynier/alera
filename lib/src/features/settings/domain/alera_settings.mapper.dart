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

class DiagnosticsLogLevelMapper extends EnumMapper<DiagnosticsLogLevel> {
  DiagnosticsLogLevelMapper._();

  static DiagnosticsLogLevelMapper? _instance;
  static DiagnosticsLogLevelMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = DiagnosticsLogLevelMapper._());
    }
    return _instance!;
  }

  static DiagnosticsLogLevel fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  DiagnosticsLogLevel decode(dynamic value) {
    switch (value) {
      case r'error':
        return DiagnosticsLogLevel.error;
      case r'warning':
        return DiagnosticsLogLevel.warning;
      case r'info':
        return DiagnosticsLogLevel.info;
      case r'debug':
        return DiagnosticsLogLevel.debug;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(DiagnosticsLogLevel self) {
    switch (self) {
      case DiagnosticsLogLevel.error:
        return r'error';
      case DiagnosticsLogLevel.warning:
        return r'warning';
      case DiagnosticsLogLevel.info:
        return r'info';
      case DiagnosticsLogLevel.debug:
        return r'debug';
    }
  }
}

extension DiagnosticsLogLevelMapperExtension on DiagnosticsLogLevel {
  String toValue() {
    DiagnosticsLogLevelMapper.ensureInitialized();
    return MapperContainer.globals.toValue<DiagnosticsLogLevel>(this) as String;
  }
}

class AgentQuotaProviderIdMapper extends EnumMapper<AgentQuotaProviderId> {
  AgentQuotaProviderIdMapper._();

  static AgentQuotaProviderIdMapper? _instance;
  static AgentQuotaProviderIdMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = AgentQuotaProviderIdMapper._());
    }
    return _instance!;
  }

  static AgentQuotaProviderId fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  AgentQuotaProviderId decode(dynamic value) {
    switch (value) {
      case r'claude':
        return AgentQuotaProviderId.claude;
      case r'codex':
        return AgentQuotaProviderId.codex;
      case r'kimi':
        return AgentQuotaProviderId.kimi;
      case r'grok':
        return AgentQuotaProviderId.grok;
      case r'cursor':
        return AgentQuotaProviderId.cursor;
      case r'antigravity':
        return AgentQuotaProviderId.antigravity;
      case r'minimax':
        return AgentQuotaProviderId.minimax;
      case r'zai':
        return AgentQuotaProviderId.zai;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(AgentQuotaProviderId self) {
    switch (self) {
      case AgentQuotaProviderId.claude:
        return r'claude';
      case AgentQuotaProviderId.codex:
        return r'codex';
      case AgentQuotaProviderId.kimi:
        return r'kimi';
      case AgentQuotaProviderId.grok:
        return r'grok';
      case AgentQuotaProviderId.cursor:
        return r'cursor';
      case AgentQuotaProviderId.antigravity:
        return r'antigravity';
      case AgentQuotaProviderId.minimax:
        return r'minimax';
      case AgentQuotaProviderId.zai:
        return r'zai';
    }
  }
}

extension AgentQuotaProviderIdMapperExtension on AgentQuotaProviderId {
  String toValue() {
    AgentQuotaProviderIdMapper.ensureInitialized();
    return MapperContainer.globals.toValue<AgentQuotaProviderId>(this)
        as String;
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
  static int _$tuiScrollSensitivity(TerminalSettings v) =>
      v.tuiScrollSensitivity;
  static const Field<TerminalSettings, int> _f$tuiScrollSensitivity = Field(
    'tuiScrollSensitivity',
    _$tuiScrollSensitivity,
    opt: true,
    def: 1,
  );
  static bool _$clipboardOnSelect(TerminalSettings v) => v.clipboardOnSelect;
  static const Field<TerminalSettings, bool> _f$clipboardOnSelect = Field(
    'clipboardOnSelect',
    _$clipboardOnSelect,
    opt: true,
    def: false,
  );
  static bool _$allowOsc52Clipboard(TerminalSettings v) =>
      v.allowOsc52Clipboard;
  static const Field<TerminalSettings, bool> _f$allowOsc52Clipboard = Field(
    'allowOsc52Clipboard',
    _$allowOsc52Clipboard,
    opt: true,
    def: false,
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
  static int _$bufferBudgetMegabytes(TerminalSettings v) =>
      v.bufferBudgetMegabytes;
  static const Field<TerminalSettings, int> _f$bufferBudgetMegabytes = Field(
    'bufferBudgetMegabytes',
    _$bufferBudgetMegabytes,
    opt: true,
    def: 256,
  );
  static bool _$keepRuntimeOpenOnAppQuit(TerminalSettings v) =>
      v.keepRuntimeOpenOnAppQuit;
  static const Field<TerminalSettings, bool> _f$keepRuntimeOpenOnAppQuit =
      Field(
        'keepRuntimeOpenOnAppQuit',
        _$keepRuntimeOpenOnAppQuit,
        opt: true,
        def: false,
      );
  static bool? _$loginShell(TerminalSettings v) => v.loginShell;
  static const Field<TerminalSettings, bool> _f$loginShell = Field(
    'loginShell',
    _$loginShell,
    opt: true,
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
    #tuiScrollSensitivity: _f$tuiScrollSensitivity,
    #clipboardOnSelect: _f$clipboardOnSelect,
    #allowOsc52Clipboard: _f$allowOsc52Clipboard,
    #hostEmptyShutdownDelaySeconds: _f$hostEmptyShutdownDelaySeconds,
    #hostDetachedSessionShutdownDelaySeconds:
        _f$hostDetachedSessionShutdownDelaySeconds,
    #hostScrollbackBytes: _f$hostScrollbackBytes,
    #bufferBudgetMegabytes: _f$bufferBudgetMegabytes,
    #keepRuntimeOpenOnAppQuit: _f$keepRuntimeOpenOnAppQuit,
    #loginShell: _f$loginShell,
  };

  @override
  final MappingHook hook = const _LegacyKeepRuntimeOpenHook();
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
      tuiScrollSensitivity: data.dec(_f$tuiScrollSensitivity),
      clipboardOnSelect: data.dec(_f$clipboardOnSelect),
      allowOsc52Clipboard: data.dec(_f$allowOsc52Clipboard),
      hostEmptyShutdownDelaySeconds: data.dec(_f$hostEmptyShutdownDelaySeconds),
      hostDetachedSessionShutdownDelaySeconds: data.dec(
        _f$hostDetachedSessionShutdownDelaySeconds,
      ),
      hostScrollbackBytes: data.dec(_f$hostScrollbackBytes),
      bufferBudgetMegabytes: data.dec(_f$bufferBudgetMegabytes),
      keepRuntimeOpenOnAppQuit: data.dec(_f$keepRuntimeOpenOnAppQuit),
      loginShell: data.dec(_f$loginShell),
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
    int? tuiScrollSensitivity,
    bool? clipboardOnSelect,
    bool? allowOsc52Clipboard,
    int? hostEmptyShutdownDelaySeconds,
    int? hostDetachedSessionShutdownDelaySeconds,
    int? hostScrollbackBytes,
    int? bufferBudgetMegabytes,
    bool? keepRuntimeOpenOnAppQuit,
    bool? loginShell,
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
    int? tuiScrollSensitivity,
    bool? clipboardOnSelect,
    bool? allowOsc52Clipboard,
    int? hostEmptyShutdownDelaySeconds,
    int? hostDetachedSessionShutdownDelaySeconds,
    int? hostScrollbackBytes,
    int? bufferBudgetMegabytes,
    bool? keepRuntimeOpenOnAppQuit,
    Object? loginShell = $none,
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
      if (tuiScrollSensitivity != null)
        #tuiScrollSensitivity: tuiScrollSensitivity,
      if (clipboardOnSelect != null) #clipboardOnSelect: clipboardOnSelect,
      if (allowOsc52Clipboard != null)
        #allowOsc52Clipboard: allowOsc52Clipboard,
      if (hostEmptyShutdownDelaySeconds != null)
        #hostEmptyShutdownDelaySeconds: hostEmptyShutdownDelaySeconds,
      if (hostDetachedSessionShutdownDelaySeconds != null)
        #hostDetachedSessionShutdownDelaySeconds:
            hostDetachedSessionShutdownDelaySeconds,
      if (hostScrollbackBytes != null)
        #hostScrollbackBytes: hostScrollbackBytes,
      if (bufferBudgetMegabytes != null)
        #bufferBudgetMegabytes: bufferBudgetMegabytes,
      if (keepRuntimeOpenOnAppQuit != null)
        #keepRuntimeOpenOnAppQuit: keepRuntimeOpenOnAppQuit,
      if (loginShell != $none) #loginShell: loginShell,
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
    tuiScrollSensitivity: data.get(
      #tuiScrollSensitivity,
      or: $value.tuiScrollSensitivity,
    ),
    clipboardOnSelect: data.get(
      #clipboardOnSelect,
      or: $value.clipboardOnSelect,
    ),
    allowOsc52Clipboard: data.get(
      #allowOsc52Clipboard,
      or: $value.allowOsc52Clipboard,
    ),
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
    bufferBudgetMegabytes: data.get(
      #bufferBudgetMegabytes,
      or: $value.bufferBudgetMegabytes,
    ),
    keepRuntimeOpenOnAppQuit: data.get(
      #keepRuntimeOpenOnAppQuit,
      or: $value.keepRuntimeOpenOnAppQuit,
    ),
    loginShell: data.get(#loginShell, or: $value.loginShell),
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
  static bool _$grok(AgentStatusHookSettings v) => v.grok;
  static const Field<AgentStatusHookSettings, bool> _f$grok = Field(
    'grok',
    _$grok,
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
    #grok: _f$grok,
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
      grok: data.dec(_f$grok),
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
    bool? grok,
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
    bool? grok,
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
      if (grok != null) #grok: grok,
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
    grok: data.get(#grok, or: $value.grok),
  );

  @override
  AgentStatusHookSettingsCopyWith<$R2, AgentStatusHookSettings, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _AgentStatusHookSettingsCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class EditorSettingsMapper extends ClassMapperBase<EditorSettings> {
  EditorSettingsMapper._();

  static EditorSettingsMapper? _instance;
  static EditorSettingsMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = EditorSettingsMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'EditorSettings';

  static int _$tabSize(EditorSettings v) => v.tabSize;
  static const Field<EditorSettings, int> _f$tabSize = Field(
    'tabSize',
    _$tabSize,
    opt: true,
    def: 4,
  );
  static String _$themeName(EditorSettings v) => v.themeName;
  static const Field<EditorSettings, String> _f$themeName = Field(
    'themeName',
    _$themeName,
    opt: true,
    def: EditorSyntaxThemeNames.alera,
  );
  static bool _$autosaveEnabled(EditorSettings v) => v.autosaveEnabled;
  static const Field<EditorSettings, bool> _f$autosaveEnabled = Field(
    'autosaveEnabled',
    _$autosaveEnabled,
    opt: true,
    def: false,
  );
  static int _$autosaveDelaySeconds(EditorSettings v) => v.autosaveDelaySeconds;
  static const Field<EditorSettings, int> _f$autosaveDelaySeconds = Field(
    'autosaveDelaySeconds',
    _$autosaveDelaySeconds,
    opt: true,
    def: EditorSettings.defaultAutosaveDelaySeconds,
  );

  @override
  final MappableFields<EditorSettings> fields = const {
    #tabSize: _f$tabSize,
    #themeName: _f$themeName,
    #autosaveEnabled: _f$autosaveEnabled,
    #autosaveDelaySeconds: _f$autosaveDelaySeconds,
  };

  static EditorSettings _instantiate(DecodingData data) {
    return EditorSettings(
      tabSize: data.dec(_f$tabSize),
      themeName: data.dec(_f$themeName),
      autosaveEnabled: data.dec(_f$autosaveEnabled),
      autosaveDelaySeconds: data.dec(_f$autosaveDelaySeconds),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static EditorSettings fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<EditorSettings>(map);
  }

  static EditorSettings fromJson(String json) {
    return ensureInitialized().decodeJson<EditorSettings>(json);
  }
}

mixin EditorSettingsMappable {
  String toJson() {
    return EditorSettingsMapper.ensureInitialized().encodeJson<EditorSettings>(
      this as EditorSettings,
    );
  }

  Map<String, dynamic> toMap() {
    return EditorSettingsMapper.ensureInitialized().encodeMap<EditorSettings>(
      this as EditorSettings,
    );
  }

  EditorSettingsCopyWith<EditorSettings, EditorSettings, EditorSettings>
  get copyWith => _EditorSettingsCopyWithImpl<EditorSettings, EditorSettings>(
    this as EditorSettings,
    $identity,
    $identity,
  );
  @override
  String toString() {
    return EditorSettingsMapper.ensureInitialized().stringifyValue(
      this as EditorSettings,
    );
  }

  @override
  bool operator ==(Object other) {
    return EditorSettingsMapper.ensureInitialized().equalsValue(
      this as EditorSettings,
      other,
    );
  }

  @override
  int get hashCode {
    return EditorSettingsMapper.ensureInitialized().hashValue(
      this as EditorSettings,
    );
  }
}

extension EditorSettingsValueCopy<$R, $Out>
    on ObjectCopyWith<$R, EditorSettings, $Out> {
  EditorSettingsCopyWith<$R, EditorSettings, $Out> get $asEditorSettings =>
      $base.as((v, t, t2) => _EditorSettingsCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class EditorSettingsCopyWith<$R, $In extends EditorSettings, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    int? tabSize,
    String? themeName,
    bool? autosaveEnabled,
    int? autosaveDelaySeconds,
  });
  EditorSettingsCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _EditorSettingsCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, EditorSettings, $Out>
    implements EditorSettingsCopyWith<$R, EditorSettings, $Out> {
  _EditorSettingsCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<EditorSettings> $mapper =
      EditorSettingsMapper.ensureInitialized();
  @override
  $R call({
    int? tabSize,
    String? themeName,
    bool? autosaveEnabled,
    int? autosaveDelaySeconds,
  }) => $apply(
    FieldCopyWithData({
      if (tabSize != null) #tabSize: tabSize,
      if (themeName != null) #themeName: themeName,
      if (autosaveEnabled != null) #autosaveEnabled: autosaveEnabled,
      if (autosaveDelaySeconds != null)
        #autosaveDelaySeconds: autosaveDelaySeconds,
    }),
  );
  @override
  EditorSettings $make(CopyWithData data) => EditorSettings(
    tabSize: data.get(#tabSize, or: $value.tabSize),
    themeName: data.get(#themeName, or: $value.themeName),
    autosaveEnabled: data.get(#autosaveEnabled, or: $value.autosaveEnabled),
    autosaveDelaySeconds: data.get(
      #autosaveDelaySeconds,
      or: $value.autosaveDelaySeconds,
    ),
  );

  @override
  EditorSettingsCopyWith<$R2, EditorSettings, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _EditorSettingsCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class GeneralSettingsMapper extends ClassMapperBase<GeneralSettings> {
  GeneralSettingsMapper._();

  static GeneralSettingsMapper? _instance;
  static GeneralSettingsMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = GeneralSettingsMapper._());
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

  @override
  final MappableFields<GeneralSettings> fields = const {
    #workspaceDirectory: _f$workspaceDirectory,
    #starClicked: _f$starClicked,
    #confirmProjectRemoval: _f$confirmProjectRemoval,
    #confirmWorkspaceRemoval: _f$confirmWorkspaceRemoval,
  };

  static GeneralSettings _instantiate(DecodingData data) {
    return GeneralSettings(
      workspaceDirectory: data.dec(_f$workspaceDirectory),
      starClicked: data.dec(_f$starClicked),
      confirmProjectRemoval: data.dec(_f$confirmProjectRemoval),
      confirmWorkspaceRemoval: data.dec(_f$confirmWorkspaceRemoval),
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
  $R call({
    String? workspaceDirectory,
    bool? starClicked,
    bool? confirmProjectRemoval,
    bool? confirmWorkspaceRemoval,
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
  $R call({
    Object? workspaceDirectory = $none,
    bool? starClicked,
    bool? confirmProjectRemoval,
    bool? confirmWorkspaceRemoval,
  }) => $apply(
    FieldCopyWithData({
      if (workspaceDirectory != $none) #workspaceDirectory: workspaceDirectory,
      if (starClicked != null) #starClicked: starClicked,
      if (confirmProjectRemoval != null)
        #confirmProjectRemoval: confirmProjectRemoval,
      if (confirmWorkspaceRemoval != null)
        #confirmWorkspaceRemoval: confirmWorkspaceRemoval,
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
  );

  @override
  GeneralSettingsCopyWith<$R2, GeneralSettings, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _GeneralSettingsCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class AgentSettingsMapper extends ClassMapperBase<AgentSettings> {
  AgentSettingsMapper._();

  static AgentSettingsMapper? _instance;
  static AgentSettingsMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = AgentSettingsMapper._());
      AgentStatusHookSettingsMapper.ensureInitialized();
      AgentQuotaSettingsMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'AgentSettings';

  static AgentStatusHookSettings _$agentStatusHooks(AgentSettings v) =>
      v.agentStatusHooks;
  static const Field<AgentSettings, AgentStatusHookSettings>
  _f$agentStatusHooks = Field(
    'agentStatusHooks',
    _$agentStatusHooks,
    opt: true,
    def: AgentStatusHookSettings.defaults,
  );
  static bool _$agentStatusNotificationsEnabled(AgentSettings v) =>
      v.agentStatusNotificationsEnabled;
  static const Field<AgentSettings, bool> _f$agentStatusNotificationsEnabled =
      Field(
        'agentStatusNotificationsEnabled',
        _$agentStatusNotificationsEnabled,
        opt: true,
        def: false,
      );
  static bool _$agentStatusFinishedNotificationsEnabled(AgentSettings v) =>
      v.agentStatusFinishedNotificationsEnabled;
  static const Field<AgentSettings, bool>
  _f$agentStatusFinishedNotificationsEnabled = Field(
    'agentStatusFinishedNotificationsEnabled',
    _$agentStatusFinishedNotificationsEnabled,
    opt: true,
    def: false,
  );
  static bool _$keepComputerAwakeWhileAgentsWork(AgentSettings v) =>
      v.keepComputerAwakeWhileAgentsWork;
  static const Field<AgentSettings, bool> _f$keepComputerAwakeWhileAgentsWork =
      Field(
        'keepComputerAwakeWhileAgentsWork',
        _$keepComputerAwakeWhileAgentsWork,
        opt: true,
        def: false,
      );
  static String? _$defaultAgentProfileId(AgentSettings v) =>
      v.defaultAgentProfileId;
  static const Field<AgentSettings, String> _f$defaultAgentProfileId = Field(
    'defaultAgentProfileId',
    _$defaultAgentProfileId,
    opt: true,
  );
  static AgentQuotaSettings _$quotas(AgentSettings v) => v.quotas;
  static const Field<AgentSettings, AgentQuotaSettings> _f$quotas = Field(
    'quotas',
    _$quotas,
    opt: true,
    def: AgentQuotaSettings.defaults,
  );

  @override
  final MappableFields<AgentSettings> fields = const {
    #agentStatusHooks: _f$agentStatusHooks,
    #agentStatusNotificationsEnabled: _f$agentStatusNotificationsEnabled,
    #agentStatusFinishedNotificationsEnabled:
        _f$agentStatusFinishedNotificationsEnabled,
    #keepComputerAwakeWhileAgentsWork: _f$keepComputerAwakeWhileAgentsWork,
    #defaultAgentProfileId: _f$defaultAgentProfileId,
    #quotas: _f$quotas,
  };

  static AgentSettings _instantiate(DecodingData data) {
    return AgentSettings(
      agentStatusHooks: data.dec(_f$agentStatusHooks),
      agentStatusNotificationsEnabled: data.dec(
        _f$agentStatusNotificationsEnabled,
      ),
      agentStatusFinishedNotificationsEnabled: data.dec(
        _f$agentStatusFinishedNotificationsEnabled,
      ),
      keepComputerAwakeWhileAgentsWork: data.dec(
        _f$keepComputerAwakeWhileAgentsWork,
      ),
      defaultAgentProfileId: data.dec(_f$defaultAgentProfileId),
      quotas: data.dec(_f$quotas),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static AgentSettings fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<AgentSettings>(map);
  }

  static AgentSettings fromJson(String json) {
    return ensureInitialized().decodeJson<AgentSettings>(json);
  }
}

mixin AgentSettingsMappable {
  String toJson() {
    return AgentSettingsMapper.ensureInitialized().encodeJson<AgentSettings>(
      this as AgentSettings,
    );
  }

  Map<String, dynamic> toMap() {
    return AgentSettingsMapper.ensureInitialized().encodeMap<AgentSettings>(
      this as AgentSettings,
    );
  }

  AgentSettingsCopyWith<AgentSettings, AgentSettings, AgentSettings>
  get copyWith => _AgentSettingsCopyWithImpl<AgentSettings, AgentSettings>(
    this as AgentSettings,
    $identity,
    $identity,
  );
  @override
  String toString() {
    return AgentSettingsMapper.ensureInitialized().stringifyValue(
      this as AgentSettings,
    );
  }

  @override
  bool operator ==(Object other) {
    return AgentSettingsMapper.ensureInitialized().equalsValue(
      this as AgentSettings,
      other,
    );
  }

  @override
  int get hashCode {
    return AgentSettingsMapper.ensureInitialized().hashValue(
      this as AgentSettings,
    );
  }
}

extension AgentSettingsValueCopy<$R, $Out>
    on ObjectCopyWith<$R, AgentSettings, $Out> {
  AgentSettingsCopyWith<$R, AgentSettings, $Out> get $asAgentSettings =>
      $base.as((v, t, t2) => _AgentSettingsCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class AgentSettingsCopyWith<$R, $In extends AgentSettings, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  AgentStatusHookSettingsCopyWith<
    $R,
    AgentStatusHookSettings,
    AgentStatusHookSettings
  >
  get agentStatusHooks;
  AgentQuotaSettingsCopyWith<$R, AgentQuotaSettings, AgentQuotaSettings>
  get quotas;
  $R call({
    AgentStatusHookSettings? agentStatusHooks,
    bool? agentStatusNotificationsEnabled,
    bool? agentStatusFinishedNotificationsEnabled,
    bool? keepComputerAwakeWhileAgentsWork,
    String? defaultAgentProfileId,
    AgentQuotaSettings? quotas,
  });
  AgentSettingsCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _AgentSettingsCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, AgentSettings, $Out>
    implements AgentSettingsCopyWith<$R, AgentSettings, $Out> {
  _AgentSettingsCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<AgentSettings> $mapper =
      AgentSettingsMapper.ensureInitialized();
  @override
  AgentStatusHookSettingsCopyWith<
    $R,
    AgentStatusHookSettings,
    AgentStatusHookSettings
  >
  get agentStatusHooks =>
      $value.agentStatusHooks.copyWith.$chain((v) => call(agentStatusHooks: v));
  @override
  AgentQuotaSettingsCopyWith<$R, AgentQuotaSettings, AgentQuotaSettings>
  get quotas => $value.quotas.copyWith.$chain((v) => call(quotas: v));
  @override
  $R call({
    AgentStatusHookSettings? agentStatusHooks,
    bool? agentStatusNotificationsEnabled,
    bool? agentStatusFinishedNotificationsEnabled,
    bool? keepComputerAwakeWhileAgentsWork,
    Object? defaultAgentProfileId = $none,
    AgentQuotaSettings? quotas,
  }) => $apply(
    FieldCopyWithData({
      if (agentStatusHooks != null) #agentStatusHooks: agentStatusHooks,
      if (agentStatusNotificationsEnabled != null)
        #agentStatusNotificationsEnabled: agentStatusNotificationsEnabled,
      if (agentStatusFinishedNotificationsEnabled != null)
        #agentStatusFinishedNotificationsEnabled:
            agentStatusFinishedNotificationsEnabled,
      if (keepComputerAwakeWhileAgentsWork != null)
        #keepComputerAwakeWhileAgentsWork: keepComputerAwakeWhileAgentsWork,
      if (defaultAgentProfileId != $none)
        #defaultAgentProfileId: defaultAgentProfileId,
      if (quotas != null) #quotas: quotas,
    }),
  );
  @override
  AgentSettings $make(CopyWithData data) => AgentSettings(
    agentStatusHooks: data.get(#agentStatusHooks, or: $value.agentStatusHooks),
    agentStatusNotificationsEnabled: data.get(
      #agentStatusNotificationsEnabled,
      or: $value.agentStatusNotificationsEnabled,
    ),
    agentStatusFinishedNotificationsEnabled: data.get(
      #agentStatusFinishedNotificationsEnabled,
      or: $value.agentStatusFinishedNotificationsEnabled,
    ),
    keepComputerAwakeWhileAgentsWork: data.get(
      #keepComputerAwakeWhileAgentsWork,
      or: $value.keepComputerAwakeWhileAgentsWork,
    ),
    defaultAgentProfileId: data.get(
      #defaultAgentProfileId,
      or: $value.defaultAgentProfileId,
    ),
    quotas: data.get(#quotas, or: $value.quotas),
  );

  @override
  AgentSettingsCopyWith<$R2, AgentSettings, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _AgentSettingsCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class AgentQuotaSettingsMapper extends ClassMapperBase<AgentQuotaSettings> {
  AgentQuotaSettingsMapper._();

  static AgentQuotaSettingsMapper? _instance;
  static AgentQuotaSettingsMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = AgentQuotaSettingsMapper._());
      AgentQuotaHostSettingsMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'AgentQuotaSettings';

  static Map<String, AgentQuotaHostSettings> _$hosts(AgentQuotaSettings v) =>
      v.hosts;
  static const Field<AgentQuotaSettings, Map<String, AgentQuotaHostSettings>>
  _f$hosts = Field(
    'hosts',
    _$hosts,
    opt: true,
    def: const <String, AgentQuotaHostSettings>{},
  );

  @override
  final MappableFields<AgentQuotaSettings> fields = const {#hosts: _f$hosts};

  static AgentQuotaSettings _instantiate(DecodingData data) {
    return AgentQuotaSettings(hosts: data.dec(_f$hosts));
  }

  @override
  final Function instantiate = _instantiate;

  static AgentQuotaSettings fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<AgentQuotaSettings>(map);
  }

  static AgentQuotaSettings fromJson(String json) {
    return ensureInitialized().decodeJson<AgentQuotaSettings>(json);
  }
}

mixin AgentQuotaSettingsMappable {
  String toJson() {
    return AgentQuotaSettingsMapper.ensureInitialized()
        .encodeJson<AgentQuotaSettings>(this as AgentQuotaSettings);
  }

  Map<String, dynamic> toMap() {
    return AgentQuotaSettingsMapper.ensureInitialized()
        .encodeMap<AgentQuotaSettings>(this as AgentQuotaSettings);
  }

  AgentQuotaSettingsCopyWith<
    AgentQuotaSettings,
    AgentQuotaSettings,
    AgentQuotaSettings
  >
  get copyWith =>
      _AgentQuotaSettingsCopyWithImpl<AgentQuotaSettings, AgentQuotaSettings>(
        this as AgentQuotaSettings,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return AgentQuotaSettingsMapper.ensureInitialized().stringifyValue(
      this as AgentQuotaSettings,
    );
  }

  @override
  bool operator ==(Object other) {
    return AgentQuotaSettingsMapper.ensureInitialized().equalsValue(
      this as AgentQuotaSettings,
      other,
    );
  }

  @override
  int get hashCode {
    return AgentQuotaSettingsMapper.ensureInitialized().hashValue(
      this as AgentQuotaSettings,
    );
  }
}

extension AgentQuotaSettingsValueCopy<$R, $Out>
    on ObjectCopyWith<$R, AgentQuotaSettings, $Out> {
  AgentQuotaSettingsCopyWith<$R, AgentQuotaSettings, $Out>
  get $asAgentQuotaSettings => $base.as(
    (v, t, t2) => _AgentQuotaSettingsCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class AgentQuotaSettingsCopyWith<
  $R,
  $In extends AgentQuotaSettings,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  MapCopyWith<
    $R,
    String,
    AgentQuotaHostSettings,
    AgentQuotaHostSettingsCopyWith<
      $R,
      AgentQuotaHostSettings,
      AgentQuotaHostSettings
    >
  >
  get hosts;
  $R call({Map<String, AgentQuotaHostSettings>? hosts});
  AgentQuotaSettingsCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _AgentQuotaSettingsCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, AgentQuotaSettings, $Out>
    implements AgentQuotaSettingsCopyWith<$R, AgentQuotaSettings, $Out> {
  _AgentQuotaSettingsCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<AgentQuotaSettings> $mapper =
      AgentQuotaSettingsMapper.ensureInitialized();
  @override
  MapCopyWith<
    $R,
    String,
    AgentQuotaHostSettings,
    AgentQuotaHostSettingsCopyWith<
      $R,
      AgentQuotaHostSettings,
      AgentQuotaHostSettings
    >
  >
  get hosts => MapCopyWith(
    $value.hosts,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(hosts: v),
  );
  @override
  $R call({Map<String, AgentQuotaHostSettings>? hosts}) =>
      $apply(FieldCopyWithData({if (hosts != null) #hosts: hosts}));
  @override
  AgentQuotaSettings $make(CopyWithData data) =>
      AgentQuotaSettings(hosts: data.get(#hosts, or: $value.hosts));

  @override
  AgentQuotaSettingsCopyWith<$R2, AgentQuotaSettings, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _AgentQuotaSettingsCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class AgentQuotaHostSettingsMapper
    extends ClassMapperBase<AgentQuotaHostSettings> {
  AgentQuotaHostSettingsMapper._();

  static AgentQuotaHostSettingsMapper? _instance;
  static AgentQuotaHostSettingsMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = AgentQuotaHostSettingsMapper._());
      AgentQuotaProviderIdMapper.ensureInitialized();
      ClaudeQuotaProfileSettingsMapper.ensureInitialized();
      AgentQuotaEnvironmentSettingsMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'AgentQuotaHostSettings';

  static List<AgentQuotaProviderId> _$enabledProviders(
    AgentQuotaHostSettings v,
  ) => v.enabledProviders;
  static const Field<AgentQuotaHostSettings, List<AgentQuotaProviderId>>
  _f$enabledProviders = Field(
    'enabledProviders',
    _$enabledProviders,
    opt: true,
    def: AgentQuotaProviderId.values,
  );
  static bool _$claudeDefaultEnabled(AgentQuotaHostSettings v) =>
      v.claudeDefaultEnabled;
  static const Field<AgentQuotaHostSettings, bool> _f$claudeDefaultEnabled =
      Field(
        'claudeDefaultEnabled',
        _$claudeDefaultEnabled,
        opt: true,
        def: true,
      );
  static List<ClaudeQuotaProfileSettings> _$claudeProfiles(
    AgentQuotaHostSettings v,
  ) => v.claudeProfiles;
  static const Field<AgentQuotaHostSettings, List<ClaudeQuotaProfileSettings>>
  _f$claudeProfiles = Field(
    'claudeProfiles',
    _$claudeProfiles,
    opt: true,
    def: const <ClaudeQuotaProfileSettings>[],
  );
  static String _$selectedClaudeProfile(AgentQuotaHostSettings v) =>
      v.selectedClaudeProfile;
  static const Field<AgentQuotaHostSettings, String> _f$selectedClaudeProfile =
      Field(
        'selectedClaudeProfile',
        _$selectedClaudeProfile,
        opt: true,
        def: 'default',
      );
  static AgentQuotaEnvironmentSettings _$environment(
    AgentQuotaHostSettings v,
  ) => v.environment;
  static const Field<AgentQuotaHostSettings, AgentQuotaEnvironmentSettings>
  _f$environment = Field(
    'environment',
    _$environment,
    opt: true,
    def: AgentQuotaEnvironmentSettings.defaults,
  );
  static List<String> _$unpinnedQuotaKeys(AgentQuotaHostSettings v) =>
      v.unpinnedQuotaKeys;
  static const Field<AgentQuotaHostSettings, List<String>>
  _f$unpinnedQuotaKeys = Field(
    'unpinnedQuotaKeys',
    _$unpinnedQuotaKeys,
    opt: true,
    def: const <String>[],
  );

  @override
  final MappableFields<AgentQuotaHostSettings> fields = const {
    #enabledProviders: _f$enabledProviders,
    #claudeDefaultEnabled: _f$claudeDefaultEnabled,
    #claudeProfiles: _f$claudeProfiles,
    #selectedClaudeProfile: _f$selectedClaudeProfile,
    #environment: _f$environment,
    #unpinnedQuotaKeys: _f$unpinnedQuotaKeys,
  };

  static AgentQuotaHostSettings _instantiate(DecodingData data) {
    return AgentQuotaHostSettings(
      enabledProviders: data.dec(_f$enabledProviders),
      claudeDefaultEnabled: data.dec(_f$claudeDefaultEnabled),
      claudeProfiles: data.dec(_f$claudeProfiles),
      selectedClaudeProfile: data.dec(_f$selectedClaudeProfile),
      environment: data.dec(_f$environment),
      unpinnedQuotaKeys: data.dec(_f$unpinnedQuotaKeys),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static AgentQuotaHostSettings fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<AgentQuotaHostSettings>(map);
  }

  static AgentQuotaHostSettings fromJson(String json) {
    return ensureInitialized().decodeJson<AgentQuotaHostSettings>(json);
  }
}

mixin AgentQuotaHostSettingsMappable {
  String toJson() {
    return AgentQuotaHostSettingsMapper.ensureInitialized()
        .encodeJson<AgentQuotaHostSettings>(this as AgentQuotaHostSettings);
  }

  Map<String, dynamic> toMap() {
    return AgentQuotaHostSettingsMapper.ensureInitialized()
        .encodeMap<AgentQuotaHostSettings>(this as AgentQuotaHostSettings);
  }

  AgentQuotaHostSettingsCopyWith<
    AgentQuotaHostSettings,
    AgentQuotaHostSettings,
    AgentQuotaHostSettings
  >
  get copyWith =>
      _AgentQuotaHostSettingsCopyWithImpl<
        AgentQuotaHostSettings,
        AgentQuotaHostSettings
      >(this as AgentQuotaHostSettings, $identity, $identity);
  @override
  String toString() {
    return AgentQuotaHostSettingsMapper.ensureInitialized().stringifyValue(
      this as AgentQuotaHostSettings,
    );
  }

  @override
  bool operator ==(Object other) {
    return AgentQuotaHostSettingsMapper.ensureInitialized().equalsValue(
      this as AgentQuotaHostSettings,
      other,
    );
  }

  @override
  int get hashCode {
    return AgentQuotaHostSettingsMapper.ensureInitialized().hashValue(
      this as AgentQuotaHostSettings,
    );
  }
}

extension AgentQuotaHostSettingsValueCopy<$R, $Out>
    on ObjectCopyWith<$R, AgentQuotaHostSettings, $Out> {
  AgentQuotaHostSettingsCopyWith<$R, AgentQuotaHostSettings, $Out>
  get $asAgentQuotaHostSettings => $base.as(
    (v, t, t2) => _AgentQuotaHostSettingsCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class AgentQuotaHostSettingsCopyWith<
  $R,
  $In extends AgentQuotaHostSettings,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<
    $R,
    AgentQuotaProviderId,
    ObjectCopyWith<$R, AgentQuotaProviderId, AgentQuotaProviderId>
  >
  get enabledProviders;
  ListCopyWith<
    $R,
    ClaudeQuotaProfileSettings,
    ClaudeQuotaProfileSettingsCopyWith<
      $R,
      ClaudeQuotaProfileSettings,
      ClaudeQuotaProfileSettings
    >
  >
  get claudeProfiles;
  AgentQuotaEnvironmentSettingsCopyWith<
    $R,
    AgentQuotaEnvironmentSettings,
    AgentQuotaEnvironmentSettings
  >
  get environment;
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>>
  get unpinnedQuotaKeys;
  $R call({
    List<AgentQuotaProviderId>? enabledProviders,
    bool? claudeDefaultEnabled,
    List<ClaudeQuotaProfileSettings>? claudeProfiles,
    String? selectedClaudeProfile,
    AgentQuotaEnvironmentSettings? environment,
    List<String>? unpinnedQuotaKeys,
  });
  AgentQuotaHostSettingsCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _AgentQuotaHostSettingsCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, AgentQuotaHostSettings, $Out>
    implements
        AgentQuotaHostSettingsCopyWith<$R, AgentQuotaHostSettings, $Out> {
  _AgentQuotaHostSettingsCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<AgentQuotaHostSettings> $mapper =
      AgentQuotaHostSettingsMapper.ensureInitialized();
  @override
  ListCopyWith<
    $R,
    AgentQuotaProviderId,
    ObjectCopyWith<$R, AgentQuotaProviderId, AgentQuotaProviderId>
  >
  get enabledProviders => ListCopyWith(
    $value.enabledProviders,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(enabledProviders: v),
  );
  @override
  ListCopyWith<
    $R,
    ClaudeQuotaProfileSettings,
    ClaudeQuotaProfileSettingsCopyWith<
      $R,
      ClaudeQuotaProfileSettings,
      ClaudeQuotaProfileSettings
    >
  >
  get claudeProfiles => ListCopyWith(
    $value.claudeProfiles,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(claudeProfiles: v),
  );
  @override
  AgentQuotaEnvironmentSettingsCopyWith<
    $R,
    AgentQuotaEnvironmentSettings,
    AgentQuotaEnvironmentSettings
  >
  get environment =>
      $value.environment.copyWith.$chain((v) => call(environment: v));
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>>
  get unpinnedQuotaKeys => ListCopyWith(
    $value.unpinnedQuotaKeys,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(unpinnedQuotaKeys: v),
  );
  @override
  $R call({
    List<AgentQuotaProviderId>? enabledProviders,
    bool? claudeDefaultEnabled,
    List<ClaudeQuotaProfileSettings>? claudeProfiles,
    String? selectedClaudeProfile,
    AgentQuotaEnvironmentSettings? environment,
    List<String>? unpinnedQuotaKeys,
  }) => $apply(
    FieldCopyWithData({
      if (enabledProviders != null) #enabledProviders: enabledProviders,
      if (claudeDefaultEnabled != null)
        #claudeDefaultEnabled: claudeDefaultEnabled,
      if (claudeProfiles != null) #claudeProfiles: claudeProfiles,
      if (selectedClaudeProfile != null)
        #selectedClaudeProfile: selectedClaudeProfile,
      if (environment != null) #environment: environment,
      if (unpinnedQuotaKeys != null) #unpinnedQuotaKeys: unpinnedQuotaKeys,
    }),
  );
  @override
  AgentQuotaHostSettings $make(CopyWithData data) => AgentQuotaHostSettings(
    enabledProviders: data.get(#enabledProviders, or: $value.enabledProviders),
    claudeDefaultEnabled: data.get(
      #claudeDefaultEnabled,
      or: $value.claudeDefaultEnabled,
    ),
    claudeProfiles: data.get(#claudeProfiles, or: $value.claudeProfiles),
    selectedClaudeProfile: data.get(
      #selectedClaudeProfile,
      or: $value.selectedClaudeProfile,
    ),
    environment: data.get(#environment, or: $value.environment),
    unpinnedQuotaKeys: data.get(
      #unpinnedQuotaKeys,
      or: $value.unpinnedQuotaKeys,
    ),
  );

  @override
  AgentQuotaHostSettingsCopyWith<$R2, AgentQuotaHostSettings, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _AgentQuotaHostSettingsCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class ClaudeQuotaProfileSettingsMapper
    extends ClassMapperBase<ClaudeQuotaProfileSettings> {
  ClaudeQuotaProfileSettingsMapper._();

  static ClaudeQuotaProfileSettingsMapper? _instance;
  static ClaudeQuotaProfileSettingsMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = ClaudeQuotaProfileSettingsMapper._(),
      );
    }
    return _instance!;
  }

  @override
  final String id = 'ClaudeQuotaProfileSettings';

  static String _$alias(ClaudeQuotaProfileSettings v) => v.alias;
  static const Field<ClaudeQuotaProfileSettings, String> _f$alias = Field(
    'alias',
    _$alias,
  );
  static String _$profile(ClaudeQuotaProfileSettings v) => v.profile;
  static const Field<ClaudeQuotaProfileSettings, String> _f$profile = Field(
    'profile',
    _$profile,
  );

  @override
  final MappableFields<ClaudeQuotaProfileSettings> fields = const {
    #alias: _f$alias,
    #profile: _f$profile,
  };

  static ClaudeQuotaProfileSettings _instantiate(DecodingData data) {
    return ClaudeQuotaProfileSettings(
      alias: data.dec(_f$alias),
      profile: data.dec(_f$profile),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ClaudeQuotaProfileSettings fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ClaudeQuotaProfileSettings>(map);
  }

  static ClaudeQuotaProfileSettings fromJson(String json) {
    return ensureInitialized().decodeJson<ClaudeQuotaProfileSettings>(json);
  }
}

mixin ClaudeQuotaProfileSettingsMappable {
  String toJson() {
    return ClaudeQuotaProfileSettingsMapper.ensureInitialized()
        .encodeJson<ClaudeQuotaProfileSettings>(
          this as ClaudeQuotaProfileSettings,
        );
  }

  Map<String, dynamic> toMap() {
    return ClaudeQuotaProfileSettingsMapper.ensureInitialized()
        .encodeMap<ClaudeQuotaProfileSettings>(
          this as ClaudeQuotaProfileSettings,
        );
  }

  ClaudeQuotaProfileSettingsCopyWith<
    ClaudeQuotaProfileSettings,
    ClaudeQuotaProfileSettings,
    ClaudeQuotaProfileSettings
  >
  get copyWith =>
      _ClaudeQuotaProfileSettingsCopyWithImpl<
        ClaudeQuotaProfileSettings,
        ClaudeQuotaProfileSettings
      >(this as ClaudeQuotaProfileSettings, $identity, $identity);
  @override
  String toString() {
    return ClaudeQuotaProfileSettingsMapper.ensureInitialized().stringifyValue(
      this as ClaudeQuotaProfileSettings,
    );
  }

  @override
  bool operator ==(Object other) {
    return ClaudeQuotaProfileSettingsMapper.ensureInitialized().equalsValue(
      this as ClaudeQuotaProfileSettings,
      other,
    );
  }

  @override
  int get hashCode {
    return ClaudeQuotaProfileSettingsMapper.ensureInitialized().hashValue(
      this as ClaudeQuotaProfileSettings,
    );
  }
}

extension ClaudeQuotaProfileSettingsValueCopy<$R, $Out>
    on ObjectCopyWith<$R, ClaudeQuotaProfileSettings, $Out> {
  ClaudeQuotaProfileSettingsCopyWith<$R, ClaudeQuotaProfileSettings, $Out>
  get $asClaudeQuotaProfileSettings => $base.as(
    (v, t, t2) => _ClaudeQuotaProfileSettingsCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class ClaudeQuotaProfileSettingsCopyWith<
  $R,
  $In extends ClaudeQuotaProfileSettings,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({String? alias, String? profile});
  ClaudeQuotaProfileSettingsCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _ClaudeQuotaProfileSettingsCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, ClaudeQuotaProfileSettings, $Out>
    implements
        ClaudeQuotaProfileSettingsCopyWith<
          $R,
          ClaudeQuotaProfileSettings,
          $Out
        > {
  _ClaudeQuotaProfileSettingsCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<ClaudeQuotaProfileSettings> $mapper =
      ClaudeQuotaProfileSettingsMapper.ensureInitialized();
  @override
  $R call({String? alias, String? profile}) => $apply(
    FieldCopyWithData({
      if (alias != null) #alias: alias,
      if (profile != null) #profile: profile,
    }),
  );
  @override
  ClaudeQuotaProfileSettings $make(CopyWithData data) =>
      ClaudeQuotaProfileSettings(
        alias: data.get(#alias, or: $value.alias),
        profile: data.get(#profile, or: $value.profile),
      );

  @override
  ClaudeQuotaProfileSettingsCopyWith<$R2, ClaudeQuotaProfileSettings, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _ClaudeQuotaProfileSettingsCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class AgentQuotaEnvironmentSettingsMapper
    extends ClassMapperBase<AgentQuotaEnvironmentSettings> {
  AgentQuotaEnvironmentSettingsMapper._();

  static AgentQuotaEnvironmentSettingsMapper? _instance;
  static AgentQuotaEnvironmentSettingsMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = AgentQuotaEnvironmentSettingsMapper._(),
      );
    }
    return _instance!;
  }

  @override
  final String id = 'AgentQuotaEnvironmentSettings';

  static String _$kimiApiKey(AgentQuotaEnvironmentSettings v) => v.kimiApiKey;
  static const Field<AgentQuotaEnvironmentSettings, String> _f$kimiApiKey =
      Field('kimiApiKey', _$kimiApiKey, opt: true, def: 'KIMI_API_KEY');
  static String _$zaiApiKey(AgentQuotaEnvironmentSettings v) => v.zaiApiKey;
  static const Field<AgentQuotaEnvironmentSettings, String> _f$zaiApiKey =
      Field('zaiApiKey', _$zaiApiKey, opt: true, def: 'ZAI_API_KEY');
  static String _$zaiBaseUrl(AgentQuotaEnvironmentSettings v) => v.zaiBaseUrl;
  static const Field<AgentQuotaEnvironmentSettings, String> _f$zaiBaseUrl =
      Field('zaiBaseUrl', _$zaiBaseUrl, opt: true, def: 'ZAI_BASE_URL');
  static String _$minimaxApiKey(AgentQuotaEnvironmentSettings v) =>
      v.minimaxApiKey;
  static const Field<AgentQuotaEnvironmentSettings, String> _f$minimaxApiKey =
      Field(
        'minimaxApiKey',
        _$minimaxApiKey,
        opt: true,
        def: 'MINIMAX_API_KEY',
      );
  static String _$minimaxApiHost(AgentQuotaEnvironmentSettings v) =>
      v.minimaxApiHost;
  static const Field<AgentQuotaEnvironmentSettings, String> _f$minimaxApiHost =
      Field(
        'minimaxApiHost',
        _$minimaxApiHost,
        opt: true,
        def: 'MINIMAX_API_HOST',
      );

  @override
  final MappableFields<AgentQuotaEnvironmentSettings> fields = const {
    #kimiApiKey: _f$kimiApiKey,
    #zaiApiKey: _f$zaiApiKey,
    #zaiBaseUrl: _f$zaiBaseUrl,
    #minimaxApiKey: _f$minimaxApiKey,
    #minimaxApiHost: _f$minimaxApiHost,
  };

  static AgentQuotaEnvironmentSettings _instantiate(DecodingData data) {
    return AgentQuotaEnvironmentSettings(
      kimiApiKey: data.dec(_f$kimiApiKey),
      zaiApiKey: data.dec(_f$zaiApiKey),
      zaiBaseUrl: data.dec(_f$zaiBaseUrl),
      minimaxApiKey: data.dec(_f$minimaxApiKey),
      minimaxApiHost: data.dec(_f$minimaxApiHost),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static AgentQuotaEnvironmentSettings fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<AgentQuotaEnvironmentSettings>(map);
  }

  static AgentQuotaEnvironmentSettings fromJson(String json) {
    return ensureInitialized().decodeJson<AgentQuotaEnvironmentSettings>(json);
  }
}

mixin AgentQuotaEnvironmentSettingsMappable {
  String toJson() {
    return AgentQuotaEnvironmentSettingsMapper.ensureInitialized()
        .encodeJson<AgentQuotaEnvironmentSettings>(
          this as AgentQuotaEnvironmentSettings,
        );
  }

  Map<String, dynamic> toMap() {
    return AgentQuotaEnvironmentSettingsMapper.ensureInitialized()
        .encodeMap<AgentQuotaEnvironmentSettings>(
          this as AgentQuotaEnvironmentSettings,
        );
  }

  AgentQuotaEnvironmentSettingsCopyWith<
    AgentQuotaEnvironmentSettings,
    AgentQuotaEnvironmentSettings,
    AgentQuotaEnvironmentSettings
  >
  get copyWith =>
      _AgentQuotaEnvironmentSettingsCopyWithImpl<
        AgentQuotaEnvironmentSettings,
        AgentQuotaEnvironmentSettings
      >(this as AgentQuotaEnvironmentSettings, $identity, $identity);
  @override
  String toString() {
    return AgentQuotaEnvironmentSettingsMapper.ensureInitialized()
        .stringifyValue(this as AgentQuotaEnvironmentSettings);
  }

  @override
  bool operator ==(Object other) {
    return AgentQuotaEnvironmentSettingsMapper.ensureInitialized().equalsValue(
      this as AgentQuotaEnvironmentSettings,
      other,
    );
  }

  @override
  int get hashCode {
    return AgentQuotaEnvironmentSettingsMapper.ensureInitialized().hashValue(
      this as AgentQuotaEnvironmentSettings,
    );
  }
}

extension AgentQuotaEnvironmentSettingsValueCopy<$R, $Out>
    on ObjectCopyWith<$R, AgentQuotaEnvironmentSettings, $Out> {
  AgentQuotaEnvironmentSettingsCopyWith<$R, AgentQuotaEnvironmentSettings, $Out>
  get $asAgentQuotaEnvironmentSettings => $base.as(
    (v, t, t2) =>
        _AgentQuotaEnvironmentSettingsCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class AgentQuotaEnvironmentSettingsCopyWith<
  $R,
  $In extends AgentQuotaEnvironmentSettings,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    String? kimiApiKey,
    String? zaiApiKey,
    String? zaiBaseUrl,
    String? minimaxApiKey,
    String? minimaxApiHost,
  });
  AgentQuotaEnvironmentSettingsCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _AgentQuotaEnvironmentSettingsCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, AgentQuotaEnvironmentSettings, $Out>
    implements
        AgentQuotaEnvironmentSettingsCopyWith<
          $R,
          AgentQuotaEnvironmentSettings,
          $Out
        > {
  _AgentQuotaEnvironmentSettingsCopyWithImpl(
    super.value,
    super.then,
    super.then2,
  );

  @override
  late final ClassMapperBase<AgentQuotaEnvironmentSettings> $mapper =
      AgentQuotaEnvironmentSettingsMapper.ensureInitialized();
  @override
  $R call({
    String? kimiApiKey,
    String? zaiApiKey,
    String? zaiBaseUrl,
    String? minimaxApiKey,
    String? minimaxApiHost,
  }) => $apply(
    FieldCopyWithData({
      if (kimiApiKey != null) #kimiApiKey: kimiApiKey,
      if (zaiApiKey != null) #zaiApiKey: zaiApiKey,
      if (zaiBaseUrl != null) #zaiBaseUrl: zaiBaseUrl,
      if (minimaxApiKey != null) #minimaxApiKey: minimaxApiKey,
      if (minimaxApiHost != null) #minimaxApiHost: minimaxApiHost,
    }),
  );
  @override
  AgentQuotaEnvironmentSettings $make(CopyWithData data) =>
      AgentQuotaEnvironmentSettings(
        kimiApiKey: data.get(#kimiApiKey, or: $value.kimiApiKey),
        zaiApiKey: data.get(#zaiApiKey, or: $value.zaiApiKey),
        zaiBaseUrl: data.get(#zaiBaseUrl, or: $value.zaiBaseUrl),
        minimaxApiKey: data.get(#minimaxApiKey, or: $value.minimaxApiKey),
        minimaxApiHost: data.get(#minimaxApiHost, or: $value.minimaxApiHost),
      );

  @override
  AgentQuotaEnvironmentSettingsCopyWith<
    $R2,
    AgentQuotaEnvironmentSettings,
    $Out2
  >
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _AgentQuotaEnvironmentSettingsCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class DiagnosticsSettingsMapper extends ClassMapperBase<DiagnosticsSettings> {
  DiagnosticsSettingsMapper._();

  static DiagnosticsSettingsMapper? _instance;
  static DiagnosticsSettingsMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = DiagnosticsSettingsMapper._());
      DiagnosticsLogLevelMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'DiagnosticsSettings';

  static DiagnosticsLogLevel _$logLevel(DiagnosticsSettings v) => v.logLevel;
  static const Field<DiagnosticsSettings, DiagnosticsLogLevel> _f$logLevel =
      Field('logLevel', _$logLevel, opt: true, def: DiagnosticsLogLevel.info);
  static bool _$crashReportingEnabled(DiagnosticsSettings v) =>
      v.crashReportingEnabled;
  static const Field<DiagnosticsSettings, bool> _f$crashReportingEnabled =
      Field(
        'crashReportingEnabled',
        _$crashReportingEnabled,
        opt: true,
        def: false,
      );

  @override
  final MappableFields<DiagnosticsSettings> fields = const {
    #logLevel: _f$logLevel,
    #crashReportingEnabled: _f$crashReportingEnabled,
  };

  static DiagnosticsSettings _instantiate(DecodingData data) {
    return DiagnosticsSettings(
      logLevel: data.dec(_f$logLevel),
      crashReportingEnabled: data.dec(_f$crashReportingEnabled),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static DiagnosticsSettings fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<DiagnosticsSettings>(map);
  }

  static DiagnosticsSettings fromJson(String json) {
    return ensureInitialized().decodeJson<DiagnosticsSettings>(json);
  }
}

mixin DiagnosticsSettingsMappable {
  String toJson() {
    return DiagnosticsSettingsMapper.ensureInitialized()
        .encodeJson<DiagnosticsSettings>(this as DiagnosticsSettings);
  }

  Map<String, dynamic> toMap() {
    return DiagnosticsSettingsMapper.ensureInitialized()
        .encodeMap<DiagnosticsSettings>(this as DiagnosticsSettings);
  }

  DiagnosticsSettingsCopyWith<
    DiagnosticsSettings,
    DiagnosticsSettings,
    DiagnosticsSettings
  >
  get copyWith =>
      _DiagnosticsSettingsCopyWithImpl<
        DiagnosticsSettings,
        DiagnosticsSettings
      >(this as DiagnosticsSettings, $identity, $identity);
  @override
  String toString() {
    return DiagnosticsSettingsMapper.ensureInitialized().stringifyValue(
      this as DiagnosticsSettings,
    );
  }

  @override
  bool operator ==(Object other) {
    return DiagnosticsSettingsMapper.ensureInitialized().equalsValue(
      this as DiagnosticsSettings,
      other,
    );
  }

  @override
  int get hashCode {
    return DiagnosticsSettingsMapper.ensureInitialized().hashValue(
      this as DiagnosticsSettings,
    );
  }
}

extension DiagnosticsSettingsValueCopy<$R, $Out>
    on ObjectCopyWith<$R, DiagnosticsSettings, $Out> {
  DiagnosticsSettingsCopyWith<$R, DiagnosticsSettings, $Out>
  get $asDiagnosticsSettings => $base.as(
    (v, t, t2) => _DiagnosticsSettingsCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class DiagnosticsSettingsCopyWith<
  $R,
  $In extends DiagnosticsSettings,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({DiagnosticsLogLevel? logLevel, bool? crashReportingEnabled});
  DiagnosticsSettingsCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _DiagnosticsSettingsCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, DiagnosticsSettings, $Out>
    implements DiagnosticsSettingsCopyWith<$R, DiagnosticsSettings, $Out> {
  _DiagnosticsSettingsCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<DiagnosticsSettings> $mapper =
      DiagnosticsSettingsMapper.ensureInitialized();
  @override
  $R call({DiagnosticsLogLevel? logLevel, bool? crashReportingEnabled}) =>
      $apply(
        FieldCopyWithData({
          if (logLevel != null) #logLevel: logLevel,
          if (crashReportingEnabled != null)
            #crashReportingEnabled: crashReportingEnabled,
        }),
      );
  @override
  DiagnosticsSettings $make(CopyWithData data) => DiagnosticsSettings(
    logLevel: data.get(#logLevel, or: $value.logLevel),
    crashReportingEnabled: data.get(
      #crashReportingEnabled,
      or: $value.crashReportingEnabled,
    ),
  );

  @override
  DiagnosticsSettingsCopyWith<$R2, DiagnosticsSettings, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _DiagnosticsSettingsCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class AleraSettingsMapper extends ClassMapperBase<AleraSettings> {
  AleraSettingsMapper._();

  static AleraSettingsMapper? _instance;
  static AleraSettingsMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = AleraSettingsMapper._());
      GeneralSettingsMapper.ensureInitialized();
      AgentSettingsMapper.ensureInitialized();
      AiTextGenerationSettingsMapper.ensureInitialized();
      TextActionsSettingsMapper.ensureInitialized();
      EditorSettingsMapper.ensureInitialized();
      DiagnosticsSettingsMapper.ensureInitialized();
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
  static AgentSettings _$agents(AleraSettings v) => v.agents;
  static const Field<AleraSettings, AgentSettings> _f$agents = Field(
    'agents',
    _$agents,
    opt: true,
    def: AgentSettings.defaults,
  );
  static AiTextGenerationSettings _$aiTextGeneration(AleraSettings v) =>
      v.aiTextGeneration;
  static const Field<AleraSettings, AiTextGenerationSettings>
  _f$aiTextGeneration = Field(
    'aiTextGeneration',
    _$aiTextGeneration,
    opt: true,
    def: AiTextGenerationSettings.defaults,
  );
  static TextActionsSettings _$textActions(AleraSettings v) => v.textActions;
  static const Field<AleraSettings, TextActionsSettings> _f$textActions = Field(
    'textActions',
    _$textActions,
    opt: true,
    def: TextActionsSettings.defaults,
  );
  static EditorSettings _$editor(AleraSettings v) => v.editor;
  static const Field<AleraSettings, EditorSettings> _f$editor = Field(
    'editor',
    _$editor,
    opt: true,
    def: EditorSettings.defaults,
  );
  static DiagnosticsSettings _$diagnostics(AleraSettings v) => v.diagnostics;
  static const Field<AleraSettings, DiagnosticsSettings> _f$diagnostics = Field(
    'diagnostics',
    _$diagnostics,
    opt: true,
    def: DiagnosticsSettings.defaults,
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
    #agents: _f$agents,
    #aiTextGeneration: _f$aiTextGeneration,
    #textActions: _f$textActions,
    #editor: _f$editor,
    #diagnostics: _f$diagnostics,
    #terminal: _f$terminal,
    #keyboard: _f$keyboard,
  };

  @override
  final MappingHook hook = const _LegacyAgentSettingsHook();
  static AleraSettings _instantiate(DecodingData data) {
    return AleraSettings(
      general: data.dec(_f$general),
      agents: data.dec(_f$agents),
      aiTextGeneration: data.dec(_f$aiTextGeneration),
      textActions: data.dec(_f$textActions),
      editor: data.dec(_f$editor),
      diagnostics: data.dec(_f$diagnostics),
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
  AgentSettingsCopyWith<$R, AgentSettings, AgentSettings> get agents;
  AiTextGenerationSettingsCopyWith<
    $R,
    AiTextGenerationSettings,
    AiTextGenerationSettings
  >
  get aiTextGeneration;
  TextActionsSettingsCopyWith<$R, TextActionsSettings, TextActionsSettings>
  get textActions;
  EditorSettingsCopyWith<$R, EditorSettings, EditorSettings> get editor;
  DiagnosticsSettingsCopyWith<$R, DiagnosticsSettings, DiagnosticsSettings>
  get diagnostics;
  TerminalSettingsCopyWith<$R, TerminalSettings, TerminalSettings> get terminal;
  KeyboardShortcutSettingsCopyWith<
    $R,
    KeyboardShortcutSettings,
    KeyboardShortcutSettings
  >
  get keyboard;
  $R call({
    GeneralSettings? general,
    AgentSettings? agents,
    AiTextGenerationSettings? aiTextGeneration,
    TextActionsSettings? textActions,
    EditorSettings? editor,
    DiagnosticsSettings? diagnostics,
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
  AgentSettingsCopyWith<$R, AgentSettings, AgentSettings> get agents =>
      $value.agents.copyWith.$chain((v) => call(agents: v));
  @override
  AiTextGenerationSettingsCopyWith<
    $R,
    AiTextGenerationSettings,
    AiTextGenerationSettings
  >
  get aiTextGeneration =>
      $value.aiTextGeneration.copyWith.$chain((v) => call(aiTextGeneration: v));
  @override
  TextActionsSettingsCopyWith<$R, TextActionsSettings, TextActionsSettings>
  get textActions =>
      $value.textActions.copyWith.$chain((v) => call(textActions: v));
  @override
  EditorSettingsCopyWith<$R, EditorSettings, EditorSettings> get editor =>
      $value.editor.copyWith.$chain((v) => call(editor: v));
  @override
  DiagnosticsSettingsCopyWith<$R, DiagnosticsSettings, DiagnosticsSettings>
  get diagnostics =>
      $value.diagnostics.copyWith.$chain((v) => call(diagnostics: v));
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
    AgentSettings? agents,
    AiTextGenerationSettings? aiTextGeneration,
    TextActionsSettings? textActions,
    EditorSettings? editor,
    DiagnosticsSettings? diagnostics,
    TerminalSettings? terminal,
    KeyboardShortcutSettings? keyboard,
  }) => $apply(
    FieldCopyWithData({
      if (general != null) #general: general,
      if (agents != null) #agents: agents,
      if (aiTextGeneration != null) #aiTextGeneration: aiTextGeneration,
      if (textActions != null) #textActions: textActions,
      if (editor != null) #editor: editor,
      if (diagnostics != null) #diagnostics: diagnostics,
      if (terminal != null) #terminal: terminal,
      if (keyboard != null) #keyboard: keyboard,
    }),
  );
  @override
  AleraSettings $make(CopyWithData data) => AleraSettings(
    general: data.get(#general, or: $value.general),
    agents: data.get(#agents, or: $value.agents),
    aiTextGeneration: data.get(#aiTextGeneration, or: $value.aiTextGeneration),
    textActions: data.get(#textActions, or: $value.textActions),
    editor: data.get(#editor, or: $value.editor),
    diagnostics: data.get(#diagnostics, or: $value.diagnostics),
    terminal: data.get(#terminal, or: $value.terminal),
    keyboard: data.get(#keyboard, or: $value.keyboard),
  );

  @override
  AleraSettingsCopyWith<$R2, AleraSettings, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _AleraSettingsCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

