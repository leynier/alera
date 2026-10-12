// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'run_timeline.dart';

class RunTimelineFilterMapper extends EnumMapper<RunTimelineFilter> {
  RunTimelineFilterMapper._();

  static RunTimelineFilterMapper? _instance;
  static RunTimelineFilterMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RunTimelineFilterMapper._());
    }
    return _instance!;
  }

  static RunTimelineFilter fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  RunTimelineFilter decode(dynamic value) {
    switch (value) {
      case r'all':
        return RunTimelineFilter.all;
      case r'dispatches':
        return RunTimelineFilter.dispatches;
      case r'messages':
        return RunTimelineFilter.messages;
      case r'gates':
        return RunTimelineFilter.gates;
      case r'integrations':
        return RunTimelineFilter.integrations;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(RunTimelineFilter self) {
    switch (self) {
      case RunTimelineFilter.all:
        return r'all';
      case RunTimelineFilter.dispatches:
        return r'dispatches';
      case RunTimelineFilter.messages:
        return r'messages';
      case RunTimelineFilter.gates:
        return r'gates';
      case RunTimelineFilter.integrations:
        return r'integrations';
    }
  }
}

extension RunTimelineFilterMapperExtension on RunTimelineFilter {
  String toValue() {
    RunTimelineFilterMapper.ensureInitialized();
    return MapperContainer.globals.toValue<RunTimelineFilter>(this) as String;
  }
}

class RunTimelineEntryMapper extends ClassMapperBase<RunTimelineEntry> {
  RunTimelineEntryMapper._();

  static RunTimelineEntryMapper? _instance;
  static RunTimelineEntryMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RunTimelineEntryMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'RunTimelineEntry';

  static String _$id(RunTimelineEntry v) => v.id;
  static const Field<RunTimelineEntry, String> _f$id = Field('id', _$id);
  static String _$source(RunTimelineEntry v) => v.source;
  static const Field<RunTimelineEntry, String> _f$source = Field(
    'source',
    _$source,
  );
  static String _$kind(RunTimelineEntry v) => v.kind;
  static const Field<RunTimelineEntry, String> _f$kind = Field('kind', _$kind);
  static String _$createdAt(RunTimelineEntry v) => v.createdAt;
  static const Field<RunTimelineEntry, String> _f$createdAt = Field(
    'createdAt',
    _$createdAt,
  );
  static String? _$taskId(RunTimelineEntry v) => v.taskId;
  static const Field<RunTimelineEntry, String> _f$taskId = Field(
    'taskId',
    _$taskId,
    opt: true,
  );
  static String? _$dispatchId(RunTimelineEntry v) => v.dispatchId;
  static const Field<RunTimelineEntry, String> _f$dispatchId = Field(
    'dispatchId',
    _$dispatchId,
    opt: true,
  );
  static String? _$gateId(RunTimelineEntry v) => v.gateId;
  static const Field<RunTimelineEntry, String> _f$gateId = Field(
    'gateId',
    _$gateId,
    opt: true,
  );
  static String? _$actorKind(RunTimelineEntry v) => v.actorKind;
  static const Field<RunTimelineEntry, String> _f$actorKind = Field(
    'actorKind',
    _$actorKind,
    opt: true,
  );
  static String? _$actorId(RunTimelineEntry v) => v.actorId;
  static const Field<RunTimelineEntry, String> _f$actorId = Field(
    'actorId',
    _$actorId,
    opt: true,
  );
  static String _$summary(RunTimelineEntry v) => v.summary;
  static const Field<RunTimelineEntry, String> _f$summary = Field(
    'summary',
    _$summary,
    opt: true,
    def: '',
  );
  static Object? _$payload(RunTimelineEntry v) => v.payload;
  static const Field<RunTimelineEntry, Object> _f$payload = Field(
    'payload',
    _$payload,
    opt: true,
  );
  static String? _$messageType(RunTimelineEntry v) => v.messageType;
  static const Field<RunTimelineEntry, String> _f$messageType = Field(
    'messageType',
    _$messageType,
    opt: true,
  );
  static String? _$from(RunTimelineEntry v) => v.from;
  static const Field<RunTimelineEntry, String> _f$from = Field(
    'from',
    _$from,
    opt: true,
  );
  static String? _$to(RunTimelineEntry v) => v.to;
  static const Field<RunTimelineEntry, String> _f$to = Field(
    'to',
    _$to,
    opt: true,
  );
  static String? _$threadId(RunTimelineEntry v) => v.threadId;
  static const Field<RunTimelineEntry, String> _f$threadId = Field(
    'threadId',
    _$threadId,
    opt: true,
  );
  static String? _$body(RunTimelineEntry v) => v.body;
  static const Field<RunTimelineEntry, String> _f$body = Field(
    'body',
    _$body,
    opt: true,
  );
  static bool _$truncated(RunTimelineEntry v) => v.truncated;
  static const Field<RunTimelineEntry, bool> _f$truncated = Field(
    'truncated',
    _$truncated,
    opt: true,
    def: false,
  );
  static String? _$workspaceId(RunTimelineEntry v) => v.workspaceId;
  static const Field<RunTimelineEntry, String> _f$workspaceId = Field(
    'workspaceId',
    _$workspaceId,
    opt: true,
  );
  static String? _$sha(RunTimelineEntry v) => v.sha;
  static const Field<RunTimelineEntry, String> _f$sha = Field(
    'sha',
    _$sha,
    opt: true,
  );
  static String? _$baseSha(RunTimelineEntry v) => v.baseSha;
  static const Field<RunTimelineEntry, String> _f$baseSha = Field(
    'baseSha',
    _$baseSha,
    opt: true,
  );

  @override
  final MappableFields<RunTimelineEntry> fields = const {
    #id: _f$id,
    #source: _f$source,
    #kind: _f$kind,
    #createdAt: _f$createdAt,
    #taskId: _f$taskId,
    #dispatchId: _f$dispatchId,
    #gateId: _f$gateId,
    #actorKind: _f$actorKind,
    #actorId: _f$actorId,
    #summary: _f$summary,
    #payload: _f$payload,
    #messageType: _f$messageType,
    #from: _f$from,
    #to: _f$to,
    #threadId: _f$threadId,
    #body: _f$body,
    #truncated: _f$truncated,
    #workspaceId: _f$workspaceId,
    #sha: _f$sha,
    #baseSha: _f$baseSha,
  };

  static RunTimelineEntry _instantiate(DecodingData data) {
    return RunTimelineEntry(
      id: data.dec(_f$id),
      source: data.dec(_f$source),
      kind: data.dec(_f$kind),
      createdAt: data.dec(_f$createdAt),
      taskId: data.dec(_f$taskId),
      dispatchId: data.dec(_f$dispatchId),
      gateId: data.dec(_f$gateId),
      actorKind: data.dec(_f$actorKind),
      actorId: data.dec(_f$actorId),
      summary: data.dec(_f$summary),
      payload: data.dec(_f$payload),
      messageType: data.dec(_f$messageType),
      from: data.dec(_f$from),
      to: data.dec(_f$to),
      threadId: data.dec(_f$threadId),
      body: data.dec(_f$body),
      truncated: data.dec(_f$truncated),
      workspaceId: data.dec(_f$workspaceId),
      sha: data.dec(_f$sha),
      baseSha: data.dec(_f$baseSha),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static RunTimelineEntry fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<RunTimelineEntry>(map);
  }

  static RunTimelineEntry fromJson(String json) {
    return ensureInitialized().decodeJson<RunTimelineEntry>(json);
  }
}

mixin RunTimelineEntryMappable {
  String toJson() {
    return RunTimelineEntryMapper.ensureInitialized()
        .encodeJson<RunTimelineEntry>(this as RunTimelineEntry);
  }

  Map<String, dynamic> toMap() {
    return RunTimelineEntryMapper.ensureInitialized()
        .encodeMap<RunTimelineEntry>(this as RunTimelineEntry);
  }

  RunTimelineEntryCopyWith<RunTimelineEntry, RunTimelineEntry, RunTimelineEntry>
  get copyWith =>
      _RunTimelineEntryCopyWithImpl<RunTimelineEntry, RunTimelineEntry>(
        this as RunTimelineEntry,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return RunTimelineEntryMapper.ensureInitialized().stringifyValue(
      this as RunTimelineEntry,
    );
  }

  @override
  bool operator ==(Object other) {
    return RunTimelineEntryMapper.ensureInitialized().equalsValue(
      this as RunTimelineEntry,
      other,
    );
  }

  @override
  int get hashCode {
    return RunTimelineEntryMapper.ensureInitialized().hashValue(
      this as RunTimelineEntry,
    );
  }
}

extension RunTimelineEntryValueCopy<$R, $Out>
    on ObjectCopyWith<$R, RunTimelineEntry, $Out> {
  RunTimelineEntryCopyWith<$R, RunTimelineEntry, $Out>
  get $asRunTimelineEntry =>
      $base.as((v, t, t2) => _RunTimelineEntryCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class RunTimelineEntryCopyWith<$R, $In extends RunTimelineEntry, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    String? id,
    String? source,
    String? kind,
    String? createdAt,
    String? taskId,
    String? dispatchId,
    String? gateId,
    String? actorKind,
    String? actorId,
    String? summary,
    Object? payload,
    String? messageType,
    String? from,
    String? to,
    String? threadId,
    String? body,
    bool? truncated,
    String? workspaceId,
    String? sha,
    String? baseSha,
  });
  RunTimelineEntryCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _RunTimelineEntryCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, RunTimelineEntry, $Out>
    implements RunTimelineEntryCopyWith<$R, RunTimelineEntry, $Out> {
  _RunTimelineEntryCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<RunTimelineEntry> $mapper =
      RunTimelineEntryMapper.ensureInitialized();
  @override
  $R call({
    String? id,
    String? source,
    String? kind,
    String? createdAt,
    Object? taskId = $none,
    Object? dispatchId = $none,
    Object? gateId = $none,
    Object? actorKind = $none,
    Object? actorId = $none,
    String? summary,
    Object? payload = $none,
    Object? messageType = $none,
    Object? from = $none,
    Object? to = $none,
    Object? threadId = $none,
    Object? body = $none,
    bool? truncated,
    Object? workspaceId = $none,
    Object? sha = $none,
    Object? baseSha = $none,
  }) => $apply(
    FieldCopyWithData({
      if (id != null) #id: id,
      if (source != null) #source: source,
      if (kind != null) #kind: kind,
      if (createdAt != null) #createdAt: createdAt,
      if (taskId != $none) #taskId: taskId,
      if (dispatchId != $none) #dispatchId: dispatchId,
      if (gateId != $none) #gateId: gateId,
      if (actorKind != $none) #actorKind: actorKind,
      if (actorId != $none) #actorId: actorId,
      if (summary != null) #summary: summary,
      if (payload != $none) #payload: payload,
      if (messageType != $none) #messageType: messageType,
      if (from != $none) #from: from,
      if (to != $none) #to: to,
      if (threadId != $none) #threadId: threadId,
      if (body != $none) #body: body,
      if (truncated != null) #truncated: truncated,
      if (workspaceId != $none) #workspaceId: workspaceId,
      if (sha != $none) #sha: sha,
      if (baseSha != $none) #baseSha: baseSha,
    }),
  );
  @override
  RunTimelineEntry $make(CopyWithData data) => RunTimelineEntry(
    id: data.get(#id, or: $value.id),
    source: data.get(#source, or: $value.source),
    kind: data.get(#kind, or: $value.kind),
    createdAt: data.get(#createdAt, or: $value.createdAt),
    taskId: data.get(#taskId, or: $value.taskId),
    dispatchId: data.get(#dispatchId, or: $value.dispatchId),
    gateId: data.get(#gateId, or: $value.gateId),
    actorKind: data.get(#actorKind, or: $value.actorKind),
    actorId: data.get(#actorId, or: $value.actorId),
    summary: data.get(#summary, or: $value.summary),
    payload: data.get(#payload, or: $value.payload),
    messageType: data.get(#messageType, or: $value.messageType),
    from: data.get(#from, or: $value.from),
    to: data.get(#to, or: $value.to),
    threadId: data.get(#threadId, or: $value.threadId),
    body: data.get(#body, or: $value.body),
    truncated: data.get(#truncated, or: $value.truncated),
    workspaceId: data.get(#workspaceId, or: $value.workspaceId),
    sha: data.get(#sha, or: $value.sha),
    baseSha: data.get(#baseSha, or: $value.baseSha),
  );

  @override
  RunTimelineEntryCopyWith<$R2, RunTimelineEntry, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _RunTimelineEntryCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class RunTimelinePageMapper extends ClassMapperBase<RunTimelinePage> {
  RunTimelinePageMapper._();

  static RunTimelinePageMapper? _instance;
  static RunTimelinePageMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RunTimelinePageMapper._());
      RunTimelineEntryMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'RunTimelinePage';

  static String _$runId(RunTimelinePage v) => v.runId;
  static const Field<RunTimelinePage, String> _f$runId = Field(
    'runId',
    _$runId,
  );
  static List<RunTimelineEntry> _$items(RunTimelinePage v) => v.items;
  static const Field<RunTimelinePage, List<RunTimelineEntry>> _f$items = Field(
    'items',
    _$items,
    opt: true,
    def: const <RunTimelineEntry>[],
  );
  static String? _$nextCursor(RunTimelinePage v) => v.nextCursor;
  static const Field<RunTimelinePage, String> _f$nextCursor = Field(
    'nextCursor',
    _$nextCursor,
    opt: true,
  );

  @override
  final MappableFields<RunTimelinePage> fields = const {
    #runId: _f$runId,
    #items: _f$items,
    #nextCursor: _f$nextCursor,
  };

  static RunTimelinePage _instantiate(DecodingData data) {
    return RunTimelinePage(
      runId: data.dec(_f$runId),
      items: data.dec(_f$items),
      nextCursor: data.dec(_f$nextCursor),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static RunTimelinePage fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<RunTimelinePage>(map);
  }

  static RunTimelinePage fromJson(String json) {
    return ensureInitialized().decodeJson<RunTimelinePage>(json);
  }
}

mixin RunTimelinePageMappable {
  String toJson() {
    return RunTimelinePageMapper.ensureInitialized()
        .encodeJson<RunTimelinePage>(this as RunTimelinePage);
  }

  Map<String, dynamic> toMap() {
    return RunTimelinePageMapper.ensureInitialized().encodeMap<RunTimelinePage>(
      this as RunTimelinePage,
    );
  }

  RunTimelinePageCopyWith<RunTimelinePage, RunTimelinePage, RunTimelinePage>
  get copyWith =>
      _RunTimelinePageCopyWithImpl<RunTimelinePage, RunTimelinePage>(
        this as RunTimelinePage,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return RunTimelinePageMapper.ensureInitialized().stringifyValue(
      this as RunTimelinePage,
    );
  }

  @override
  bool operator ==(Object other) {
    return RunTimelinePageMapper.ensureInitialized().equalsValue(
      this as RunTimelinePage,
      other,
    );
  }

  @override
  int get hashCode {
    return RunTimelinePageMapper.ensureInitialized().hashValue(
      this as RunTimelinePage,
    );
  }
}

extension RunTimelinePageValueCopy<$R, $Out>
    on ObjectCopyWith<$R, RunTimelinePage, $Out> {
  RunTimelinePageCopyWith<$R, RunTimelinePage, $Out> get $asRunTimelinePage =>
      $base.as((v, t, t2) => _RunTimelinePageCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class RunTimelinePageCopyWith<$R, $In extends RunTimelinePage, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<
    $R,
    RunTimelineEntry,
    RunTimelineEntryCopyWith<$R, RunTimelineEntry, RunTimelineEntry>
  >
  get items;
  $R call({String? runId, List<RunTimelineEntry>? items, String? nextCursor});
  RunTimelinePageCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _RunTimelinePageCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, RunTimelinePage, $Out>
    implements RunTimelinePageCopyWith<$R, RunTimelinePage, $Out> {
  _RunTimelinePageCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<RunTimelinePage> $mapper =
      RunTimelinePageMapper.ensureInitialized();
  @override
  ListCopyWith<
    $R,
    RunTimelineEntry,
    RunTimelineEntryCopyWith<$R, RunTimelineEntry, RunTimelineEntry>
  >
  get items => ListCopyWith(
    $value.items,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(items: v),
  );
  @override
  $R call({
    String? runId,
    List<RunTimelineEntry>? items,
    Object? nextCursor = $none,
  }) => $apply(
    FieldCopyWithData({
      if (runId != null) #runId: runId,
      if (items != null) #items: items,
      if (nextCursor != $none) #nextCursor: nextCursor,
    }),
  );
  @override
  RunTimelinePage $make(CopyWithData data) => RunTimelinePage(
    runId: data.get(#runId, or: $value.runId),
    items: data.get(#items, or: $value.items),
    nextCursor: data.get(#nextCursor, or: $value.nextCursor),
  );

  @override
  RunTimelinePageCopyWith<$R2, RunTimelinePage, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _RunTimelinePageCopyWithImpl<$R2, $Out2>($value, $cast, t);
}
