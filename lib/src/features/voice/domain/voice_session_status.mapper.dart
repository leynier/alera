// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'voice_session_status.dart';

class VoiceSessionPhaseMapper extends EnumMapper<VoiceSessionPhase> {
  VoiceSessionPhaseMapper._();

  static VoiceSessionPhaseMapper? _instance;
  static VoiceSessionPhaseMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = VoiceSessionPhaseMapper._());
    }
    return _instance!;
  }

  static VoiceSessionPhase fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  VoiceSessionPhase decode(dynamic value) {
    switch (value) {
      case r'idle':
        return VoiceSessionPhase.idle;
      case r'listening':
        return VoiceSessionPhase.listening;
      case r'thinking':
        return VoiceSessionPhase.thinking;
      case r'speaking':
        return VoiceSessionPhase.speaking;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(VoiceSessionPhase self) {
    switch (self) {
      case VoiceSessionPhase.idle:
        return r'idle';
      case VoiceSessionPhase.listening:
        return r'listening';
      case VoiceSessionPhase.thinking:
        return r'thinking';
      case VoiceSessionPhase.speaking:
        return r'speaking';
    }
  }
}

extension VoiceSessionPhaseMapperExtension on VoiceSessionPhase {
  String toValue() {
    VoiceSessionPhaseMapper.ensureInitialized();
    return MapperContainer.globals.toValue<VoiceSessionPhase>(this) as String;
  }
}

class VoiceSessionStatusMapper extends ClassMapperBase<VoiceSessionStatus> {
  VoiceSessionStatusMapper._();

  static VoiceSessionStatusMapper? _instance;
  static VoiceSessionStatusMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = VoiceSessionStatusMapper._());
      VoiceSessionPhaseMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'VoiceSessionStatus';

  static String? _$homeWorkspaceId(VoiceSessionStatus v) => v.homeWorkspaceId;
  static const Field<VoiceSessionStatus, String> _f$homeWorkspaceId = Field(
    'homeWorkspaceId',
    _$homeWorkspaceId,
    opt: true,
  );
  static String? _$homeProjectId(VoiceSessionStatus v) => v.homeProjectId;
  static const Field<VoiceSessionStatus, String> _f$homeProjectId = Field(
    'homeProjectId',
    _$homeProjectId,
    opt: true,
  );
  static String? _$homeDir(VoiceSessionStatus v) => v.homeDir;
  static const Field<VoiceSessionStatus, String> _f$homeDir = Field(
    'homeDir',
    _$homeDir,
    opt: true,
  );
  static String? _$homeTabId(VoiceSessionStatus v) => v.homeTabId;
  static const Field<VoiceSessionStatus, String> _f$homeTabId = Field(
    'homeTabId',
    _$homeTabId,
    opt: true,
  );
  static String? _$homeSessionId(VoiceSessionStatus v) => v.homeSessionId;
  static const Field<VoiceSessionStatus, String> _f$homeSessionId = Field(
    'homeSessionId',
    _$homeSessionId,
    opt: true,
  );
  static VoiceSessionPhase _$phase(VoiceSessionStatus v) => v.phase;
  static const Field<VoiceSessionStatus, VoiceSessionPhase> _f$phase = Field(
    'phase',
    _$phase,
    opt: true,
    def: VoiceSessionPhase.idle,
  );
  static bool _$speaking(VoiceSessionStatus v) => v.speaking;
  static const Field<VoiceSessionStatus, bool> _f$speaking = Field(
    'speaking',
    _$speaking,
    opt: true,
    def: false,
  );
  static int _$queuedSpeakCount(VoiceSessionStatus v) => v.queuedSpeakCount;
  static const Field<VoiceSessionStatus, int> _f$queuedSpeakCount = Field(
    'queuedSpeakCount',
    _$queuedSpeakCount,
    opt: true,
    def: 0,
  );
  static int _$queuedTurnCount(VoiceSessionStatus v) => v.queuedTurnCount;
  static const Field<VoiceSessionStatus, int> _f$queuedTurnCount = Field(
    'queuedTurnCount',
    _$queuedTurnCount,
    opt: true,
    def: 0,
  );
  static String? _$lastSpoken(VoiceSessionStatus v) => v.lastSpoken;
  static const Field<VoiceSessionStatus, String> _f$lastSpoken = Field(
    'lastSpoken',
    _$lastSpoken,
    opt: true,
  );
  static String? _$lastError(VoiceSessionStatus v) => v.lastError;
  static const Field<VoiceSessionStatus, String> _f$lastError = Field(
    'lastError',
    _$lastError,
    opt: true,
  );
  static bool _$realtime(VoiceSessionStatus v) => v.realtime;
  static const Field<VoiceSessionStatus, bool> _f$realtime = Field(
    'realtime',
    _$realtime,
    opt: true,
    def: false,
  );
  static int _$sessionGeneration(VoiceSessionStatus v) => v.sessionGeneration;
  static const Field<VoiceSessionStatus, int> _f$sessionGeneration = Field(
    'sessionGeneration',
    _$sessionGeneration,
    opt: true,
    def: 0,
  );
  static int? _$captureOwnerClientId(VoiceSessionStatus v) =>
      v.captureOwnerClientId;
  static const Field<VoiceSessionStatus, int> _f$captureOwnerClientId = Field(
    'captureOwnerClientId',
    _$captureOwnerClientId,
    opt: true,
  );

  @override
  final MappableFields<VoiceSessionStatus> fields = const {
    #homeWorkspaceId: _f$homeWorkspaceId,
    #homeProjectId: _f$homeProjectId,
    #homeDir: _f$homeDir,
    #homeTabId: _f$homeTabId,
    #homeSessionId: _f$homeSessionId,
    #phase: _f$phase,
    #speaking: _f$speaking,
    #queuedSpeakCount: _f$queuedSpeakCount,
    #queuedTurnCount: _f$queuedTurnCount,
    #lastSpoken: _f$lastSpoken,
    #lastError: _f$lastError,
    #realtime: _f$realtime,
    #sessionGeneration: _f$sessionGeneration,
    #captureOwnerClientId: _f$captureOwnerClientId,
  };

  static VoiceSessionStatus _instantiate(DecodingData data) {
    return VoiceSessionStatus(
      homeWorkspaceId: data.dec(_f$homeWorkspaceId),
      homeProjectId: data.dec(_f$homeProjectId),
      homeDir: data.dec(_f$homeDir),
      homeTabId: data.dec(_f$homeTabId),
      homeSessionId: data.dec(_f$homeSessionId),
      phase: data.dec(_f$phase),
      speaking: data.dec(_f$speaking),
      queuedSpeakCount: data.dec(_f$queuedSpeakCount),
      queuedTurnCount: data.dec(_f$queuedTurnCount),
      lastSpoken: data.dec(_f$lastSpoken),
      lastError: data.dec(_f$lastError),
      realtime: data.dec(_f$realtime),
      sessionGeneration: data.dec(_f$sessionGeneration),
      captureOwnerClientId: data.dec(_f$captureOwnerClientId),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static VoiceSessionStatus fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<VoiceSessionStatus>(map);
  }

  static VoiceSessionStatus fromJson(String json) {
    return ensureInitialized().decodeJson<VoiceSessionStatus>(json);
  }
}

mixin VoiceSessionStatusMappable {
  String toJson() {
    return VoiceSessionStatusMapper.ensureInitialized()
        .encodeJson<VoiceSessionStatus>(this as VoiceSessionStatus);
  }

  Map<String, dynamic> toMap() {
    return VoiceSessionStatusMapper.ensureInitialized()
        .encodeMap<VoiceSessionStatus>(this as VoiceSessionStatus);
  }

  VoiceSessionStatusCopyWith<
    VoiceSessionStatus,
    VoiceSessionStatus,
    VoiceSessionStatus
  >
  get copyWith =>
      _VoiceSessionStatusCopyWithImpl<VoiceSessionStatus, VoiceSessionStatus>(
        this as VoiceSessionStatus,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return VoiceSessionStatusMapper.ensureInitialized().stringifyValue(
      this as VoiceSessionStatus,
    );
  }

  @override
  bool operator ==(Object other) {
    return VoiceSessionStatusMapper.ensureInitialized().equalsValue(
      this as VoiceSessionStatus,
      other,
    );
  }

  @override
  int get hashCode {
    return VoiceSessionStatusMapper.ensureInitialized().hashValue(
      this as VoiceSessionStatus,
    );
  }
}

extension VoiceSessionStatusValueCopy<$R, $Out>
    on ObjectCopyWith<$R, VoiceSessionStatus, $Out> {
  VoiceSessionStatusCopyWith<$R, VoiceSessionStatus, $Out>
  get $asVoiceSessionStatus => $base.as(
    (v, t, t2) => _VoiceSessionStatusCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class VoiceSessionStatusCopyWith<
  $R,
  $In extends VoiceSessionStatus,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    String? homeWorkspaceId,
    String? homeProjectId,
    String? homeDir,
    String? homeTabId,
    String? homeSessionId,
    VoiceSessionPhase? phase,
    bool? speaking,
    int? queuedSpeakCount,
    int? queuedTurnCount,
    String? lastSpoken,
    String? lastError,
    bool? realtime,
    int? sessionGeneration,
    int? captureOwnerClientId,
  });
  VoiceSessionStatusCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _VoiceSessionStatusCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, VoiceSessionStatus, $Out>
    implements VoiceSessionStatusCopyWith<$R, VoiceSessionStatus, $Out> {
  _VoiceSessionStatusCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<VoiceSessionStatus> $mapper =
      VoiceSessionStatusMapper.ensureInitialized();
  @override
  $R call({
    Object? homeWorkspaceId = $none,
    Object? homeProjectId = $none,
    Object? homeDir = $none,
    Object? homeTabId = $none,
    Object? homeSessionId = $none,
    VoiceSessionPhase? phase,
    bool? speaking,
    int? queuedSpeakCount,
    int? queuedTurnCount,
    Object? lastSpoken = $none,
    Object? lastError = $none,
    bool? realtime,
    int? sessionGeneration,
    Object? captureOwnerClientId = $none,
  }) => $apply(
    FieldCopyWithData({
      if (homeWorkspaceId != $none) #homeWorkspaceId: homeWorkspaceId,
      if (homeProjectId != $none) #homeProjectId: homeProjectId,
      if (homeDir != $none) #homeDir: homeDir,
      if (homeTabId != $none) #homeTabId: homeTabId,
      if (homeSessionId != $none) #homeSessionId: homeSessionId,
      if (phase != null) #phase: phase,
      if (speaking != null) #speaking: speaking,
      if (queuedSpeakCount != null) #queuedSpeakCount: queuedSpeakCount,
      if (queuedTurnCount != null) #queuedTurnCount: queuedTurnCount,
      if (lastSpoken != $none) #lastSpoken: lastSpoken,
      if (lastError != $none) #lastError: lastError,
      if (realtime != null) #realtime: realtime,
      if (sessionGeneration != null) #sessionGeneration: sessionGeneration,
      if (captureOwnerClientId != $none)
        #captureOwnerClientId: captureOwnerClientId,
    }),
  );
  @override
  VoiceSessionStatus $make(CopyWithData data) => VoiceSessionStatus(
    homeWorkspaceId: data.get(#homeWorkspaceId, or: $value.homeWorkspaceId),
    homeProjectId: data.get(#homeProjectId, or: $value.homeProjectId),
    homeDir: data.get(#homeDir, or: $value.homeDir),
    homeTabId: data.get(#homeTabId, or: $value.homeTabId),
    homeSessionId: data.get(#homeSessionId, or: $value.homeSessionId),
    phase: data.get(#phase, or: $value.phase),
    speaking: data.get(#speaking, or: $value.speaking),
    queuedSpeakCount: data.get(#queuedSpeakCount, or: $value.queuedSpeakCount),
    queuedTurnCount: data.get(#queuedTurnCount, or: $value.queuedTurnCount),
    lastSpoken: data.get(#lastSpoken, or: $value.lastSpoken),
    lastError: data.get(#lastError, or: $value.lastError),
    realtime: data.get(#realtime, or: $value.realtime),
    sessionGeneration: data.get(
      #sessionGeneration,
      or: $value.sessionGeneration,
    ),
    captureOwnerClientId: data.get(
      #captureOwnerClientId,
      or: $value.captureOwnerClientId,
    ),
  );

  @override
  VoiceSessionStatusCopyWith<$R2, VoiceSessionStatus, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _VoiceSessionStatusCopyWithImpl<$R2, $Out2>($value, $cast, t);
}
