// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'agent_canvas.dart';

class AgentCanvasStateMapper extends EnumMapper<AgentCanvasState> {
  AgentCanvasStateMapper._();

  static AgentCanvasStateMapper? _instance;
  static AgentCanvasStateMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = AgentCanvasStateMapper._());
    }
    return _instance!;
  }

  static AgentCanvasState fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  AgentCanvasState decode(dynamic value) {
    switch (value) {
      case r'waiting':
        return AgentCanvasState.waiting;
      case r'live':
        return AgentCanvasState.live;
      case r'completed':
        return AgentCanvasState.completed;
      case r'orphaned':
        return AgentCanvasState.orphaned;
      case r'closed':
        return AgentCanvasState.closed;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(AgentCanvasState self) {
    switch (self) {
      case AgentCanvasState.waiting:
        return r'waiting';
      case AgentCanvasState.live:
        return r'live';
      case AgentCanvasState.completed:
        return r'completed';
      case AgentCanvasState.orphaned:
        return r'orphaned';
      case AgentCanvasState.closed:
        return r'closed';
    }
  }
}

extension AgentCanvasStateMapperExtension on AgentCanvasState {
  String toValue() {
    AgentCanvasStateMapper.ensureInitialized();
    return MapperContainer.globals.toValue<AgentCanvasState>(this) as String;
  }
}

class AgentCanvasDecisionStateMapper
    extends EnumMapper<AgentCanvasDecisionState> {
  AgentCanvasDecisionStateMapper._();

  static AgentCanvasDecisionStateMapper? _instance;
  static AgentCanvasDecisionStateMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = AgentCanvasDecisionStateMapper._(),
      );
    }
    return _instance!;
  }

  static AgentCanvasDecisionState fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  AgentCanvasDecisionState decode(dynamic value) {
    switch (value) {
      case r'pending':
        return AgentCanvasDecisionState.pending;
      case r'resolved':
        return AgentCanvasDecisionState.resolved;
      case r'timeout':
        return AgentCanvasDecisionState.timeout;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(AgentCanvasDecisionState self) {
    switch (self) {
      case AgentCanvasDecisionState.pending:
        return r'pending';
      case AgentCanvasDecisionState.resolved:
        return r'resolved';
      case AgentCanvasDecisionState.timeout:
        return r'timeout';
    }
  }
}

extension AgentCanvasDecisionStateMapperExtension on AgentCanvasDecisionState {
  String toValue() {
    AgentCanvasDecisionStateMapper.ensureInitialized();
    return MapperContainer.globals.toValue<AgentCanvasDecisionState>(this)
        as String;
  }
}

class AgentCanvasDecisionMapper extends ClassMapperBase<AgentCanvasDecision> {
  AgentCanvasDecisionMapper._();

  static AgentCanvasDecisionMapper? _instance;
  static AgentCanvasDecisionMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = AgentCanvasDecisionMapper._());
      AgentCanvasDecisionStateMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'AgentCanvasDecision';

  static String _$id(AgentCanvasDecision v) => v.id;
  static const Field<AgentCanvasDecision, String> _f$id = Field('id', _$id);
  static String _$canvasId(AgentCanvasDecision v) => v.canvasId;
  static const Field<AgentCanvasDecision, String> _f$canvasId = Field(
    'canvasId',
    _$canvasId,
  );
  static int _$revision(AgentCanvasDecision v) => v.revision;
  static const Field<AgentCanvasDecision, int> _f$revision = Field(
    'revision',
    _$revision,
  );
  static String _$question(AgentCanvasDecision v) => v.question;
  static const Field<AgentCanvasDecision, String> _f$question = Field(
    'question',
    _$question,
  );
  static Object? _$options(AgentCanvasDecision v) => v.options;
  static const Field<AgentCanvasDecision, Object> _f$options = Field(
    'options',
    _$options,
  );
  static AgentCanvasDecisionState _$state(AgentCanvasDecision v) => v.state;
  static const Field<AgentCanvasDecision, AgentCanvasDecisionState> _f$state =
      Field('state', _$state);
  static DateTime _$createdAt(AgentCanvasDecision v) => v.createdAt;
  static const Field<AgentCanvasDecision, DateTime> _f$createdAt = Field(
    'createdAt',
    _$createdAt,
  );
  static Object? _$resolution(AgentCanvasDecision v) => v.resolution;
  static const Field<AgentCanvasDecision, Object> _f$resolution = Field(
    'resolution',
    _$resolution,
    opt: true,
  );
  static DateTime? _$resolvedAt(AgentCanvasDecision v) => v.resolvedAt;
  static const Field<AgentCanvasDecision, DateTime> _f$resolvedAt = Field(
    'resolvedAt',
    _$resolvedAt,
    opt: true,
  );
  static DateTime? _$expiresAt(AgentCanvasDecision v) => v.expiresAt;
  static const Field<AgentCanvasDecision, DateTime> _f$expiresAt = Field(
    'expiresAt',
    _$expiresAt,
    opt: true,
  );

  @override
  final MappableFields<AgentCanvasDecision> fields = const {
    #id: _f$id,
    #canvasId: _f$canvasId,
    #revision: _f$revision,
    #question: _f$question,
    #options: _f$options,
    #state: _f$state,
    #createdAt: _f$createdAt,
    #resolution: _f$resolution,
    #resolvedAt: _f$resolvedAt,
    #expiresAt: _f$expiresAt,
  };

  static AgentCanvasDecision _instantiate(DecodingData data) {
    return AgentCanvasDecision(
      id: data.dec(_f$id),
      canvasId: data.dec(_f$canvasId),
      revision: data.dec(_f$revision),
      question: data.dec(_f$question),
      options: data.dec(_f$options),
      state: data.dec(_f$state),
      createdAt: data.dec(_f$createdAt),
      resolution: data.dec(_f$resolution),
      resolvedAt: data.dec(_f$resolvedAt),
      expiresAt: data.dec(_f$expiresAt),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static AgentCanvasDecision fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<AgentCanvasDecision>(map);
  }

  static AgentCanvasDecision fromJson(String json) {
    return ensureInitialized().decodeJson<AgentCanvasDecision>(json);
  }
}

mixin AgentCanvasDecisionMappable {
  String toJson() {
    return AgentCanvasDecisionMapper.ensureInitialized()
        .encodeJson<AgentCanvasDecision>(this as AgentCanvasDecision);
  }

  Map<String, dynamic> toMap() {
    return AgentCanvasDecisionMapper.ensureInitialized()
        .encodeMap<AgentCanvasDecision>(this as AgentCanvasDecision);
  }

  AgentCanvasDecisionCopyWith<
    AgentCanvasDecision,
    AgentCanvasDecision,
    AgentCanvasDecision
  >
  get copyWith =>
      _AgentCanvasDecisionCopyWithImpl<
        AgentCanvasDecision,
        AgentCanvasDecision
      >(this as AgentCanvasDecision, $identity, $identity);
  @override
  String toString() {
    return AgentCanvasDecisionMapper.ensureInitialized().stringifyValue(
      this as AgentCanvasDecision,
    );
  }

  @override
  bool operator ==(Object other) {
    return AgentCanvasDecisionMapper.ensureInitialized().equalsValue(
      this as AgentCanvasDecision,
      other,
    );
  }

  @override
  int get hashCode {
    return AgentCanvasDecisionMapper.ensureInitialized().hashValue(
      this as AgentCanvasDecision,
    );
  }
}

extension AgentCanvasDecisionValueCopy<$R, $Out>
    on ObjectCopyWith<$R, AgentCanvasDecision, $Out> {
  AgentCanvasDecisionCopyWith<$R, AgentCanvasDecision, $Out>
  get $asAgentCanvasDecision => $base.as(
    (v, t, t2) => _AgentCanvasDecisionCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class AgentCanvasDecisionCopyWith<
  $R,
  $In extends AgentCanvasDecision,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    String? id,
    String? canvasId,
    int? revision,
    String? question,
    Object? options,
    AgentCanvasDecisionState? state,
    DateTime? createdAt,
    Object? resolution,
    DateTime? resolvedAt,
    DateTime? expiresAt,
  });
  AgentCanvasDecisionCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _AgentCanvasDecisionCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, AgentCanvasDecision, $Out>
    implements AgentCanvasDecisionCopyWith<$R, AgentCanvasDecision, $Out> {
  _AgentCanvasDecisionCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<AgentCanvasDecision> $mapper =
      AgentCanvasDecisionMapper.ensureInitialized();
  @override
  $R call({
    String? id,
    String? canvasId,
    int? revision,
    String? question,
    Object? options = $none,
    AgentCanvasDecisionState? state,
    DateTime? createdAt,
    Object? resolution = $none,
    Object? resolvedAt = $none,
    Object? expiresAt = $none,
  }) => $apply(
    FieldCopyWithData({
      if (id != null) #id: id,
      if (canvasId != null) #canvasId: canvasId,
      if (revision != null) #revision: revision,
      if (question != null) #question: question,
      if (options != $none) #options: options,
      if (state != null) #state: state,
      if (createdAt != null) #createdAt: createdAt,
      if (resolution != $none) #resolution: resolution,
      if (resolvedAt != $none) #resolvedAt: resolvedAt,
      if (expiresAt != $none) #expiresAt: expiresAt,
    }),
  );
  @override
  AgentCanvasDecision $make(CopyWithData data) => AgentCanvasDecision(
    id: data.get(#id, or: $value.id),
    canvasId: data.get(#canvasId, or: $value.canvasId),
    revision: data.get(#revision, or: $value.revision),
    question: data.get(#question, or: $value.question),
    options: data.get(#options, or: $value.options),
    state: data.get(#state, or: $value.state),
    createdAt: data.get(#createdAt, or: $value.createdAt),
    resolution: data.get(#resolution, or: $value.resolution),
    resolvedAt: data.get(#resolvedAt, or: $value.resolvedAt),
    expiresAt: data.get(#expiresAt, or: $value.expiresAt),
  );

  @override
  AgentCanvasDecisionCopyWith<$R2, AgentCanvasDecision, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _AgentCanvasDecisionCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class AgentCanvasMapper extends ClassMapperBase<AgentCanvas> {
  AgentCanvasMapper._();

  static AgentCanvasMapper? _instance;
  static AgentCanvasMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = AgentCanvasMapper._());
      AgentCanvasStateMapper.ensureInitialized();
      AgentCanvasDecisionMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'AgentCanvas';

  static String _$id(AgentCanvas v) => v.id;
  static const Field<AgentCanvas, String> _f$id = Field('id', _$id);
  static String _$workspaceId(AgentCanvas v) => v.workspaceId;
  static const Field<AgentCanvas, String> _f$workspaceId = Field(
    'workspaceId',
    _$workspaceId,
  );
  static String _$terminalSessionId(AgentCanvas v) => v.terminalSessionId;
  static const Field<AgentCanvas, String> _f$terminalSessionId = Field(
    'terminalSessionId',
    _$terminalSessionId,
  );
  static String _$agentType(AgentCanvas v) => v.agentType;
  static const Field<AgentCanvas, String> _f$agentType = Field(
    'agentType',
    _$agentType,
  );
  static String _$title(AgentCanvas v) => v.title;
  static const Field<AgentCanvas, String> _f$title = Field('title', _$title);
  static AgentCanvasState _$state(AgentCanvas v) => v.state;
  static const Field<AgentCanvas, AgentCanvasState> _f$state = Field(
    'state',
    _$state,
  );
  static bool _$pinned(AgentCanvas v) => v.pinned;
  static const Field<AgentCanvas, bool> _f$pinned = Field('pinned', _$pinned);
  static bool _$frozen(AgentCanvas v) => v.frozen;
  static const Field<AgentCanvas, bool> _f$frozen = Field('frozen', _$frozen);
  static int _$revision(AgentCanvas v) => v.revision;
  static const Field<AgentCanvas, int> _f$revision = Field(
    'revision',
    _$revision,
  );
  static Map<String, Object?> _$document(AgentCanvas v) => v.document;
  static const Field<AgentCanvas, Map<String, Object?>> _f$document = Field(
    'document',
    _$document,
  );
  static List<AgentCanvasDecision> _$decisions(AgentCanvas v) => v.decisions;
  static const Field<AgentCanvas, List<AgentCanvasDecision>> _f$decisions =
      Field('decisions', _$decisions);
  static DateTime _$createdAt(AgentCanvas v) => v.createdAt;
  static const Field<AgentCanvas, DateTime> _f$createdAt = Field(
    'createdAt',
    _$createdAt,
  );
  static DateTime _$updatedAt(AgentCanvas v) => v.updatedAt;
  static const Field<AgentCanvas, DateTime> _f$updatedAt = Field(
    'updatedAt',
    _$updatedAt,
  );
  static String? _$tabId(AgentCanvas v) => v.tabId;
  static const Field<AgentCanvas, String> _f$tabId = Field(
    'tabId',
    _$tabId,
    opt: true,
  );
  static int? _$finalRevision(AgentCanvas v) => v.finalRevision;
  static const Field<AgentCanvas, int> _f$finalRevision = Field(
    'finalRevision',
    _$finalRevision,
    opt: true,
  );
  static DateTime? _$completedAt(AgentCanvas v) => v.completedAt;
  static const Field<AgentCanvas, DateTime> _f$completedAt = Field(
    'completedAt',
    _$completedAt,
    opt: true,
  );
  static DateTime? _$expiresAt(AgentCanvas v) => v.expiresAt;
  static const Field<AgentCanvas, DateTime> _f$expiresAt = Field(
    'expiresAt',
    _$expiresAt,
    opt: true,
  );

  @override
  final MappableFields<AgentCanvas> fields = const {
    #id: _f$id,
    #workspaceId: _f$workspaceId,
    #terminalSessionId: _f$terminalSessionId,
    #agentType: _f$agentType,
    #title: _f$title,
    #state: _f$state,
    #pinned: _f$pinned,
    #frozen: _f$frozen,
    #revision: _f$revision,
    #document: _f$document,
    #decisions: _f$decisions,
    #createdAt: _f$createdAt,
    #updatedAt: _f$updatedAt,
    #tabId: _f$tabId,
    #finalRevision: _f$finalRevision,
    #completedAt: _f$completedAt,
    #expiresAt: _f$expiresAt,
  };

  static AgentCanvas _instantiate(DecodingData data) {
    return AgentCanvas(
      id: data.dec(_f$id),
      workspaceId: data.dec(_f$workspaceId),
      terminalSessionId: data.dec(_f$terminalSessionId),
      agentType: data.dec(_f$agentType),
      title: data.dec(_f$title),
      state: data.dec(_f$state),
      pinned: data.dec(_f$pinned),
      frozen: data.dec(_f$frozen),
      revision: data.dec(_f$revision),
      document: data.dec(_f$document),
      decisions: data.dec(_f$decisions),
      createdAt: data.dec(_f$createdAt),
      updatedAt: data.dec(_f$updatedAt),
      tabId: data.dec(_f$tabId),
      finalRevision: data.dec(_f$finalRevision),
      completedAt: data.dec(_f$completedAt),
      expiresAt: data.dec(_f$expiresAt),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static AgentCanvas fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<AgentCanvas>(map);
  }

  static AgentCanvas fromJson(String json) {
    return ensureInitialized().decodeJson<AgentCanvas>(json);
  }
}

mixin AgentCanvasMappable {
  String toJson() {
    return AgentCanvasMapper.ensureInitialized().encodeJson<AgentCanvas>(
      this as AgentCanvas,
    );
  }

  Map<String, dynamic> toMap() {
    return AgentCanvasMapper.ensureInitialized().encodeMap<AgentCanvas>(
      this as AgentCanvas,
    );
  }

  AgentCanvasCopyWith<AgentCanvas, AgentCanvas, AgentCanvas> get copyWith =>
      _AgentCanvasCopyWithImpl<AgentCanvas, AgentCanvas>(
        this as AgentCanvas,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return AgentCanvasMapper.ensureInitialized().stringifyValue(
      this as AgentCanvas,
    );
  }

  @override
  bool operator ==(Object other) {
    return AgentCanvasMapper.ensureInitialized().equalsValue(
      this as AgentCanvas,
      other,
    );
  }

  @override
  int get hashCode {
    return AgentCanvasMapper.ensureInitialized().hashValue(this as AgentCanvas);
  }
}

extension AgentCanvasValueCopy<$R, $Out>
    on ObjectCopyWith<$R, AgentCanvas, $Out> {
  AgentCanvasCopyWith<$R, AgentCanvas, $Out> get $asAgentCanvas =>
      $base.as((v, t, t2) => _AgentCanvasCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class AgentCanvasCopyWith<$R, $In extends AgentCanvas, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  MapCopyWith<$R, String, Object?, ObjectCopyWith<$R, Object?, Object?>?>
  get document;
  ListCopyWith<
    $R,
    AgentCanvasDecision,
    AgentCanvasDecisionCopyWith<$R, AgentCanvasDecision, AgentCanvasDecision>
  >
  get decisions;
  $R call({
    String? id,
    String? workspaceId,
    String? terminalSessionId,
    String? agentType,
    String? title,
    AgentCanvasState? state,
    bool? pinned,
    bool? frozen,
    int? revision,
    Map<String, Object?>? document,
    List<AgentCanvasDecision>? decisions,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? tabId,
    int? finalRevision,
    DateTime? completedAt,
    DateTime? expiresAt,
  });
  AgentCanvasCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _AgentCanvasCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, AgentCanvas, $Out>
    implements AgentCanvasCopyWith<$R, AgentCanvas, $Out> {
  _AgentCanvasCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<AgentCanvas> $mapper =
      AgentCanvasMapper.ensureInitialized();
  @override
  MapCopyWith<$R, String, Object?, ObjectCopyWith<$R, Object?, Object?>?>
  get document => MapCopyWith(
    $value.document,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(document: v),
  );
  @override
  ListCopyWith<
    $R,
    AgentCanvasDecision,
    AgentCanvasDecisionCopyWith<$R, AgentCanvasDecision, AgentCanvasDecision>
  >
  get decisions => ListCopyWith(
    $value.decisions,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(decisions: v),
  );
  @override
  $R call({
    String? id,
    String? workspaceId,
    String? terminalSessionId,
    String? agentType,
    String? title,
    AgentCanvasState? state,
    bool? pinned,
    bool? frozen,
    int? revision,
    Map<String, Object?>? document,
    List<AgentCanvasDecision>? decisions,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? tabId = $none,
    Object? finalRevision = $none,
    Object? completedAt = $none,
    Object? expiresAt = $none,
  }) => $apply(
    FieldCopyWithData({
      if (id != null) #id: id,
      if (workspaceId != null) #workspaceId: workspaceId,
      if (terminalSessionId != null) #terminalSessionId: terminalSessionId,
      if (agentType != null) #agentType: agentType,
      if (title != null) #title: title,
      if (state != null) #state: state,
      if (pinned != null) #pinned: pinned,
      if (frozen != null) #frozen: frozen,
      if (revision != null) #revision: revision,
      if (document != null) #document: document,
      if (decisions != null) #decisions: decisions,
      if (createdAt != null) #createdAt: createdAt,
      if (updatedAt != null) #updatedAt: updatedAt,
      if (tabId != $none) #tabId: tabId,
      if (finalRevision != $none) #finalRevision: finalRevision,
      if (completedAt != $none) #completedAt: completedAt,
      if (expiresAt != $none) #expiresAt: expiresAt,
    }),
  );
  @override
  AgentCanvas $make(CopyWithData data) => AgentCanvas(
    id: data.get(#id, or: $value.id),
    workspaceId: data.get(#workspaceId, or: $value.workspaceId),
    terminalSessionId: data.get(
      #terminalSessionId,
      or: $value.terminalSessionId,
    ),
    agentType: data.get(#agentType, or: $value.agentType),
    title: data.get(#title, or: $value.title),
    state: data.get(#state, or: $value.state),
    pinned: data.get(#pinned, or: $value.pinned),
    frozen: data.get(#frozen, or: $value.frozen),
    revision: data.get(#revision, or: $value.revision),
    document: data.get(#document, or: $value.document),
    decisions: data.get(#decisions, or: $value.decisions),
    createdAt: data.get(#createdAt, or: $value.createdAt),
    updatedAt: data.get(#updatedAt, or: $value.updatedAt),
    tabId: data.get(#tabId, or: $value.tabId),
    finalRevision: data.get(#finalRevision, or: $value.finalRevision),
    completedAt: data.get(#completedAt, or: $value.completedAt),
    expiresAt: data.get(#expiresAt, or: $value.expiresAt),
  );

  @override
  AgentCanvasCopyWith<$R2, AgentCanvas, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _AgentCanvasCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class AgentCanvasEventMapper extends ClassMapperBase<AgentCanvasEvent> {
  AgentCanvasEventMapper._();

  static AgentCanvasEventMapper? _instance;
  static AgentCanvasEventMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = AgentCanvasEventMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'AgentCanvasEvent';

  static int _$sequence(AgentCanvasEvent v) => v.sequence;
  static const Field<AgentCanvasEvent, int> _f$sequence = Field(
    'sequence',
    _$sequence,
  );
  static String _$canvasId(AgentCanvasEvent v) => v.canvasId;
  static const Field<AgentCanvasEvent, String> _f$canvasId = Field(
    'canvasId',
    _$canvasId,
  );
  static String _$workspaceId(AgentCanvasEvent v) => v.workspaceId;
  static const Field<AgentCanvasEvent, String> _f$workspaceId = Field(
    'workspaceId',
    _$workspaceId,
  );
  static String _$eventType(AgentCanvasEvent v) => v.eventType;
  static const Field<AgentCanvasEvent, String> _f$eventType = Field(
    'eventType',
    _$eventType,
  );
  static Map<String, Object?> _$payload(AgentCanvasEvent v) => v.payload;
  static const Field<AgentCanvasEvent, Map<String, Object?>> _f$payload = Field(
    'payload',
    _$payload,
  );
  static DateTime _$createdAt(AgentCanvasEvent v) => v.createdAt;
  static const Field<AgentCanvasEvent, DateTime> _f$createdAt = Field(
    'createdAt',
    _$createdAt,
  );

  @override
  final MappableFields<AgentCanvasEvent> fields = const {
    #sequence: _f$sequence,
    #canvasId: _f$canvasId,
    #workspaceId: _f$workspaceId,
    #eventType: _f$eventType,
    #payload: _f$payload,
    #createdAt: _f$createdAt,
  };

  static AgentCanvasEvent _instantiate(DecodingData data) {
    return AgentCanvasEvent(
      sequence: data.dec(_f$sequence),
      canvasId: data.dec(_f$canvasId),
      workspaceId: data.dec(_f$workspaceId),
      eventType: data.dec(_f$eventType),
      payload: data.dec(_f$payload),
      createdAt: data.dec(_f$createdAt),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static AgentCanvasEvent fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<AgentCanvasEvent>(map);
  }

  static AgentCanvasEvent fromJson(String json) {
    return ensureInitialized().decodeJson<AgentCanvasEvent>(json);
  }
}

mixin AgentCanvasEventMappable {
  String toJson() {
    return AgentCanvasEventMapper.ensureInitialized()
        .encodeJson<AgentCanvasEvent>(this as AgentCanvasEvent);
  }

  Map<String, dynamic> toMap() {
    return AgentCanvasEventMapper.ensureInitialized()
        .encodeMap<AgentCanvasEvent>(this as AgentCanvasEvent);
  }

  AgentCanvasEventCopyWith<AgentCanvasEvent, AgentCanvasEvent, AgentCanvasEvent>
  get copyWith =>
      _AgentCanvasEventCopyWithImpl<AgentCanvasEvent, AgentCanvasEvent>(
        this as AgentCanvasEvent,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return AgentCanvasEventMapper.ensureInitialized().stringifyValue(
      this as AgentCanvasEvent,
    );
  }

  @override
  bool operator ==(Object other) {
    return AgentCanvasEventMapper.ensureInitialized().equalsValue(
      this as AgentCanvasEvent,
      other,
    );
  }

  @override
  int get hashCode {
    return AgentCanvasEventMapper.ensureInitialized().hashValue(
      this as AgentCanvasEvent,
    );
  }
}

extension AgentCanvasEventValueCopy<$R, $Out>
    on ObjectCopyWith<$R, AgentCanvasEvent, $Out> {
  AgentCanvasEventCopyWith<$R, AgentCanvasEvent, $Out>
  get $asAgentCanvasEvent =>
      $base.as((v, t, t2) => _AgentCanvasEventCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class AgentCanvasEventCopyWith<$R, $In extends AgentCanvasEvent, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  MapCopyWith<$R, String, Object?, ObjectCopyWith<$R, Object?, Object?>?>
  get payload;
  $R call({
    int? sequence,
    String? canvasId,
    String? workspaceId,
    String? eventType,
    Map<String, Object?>? payload,
    DateTime? createdAt,
  });
  AgentCanvasEventCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _AgentCanvasEventCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, AgentCanvasEvent, $Out>
    implements AgentCanvasEventCopyWith<$R, AgentCanvasEvent, $Out> {
  _AgentCanvasEventCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<AgentCanvasEvent> $mapper =
      AgentCanvasEventMapper.ensureInitialized();
  @override
  MapCopyWith<$R, String, Object?, ObjectCopyWith<$R, Object?, Object?>?>
  get payload => MapCopyWith(
    $value.payload,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(payload: v),
  );
  @override
  $R call({
    int? sequence,
    String? canvasId,
    String? workspaceId,
    String? eventType,
    Map<String, Object?>? payload,
    DateTime? createdAt,
  }) => $apply(
    FieldCopyWithData({
      if (sequence != null) #sequence: sequence,
      if (canvasId != null) #canvasId: canvasId,
      if (workspaceId != null) #workspaceId: workspaceId,
      if (eventType != null) #eventType: eventType,
      if (payload != null) #payload: payload,
      if (createdAt != null) #createdAt: createdAt,
    }),
  );
  @override
  AgentCanvasEvent $make(CopyWithData data) => AgentCanvasEvent(
    sequence: data.get(#sequence, or: $value.sequence),
    canvasId: data.get(#canvasId, or: $value.canvasId),
    workspaceId: data.get(#workspaceId, or: $value.workspaceId),
    eventType: data.get(#eventType, or: $value.eventType),
    payload: data.get(#payload, or: $value.payload),
    createdAt: data.get(#createdAt, or: $value.createdAt),
  );

  @override
  AgentCanvasEventCopyWith<$R2, AgentCanvasEvent, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _AgentCanvasEventCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

