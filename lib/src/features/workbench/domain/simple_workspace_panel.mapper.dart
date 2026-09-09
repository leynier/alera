// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'simple_workspace_panel.dart';

class DesktopWorkspaceLayoutMapper extends EnumMapper<DesktopWorkspaceLayout> {
  DesktopWorkspaceLayoutMapper._();

  static DesktopWorkspaceLayoutMapper? _instance;
  static DesktopWorkspaceLayoutMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = DesktopWorkspaceLayoutMapper._());
    }
    return _instance!;
  }

  static DesktopWorkspaceLayout fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  DesktopWorkspaceLayout decode(dynamic value) {
    switch (value) {
      case r'classic':
        return DesktopWorkspaceLayout.classic;
      case r'simple':
        return DesktopWorkspaceLayout.simple;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(DesktopWorkspaceLayout self) {
    switch (self) {
      case DesktopWorkspaceLayout.classic:
        return r'classic';
      case DesktopWorkspaceLayout.simple:
        return r'simple';
    }
  }
}

extension DesktopWorkspaceLayoutMapperExtension on DesktopWorkspaceLayout {
  String toValue() {
    DesktopWorkspaceLayoutMapper.ensureInitialized();
    return MapperContainer.globals.toValue<DesktopWorkspaceLayout>(this)
        as String;
  }
}

class SimpleWorkspaceToolMapper extends EnumMapper<SimpleWorkspaceTool> {
  SimpleWorkspaceToolMapper._();

  static SimpleWorkspaceToolMapper? _instance;
  static SimpleWorkspaceToolMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = SimpleWorkspaceToolMapper._());
    }
    return _instance!;
  }

  static SimpleWorkspaceTool fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  SimpleWorkspaceTool decode(dynamic value) {
    switch (value) {
      case r'explorer':
        return SimpleWorkspaceTool.explorer;
      case r'search':
        return SimpleWorkspaceTool.search;
      case r'sourceControl':
        return SimpleWorkspaceTool.sourceControl;
      case r'pullRequest':
        return SimpleWorkspaceTool.pullRequest;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(SimpleWorkspaceTool self) {
    switch (self) {
      case SimpleWorkspaceTool.explorer:
        return r'explorer';
      case SimpleWorkspaceTool.search:
        return r'search';
      case SimpleWorkspaceTool.sourceControl:
        return r'sourceControl';
      case SimpleWorkspaceTool.pullRequest:
        return r'pullRequest';
    }
  }
}

extension SimpleWorkspaceToolMapperExtension on SimpleWorkspaceTool {
  String toValue() {
    SimpleWorkspaceToolMapper.ensureInitialized();
    return MapperContainer.globals.toValue<SimpleWorkspaceTool>(this) as String;
  }
}

class SimpleWorkspacePanelMapper extends ClassMapperBase<SimpleWorkspacePanel> {
  SimpleWorkspacePanelMapper._();

  static SimpleWorkspacePanelMapper? _instance;
  static SimpleWorkspacePanelMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = SimpleWorkspacePanelMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'SimpleWorkspacePanel';

  static String? _$primaryTabId(SimpleWorkspacePanel v) => v.primaryTabId;
  static const Field<SimpleWorkspacePanel, String> _f$primaryTabId = Field(
    'primaryTabId',
    _$primaryTabId,
    opt: true,
  );
  static List<String> _$tabKeys(SimpleWorkspacePanel v) => v.tabKeys;
  static const Field<SimpleWorkspacePanel, List<String>> _f$tabKeys = Field(
    'tabKeys',
    _$tabKeys,
    opt: true,
    def: const <String>[],
  );
  static String? _$activeKey(SimpleWorkspacePanel v) => v.activeKey;
  static const Field<SimpleWorkspacePanel, String> _f$activeKey = Field(
    'activeKey',
    _$activeKey,
    opt: true,
  );
  static String? _$focusedKey(SimpleWorkspacePanel v) => v.focusedKey;
  static const Field<SimpleWorkspacePanel, String> _f$focusedKey = Field(
    'focusedKey',
    _$focusedKey,
    opt: true,
  );

  @override
  final MappableFields<SimpleWorkspacePanel> fields = const {
    #primaryTabId: _f$primaryTabId,
    #tabKeys: _f$tabKeys,
    #activeKey: _f$activeKey,
    #focusedKey: _f$focusedKey,
  };

  static SimpleWorkspacePanel _instantiate(DecodingData data) {
    return SimpleWorkspacePanel(
      primaryTabId: data.dec(_f$primaryTabId),
      tabKeys: data.dec(_f$tabKeys),
      activeKey: data.dec(_f$activeKey),
      focusedKey: data.dec(_f$focusedKey),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static SimpleWorkspacePanel fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<SimpleWorkspacePanel>(map);
  }

  static SimpleWorkspacePanel fromJson(String json) {
    return ensureInitialized().decodeJson<SimpleWorkspacePanel>(json);
  }
}

mixin SimpleWorkspacePanelMappable {
  String toJson() {
    return SimpleWorkspacePanelMapper.ensureInitialized()
        .encodeJson<SimpleWorkspacePanel>(this as SimpleWorkspacePanel);
  }

  Map<String, dynamic> toMap() {
    return SimpleWorkspacePanelMapper.ensureInitialized()
        .encodeMap<SimpleWorkspacePanel>(this as SimpleWorkspacePanel);
  }

  SimpleWorkspacePanelCopyWith<
    SimpleWorkspacePanel,
    SimpleWorkspacePanel,
    SimpleWorkspacePanel
  >
  get copyWith =>
      _SimpleWorkspacePanelCopyWithImpl<
        SimpleWorkspacePanel,
        SimpleWorkspacePanel
      >(this as SimpleWorkspacePanel, $identity, $identity);
  @override
  String toString() {
    return SimpleWorkspacePanelMapper.ensureInitialized().stringifyValue(
      this as SimpleWorkspacePanel,
    );
  }

  @override
  bool operator ==(Object other) {
    return SimpleWorkspacePanelMapper.ensureInitialized().equalsValue(
      this as SimpleWorkspacePanel,
      other,
    );
  }

  @override
  int get hashCode {
    return SimpleWorkspacePanelMapper.ensureInitialized().hashValue(
      this as SimpleWorkspacePanel,
    );
  }
}

extension SimpleWorkspacePanelValueCopy<$R, $Out>
    on ObjectCopyWith<$R, SimpleWorkspacePanel, $Out> {
  SimpleWorkspacePanelCopyWith<$R, SimpleWorkspacePanel, $Out>
  get $asSimpleWorkspacePanel => $base.as(
    (v, t, t2) => _SimpleWorkspacePanelCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class SimpleWorkspacePanelCopyWith<
  $R,
  $In extends SimpleWorkspacePanel,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get tabKeys;
  $R call({
    String? primaryTabId,
    List<String>? tabKeys,
    String? activeKey,
    String? focusedKey,
  });
  SimpleWorkspacePanelCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _SimpleWorkspacePanelCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, SimpleWorkspacePanel, $Out>
    implements SimpleWorkspacePanelCopyWith<$R, SimpleWorkspacePanel, $Out> {
  _SimpleWorkspacePanelCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<SimpleWorkspacePanel> $mapper =
      SimpleWorkspacePanelMapper.ensureInitialized();
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get tabKeys =>
      ListCopyWith(
        $value.tabKeys,
        (v, t) => ObjectCopyWith(v, $identity, t),
        (v) => call(tabKeys: v),
      );
  @override
  $R call({
    Object? primaryTabId = $none,
    List<String>? tabKeys,
    Object? activeKey = $none,
    Object? focusedKey = $none,
  }) => $apply(
    FieldCopyWithData({
      if (primaryTabId != $none) #primaryTabId: primaryTabId,
      if (tabKeys != null) #tabKeys: tabKeys,
      if (activeKey != $none) #activeKey: activeKey,
      if (focusedKey != $none) #focusedKey: focusedKey,
    }),
  );
  @override
  SimpleWorkspacePanel $make(CopyWithData data) => SimpleWorkspacePanel(
    primaryTabId: data.get(#primaryTabId, or: $value.primaryTabId),
    tabKeys: data.get(#tabKeys, or: $value.tabKeys),
    activeKey: data.get(#activeKey, or: $value.activeKey),
    focusedKey: data.get(#focusedKey, or: $value.focusedKey),
  );

  @override
  SimpleWorkspacePanelCopyWith<$R2, SimpleWorkspacePanel, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _SimpleWorkspacePanelCopyWithImpl<$R2, $Out2>($value, $cast, t);
}
