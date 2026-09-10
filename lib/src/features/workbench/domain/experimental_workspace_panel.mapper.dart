// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'experimental_workspace_panel.dart';

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
      case r'experimental':
        return DesktopWorkspaceLayout.experimental;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(DesktopWorkspaceLayout self) {
    switch (self) {
      case DesktopWorkspaceLayout.classic:
        return r'classic';
      case DesktopWorkspaceLayout.experimental:
        return r'experimental';
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

class ExperimentalWorkspaceToolMapper
    extends EnumMapper<ExperimentalWorkspaceTool> {
  ExperimentalWorkspaceToolMapper._();

  static ExperimentalWorkspaceToolMapper? _instance;
  static ExperimentalWorkspaceToolMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = ExperimentalWorkspaceToolMapper._(),
      );
    }
    return _instance!;
  }

  static ExperimentalWorkspaceTool fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  ExperimentalWorkspaceTool decode(dynamic value) {
    switch (value) {
      case r'explorer':
        return ExperimentalWorkspaceTool.explorer;
      case r'search':
        return ExperimentalWorkspaceTool.search;
      case r'sourceControl':
        return ExperimentalWorkspaceTool.sourceControl;
      case r'pullRequest':
        return ExperimentalWorkspaceTool.pullRequest;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(ExperimentalWorkspaceTool self) {
    switch (self) {
      case ExperimentalWorkspaceTool.explorer:
        return r'explorer';
      case ExperimentalWorkspaceTool.search:
        return r'search';
      case ExperimentalWorkspaceTool.sourceControl:
        return r'sourceControl';
      case ExperimentalWorkspaceTool.pullRequest:
        return r'pullRequest';
    }
  }
}

extension ExperimentalWorkspaceToolMapperExtension
    on ExperimentalWorkspaceTool {
  String toValue() {
    ExperimentalWorkspaceToolMapper.ensureInitialized();
    return MapperContainer.globals.toValue<ExperimentalWorkspaceTool>(this)
        as String;
  }
}

class ExperimentalWorkspacePanelMapper
    extends ClassMapperBase<ExperimentalWorkspacePanel> {
  ExperimentalWorkspacePanelMapper._();

  static ExperimentalWorkspacePanelMapper? _instance;
  static ExperimentalWorkspacePanelMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = ExperimentalWorkspacePanelMapper._(),
      );
      WorkbenchLayoutMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ExperimentalWorkspacePanel';

  static String? _$primaryTabId(ExperimentalWorkspacePanel v) => v.primaryTabId;
  static const Field<ExperimentalWorkspacePanel, String> _f$primaryTabId =
      Field('primaryTabId', _$primaryTabId, opt: true);
  static List<String> _$tabKeys(ExperimentalWorkspacePanel v) => v.tabKeys;
  static const Field<ExperimentalWorkspacePanel, List<String>> _f$tabKeys =
      Field('tabKeys', _$tabKeys, opt: true, def: const <String>[]);
  static String? _$activeKey(ExperimentalWorkspacePanel v) => v.activeKey;
  static const Field<ExperimentalWorkspacePanel, String> _f$activeKey = Field(
    'activeKey',
    _$activeKey,
    opt: true,
  );
  static String? _$focusedKey(ExperimentalWorkspacePanel v) => v.focusedKey;
  static const Field<ExperimentalWorkspacePanel, String> _f$focusedKey = Field(
    'focusedKey',
    _$focusedKey,
    opt: true,
  );
  static WorkbenchLayout? _$paneLayout(ExperimentalWorkspacePanel v) =>
      v.paneLayout;
  static const Field<ExperimentalWorkspacePanel, WorkbenchLayout>
  _f$paneLayout = Field('paneLayout', _$paneLayout, opt: true);

  @override
  final MappableFields<ExperimentalWorkspacePanel> fields = const {
    #primaryTabId: _f$primaryTabId,
    #tabKeys: _f$tabKeys,
    #activeKey: _f$activeKey,
    #focusedKey: _f$focusedKey,
    #paneLayout: _f$paneLayout,
  };

  static ExperimentalWorkspacePanel _instantiate(DecodingData data) {
    return ExperimentalWorkspacePanel(
      primaryTabId: data.dec(_f$primaryTabId),
      tabKeys: data.dec(_f$tabKeys),
      activeKey: data.dec(_f$activeKey),
      focusedKey: data.dec(_f$focusedKey),
      paneLayout: data.dec(_f$paneLayout),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ExperimentalWorkspacePanel fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ExperimentalWorkspacePanel>(map);
  }

  static ExperimentalWorkspacePanel fromJson(String json) {
    return ensureInitialized().decodeJson<ExperimentalWorkspacePanel>(json);
  }
}

mixin ExperimentalWorkspacePanelMappable {
  String toJson() {
    return ExperimentalWorkspacePanelMapper.ensureInitialized()
        .encodeJson<ExperimentalWorkspacePanel>(
          this as ExperimentalWorkspacePanel,
        );
  }

  Map<String, dynamic> toMap() {
    return ExperimentalWorkspacePanelMapper.ensureInitialized()
        .encodeMap<ExperimentalWorkspacePanel>(
          this as ExperimentalWorkspacePanel,
        );
  }

  ExperimentalWorkspacePanelCopyWith<
    ExperimentalWorkspacePanel,
    ExperimentalWorkspacePanel,
    ExperimentalWorkspacePanel
  >
  get copyWith =>
      _ExperimentalWorkspacePanelCopyWithImpl<
        ExperimentalWorkspacePanel,
        ExperimentalWorkspacePanel
      >(this as ExperimentalWorkspacePanel, $identity, $identity);
  @override
  String toString() {
    return ExperimentalWorkspacePanelMapper.ensureInitialized().stringifyValue(
      this as ExperimentalWorkspacePanel,
    );
  }

  @override
  bool operator ==(Object other) {
    return ExperimentalWorkspacePanelMapper.ensureInitialized().equalsValue(
      this as ExperimentalWorkspacePanel,
      other,
    );
  }

  @override
  int get hashCode {
    return ExperimentalWorkspacePanelMapper.ensureInitialized().hashValue(
      this as ExperimentalWorkspacePanel,
    );
  }
}

extension ExperimentalWorkspacePanelValueCopy<$R, $Out>
    on ObjectCopyWith<$R, ExperimentalWorkspacePanel, $Out> {
  ExperimentalWorkspacePanelCopyWith<$R, ExperimentalWorkspacePanel, $Out>
  get $asExperimentalWorkspacePanel => $base.as(
    (v, t, t2) => _ExperimentalWorkspacePanelCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class ExperimentalWorkspacePanelCopyWith<
  $R,
  $In extends ExperimentalWorkspacePanel,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get tabKeys;
  WorkbenchLayoutCopyWith<$R, WorkbenchLayout, WorkbenchLayout>? get paneLayout;
  $R call({
    String? primaryTabId,
    List<String>? tabKeys,
    String? activeKey,
    String? focusedKey,
    WorkbenchLayout? paneLayout,
  });
  ExperimentalWorkspacePanelCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _ExperimentalWorkspacePanelCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, ExperimentalWorkspacePanel, $Out>
    implements
        ExperimentalWorkspacePanelCopyWith<
          $R,
          ExperimentalWorkspacePanel,
          $Out
        > {
  _ExperimentalWorkspacePanelCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<ExperimentalWorkspacePanel> $mapper =
      ExperimentalWorkspacePanelMapper.ensureInitialized();
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get tabKeys =>
      ListCopyWith(
        $value.tabKeys,
        (v, t) => ObjectCopyWith(v, $identity, t),
        (v) => call(tabKeys: v),
      );
  @override
  WorkbenchLayoutCopyWith<$R, WorkbenchLayout, WorkbenchLayout>?
  get paneLayout =>
      $value.paneLayout?.copyWith.$chain((v) => call(paneLayout: v));
  @override
  $R call({
    Object? primaryTabId = $none,
    List<String>? tabKeys,
    Object? activeKey = $none,
    Object? focusedKey = $none,
    Object? paneLayout = $none,
  }) => $apply(
    FieldCopyWithData({
      if (primaryTabId != $none) #primaryTabId: primaryTabId,
      if (tabKeys != null) #tabKeys: tabKeys,
      if (activeKey != $none) #activeKey: activeKey,
      if (focusedKey != $none) #focusedKey: focusedKey,
      if (paneLayout != $none) #paneLayout: paneLayout,
    }),
  );
  @override
  ExperimentalWorkspacePanel $make(CopyWithData data) =>
      ExperimentalWorkspacePanel(
        primaryTabId: data.get(#primaryTabId, or: $value.primaryTabId),
        tabKeys: data.get(#tabKeys, or: $value.tabKeys),
        activeKey: data.get(#activeKey, or: $value.activeKey),
        focusedKey: data.get(#focusedKey, or: $value.focusedKey),
        paneLayout: data.get(#paneLayout, or: $value.paneLayout),
      );

  @override
  ExperimentalWorkspacePanelCopyWith<$R2, ExperimentalWorkspacePanel, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _ExperimentalWorkspacePanelCopyWithImpl<$R2, $Out2>($value, $cast, t);
}
