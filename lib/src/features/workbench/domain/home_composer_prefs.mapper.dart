// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'home_composer_prefs.dart';

class HomeComposerPrefsMapper extends ClassMapperBase<HomeComposerPrefs> {
  HomeComposerPrefsMapper._();

  static HomeComposerPrefsMapper? _instance;
  static HomeComposerPrefsMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = HomeComposerPrefsMapper._());
      HomeComposerProjectPrefsMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'HomeComposerPrefs';

  static String? _$projectId(HomeComposerPrefs v) => v.projectId;
  static const Field<HomeComposerPrefs, String> _f$projectId = Field(
    'projectId',
    _$projectId,
    opt: true,
  );
  static String? _$profileId(HomeComposerPrefs v) => v.profileId;
  static const Field<HomeComposerPrefs, String> _f$profileId = Field(
    'profileId',
    _$profileId,
    opt: true,
  );
  static String _$prompt(HomeComposerPrefs v) => v.prompt;
  static const Field<HomeComposerPrefs, String> _f$prompt = Field(
    'prompt',
    _$prompt,
    opt: true,
    def: '',
  );
  static Map<String, HomeComposerProjectPrefs> _$projects(
    HomeComposerPrefs v,
  ) => v.projects;
  static const Field<HomeComposerPrefs, Map<String, HomeComposerProjectPrefs>>
  _f$projects = Field(
    'projects',
    _$projects,
    opt: true,
    def: const <String, HomeComposerProjectPrefs>{},
  );

  @override
  final MappableFields<HomeComposerPrefs> fields = const {
    #projectId: _f$projectId,
    #profileId: _f$profileId,
    #prompt: _f$prompt,
    #projects: _f$projects,
  };

  static HomeComposerPrefs _instantiate(DecodingData data) {
    return HomeComposerPrefs(
      projectId: data.dec(_f$projectId),
      profileId: data.dec(_f$profileId),
      prompt: data.dec(_f$prompt),
      projects: data.dec(_f$projects),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static HomeComposerPrefs fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<HomeComposerPrefs>(map);
  }

  static HomeComposerPrefs fromJson(String json) {
    return ensureInitialized().decodeJson<HomeComposerPrefs>(json);
  }
}

mixin HomeComposerPrefsMappable {
  String toJson() {
    return HomeComposerPrefsMapper.ensureInitialized()
        .encodeJson<HomeComposerPrefs>(this as HomeComposerPrefs);
  }

  Map<String, dynamic> toMap() {
    return HomeComposerPrefsMapper.ensureInitialized()
        .encodeMap<HomeComposerPrefs>(this as HomeComposerPrefs);
  }

  HomeComposerPrefsCopyWith<
    HomeComposerPrefs,
    HomeComposerPrefs,
    HomeComposerPrefs
  >
  get copyWith =>
      _HomeComposerPrefsCopyWithImpl<HomeComposerPrefs, HomeComposerPrefs>(
        this as HomeComposerPrefs,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return HomeComposerPrefsMapper.ensureInitialized().stringifyValue(
      this as HomeComposerPrefs,
    );
  }

  @override
  bool operator ==(Object other) {
    return HomeComposerPrefsMapper.ensureInitialized().equalsValue(
      this as HomeComposerPrefs,
      other,
    );
  }

  @override
  int get hashCode {
    return HomeComposerPrefsMapper.ensureInitialized().hashValue(
      this as HomeComposerPrefs,
    );
  }
}

extension HomeComposerPrefsValueCopy<$R, $Out>
    on ObjectCopyWith<$R, HomeComposerPrefs, $Out> {
  HomeComposerPrefsCopyWith<$R, HomeComposerPrefs, $Out>
  get $asHomeComposerPrefs => $base.as(
    (v, t, t2) => _HomeComposerPrefsCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class HomeComposerPrefsCopyWith<
  $R,
  $In extends HomeComposerPrefs,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  MapCopyWith<
    $R,
    String,
    HomeComposerProjectPrefs,
    HomeComposerProjectPrefsCopyWith<
      $R,
      HomeComposerProjectPrefs,
      HomeComposerProjectPrefs
    >
  >
  get projects;
  $R call({
    String? projectId,
    String? profileId,
    String? prompt,
    Map<String, HomeComposerProjectPrefs>? projects,
  });
  HomeComposerPrefsCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _HomeComposerPrefsCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, HomeComposerPrefs, $Out>
    implements HomeComposerPrefsCopyWith<$R, HomeComposerPrefs, $Out> {
  _HomeComposerPrefsCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<HomeComposerPrefs> $mapper =
      HomeComposerPrefsMapper.ensureInitialized();
  @override
  MapCopyWith<
    $R,
    String,
    HomeComposerProjectPrefs,
    HomeComposerProjectPrefsCopyWith<
      $R,
      HomeComposerProjectPrefs,
      HomeComposerProjectPrefs
    >
  >
  get projects => MapCopyWith(
    $value.projects,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(projects: v),
  );
  @override
  $R call({
    Object? projectId = $none,
    Object? profileId = $none,
    String? prompt,
    Map<String, HomeComposerProjectPrefs>? projects,
  }) => $apply(
    FieldCopyWithData({
      if (projectId != $none) #projectId: projectId,
      if (profileId != $none) #profileId: profileId,
      if (prompt != null) #prompt: prompt,
      if (projects != null) #projects: projects,
    }),
  );
  @override
  HomeComposerPrefs $make(CopyWithData data) => HomeComposerPrefs(
    projectId: data.get(#projectId, or: $value.projectId),
    profileId: data.get(#profileId, or: $value.profileId),
    prompt: data.get(#prompt, or: $value.prompt),
    projects: data.get(#projects, or: $value.projects),
  );

  @override
  HomeComposerPrefsCopyWith<$R2, HomeComposerPrefs, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _HomeComposerPrefsCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class HomeComposerProjectPrefsMapper
    extends ClassMapperBase<HomeComposerProjectPrefs> {
  HomeComposerProjectPrefsMapper._();

  static HomeComposerProjectPrefsMapper? _instance;
  static HomeComposerProjectPrefsMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = HomeComposerProjectPrefsMapper._(),
      );
    }
    return _instance!;
  }

  @override
  final String id = 'HomeComposerProjectPrefs';

  static String? _$hostId(HomeComposerProjectPrefs v) => v.hostId;
  static const Field<HomeComposerProjectPrefs, String> _f$hostId = Field(
    'hostId',
    _$hostId,
    opt: true,
  );
  static String? _$parentWorkspaceId(HomeComposerProjectPrefs v) =>
      v.parentWorkspaceId;
  static const Field<HomeComposerProjectPrefs, String> _f$parentWorkspaceId =
      Field('parentWorkspaceId', _$parentWorkspaceId, opt: true);
  static bool _$useProjectCheckout(HomeComposerProjectPrefs v) =>
      v.useProjectCheckout;
  static const Field<HomeComposerProjectPrefs, bool> _f$useProjectCheckout =
      Field('useProjectCheckout', _$useProjectCheckout, opt: true, def: true);
  static String? _$sourceBranch(HomeComposerProjectPrefs v) => v.sourceBranch;
  static const Field<HomeComposerProjectPrefs, String> _f$sourceBranch = Field(
    'sourceBranch',
    _$sourceBranch,
    opt: true,
  );

  @override
  final MappableFields<HomeComposerProjectPrefs> fields = const {
    #hostId: _f$hostId,
    #parentWorkspaceId: _f$parentWorkspaceId,
    #useProjectCheckout: _f$useProjectCheckout,
    #sourceBranch: _f$sourceBranch,
  };

  static HomeComposerProjectPrefs _instantiate(DecodingData data) {
    return HomeComposerProjectPrefs(
      hostId: data.dec(_f$hostId),
      parentWorkspaceId: data.dec(_f$parentWorkspaceId),
      useProjectCheckout: data.dec(_f$useProjectCheckout),
      sourceBranch: data.dec(_f$sourceBranch),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static HomeComposerProjectPrefs fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<HomeComposerProjectPrefs>(map);
  }

  static HomeComposerProjectPrefs fromJson(String json) {
    return ensureInitialized().decodeJson<HomeComposerProjectPrefs>(json);
  }
}

mixin HomeComposerProjectPrefsMappable {
  String toJson() {
    return HomeComposerProjectPrefsMapper.ensureInitialized()
        .encodeJson<HomeComposerProjectPrefs>(this as HomeComposerProjectPrefs);
  }

  Map<String, dynamic> toMap() {
    return HomeComposerProjectPrefsMapper.ensureInitialized()
        .encodeMap<HomeComposerProjectPrefs>(this as HomeComposerProjectPrefs);
  }

  HomeComposerProjectPrefsCopyWith<
    HomeComposerProjectPrefs,
    HomeComposerProjectPrefs,
    HomeComposerProjectPrefs
  >
  get copyWith =>
      _HomeComposerProjectPrefsCopyWithImpl<
        HomeComposerProjectPrefs,
        HomeComposerProjectPrefs
      >(this as HomeComposerProjectPrefs, $identity, $identity);
  @override
  String toString() {
    return HomeComposerProjectPrefsMapper.ensureInitialized().stringifyValue(
      this as HomeComposerProjectPrefs,
    );
  }

  @override
  bool operator ==(Object other) {
    return HomeComposerProjectPrefsMapper.ensureInitialized().equalsValue(
      this as HomeComposerProjectPrefs,
      other,
    );
  }

  @override
  int get hashCode {
    return HomeComposerProjectPrefsMapper.ensureInitialized().hashValue(
      this as HomeComposerProjectPrefs,
    );
  }
}

extension HomeComposerProjectPrefsValueCopy<$R, $Out>
    on ObjectCopyWith<$R, HomeComposerProjectPrefs, $Out> {
  HomeComposerProjectPrefsCopyWith<$R, HomeComposerProjectPrefs, $Out>
  get $asHomeComposerProjectPrefs => $base.as(
    (v, t, t2) => _HomeComposerProjectPrefsCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class HomeComposerProjectPrefsCopyWith<
  $R,
  $In extends HomeComposerProjectPrefs,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    String? hostId,
    String? parentWorkspaceId,
    bool? useProjectCheckout,
    String? sourceBranch,
  });
  HomeComposerProjectPrefsCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _HomeComposerProjectPrefsCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, HomeComposerProjectPrefs, $Out>
    implements
        HomeComposerProjectPrefsCopyWith<$R, HomeComposerProjectPrefs, $Out> {
  _HomeComposerProjectPrefsCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<HomeComposerProjectPrefs> $mapper =
      HomeComposerProjectPrefsMapper.ensureInitialized();
  @override
  $R call({
    Object? hostId = $none,
    Object? parentWorkspaceId = $none,
    bool? useProjectCheckout,
    Object? sourceBranch = $none,
  }) => $apply(
    FieldCopyWithData({
      if (hostId != $none) #hostId: hostId,
      if (parentWorkspaceId != $none) #parentWorkspaceId: parentWorkspaceId,
      if (useProjectCheckout != null) #useProjectCheckout: useProjectCheckout,
      if (sourceBranch != $none) #sourceBranch: sourceBranch,
    }),
  );
  @override
  HomeComposerProjectPrefs $make(CopyWithData data) => HomeComposerProjectPrefs(
    hostId: data.get(#hostId, or: $value.hostId),
    parentWorkspaceId: data.get(
      #parentWorkspaceId,
      or: $value.parentWorkspaceId,
    ),
    useProjectCheckout: data.get(
      #useProjectCheckout,
      or: $value.useProjectCheckout,
    ),
    sourceBranch: data.get(#sourceBranch, or: $value.sourceBranch),
  );

  @override
  HomeComposerProjectPrefsCopyWith<$R2, HomeComposerProjectPrefs, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _HomeComposerProjectPrefsCopyWithImpl<$R2, $Out2>($value, $cast, t);
}
