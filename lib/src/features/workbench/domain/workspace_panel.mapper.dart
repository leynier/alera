// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'workspace_panel.dart';

class WorkspaceToolMapper extends EnumMapper<WorkspaceTool> {
  WorkspaceToolMapper._();

  static WorkspaceToolMapper? _instance;
  static WorkspaceToolMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = WorkspaceToolMapper._());
    }
    return _instance!;
  }

  static WorkspaceTool fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  WorkspaceTool decode(dynamic value) {
    switch (value) {
      case r'explorer':
        return WorkspaceTool.explorer;
      case r'search':
        return WorkspaceTool.search;
      case r'sourceControl':
        return WorkspaceTool.sourceControl;
      case r'pullRequest':
        return WorkspaceTool.pullRequest;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(WorkspaceTool self) {
    switch (self) {
      case WorkspaceTool.explorer:
        return r'explorer';
      case WorkspaceTool.search:
        return r'search';
      case WorkspaceTool.sourceControl:
        return r'sourceControl';
      case WorkspaceTool.pullRequest:
        return r'pullRequest';
    }
  }
}

extension WorkspaceToolMapperExtension on WorkspaceTool {
  String toValue() {
    WorkspaceToolMapper.ensureInitialized();
    return MapperContainer.globals.toValue<WorkspaceTool>(this) as String;
  }
}

class WorkspacePanelMapper extends ClassMapperBase<WorkspacePanel> {
  WorkspacePanelMapper._();

  static WorkspacePanelMapper? _instance;
  static WorkspacePanelMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = WorkspacePanelMapper._());
      WorkbenchLayoutMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'WorkspacePanel';

  static String? _$primaryTabId(WorkspacePanel v) => v.primaryTabId;
  static const Field<WorkspacePanel, String> _f$primaryTabId = Field(
    'primaryTabId',
    _$primaryTabId,
    opt: true,
  );
  static List<String> _$tabKeys(WorkspacePanel v) => v.tabKeys;
  static const Field<WorkspacePanel, List<String>> _f$tabKeys = Field(
    'tabKeys',
    _$tabKeys,
    opt: true,
    def: const <String>[],
  );
  static String? _$activeKey(WorkspacePanel v) => v.activeKey;
  static const Field<WorkspacePanel, String> _f$activeKey = Field(
    'activeKey',
    _$activeKey,
    opt: true,
  );
  static String? _$focusedKey(WorkspacePanel v) => v.focusedKey;
  static const Field<WorkspacePanel, String> _f$focusedKey = Field(
    'focusedKey',
    _$focusedKey,
    opt: true,
  );
  static WorkbenchLayout? _$paneLayout(WorkspacePanel v) => v.paneLayout;
  static const Field<WorkspacePanel, WorkbenchLayout> _f$paneLayout = Field(
    'paneLayout',
    _$paneLayout,
    opt: true,
  );
  static WorkbenchLayout? _$mainLayout(WorkspacePanel v) => v.mainLayout;
  static const Field<WorkspacePanel, WorkbenchLayout> _f$mainLayout = Field(
    'mainLayout',
    _$mainLayout,
    opt: true,
  );

  @override
  final MappableFields<WorkspacePanel> fields = const {
    #primaryTabId: _f$primaryTabId,
    #tabKeys: _f$tabKeys,
    #activeKey: _f$activeKey,
    #focusedKey: _f$focusedKey,
    #paneLayout: _f$paneLayout,
    #mainLayout: _f$mainLayout,
  };

  static WorkspacePanel _instantiate(DecodingData data) {
    return WorkspacePanel(
      primaryTabId: data.dec(_f$primaryTabId),
      tabKeys: data.dec(_f$tabKeys),
      activeKey: data.dec(_f$activeKey),
      focusedKey: data.dec(_f$focusedKey),
      paneLayout: data.dec(_f$paneLayout),
      mainLayout: data.dec(_f$mainLayout),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static WorkspacePanel fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<WorkspacePanel>(map);
  }

  static WorkspacePanel fromJson(String json) {
    return ensureInitialized().decodeJson<WorkspacePanel>(json);
  }
}

mixin WorkspacePanelMappable {
  String toJson() {
    return WorkspacePanelMapper.ensureInitialized().encodeJson<WorkspacePanel>(
      this as WorkspacePanel,
    );
  }

  Map<String, dynamic> toMap() {
    return WorkspacePanelMapper.ensureInitialized().encodeMap<WorkspacePanel>(
      this as WorkspacePanel,
    );
  }

  WorkspacePanelCopyWith<WorkspacePanel, WorkspacePanel, WorkspacePanel>
  get copyWith => _WorkspacePanelCopyWithImpl<WorkspacePanel, WorkspacePanel>(
    this as WorkspacePanel,
    $identity,
    $identity,
  );
  @override
  String toString() {
    return WorkspacePanelMapper.ensureInitialized().stringifyValue(
      this as WorkspacePanel,
    );
  }

  @override
  bool operator ==(Object other) {
    return WorkspacePanelMapper.ensureInitialized().equalsValue(
      this as WorkspacePanel,
      other,
    );
  }

  @override
  int get hashCode {
    return WorkspacePanelMapper.ensureInitialized().hashValue(
      this as WorkspacePanel,
    );
  }
}

extension WorkspacePanelValueCopy<$R, $Out>
    on ObjectCopyWith<$R, WorkspacePanel, $Out> {
  WorkspacePanelCopyWith<$R, WorkspacePanel, $Out> get $asWorkspacePanel =>
      $base.as((v, t, t2) => _WorkspacePanelCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class WorkspacePanelCopyWith<$R, $In extends WorkspacePanel, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get tabKeys;
  WorkbenchLayoutCopyWith<$R, WorkbenchLayout, WorkbenchLayout>? get paneLayout;
  WorkbenchLayoutCopyWith<$R, WorkbenchLayout, WorkbenchLayout>? get mainLayout;
  $R call({
    String? primaryTabId,
    List<String>? tabKeys,
    String? activeKey,
    String? focusedKey,
    WorkbenchLayout? paneLayout,
    WorkbenchLayout? mainLayout,
  });
  WorkspacePanelCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _WorkspacePanelCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, WorkspacePanel, $Out>
    implements WorkspacePanelCopyWith<$R, WorkspacePanel, $Out> {
  _WorkspacePanelCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<WorkspacePanel> $mapper =
      WorkspacePanelMapper.ensureInitialized();
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
  WorkbenchLayoutCopyWith<$R, WorkbenchLayout, WorkbenchLayout>?
  get mainLayout =>
      $value.mainLayout?.copyWith.$chain((v) => call(mainLayout: v));
  @override
  $R call({
    Object? primaryTabId = $none,
    List<String>? tabKeys,
    Object? activeKey = $none,
    Object? focusedKey = $none,
    Object? paneLayout = $none,
    Object? mainLayout = $none,
  }) => $apply(
    FieldCopyWithData({
      if (primaryTabId != $none) #primaryTabId: primaryTabId,
      if (tabKeys != null) #tabKeys: tabKeys,
      if (activeKey != $none) #activeKey: activeKey,
      if (focusedKey != $none) #focusedKey: focusedKey,
      if (paneLayout != $none) #paneLayout: paneLayout,
      if (mainLayout != $none) #mainLayout: mainLayout,
    }),
  );
  @override
  WorkspacePanel $make(CopyWithData data) => WorkspacePanel(
    primaryTabId: data.get(#primaryTabId, or: $value.primaryTabId),
    tabKeys: data.get(#tabKeys, or: $value.tabKeys),
    activeKey: data.get(#activeKey, or: $value.activeKey),
    focusedKey: data.get(#focusedKey, or: $value.focusedKey),
    paneLayout: data.get(#paneLayout, or: $value.paneLayout),
    mainLayout: data.get(#mainLayout, or: $value.mainLayout),
  );

  @override
  WorkspacePanelCopyWith<$R2, WorkspacePanel, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _WorkspacePanelCopyWithImpl<$R2, $Out2>($value, $cast, t);
}
