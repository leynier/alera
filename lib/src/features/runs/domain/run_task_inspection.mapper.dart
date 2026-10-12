// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'run_task_inspection.dart';

class TaskHistoryCursorMapper extends ClassMapperBase<TaskHistoryCursor> {
  TaskHistoryCursorMapper._();

  static TaskHistoryCursorMapper? _instance;
  static TaskHistoryCursorMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = TaskHistoryCursorMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'TaskHistoryCursor';

  static String _$occurredAt(TaskHistoryCursor v) => v.occurredAt;
  static const Field<TaskHistoryCursor, String> _f$occurredAt = Field(
    'occurredAt',
    _$occurredAt,
  );
  static String _$id(TaskHistoryCursor v) => v.id;
  static const Field<TaskHistoryCursor, String> _f$id = Field('id', _$id);
  static int _$revision(TaskHistoryCursor v) => v.revision;
  static const Field<TaskHistoryCursor, int> _f$revision = Field(
    'revision',
    _$revision,
  );

  @override
  final MappableFields<TaskHistoryCursor> fields = const {
    #occurredAt: _f$occurredAt,
    #id: _f$id,
    #revision: _f$revision,
  };

  static TaskHistoryCursor _instantiate(DecodingData data) {
    return TaskHistoryCursor(
      occurredAt: data.dec(_f$occurredAt),
      id: data.dec(_f$id),
      revision: data.dec(_f$revision),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static TaskHistoryCursor fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<TaskHistoryCursor>(map);
  }

  static TaskHistoryCursor fromJson(String json) {
    return ensureInitialized().decodeJson<TaskHistoryCursor>(json);
  }
}

mixin TaskHistoryCursorMappable {
  String toJson() {
    return TaskHistoryCursorMapper.ensureInitialized()
        .encodeJson<TaskHistoryCursor>(this as TaskHistoryCursor);
  }

  Map<String, dynamic> toMap() {
    return TaskHistoryCursorMapper.ensureInitialized()
        .encodeMap<TaskHistoryCursor>(this as TaskHistoryCursor);
  }

  TaskHistoryCursorCopyWith<
    TaskHistoryCursor,
    TaskHistoryCursor,
    TaskHistoryCursor
  >
  get copyWith =>
      _TaskHistoryCursorCopyWithImpl<TaskHistoryCursor, TaskHistoryCursor>(
        this as TaskHistoryCursor,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return TaskHistoryCursorMapper.ensureInitialized().stringifyValue(
      this as TaskHistoryCursor,
    );
  }

  @override
  bool operator ==(Object other) {
    return TaskHistoryCursorMapper.ensureInitialized().equalsValue(
      this as TaskHistoryCursor,
      other,
    );
  }

  @override
  int get hashCode {
    return TaskHistoryCursorMapper.ensureInitialized().hashValue(
      this as TaskHistoryCursor,
    );
  }
}

extension TaskHistoryCursorValueCopy<$R, $Out>
    on ObjectCopyWith<$R, TaskHistoryCursor, $Out> {
  TaskHistoryCursorCopyWith<$R, TaskHistoryCursor, $Out>
  get $asTaskHistoryCursor => $base.as(
    (v, t, t2) => _TaskHistoryCursorCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class TaskHistoryCursorCopyWith<
  $R,
  $In extends TaskHistoryCursor,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({String? occurredAt, String? id, int? revision});
  TaskHistoryCursorCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _TaskHistoryCursorCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, TaskHistoryCursor, $Out>
    implements TaskHistoryCursorCopyWith<$R, TaskHistoryCursor, $Out> {
  _TaskHistoryCursorCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<TaskHistoryCursor> $mapper =
      TaskHistoryCursorMapper.ensureInitialized();
  @override
  $R call({String? occurredAt, String? id, int? revision}) => $apply(
    FieldCopyWithData({
      if (occurredAt != null) #occurredAt: occurredAt,
      if (id != null) #id: id,
      if (revision != null) #revision: revision,
    }),
  );
  @override
  TaskHistoryCursor $make(CopyWithData data) => TaskHistoryCursor(
    occurredAt: data.get(#occurredAt, or: $value.occurredAt),
    id: data.get(#id, or: $value.id),
    revision: data.get(#revision, or: $value.revision),
  );

  @override
  TaskHistoryCursorCopyWith<$R2, TaskHistoryCursor, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _TaskHistoryCursorCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class TaskHistoryEntryMapper extends ClassMapperBase<TaskHistoryEntry> {
  TaskHistoryEntryMapper._();

  static TaskHistoryEntryMapper? _instance;
  static TaskHistoryEntryMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = TaskHistoryEntryMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'TaskHistoryEntry';

  static String _$id(TaskHistoryEntry v) => v.id;
  static const Field<TaskHistoryEntry, String> _f$id = Field('id', _$id);
  static String _$occurredAt(TaskHistoryEntry v) => v.occurredAt;
  static const Field<TaskHistoryEntry, String> _f$occurredAt = Field(
    'occurredAt',
    _$occurredAt,
  );
  static String _$kind(TaskHistoryEntry v) => v.kind;
  static const Field<TaskHistoryEntry, String> _f$kind = Field('kind', _$kind);
  static String _$status(TaskHistoryEntry v) => v.status;
  static const Field<TaskHistoryEntry, String> _f$status = Field(
    'status',
    _$status,
  );
  static String? _$summary(TaskHistoryEntry v) => v.summary;
  static const Field<TaskHistoryEntry, String> _f$summary = Field(
    'summary',
    _$summary,
    opt: true,
  );

  @override
  final MappableFields<TaskHistoryEntry> fields = const {
    #id: _f$id,
    #occurredAt: _f$occurredAt,
    #kind: _f$kind,
    #status: _f$status,
    #summary: _f$summary,
  };

  static TaskHistoryEntry _instantiate(DecodingData data) {
    return TaskHistoryEntry(
      id: data.dec(_f$id),
      occurredAt: data.dec(_f$occurredAt),
      kind: data.dec(_f$kind),
      status: data.dec(_f$status),
      summary: data.dec(_f$summary),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static TaskHistoryEntry fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<TaskHistoryEntry>(map);
  }

  static TaskHistoryEntry fromJson(String json) {
    return ensureInitialized().decodeJson<TaskHistoryEntry>(json);
  }
}

mixin TaskHistoryEntryMappable {
  String toJson() {
    return TaskHistoryEntryMapper.ensureInitialized()
        .encodeJson<TaskHistoryEntry>(this as TaskHistoryEntry);
  }

  Map<String, dynamic> toMap() {
    return TaskHistoryEntryMapper.ensureInitialized()
        .encodeMap<TaskHistoryEntry>(this as TaskHistoryEntry);
  }

  TaskHistoryEntryCopyWith<TaskHistoryEntry, TaskHistoryEntry, TaskHistoryEntry>
  get copyWith =>
      _TaskHistoryEntryCopyWithImpl<TaskHistoryEntry, TaskHistoryEntry>(
        this as TaskHistoryEntry,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return TaskHistoryEntryMapper.ensureInitialized().stringifyValue(
      this as TaskHistoryEntry,
    );
  }

  @override
  bool operator ==(Object other) {
    return TaskHistoryEntryMapper.ensureInitialized().equalsValue(
      this as TaskHistoryEntry,
      other,
    );
  }

  @override
  int get hashCode {
    return TaskHistoryEntryMapper.ensureInitialized().hashValue(
      this as TaskHistoryEntry,
    );
  }
}

extension TaskHistoryEntryValueCopy<$R, $Out>
    on ObjectCopyWith<$R, TaskHistoryEntry, $Out> {
  TaskHistoryEntryCopyWith<$R, TaskHistoryEntry, $Out>
  get $asTaskHistoryEntry =>
      $base.as((v, t, t2) => _TaskHistoryEntryCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class TaskHistoryEntryCopyWith<$R, $In extends TaskHistoryEntry, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    String? id,
    String? occurredAt,
    String? kind,
    String? status,
    String? summary,
  });
  TaskHistoryEntryCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _TaskHistoryEntryCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, TaskHistoryEntry, $Out>
    implements TaskHistoryEntryCopyWith<$R, TaskHistoryEntry, $Out> {
  _TaskHistoryEntryCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<TaskHistoryEntry> $mapper =
      TaskHistoryEntryMapper.ensureInitialized();
  @override
  $R call({
    String? id,
    String? occurredAt,
    String? kind,
    String? status,
    Object? summary = $none,
  }) => $apply(
    FieldCopyWithData({
      if (id != null) #id: id,
      if (occurredAt != null) #occurredAt: occurredAt,
      if (kind != null) #kind: kind,
      if (status != null) #status: status,
      if (summary != $none) #summary: summary,
    }),
  );
  @override
  TaskHistoryEntry $make(CopyWithData data) => TaskHistoryEntry(
    id: data.get(#id, or: $value.id),
    occurredAt: data.get(#occurredAt, or: $value.occurredAt),
    kind: data.get(#kind, or: $value.kind),
    status: data.get(#status, or: $value.status),
    summary: data.get(#summary, or: $value.summary),
  );

  @override
  TaskHistoryEntryCopyWith<$R2, TaskHistoryEntry, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _TaskHistoryEntryCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class TaskResultInspectionMapper extends ClassMapperBase<TaskResultInspection> {
  TaskResultInspectionMapper._();

  static TaskResultInspectionMapper? _instance;
  static TaskResultInspectionMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = TaskResultInspectionMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'TaskResultInspection';

  static String? _$summary(TaskResultInspection v) => v.summary;
  static const Field<TaskResultInspection, String> _f$summary = Field(
    'summary',
    _$summary,
    opt: true,
  );
  static String? _$completionKind(TaskResultInspection v) => v.completionKind;
  static const Field<TaskResultInspection, String> _f$completionKind = Field(
    'completionKind',
    _$completionKind,
    opt: true,
  );
  static List<String> _$artifacts(TaskResultInspection v) => v.artifacts;
  static const Field<TaskResultInspection, List<String>> _f$artifacts = Field(
    'artifacts',
    _$artifacts,
    opt: true,
    def: const <String>[],
  );
  static List<String> _$validation(TaskResultInspection v) => v.validation;
  static const Field<TaskResultInspection, List<String>> _f$validation = Field(
    'validation',
    _$validation,
    opt: true,
    def: const <String>[],
  );
  static String? _$preview(TaskResultInspection v) => v.preview;
  static const Field<TaskResultInspection, String> _f$preview = Field(
    'preview',
    _$preview,
    opt: true,
  );
  static bool _$truncated(TaskResultInspection v) => v.truncated;
  static const Field<TaskResultInspection, bool> _f$truncated = Field(
    'truncated',
    _$truncated,
    opt: true,
    def: false,
  );

  @override
  final MappableFields<TaskResultInspection> fields = const {
    #summary: _f$summary,
    #completionKind: _f$completionKind,
    #artifacts: _f$artifacts,
    #validation: _f$validation,
    #preview: _f$preview,
    #truncated: _f$truncated,
  };

  static TaskResultInspection _instantiate(DecodingData data) {
    return TaskResultInspection(
      summary: data.dec(_f$summary),
      completionKind: data.dec(_f$completionKind),
      artifacts: data.dec(_f$artifacts),
      validation: data.dec(_f$validation),
      preview: data.dec(_f$preview),
      truncated: data.dec(_f$truncated),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static TaskResultInspection fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<TaskResultInspection>(map);
  }

  static TaskResultInspection fromJson(String json) {
    return ensureInitialized().decodeJson<TaskResultInspection>(json);
  }
}

mixin TaskResultInspectionMappable {
  String toJson() {
    return TaskResultInspectionMapper.ensureInitialized()
        .encodeJson<TaskResultInspection>(this as TaskResultInspection);
  }

  Map<String, dynamic> toMap() {
    return TaskResultInspectionMapper.ensureInitialized()
        .encodeMap<TaskResultInspection>(this as TaskResultInspection);
  }

  TaskResultInspectionCopyWith<
    TaskResultInspection,
    TaskResultInspection,
    TaskResultInspection
  >
  get copyWith =>
      _TaskResultInspectionCopyWithImpl<
        TaskResultInspection,
        TaskResultInspection
      >(this as TaskResultInspection, $identity, $identity);
  @override
  String toString() {
    return TaskResultInspectionMapper.ensureInitialized().stringifyValue(
      this as TaskResultInspection,
    );
  }

  @override
  bool operator ==(Object other) {
    return TaskResultInspectionMapper.ensureInitialized().equalsValue(
      this as TaskResultInspection,
      other,
    );
  }

  @override
  int get hashCode {
    return TaskResultInspectionMapper.ensureInitialized().hashValue(
      this as TaskResultInspection,
    );
  }
}

extension TaskResultInspectionValueCopy<$R, $Out>
    on ObjectCopyWith<$R, TaskResultInspection, $Out> {
  TaskResultInspectionCopyWith<$R, TaskResultInspection, $Out>
  get $asTaskResultInspection => $base.as(
    (v, t, t2) => _TaskResultInspectionCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class TaskResultInspectionCopyWith<
  $R,
  $In extends TaskResultInspection,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get artifacts;
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get validation;
  $R call({
    String? summary,
    String? completionKind,
    List<String>? artifacts,
    List<String>? validation,
    String? preview,
    bool? truncated,
  });
  TaskResultInspectionCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _TaskResultInspectionCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, TaskResultInspection, $Out>
    implements TaskResultInspectionCopyWith<$R, TaskResultInspection, $Out> {
  _TaskResultInspectionCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<TaskResultInspection> $mapper =
      TaskResultInspectionMapper.ensureInitialized();
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get artifacts =>
      ListCopyWith(
        $value.artifacts,
        (v, t) => ObjectCopyWith(v, $identity, t),
        (v) => call(artifacts: v),
      );
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get validation =>
      ListCopyWith(
        $value.validation,
        (v, t) => ObjectCopyWith(v, $identity, t),
        (v) => call(validation: v),
      );
  @override
  $R call({
    Object? summary = $none,
    Object? completionKind = $none,
    List<String>? artifacts,
    List<String>? validation,
    Object? preview = $none,
    bool? truncated,
  }) => $apply(
    FieldCopyWithData({
      if (summary != $none) #summary: summary,
      if (completionKind != $none) #completionKind: completionKind,
      if (artifacts != null) #artifacts: artifacts,
      if (validation != null) #validation: validation,
      if (preview != $none) #preview: preview,
      if (truncated != null) #truncated: truncated,
    }),
  );
  @override
  TaskResultInspection $make(CopyWithData data) => TaskResultInspection(
    summary: data.get(#summary, or: $value.summary),
    completionKind: data.get(#completionKind, or: $value.completionKind),
    artifacts: data.get(#artifacts, or: $value.artifacts),
    validation: data.get(#validation, or: $value.validation),
    preview: data.get(#preview, or: $value.preview),
    truncated: data.get(#truncated, or: $value.truncated),
  );

  @override
  TaskResultInspectionCopyWith<$R2, TaskResultInspection, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _TaskResultInspectionCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class TaskAttemptInspectionMapper
    extends ClassMapperBase<TaskAttemptInspection> {
  TaskAttemptInspectionMapper._();

  static TaskAttemptInspectionMapper? _instance;
  static TaskAttemptInspectionMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = TaskAttemptInspectionMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'TaskAttemptInspection';

  static int _$planRevision(TaskAttemptInspection v) => v.planRevision;
  static const Field<TaskAttemptInspection, int> _f$planRevision = Field(
    'planRevision',
    _$planRevision,
    opt: true,
    def: 0,
  );
  static int _$attempt(TaskAttemptInspection v) => v.attempt;
  static const Field<TaskAttemptInspection, int> _f$attempt = Field(
    'attempt',
    _$attempt,
    opt: true,
    def: 1,
  );
  static String _$phase(TaskAttemptInspection v) => v.phase;
  static const Field<TaskAttemptInspection, String> _f$phase = Field(
    'phase',
    _$phase,
    opt: true,
    def: '',
  );
  static bool _$canRetry(TaskAttemptInspection v) => v.canRetry;
  static const Field<TaskAttemptInspection, bool> _f$canRetry = Field(
    'canRetry',
    _$canRetry,
    opt: true,
    def: false,
  );
  static bool _$canRetryIntegration(TaskAttemptInspection v) =>
      v.canRetryIntegration;
  static const Field<TaskAttemptInspection, bool> _f$canRetryIntegration =
      Field(
        'canRetryIntegration',
        _$canRetryIntegration,
        opt: true,
        def: false,
      );
  static String _$state(TaskAttemptInspection v) => v.state;
  static const Field<TaskAttemptInspection, String> _f$state = Field(
    'state',
    _$state,
    opt: true,
    def: '',
  );
  static String? _$integrationId(TaskAttemptInspection v) => v.integrationId;
  static const Field<TaskAttemptInspection, String> _f$integrationId = Field(
    'integrationId',
    _$integrationId,
    opt: true,
  );
  static String? _$integrationRequestId(TaskAttemptInspection v) =>
      v.integrationRequestId;
  static const Field<TaskAttemptInspection, String> _f$integrationRequestId =
      Field('integrationRequestId', _$integrationRequestId, opt: true);
  static String? _$launchId(TaskAttemptInspection v) => v.launchId;
  static const Field<TaskAttemptInspection, String> _f$launchId = Field(
    'launchId',
    _$launchId,
    opt: true,
  );
  static String _$executionWorkspaceId(TaskAttemptInspection v) =>
      v.executionWorkspaceId;
  static const Field<TaskAttemptInspection, String> _f$executionWorkspaceId =
      Field('executionWorkspaceId', _$executionWorkspaceId);
  static String? _$worktree(TaskAttemptInspection v) => v.worktree;
  static const Field<TaskAttemptInspection, String> _f$worktree = Field(
    'worktree',
    _$worktree,
    opt: true,
  );
  static String? _$branch(TaskAttemptInspection v) => v.branch;
  static const Field<TaskAttemptInspection, String> _f$branch = Field(
    'branch',
    _$branch,
    opt: true,
  );
  static String? _$baseSha(TaskAttemptInspection v) => v.baseSha;
  static const Field<TaskAttemptInspection, String> _f$baseSha = Field(
    'baseSha',
    _$baseSha,
    opt: true,
  );
  static String? _$completionSha(TaskAttemptInspection v) => v.completionSha;
  static const Field<TaskAttemptInspection, String> _f$completionSha = Field(
    'completionSha',
    _$completionSha,
    opt: true,
  );
  static String? _$integratedSha(TaskAttemptInspection v) => v.integratedSha;
  static const Field<TaskAttemptInspection, String> _f$integratedSha = Field(
    'integratedSha',
    _$integratedSha,
    opt: true,
  );
  static List<String> _$conflictPaths(TaskAttemptInspection v) =>
      v.conflictPaths;
  static const Field<TaskAttemptInspection, List<String>> _f$conflictPaths =
      Field('conflictPaths', _$conflictPaths, opt: true, def: const <String>[]);
  static bool _$conflictsTruncated(TaskAttemptInspection v) =>
      v.conflictsTruncated;
  static const Field<TaskAttemptInspection, bool> _f$conflictsTruncated = Field(
    'conflictsTruncated',
    _$conflictsTruncated,
    opt: true,
    def: false,
  );
  static String? _$error(TaskAttemptInspection v) => v.error;
  static const Field<TaskAttemptInspection, String> _f$error = Field(
    'error',
    _$error,
    opt: true,
  );

  @override
  final MappableFields<TaskAttemptInspection> fields = const {
    #planRevision: _f$planRevision,
    #attempt: _f$attempt,
    #phase: _f$phase,
    #canRetry: _f$canRetry,
    #canRetryIntegration: _f$canRetryIntegration,
    #state: _f$state,
    #integrationId: _f$integrationId,
    #integrationRequestId: _f$integrationRequestId,
    #launchId: _f$launchId,
    #executionWorkspaceId: _f$executionWorkspaceId,
    #worktree: _f$worktree,
    #branch: _f$branch,
    #baseSha: _f$baseSha,
    #completionSha: _f$completionSha,
    #integratedSha: _f$integratedSha,
    #conflictPaths: _f$conflictPaths,
    #conflictsTruncated: _f$conflictsTruncated,
    #error: _f$error,
  };

  static TaskAttemptInspection _instantiate(DecodingData data) {
    return TaskAttemptInspection(
      planRevision: data.dec(_f$planRevision),
      attempt: data.dec(_f$attempt),
      phase: data.dec(_f$phase),
      canRetry: data.dec(_f$canRetry),
      canRetryIntegration: data.dec(_f$canRetryIntegration),
      state: data.dec(_f$state),
      integrationId: data.dec(_f$integrationId),
      integrationRequestId: data.dec(_f$integrationRequestId),
      launchId: data.dec(_f$launchId),
      executionWorkspaceId: data.dec(_f$executionWorkspaceId),
      worktree: data.dec(_f$worktree),
      branch: data.dec(_f$branch),
      baseSha: data.dec(_f$baseSha),
      completionSha: data.dec(_f$completionSha),
      integratedSha: data.dec(_f$integratedSha),
      conflictPaths: data.dec(_f$conflictPaths),
      conflictsTruncated: data.dec(_f$conflictsTruncated),
      error: data.dec(_f$error),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static TaskAttemptInspection fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<TaskAttemptInspection>(map);
  }

  static TaskAttemptInspection fromJson(String json) {
    return ensureInitialized().decodeJson<TaskAttemptInspection>(json);
  }
}

mixin TaskAttemptInspectionMappable {
  String toJson() {
    return TaskAttemptInspectionMapper.ensureInitialized()
        .encodeJson<TaskAttemptInspection>(this as TaskAttemptInspection);
  }

  Map<String, dynamic> toMap() {
    return TaskAttemptInspectionMapper.ensureInitialized()
        .encodeMap<TaskAttemptInspection>(this as TaskAttemptInspection);
  }

  TaskAttemptInspectionCopyWith<
    TaskAttemptInspection,
    TaskAttemptInspection,
    TaskAttemptInspection
  >
  get copyWith =>
      _TaskAttemptInspectionCopyWithImpl<
        TaskAttemptInspection,
        TaskAttemptInspection
      >(this as TaskAttemptInspection, $identity, $identity);
  @override
  String toString() {
    return TaskAttemptInspectionMapper.ensureInitialized().stringifyValue(
      this as TaskAttemptInspection,
    );
  }

  @override
  bool operator ==(Object other) {
    return TaskAttemptInspectionMapper.ensureInitialized().equalsValue(
      this as TaskAttemptInspection,
      other,
    );
  }

  @override
  int get hashCode {
    return TaskAttemptInspectionMapper.ensureInitialized().hashValue(
      this as TaskAttemptInspection,
    );
  }
}

extension TaskAttemptInspectionValueCopy<$R, $Out>
    on ObjectCopyWith<$R, TaskAttemptInspection, $Out> {
  TaskAttemptInspectionCopyWith<$R, TaskAttemptInspection, $Out>
  get $asTaskAttemptInspection => $base.as(
    (v, t, t2) => _TaskAttemptInspectionCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class TaskAttemptInspectionCopyWith<
  $R,
  $In extends TaskAttemptInspection,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>>
  get conflictPaths;
  $R call({
    int? planRevision,
    int? attempt,
    String? phase,
    bool? canRetry,
    bool? canRetryIntegration,
    String? state,
    String? integrationId,
    String? integrationRequestId,
    String? launchId,
    String? executionWorkspaceId,
    String? worktree,
    String? branch,
    String? baseSha,
    String? completionSha,
    String? integratedSha,
    List<String>? conflictPaths,
    bool? conflictsTruncated,
    String? error,
  });
  TaskAttemptInspectionCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _TaskAttemptInspectionCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, TaskAttemptInspection, $Out>
    implements TaskAttemptInspectionCopyWith<$R, TaskAttemptInspection, $Out> {
  _TaskAttemptInspectionCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<TaskAttemptInspection> $mapper =
      TaskAttemptInspectionMapper.ensureInitialized();
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>>
  get conflictPaths => ListCopyWith(
    $value.conflictPaths,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(conflictPaths: v),
  );
  @override
  $R call({
    int? planRevision,
    int? attempt,
    String? phase,
    bool? canRetry,
    bool? canRetryIntegration,
    String? state,
    Object? integrationId = $none,
    Object? integrationRequestId = $none,
    Object? launchId = $none,
    String? executionWorkspaceId,
    Object? worktree = $none,
    Object? branch = $none,
    Object? baseSha = $none,
    Object? completionSha = $none,
    Object? integratedSha = $none,
    List<String>? conflictPaths,
    bool? conflictsTruncated,
    Object? error = $none,
  }) => $apply(
    FieldCopyWithData({
      if (planRevision != null) #planRevision: planRevision,
      if (attempt != null) #attempt: attempt,
      if (phase != null) #phase: phase,
      if (canRetry != null) #canRetry: canRetry,
      if (canRetryIntegration != null)
        #canRetryIntegration: canRetryIntegration,
      if (state != null) #state: state,
      if (integrationId != $none) #integrationId: integrationId,
      if (integrationRequestId != $none)
        #integrationRequestId: integrationRequestId,
      if (launchId != $none) #launchId: launchId,
      if (executionWorkspaceId != null)
        #executionWorkspaceId: executionWorkspaceId,
      if (worktree != $none) #worktree: worktree,
      if (branch != $none) #branch: branch,
      if (baseSha != $none) #baseSha: baseSha,
      if (completionSha != $none) #completionSha: completionSha,
      if (integratedSha != $none) #integratedSha: integratedSha,
      if (conflictPaths != null) #conflictPaths: conflictPaths,
      if (conflictsTruncated != null) #conflictsTruncated: conflictsTruncated,
      if (error != $none) #error: error,
    }),
  );
  @override
  TaskAttemptInspection $make(CopyWithData data) => TaskAttemptInspection(
    planRevision: data.get(#planRevision, or: $value.planRevision),
    attempt: data.get(#attempt, or: $value.attempt),
    phase: data.get(#phase, or: $value.phase),
    canRetry: data.get(#canRetry, or: $value.canRetry),
    canRetryIntegration: data.get(
      #canRetryIntegration,
      or: $value.canRetryIntegration,
    ),
    state: data.get(#state, or: $value.state),
    integrationId: data.get(#integrationId, or: $value.integrationId),
    integrationRequestId: data.get(
      #integrationRequestId,
      or: $value.integrationRequestId,
    ),
    launchId: data.get(#launchId, or: $value.launchId),
    executionWorkspaceId: data.get(
      #executionWorkspaceId,
      or: $value.executionWorkspaceId,
    ),
    worktree: data.get(#worktree, or: $value.worktree),
    branch: data.get(#branch, or: $value.branch),
    baseSha: data.get(#baseSha, or: $value.baseSha),
    completionSha: data.get(#completionSha, or: $value.completionSha),
    integratedSha: data.get(#integratedSha, or: $value.integratedSha),
    conflictPaths: data.get(#conflictPaths, or: $value.conflictPaths),
    conflictsTruncated: data.get(
      #conflictsTruncated,
      or: $value.conflictsTruncated,
    ),
    error: data.get(#error, or: $value.error),
  );

  @override
  TaskAttemptInspectionCopyWith<$R2, TaskAttemptInspection, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _TaskAttemptInspectionCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class TaskInspectionMapper extends ClassMapperBase<TaskInspection> {
  TaskInspectionMapper._();

  static TaskInspectionMapper? _instance;
  static TaskInspectionMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = TaskInspectionMapper._());
      TaskResultInspectionMapper.ensureInitialized();
      TaskHistoryEntryMapper.ensureInitialized();
      TaskHistoryCursorMapper.ensureInitialized();
      TaskAttemptInspectionMapper.ensureInitialized();
      RunGateMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'TaskInspection';

  static int _$revision(TaskInspection v) => v.revision;
  static const Field<TaskInspection, int> _f$revision = Field(
    'revision',
    _$revision,
  );
  static String _$taskId(TaskInspection v) => v.taskId;
  static const Field<TaskInspection, String> _f$taskId = Field(
    'taskId',
    _$taskId,
  );
  static String _$runId(TaskInspection v) => v.runId;
  static const Field<TaskInspection, String> _f$runId = Field('runId', _$runId);
  static String _$title(TaskInspection v) => v.title;
  static const Field<TaskInspection, String> _f$title = Field('title', _$title);
  static String _$description(TaskInspection v) => v.description;
  static const Field<TaskInspection, String> _f$description = Field(
    'description',
    _$description,
    opt: true,
    def: '',
  );
  static bool _$descriptionTruncated(TaskInspection v) =>
      v.descriptionTruncated;
  static const Field<TaskInspection, bool> _f$descriptionTruncated = Field(
    'descriptionTruncated',
    _$descriptionTruncated,
    opt: true,
    def: false,
  );
  static String _$status(TaskInspection v) => v.status;
  static const Field<TaskInspection, String> _f$status = Field(
    'status',
    _$status,
  );
  static String? _$stageId(TaskInspection v) => v.stageId;
  static const Field<TaskInspection, String> _f$stageId = Field(
    'stageId',
    _$stageId,
    opt: true,
  );
  static String _$workspaceId(TaskInspection v) => v.workspaceId;
  static const Field<TaskInspection, String> _f$workspaceId = Field(
    'workspaceId',
    _$workspaceId,
  );
  static String? _$workspaceName(TaskInspection v) => v.workspaceName;
  static const Field<TaskInspection, String> _f$workspaceName = Field(
    'workspaceName',
    _$workspaceName,
    opt: true,
  );
  static String? _$workspacePath(TaskInspection v) => v.workspacePath;
  static const Field<TaskInspection, String> _f$workspacePath = Field(
    'workspacePath',
    _$workspacePath,
    opt: true,
  );
  static String? _$branch(TaskInspection v) => v.branch;
  static const Field<TaskInspection, String> _f$branch = Field(
    'branch',
    _$branch,
    opt: true,
  );
  static String? _$baseSha(TaskInspection v) => v.baseSha;
  static const Field<TaskInspection, String> _f$baseSha = Field(
    'baseSha',
    _$baseSha,
    opt: true,
  );
  static String? _$profile(TaskInspection v) => v.profile;
  static const Field<TaskInspection, String> _f$profile = Field(
    'profile',
    _$profile,
    opt: true,
  );
  static String? _$terminalHandle(TaskInspection v) => v.terminalHandle;
  static const Field<TaskInspection, String> _f$terminalHandle = Field(
    'terminalHandle',
    _$terminalHandle,
    opt: true,
  );
  static List<String> _$dependencies(TaskInspection v) => v.dependencies;
  static const Field<TaskInspection, List<String>> _f$dependencies = Field(
    'dependencies',
    _$dependencies,
    opt: true,
    def: const <String>[],
  );
  static bool _$dependenciesTruncated(TaskInspection v) =>
      v.dependenciesTruncated;
  static const Field<TaskInspection, bool> _f$dependenciesTruncated = Field(
    'dependenciesTruncated',
    _$dependenciesTruncated,
    opt: true,
    def: false,
  );
  static TaskResultInspection _$result(TaskInspection v) => v.result;
  static const Field<TaskInspection, TaskResultInspection> _f$result = Field(
    'result',
    _$result,
    opt: true,
    def: const TaskResultInspection(),
  );
  static List<TaskHistoryEntry> _$history(TaskInspection v) => v.history;
  static const Field<TaskInspection, List<TaskHistoryEntry>> _f$history = Field(
    'history',
    _$history,
    opt: true,
    def: const <TaskHistoryEntry>[],
  );
  static TaskHistoryCursor? _$nextCursor(TaskInspection v) => v.nextCursor;
  static const Field<TaskInspection, TaskHistoryCursor> _f$nextCursor = Field(
    'nextCursor',
    _$nextCursor,
    opt: true,
  );
  static TaskAttemptInspection? _$attempt(TaskInspection v) => v.attempt;
  static const Field<TaskInspection, TaskAttemptInspection> _f$attempt = Field(
    'attempt',
    _$attempt,
    opt: true,
  );
  static List<RunGate> _$gates(TaskInspection v) => v.gates;
  static const Field<TaskInspection, List<RunGate>> _f$gates = Field(
    'gates',
    _$gates,
    opt: true,
    def: const <RunGate>[],
  );
  static String? _$logicalId(TaskInspection v) => v.logicalId;
  static const Field<TaskInspection, String> _f$logicalId = Field(
    'logicalId',
    _$logicalId,
    opt: true,
  );
  static int? _$planRevision(TaskInspection v) => v.planRevision;
  static const Field<TaskInspection, int> _f$planRevision = Field(
    'planRevision',
    _$planRevision,
    opt: true,
  );
  static String? _$roleId(TaskInspection v) => v.roleId;
  static const Field<TaskInspection, String> _f$roleId = Field(
    'roleId',
    _$roleId,
    opt: true,
  );

  @override
  final MappableFields<TaskInspection> fields = const {
    #revision: _f$revision,
    #taskId: _f$taskId,
    #runId: _f$runId,
    #title: _f$title,
    #description: _f$description,
    #descriptionTruncated: _f$descriptionTruncated,
    #status: _f$status,
    #stageId: _f$stageId,
    #workspaceId: _f$workspaceId,
    #workspaceName: _f$workspaceName,
    #workspacePath: _f$workspacePath,
    #branch: _f$branch,
    #baseSha: _f$baseSha,
    #profile: _f$profile,
    #terminalHandle: _f$terminalHandle,
    #dependencies: _f$dependencies,
    #dependenciesTruncated: _f$dependenciesTruncated,
    #result: _f$result,
    #history: _f$history,
    #nextCursor: _f$nextCursor,
    #attempt: _f$attempt,
    #gates: _f$gates,
    #logicalId: _f$logicalId,
    #planRevision: _f$planRevision,
    #roleId: _f$roleId,
  };

  static TaskInspection _instantiate(DecodingData data) {
    return TaskInspection(
      revision: data.dec(_f$revision),
      taskId: data.dec(_f$taskId),
      runId: data.dec(_f$runId),
      title: data.dec(_f$title),
      description: data.dec(_f$description),
      descriptionTruncated: data.dec(_f$descriptionTruncated),
      status: data.dec(_f$status),
      stageId: data.dec(_f$stageId),
      workspaceId: data.dec(_f$workspaceId),
      workspaceName: data.dec(_f$workspaceName),
      workspacePath: data.dec(_f$workspacePath),
      branch: data.dec(_f$branch),
      baseSha: data.dec(_f$baseSha),
      profile: data.dec(_f$profile),
      terminalHandle: data.dec(_f$terminalHandle),
      dependencies: data.dec(_f$dependencies),
      dependenciesTruncated: data.dec(_f$dependenciesTruncated),
      result: data.dec(_f$result),
      history: data.dec(_f$history),
      nextCursor: data.dec(_f$nextCursor),
      attempt: data.dec(_f$attempt),
      gates: data.dec(_f$gates),
      logicalId: data.dec(_f$logicalId),
      planRevision: data.dec(_f$planRevision),
      roleId: data.dec(_f$roleId),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static TaskInspection fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<TaskInspection>(map);
  }

  static TaskInspection fromJson(String json) {
    return ensureInitialized().decodeJson<TaskInspection>(json);
  }
}

mixin TaskInspectionMappable {
  String toJson() {
    return TaskInspectionMapper.ensureInitialized().encodeJson<TaskInspection>(
      this as TaskInspection,
    );
  }

  Map<String, dynamic> toMap() {
    return TaskInspectionMapper.ensureInitialized().encodeMap<TaskInspection>(
      this as TaskInspection,
    );
  }

  TaskInspectionCopyWith<TaskInspection, TaskInspection, TaskInspection>
  get copyWith => _TaskInspectionCopyWithImpl<TaskInspection, TaskInspection>(
    this as TaskInspection,
    $identity,
    $identity,
  );
  @override
  String toString() {
    return TaskInspectionMapper.ensureInitialized().stringifyValue(
      this as TaskInspection,
    );
  }

  @override
  bool operator ==(Object other) {
    return TaskInspectionMapper.ensureInitialized().equalsValue(
      this as TaskInspection,
      other,
    );
  }

  @override
  int get hashCode {
    return TaskInspectionMapper.ensureInitialized().hashValue(
      this as TaskInspection,
    );
  }
}

extension TaskInspectionValueCopy<$R, $Out>
    on ObjectCopyWith<$R, TaskInspection, $Out> {
  TaskInspectionCopyWith<$R, TaskInspection, $Out> get $asTaskInspection =>
      $base.as((v, t, t2) => _TaskInspectionCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class TaskInspectionCopyWith<$R, $In extends TaskInspection, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get dependencies;
  TaskResultInspectionCopyWith<$R, TaskResultInspection, TaskResultInspection>
  get result;
  ListCopyWith<
    $R,
    TaskHistoryEntry,
    TaskHistoryEntryCopyWith<$R, TaskHistoryEntry, TaskHistoryEntry>
  >
  get history;
  TaskHistoryCursorCopyWith<$R, TaskHistoryCursor, TaskHistoryCursor>?
  get nextCursor;
  TaskAttemptInspectionCopyWith<
    $R,
    TaskAttemptInspection,
    TaskAttemptInspection
  >?
  get attempt;
  ListCopyWith<$R, RunGate, RunGateCopyWith<$R, RunGate, RunGate>> get gates;
  $R call({
    int? revision,
    String? taskId,
    String? runId,
    String? title,
    String? description,
    bool? descriptionTruncated,
    String? status,
    String? stageId,
    String? workspaceId,
    String? workspaceName,
    String? workspacePath,
    String? branch,
    String? baseSha,
    String? profile,
    String? terminalHandle,
    List<String>? dependencies,
    bool? dependenciesTruncated,
    TaskResultInspection? result,
    List<TaskHistoryEntry>? history,
    TaskHistoryCursor? nextCursor,
    TaskAttemptInspection? attempt,
    List<RunGate>? gates,
    String? logicalId,
    int? planRevision,
    String? roleId,
  });
  TaskInspectionCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _TaskInspectionCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, TaskInspection, $Out>
    implements TaskInspectionCopyWith<$R, TaskInspection, $Out> {
  _TaskInspectionCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<TaskInspection> $mapper =
      TaskInspectionMapper.ensureInitialized();
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>>
  get dependencies => ListCopyWith(
    $value.dependencies,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(dependencies: v),
  );
  @override
  TaskResultInspectionCopyWith<$R, TaskResultInspection, TaskResultInspection>
  get result => $value.result.copyWith.$chain((v) => call(result: v));
  @override
  ListCopyWith<
    $R,
    TaskHistoryEntry,
    TaskHistoryEntryCopyWith<$R, TaskHistoryEntry, TaskHistoryEntry>
  >
  get history => ListCopyWith(
    $value.history,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(history: v),
  );
  @override
  TaskHistoryCursorCopyWith<$R, TaskHistoryCursor, TaskHistoryCursor>?
  get nextCursor =>
      $value.nextCursor?.copyWith.$chain((v) => call(nextCursor: v));
  @override
  TaskAttemptInspectionCopyWith<
    $R,
    TaskAttemptInspection,
    TaskAttemptInspection
  >?
  get attempt => $value.attempt?.copyWith.$chain((v) => call(attempt: v));
  @override
  ListCopyWith<$R, RunGate, RunGateCopyWith<$R, RunGate, RunGate>> get gates =>
      ListCopyWith(
        $value.gates,
        (v, t) => v.copyWith.$chain(t),
        (v) => call(gates: v),
      );
  @override
  $R call({
    int? revision,
    String? taskId,
    String? runId,
    String? title,
    String? description,
    bool? descriptionTruncated,
    String? status,
    Object? stageId = $none,
    String? workspaceId,
    Object? workspaceName = $none,
    Object? workspacePath = $none,
    Object? branch = $none,
    Object? baseSha = $none,
    Object? profile = $none,
    Object? terminalHandle = $none,
    List<String>? dependencies,
    bool? dependenciesTruncated,
    TaskResultInspection? result,
    List<TaskHistoryEntry>? history,
    Object? nextCursor = $none,
    Object? attempt = $none,
    List<RunGate>? gates,
    Object? logicalId = $none,
    Object? planRevision = $none,
    Object? roleId = $none,
  }) => $apply(
    FieldCopyWithData({
      if (revision != null) #revision: revision,
      if (taskId != null) #taskId: taskId,
      if (runId != null) #runId: runId,
      if (title != null) #title: title,
      if (description != null) #description: description,
      if (descriptionTruncated != null)
        #descriptionTruncated: descriptionTruncated,
      if (status != null) #status: status,
      if (stageId != $none) #stageId: stageId,
      if (workspaceId != null) #workspaceId: workspaceId,
      if (workspaceName != $none) #workspaceName: workspaceName,
      if (workspacePath != $none) #workspacePath: workspacePath,
      if (branch != $none) #branch: branch,
      if (baseSha != $none) #baseSha: baseSha,
      if (profile != $none) #profile: profile,
      if (terminalHandle != $none) #terminalHandle: terminalHandle,
      if (dependencies != null) #dependencies: dependencies,
      if (dependenciesTruncated != null)
        #dependenciesTruncated: dependenciesTruncated,
      if (result != null) #result: result,
      if (history != null) #history: history,
      if (nextCursor != $none) #nextCursor: nextCursor,
      if (attempt != $none) #attempt: attempt,
      if (gates != null) #gates: gates,
      if (logicalId != $none) #logicalId: logicalId,
      if (planRevision != $none) #planRevision: planRevision,
      if (roleId != $none) #roleId: roleId,
    }),
  );
  @override
  TaskInspection $make(CopyWithData data) => TaskInspection(
    revision: data.get(#revision, or: $value.revision),
    taskId: data.get(#taskId, or: $value.taskId),
    runId: data.get(#runId, or: $value.runId),
    title: data.get(#title, or: $value.title),
    description: data.get(#description, or: $value.description),
    descriptionTruncated: data.get(
      #descriptionTruncated,
      or: $value.descriptionTruncated,
    ),
    status: data.get(#status, or: $value.status),
    stageId: data.get(#stageId, or: $value.stageId),
    workspaceId: data.get(#workspaceId, or: $value.workspaceId),
    workspaceName: data.get(#workspaceName, or: $value.workspaceName),
    workspacePath: data.get(#workspacePath, or: $value.workspacePath),
    branch: data.get(#branch, or: $value.branch),
    baseSha: data.get(#baseSha, or: $value.baseSha),
    profile: data.get(#profile, or: $value.profile),
    terminalHandle: data.get(#terminalHandle, or: $value.terminalHandle),
    dependencies: data.get(#dependencies, or: $value.dependencies),
    dependenciesTruncated: data.get(
      #dependenciesTruncated,
      or: $value.dependenciesTruncated,
    ),
    result: data.get(#result, or: $value.result),
    history: data.get(#history, or: $value.history),
    nextCursor: data.get(#nextCursor, or: $value.nextCursor),
    attempt: data.get(#attempt, or: $value.attempt),
    gates: data.get(#gates, or: $value.gates),
    logicalId: data.get(#logicalId, or: $value.logicalId),
    planRevision: data.get(#planRevision, or: $value.planRevision),
    roleId: data.get(#roleId, or: $value.roleId),
  );

  @override
  TaskInspectionCopyWith<$R2, TaskInspection, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _TaskInspectionCopyWithImpl<$R2, $Out2>($value, $cast, t);
}
