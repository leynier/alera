// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'alera_update.dart';

class AleraUpdateChannelMapper extends EnumMapper<AleraUpdateChannel> {
  AleraUpdateChannelMapper._();

  static AleraUpdateChannelMapper? _instance;
  static AleraUpdateChannelMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = AleraUpdateChannelMapper._());
    }
    return _instance!;
  }

  static AleraUpdateChannel fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  AleraUpdateChannel decode(dynamic value) {
    switch (value) {
      case r'stable':
        return AleraUpdateChannel.stable;
      case r'rc':
        return AleraUpdateChannel.rc;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(AleraUpdateChannel self) {
    switch (self) {
      case AleraUpdateChannel.stable:
        return r'stable';
      case AleraUpdateChannel.rc:
        return r'rc';
    }
  }
}

extension AleraUpdateChannelMapperExtension on AleraUpdateChannel {
  String toValue() {
    AleraUpdateChannelMapper.ensureInitialized();
    return MapperContainer.globals.toValue<AleraUpdateChannel>(this) as String;
  }
}

class AleraUpdateStatusMapper extends EnumMapper<AleraUpdateStatus> {
  AleraUpdateStatusMapper._();

  static AleraUpdateStatusMapper? _instance;
  static AleraUpdateStatusMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = AleraUpdateStatusMapper._());
    }
    return _instance!;
  }

  static AleraUpdateStatus fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  AleraUpdateStatus decode(dynamic value) {
    switch (value) {
      case r'idle':
        return AleraUpdateStatus.idle;
      case r'checking':
        return AleraUpdateStatus.checking;
      case r'notAvailable':
        return AleraUpdateStatus.notAvailable;
      case r'manualDownloadRequired':
        return AleraUpdateStatus.manualDownloadRequired;
      case r'available':
        return AleraUpdateStatus.available;
      case r'downloading':
        return AleraUpdateStatus.downloading;
      case r'downloaded':
        return AleraUpdateStatus.downloaded;
      case r'error':
        return AleraUpdateStatus.error;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(AleraUpdateStatus self) {
    switch (self) {
      case AleraUpdateStatus.idle:
        return r'idle';
      case AleraUpdateStatus.checking:
        return r'checking';
      case AleraUpdateStatus.notAvailable:
        return r'notAvailable';
      case AleraUpdateStatus.manualDownloadRequired:
        return r'manualDownloadRequired';
      case AleraUpdateStatus.available:
        return r'available';
      case AleraUpdateStatus.downloading:
        return r'downloading';
      case AleraUpdateStatus.downloaded:
        return r'downloaded';
      case AleraUpdateStatus.error:
        return r'error';
    }
  }
}

extension AleraUpdateStatusMapperExtension on AleraUpdateStatus {
  String toValue() {
    AleraUpdateStatusMapper.ensureInitialized();
    return MapperContainer.globals.toValue<AleraUpdateStatus>(this) as String;
  }
}

class AleraUpdateConfigMapper extends ClassMapperBase<AleraUpdateConfig> {
  AleraUpdateConfigMapper._();

  static AleraUpdateConfigMapper? _instance;
  static AleraUpdateConfigMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = AleraUpdateConfigMapper._());
      AleraUpdateChannelMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'AleraUpdateConfig';

  static Uri _$archiveUrl(AleraUpdateConfig v) => v.archiveUrl;
  static const Field<AleraUpdateConfig, Uri> _f$archiveUrl = Field(
    'archiveUrl',
    _$archiveUrl,
    hook: _UriStringHook(),
  );
  static Uri _$releasePageUrl(AleraUpdateConfig v) => v.releasePageUrl;
  static const Field<AleraUpdateConfig, Uri> _f$releasePageUrl = Field(
    'releasePageUrl',
    _$releasePageUrl,
    hook: _UriStringHook(),
  );
  static AleraUpdateChannel _$channel(AleraUpdateConfig v) => v.channel;
  static const Field<AleraUpdateConfig, AleraUpdateChannel> _f$channel = Field(
    'channel',
    _$channel,
  );
  static bool _$autoInstallEnabled(AleraUpdateConfig v) => v.autoInstallEnabled;
  static const Field<AleraUpdateConfig, bool> _f$autoInstallEnabled = Field(
    'autoInstallEnabled',
    _$autoInstallEnabled,
  );
  static bool _$signedRelease(AleraUpdateConfig v) => v.signedRelease;
  static const Field<AleraUpdateConfig, bool> _f$signedRelease = Field(
    'signedRelease',
    _$signedRelease,
  );
  static String _$manifestPublicKey(AleraUpdateConfig v) => v.manifestPublicKey;
  static const Field<AleraUpdateConfig, String> _f$manifestPublicKey = Field(
    'manifestPublicKey',
    _$manifestPublicKey,
    opt: true,
    def: '',
  );

  @override
  final MappableFields<AleraUpdateConfig> fields = const {
    #archiveUrl: _f$archiveUrl,
    #releasePageUrl: _f$releasePageUrl,
    #channel: _f$channel,
    #autoInstallEnabled: _f$autoInstallEnabled,
    #signedRelease: _f$signedRelease,
    #manifestPublicKey: _f$manifestPublicKey,
  };

  static AleraUpdateConfig _instantiate(DecodingData data) {
    return AleraUpdateConfig(
      archiveUrl: data.dec(_f$archiveUrl),
      releasePageUrl: data.dec(_f$releasePageUrl),
      channel: data.dec(_f$channel),
      autoInstallEnabled: data.dec(_f$autoInstallEnabled),
      signedRelease: data.dec(_f$signedRelease),
      manifestPublicKey: data.dec(_f$manifestPublicKey),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static AleraUpdateConfig fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<AleraUpdateConfig>(map);
  }

  static AleraUpdateConfig fromJson(String json) {
    return ensureInitialized().decodeJson<AleraUpdateConfig>(json);
  }
}

mixin AleraUpdateConfigMappable {
  String toJson() {
    return AleraUpdateConfigMapper.ensureInitialized()
        .encodeJson<AleraUpdateConfig>(this as AleraUpdateConfig);
  }

  Map<String, dynamic> toMap() {
    return AleraUpdateConfigMapper.ensureInitialized()
        .encodeMap<AleraUpdateConfig>(this as AleraUpdateConfig);
  }

  AleraUpdateConfigCopyWith<
    AleraUpdateConfig,
    AleraUpdateConfig,
    AleraUpdateConfig
  >
  get copyWith =>
      _AleraUpdateConfigCopyWithImpl<AleraUpdateConfig, AleraUpdateConfig>(
        this as AleraUpdateConfig,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return AleraUpdateConfigMapper.ensureInitialized().stringifyValue(
      this as AleraUpdateConfig,
    );
  }

  @override
  bool operator ==(Object other) {
    return AleraUpdateConfigMapper.ensureInitialized().equalsValue(
      this as AleraUpdateConfig,
      other,
    );
  }

  @override
  int get hashCode {
    return AleraUpdateConfigMapper.ensureInitialized().hashValue(
      this as AleraUpdateConfig,
    );
  }
}

extension AleraUpdateConfigValueCopy<$R, $Out>
    on ObjectCopyWith<$R, AleraUpdateConfig, $Out> {
  AleraUpdateConfigCopyWith<$R, AleraUpdateConfig, $Out>
  get $asAleraUpdateConfig => $base.as(
    (v, t, t2) => _AleraUpdateConfigCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class AleraUpdateConfigCopyWith<
  $R,
  $In extends AleraUpdateConfig,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    Uri? archiveUrl,
    Uri? releasePageUrl,
    AleraUpdateChannel? channel,
    bool? autoInstallEnabled,
    bool? signedRelease,
    String? manifestPublicKey,
  });
  AleraUpdateConfigCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _AleraUpdateConfigCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, AleraUpdateConfig, $Out>
    implements AleraUpdateConfigCopyWith<$R, AleraUpdateConfig, $Out> {
  _AleraUpdateConfigCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<AleraUpdateConfig> $mapper =
      AleraUpdateConfigMapper.ensureInitialized();
  @override
  $R call({
    Uri? archiveUrl,
    Uri? releasePageUrl,
    AleraUpdateChannel? channel,
    bool? autoInstallEnabled,
    bool? signedRelease,
    String? manifestPublicKey,
  }) => $apply(
    FieldCopyWithData({
      if (archiveUrl != null) #archiveUrl: archiveUrl,
      if (releasePageUrl != null) #releasePageUrl: releasePageUrl,
      if (channel != null) #channel: channel,
      if (autoInstallEnabled != null) #autoInstallEnabled: autoInstallEnabled,
      if (signedRelease != null) #signedRelease: signedRelease,
      if (manifestPublicKey != null) #manifestPublicKey: manifestPublicKey,
    }),
  );
  @override
  AleraUpdateConfig $make(CopyWithData data) => AleraUpdateConfig(
    archiveUrl: data.get(#archiveUrl, or: $value.archiveUrl),
    releasePageUrl: data.get(#releasePageUrl, or: $value.releasePageUrl),
    channel: data.get(#channel, or: $value.channel),
    autoInstallEnabled: data.get(
      #autoInstallEnabled,
      or: $value.autoInstallEnabled,
    ),
    signedRelease: data.get(#signedRelease, or: $value.signedRelease),
    manifestPublicKey: data.get(
      #manifestPublicKey,
      or: $value.manifestPublicKey,
    ),
  );

  @override
  AleraUpdateConfigCopyWith<$R2, AleraUpdateConfig, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _AleraUpdateConfigCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class AleraUpdateInfoMapper extends ClassMapperBase<AleraUpdateInfo> {
  AleraUpdateInfoMapper._();

  static AleraUpdateInfoMapper? _instance;
  static AleraUpdateInfoMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = AleraUpdateInfoMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'AleraUpdateInfo';

  static String _$version(AleraUpdateInfo v) => v.version;
  static const Field<AleraUpdateInfo, String> _f$version = Field(
    'version',
    _$version,
  );
  static int _$shortVersion(AleraUpdateInfo v) => v.shortVersion;
  static const Field<AleraUpdateInfo, int> _f$shortVersion = Field(
    'shortVersion',
    _$shortVersion,
  );
  static String _$date(AleraUpdateInfo v) => v.date;
  static const Field<AleraUpdateInfo, String> _f$date = Field('date', _$date);
  static bool _$mandatory(AleraUpdateInfo v) => v.mandatory;
  static const Field<AleraUpdateInfo, bool> _f$mandatory = Field(
    'mandatory',
    _$mandatory,
  );
  static Uri _$url(AleraUpdateInfo v) => v.url;
  static const Field<AleraUpdateInfo, Uri> _f$url = Field(
    'url',
    _$url,
    hook: _UriStringHook(),
  );
  static String _$platform(AleraUpdateInfo v) => v.platform;
  static const Field<AleraUpdateInfo, String> _f$platform = Field(
    'platform',
    _$platform,
  );
  static List<String> _$changes(AleraUpdateInfo v) => v.changes;
  static const Field<AleraUpdateInfo, List<String>> _f$changes = Field(
    'changes',
    _$changes,
  );
  static String _$installerKind(AleraUpdateInfo v) => v.installerKind;
  static const Field<AleraUpdateInfo, String> _f$installerKind = Field(
    'installerKind',
    _$installerKind,
    opt: true,
    def: 'directory',
  );
  static String? _$sha256(AleraUpdateInfo v) => v.sha256;
  static const Field<AleraUpdateInfo, String> _f$sha256 = Field(
    'sha256',
    _$sha256,
    opt: true,
  );
  static int? _$size(AleraUpdateInfo v) => v.size;
  static const Field<AleraUpdateInfo, int> _f$size = Field(
    'size',
    _$size,
    opt: true,
  );
  static Uri? _$signatureBundleUrl(AleraUpdateInfo v) => v.signatureBundleUrl;
  static const Field<AleraUpdateInfo, Uri> _f$signatureBundleUrl = Field(
    'signatureBundleUrl',
    _$signatureBundleUrl,
    opt: true,
    hook: _UriStringHook(),
  );
  static Uri? _$provenanceUrl(AleraUpdateInfo v) => v.provenanceUrl;
  static const Field<AleraUpdateInfo, Uri> _f$provenanceUrl = Field(
    'provenanceUrl',
    _$provenanceUrl,
    opt: true,
    hook: _UriStringHook(),
  );

  @override
  final MappableFields<AleraUpdateInfo> fields = const {
    #version: _f$version,
    #shortVersion: _f$shortVersion,
    #date: _f$date,
    #mandatory: _f$mandatory,
    #url: _f$url,
    #platform: _f$platform,
    #changes: _f$changes,
    #installerKind: _f$installerKind,
    #sha256: _f$sha256,
    #size: _f$size,
    #signatureBundleUrl: _f$signatureBundleUrl,
    #provenanceUrl: _f$provenanceUrl,
  };

  static AleraUpdateInfo _instantiate(DecodingData data) {
    return AleraUpdateInfo(
      version: data.dec(_f$version),
      shortVersion: data.dec(_f$shortVersion),
      date: data.dec(_f$date),
      mandatory: data.dec(_f$mandatory),
      url: data.dec(_f$url),
      platform: data.dec(_f$platform),
      changes: data.dec(_f$changes),
      installerKind: data.dec(_f$installerKind),
      sha256: data.dec(_f$sha256),
      size: data.dec(_f$size),
      signatureBundleUrl: data.dec(_f$signatureBundleUrl),
      provenanceUrl: data.dec(_f$provenanceUrl),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static AleraUpdateInfo fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<AleraUpdateInfo>(map);
  }

  static AleraUpdateInfo fromJson(String json) {
    return ensureInitialized().decodeJson<AleraUpdateInfo>(json);
  }
}

mixin AleraUpdateInfoMappable {
  String toJson() {
    return AleraUpdateInfoMapper.ensureInitialized()
        .encodeJson<AleraUpdateInfo>(this as AleraUpdateInfo);
  }

  Map<String, dynamic> toMap() {
    return AleraUpdateInfoMapper.ensureInitialized().encodeMap<AleraUpdateInfo>(
      this as AleraUpdateInfo,
    );
  }

  AleraUpdateInfoCopyWith<AleraUpdateInfo, AleraUpdateInfo, AleraUpdateInfo>
  get copyWith =>
      _AleraUpdateInfoCopyWithImpl<AleraUpdateInfo, AleraUpdateInfo>(
        this as AleraUpdateInfo,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return AleraUpdateInfoMapper.ensureInitialized().stringifyValue(
      this as AleraUpdateInfo,
    );
  }

  @override
  bool operator ==(Object other) {
    return AleraUpdateInfoMapper.ensureInitialized().equalsValue(
      this as AleraUpdateInfo,
      other,
    );
  }

  @override
  int get hashCode {
    return AleraUpdateInfoMapper.ensureInitialized().hashValue(
      this as AleraUpdateInfo,
    );
  }
}

extension AleraUpdateInfoValueCopy<$R, $Out>
    on ObjectCopyWith<$R, AleraUpdateInfo, $Out> {
  AleraUpdateInfoCopyWith<$R, AleraUpdateInfo, $Out> get $asAleraUpdateInfo =>
      $base.as((v, t, t2) => _AleraUpdateInfoCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class AleraUpdateInfoCopyWith<$R, $In extends AleraUpdateInfo, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get changes;
  $R call({
    String? version,
    int? shortVersion,
    String? date,
    bool? mandatory,
    Uri? url,
    String? platform,
    List<String>? changes,
    String? installerKind,
    String? sha256,
    int? size,
    Uri? signatureBundleUrl,
    Uri? provenanceUrl,
  });
  AleraUpdateInfoCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _AleraUpdateInfoCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, AleraUpdateInfo, $Out>
    implements AleraUpdateInfoCopyWith<$R, AleraUpdateInfo, $Out> {
  _AleraUpdateInfoCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<AleraUpdateInfo> $mapper =
      AleraUpdateInfoMapper.ensureInitialized();
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get changes =>
      ListCopyWith(
        $value.changes,
        (v, t) => ObjectCopyWith(v, $identity, t),
        (v) => call(changes: v),
      );
  @override
  $R call({
    String? version,
    int? shortVersion,
    String? date,
    bool? mandatory,
    Uri? url,
    String? platform,
    List<String>? changes,
    String? installerKind,
    Object? sha256 = $none,
    Object? size = $none,
    Object? signatureBundleUrl = $none,
    Object? provenanceUrl = $none,
  }) => $apply(
    FieldCopyWithData({
      if (version != null) #version: version,
      if (shortVersion != null) #shortVersion: shortVersion,
      if (date != null) #date: date,
      if (mandatory != null) #mandatory: mandatory,
      if (url != null) #url: url,
      if (platform != null) #platform: platform,
      if (changes != null) #changes: changes,
      if (installerKind != null) #installerKind: installerKind,
      if (sha256 != $none) #sha256: sha256,
      if (size != $none) #size: size,
      if (signatureBundleUrl != $none) #signatureBundleUrl: signatureBundleUrl,
      if (provenanceUrl != $none) #provenanceUrl: provenanceUrl,
    }),
  );
  @override
  AleraUpdateInfo $make(CopyWithData data) => AleraUpdateInfo(
    version: data.get(#version, or: $value.version),
    shortVersion: data.get(#shortVersion, or: $value.shortVersion),
    date: data.get(#date, or: $value.date),
    mandatory: data.get(#mandatory, or: $value.mandatory),
    url: data.get(#url, or: $value.url),
    platform: data.get(#platform, or: $value.platform),
    changes: data.get(#changes, or: $value.changes),
    installerKind: data.get(#installerKind, or: $value.installerKind),
    sha256: data.get(#sha256, or: $value.sha256),
    size: data.get(#size, or: $value.size),
    signatureBundleUrl: data.get(
      #signatureBundleUrl,
      or: $value.signatureBundleUrl,
    ),
    provenanceUrl: data.get(#provenanceUrl, or: $value.provenanceUrl),
  );

  @override
  AleraUpdateInfoCopyWith<$R2, AleraUpdateInfo, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _AleraUpdateInfoCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class AleraUpdateStateMapper extends ClassMapperBase<AleraUpdateState> {
  AleraUpdateStateMapper._();

  static AleraUpdateStateMapper? _instance;
  static AleraUpdateStateMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = AleraUpdateStateMapper._());
      AleraUpdateStatusMapper.ensureInitialized();
      AleraUpdateConfigMapper.ensureInitialized();
      AleraUpdateInfoMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'AleraUpdateState';

  static AleraUpdateStatus _$status(AleraUpdateState v) => v.status;
  static const Field<AleraUpdateState, AleraUpdateStatus> _f$status = Field(
    'status',
    _$status,
  );
  static AleraUpdateConfig _$config(AleraUpdateState v) => v.config;
  static const Field<AleraUpdateState, AleraUpdateConfig> _f$config = Field(
    'config',
    _$config,
  );
  static AleraUpdateInfo? _$latest(AleraUpdateState v) => v.latest;
  static const Field<AleraUpdateState, AleraUpdateInfo> _f$latest = Field(
    'latest',
    _$latest,
    opt: true,
  );
  static String? _$message(AleraUpdateState v) => v.message;
  static const Field<AleraUpdateState, String> _f$message = Field(
    'message',
    _$message,
    opt: true,
  );
  static double _$progress(AleraUpdateState v) => v.progress;
  static const Field<AleraUpdateState, double> _f$progress = Field(
    'progress',
    _$progress,
    opt: true,
    def: 0,
  );

  @override
  final MappableFields<AleraUpdateState> fields = const {
    #status: _f$status,
    #config: _f$config,
    #latest: _f$latest,
    #message: _f$message,
    #progress: _f$progress,
  };

  static AleraUpdateState _instantiate(DecodingData data) {
    return AleraUpdateState(
      status: data.dec(_f$status),
      config: data.dec(_f$config),
      latest: data.dec(_f$latest),
      message: data.dec(_f$message),
      progress: data.dec(_f$progress),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static AleraUpdateState fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<AleraUpdateState>(map);
  }

  static AleraUpdateState fromJson(String json) {
    return ensureInitialized().decodeJson<AleraUpdateState>(json);
  }
}

mixin AleraUpdateStateMappable {
  String toJson() {
    return AleraUpdateStateMapper.ensureInitialized()
        .encodeJson<AleraUpdateState>(this as AleraUpdateState);
  }

  Map<String, dynamic> toMap() {
    return AleraUpdateStateMapper.ensureInitialized()
        .encodeMap<AleraUpdateState>(this as AleraUpdateState);
  }

  AleraUpdateStateCopyWith<AleraUpdateState, AleraUpdateState, AleraUpdateState>
  get copyWith =>
      _AleraUpdateStateCopyWithImpl<AleraUpdateState, AleraUpdateState>(
        this as AleraUpdateState,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return AleraUpdateStateMapper.ensureInitialized().stringifyValue(
      this as AleraUpdateState,
    );
  }

  @override
  bool operator ==(Object other) {
    return AleraUpdateStateMapper.ensureInitialized().equalsValue(
      this as AleraUpdateState,
      other,
    );
  }

  @override
  int get hashCode {
    return AleraUpdateStateMapper.ensureInitialized().hashValue(
      this as AleraUpdateState,
    );
  }
}

extension AleraUpdateStateValueCopy<$R, $Out>
    on ObjectCopyWith<$R, AleraUpdateState, $Out> {
  AleraUpdateStateCopyWith<$R, AleraUpdateState, $Out>
  get $asAleraUpdateState =>
      $base.as((v, t, t2) => _AleraUpdateStateCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class AleraUpdateStateCopyWith<$R, $In extends AleraUpdateState, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  AleraUpdateConfigCopyWith<$R, AleraUpdateConfig, AleraUpdateConfig>
  get config;
  AleraUpdateInfoCopyWith<$R, AleraUpdateInfo, AleraUpdateInfo>? get latest;
  $R call({
    AleraUpdateStatus? status,
    AleraUpdateConfig? config,
    AleraUpdateInfo? latest,
    String? message,
    double? progress,
  });
  AleraUpdateStateCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _AleraUpdateStateCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, AleraUpdateState, $Out>
    implements AleraUpdateStateCopyWith<$R, AleraUpdateState, $Out> {
  _AleraUpdateStateCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<AleraUpdateState> $mapper =
      AleraUpdateStateMapper.ensureInitialized();
  @override
  AleraUpdateConfigCopyWith<$R, AleraUpdateConfig, AleraUpdateConfig>
  get config => $value.config.copyWith.$chain((v) => call(config: v));
  @override
  AleraUpdateInfoCopyWith<$R, AleraUpdateInfo, AleraUpdateInfo>? get latest =>
      $value.latest?.copyWith.$chain((v) => call(latest: v));
  @override
  $R call({
    AleraUpdateStatus? status,
    AleraUpdateConfig? config,
    Object? latest = $none,
    Object? message = $none,
    double? progress,
  }) => $apply(
    FieldCopyWithData({
      if (status != null) #status: status,
      if (config != null) #config: config,
      if (latest != $none) #latest: latest,
      if (message != $none) #message: message,
      if (progress != null) #progress: progress,
    }),
  );
  @override
  AleraUpdateState $make(CopyWithData data) => AleraUpdateState(
    status: data.get(#status, or: $value.status),
    config: data.get(#config, or: $value.config),
    latest: data.get(#latest, or: $value.latest),
    message: data.get(#message, or: $value.message),
    progress: data.get(#progress, or: $value.progress),
  );

  @override
  AleraUpdateStateCopyWith<$R2, AleraUpdateState, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _AleraUpdateStateCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

