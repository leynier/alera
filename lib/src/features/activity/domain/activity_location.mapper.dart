// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'activity_location.dart';

class ActivityLocationMapper extends ClassMapperBase<ActivityLocation> {
  ActivityLocationMapper._();

  static ActivityLocationMapper? _instance;
  static ActivityLocationMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ActivityLocationMapper._());
      ActivitySectionMapper.ensureInitialized();
      RunsLocationMapper.ensureInitialized();
      QuestionsLocationMapper.ensureInitialized();
      AutomationsLocationMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ActivityLocation';

  static bool _$visible(ActivityLocation v) => v.visible;
  static const Field<ActivityLocation, bool> _f$visible = Field(
    'visible',
    _$visible,
    opt: true,
    def: false,
  );
  static ActivitySection _$section(ActivityLocation v) => v.section;
  static const Field<ActivityLocation, ActivitySection> _f$section = Field(
    'section',
    _$section,
    opt: true,
    def: ActivitySection.runs,
  );
  static RunsLocation _$runs(ActivityLocation v) => v.runs;
  static const Field<ActivityLocation, RunsLocation> _f$runs = Field(
    'runs',
    _$runs,
    opt: true,
    def: const RunsLocation(),
  );
  static QuestionsLocation _$questions(ActivityLocation v) => v.questions;
  static const Field<ActivityLocation, QuestionsLocation> _f$questions = Field(
    'questions',
    _$questions,
    opt: true,
    def: const QuestionsLocation(),
  );
  static AutomationsLocation _$automations(ActivityLocation v) => v.automations;
  static const Field<ActivityLocation, AutomationsLocation> _f$automations =
      Field(
        'automations',
        _$automations,
        opt: true,
        def: const AutomationsLocation(),
      );

  @override
  final MappableFields<ActivityLocation> fields = const {
    #visible: _f$visible,
    #section: _f$section,
    #runs: _f$runs,
    #questions: _f$questions,
    #automations: _f$automations,
  };

  static ActivityLocation _instantiate(DecodingData data) {
    return ActivityLocation(
      visible: data.dec(_f$visible),
      section: data.dec(_f$section),
      runs: data.dec(_f$runs),
      questions: data.dec(_f$questions),
      automations: data.dec(_f$automations),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ActivityLocation fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ActivityLocation>(map);
  }

  static ActivityLocation fromJson(String json) {
    return ensureInitialized().decodeJson<ActivityLocation>(json);
  }
}

mixin ActivityLocationMappable {
  String toJson() {
    return ActivityLocationMapper.ensureInitialized()
        .encodeJson<ActivityLocation>(this as ActivityLocation);
  }

  Map<String, dynamic> toMap() {
    return ActivityLocationMapper.ensureInitialized()
        .encodeMap<ActivityLocation>(this as ActivityLocation);
  }

  ActivityLocationCopyWith<ActivityLocation, ActivityLocation, ActivityLocation>
  get copyWith =>
      _ActivityLocationCopyWithImpl<ActivityLocation, ActivityLocation>(
        this as ActivityLocation,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return ActivityLocationMapper.ensureInitialized().stringifyValue(
      this as ActivityLocation,
    );
  }

  @override
  bool operator ==(Object other) {
    return ActivityLocationMapper.ensureInitialized().equalsValue(
      this as ActivityLocation,
      other,
    );
  }

  @override
  int get hashCode {
    return ActivityLocationMapper.ensureInitialized().hashValue(
      this as ActivityLocation,
    );
  }
}

extension ActivityLocationValueCopy<$R, $Out>
    on ObjectCopyWith<$R, ActivityLocation, $Out> {
  ActivityLocationCopyWith<$R, ActivityLocation, $Out>
  get $asActivityLocation =>
      $base.as((v, t, t2) => _ActivityLocationCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class ActivityLocationCopyWith<$R, $In extends ActivityLocation, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  RunsLocationCopyWith<$R, RunsLocation, RunsLocation> get runs;
  QuestionsLocationCopyWith<$R, QuestionsLocation, QuestionsLocation>
  get questions;
  AutomationsLocationCopyWith<$R, AutomationsLocation, AutomationsLocation>
  get automations;
  $R call({
    bool? visible,
    ActivitySection? section,
    RunsLocation? runs,
    QuestionsLocation? questions,
    AutomationsLocation? automations,
  });
  ActivityLocationCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _ActivityLocationCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, ActivityLocation, $Out>
    implements ActivityLocationCopyWith<$R, ActivityLocation, $Out> {
  _ActivityLocationCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<ActivityLocation> $mapper =
      ActivityLocationMapper.ensureInitialized();
  @override
  RunsLocationCopyWith<$R, RunsLocation, RunsLocation> get runs =>
      $value.runs.copyWith.$chain((v) => call(runs: v));
  @override
  QuestionsLocationCopyWith<$R, QuestionsLocation, QuestionsLocation>
  get questions => $value.questions.copyWith.$chain((v) => call(questions: v));
  @override
  AutomationsLocationCopyWith<$R, AutomationsLocation, AutomationsLocation>
  get automations =>
      $value.automations.copyWith.$chain((v) => call(automations: v));
  @override
  $R call({
    bool? visible,
    ActivitySection? section,
    RunsLocation? runs,
    QuestionsLocation? questions,
    AutomationsLocation? automations,
  }) => $apply(
    FieldCopyWithData({
      if (visible != null) #visible: visible,
      if (section != null) #section: section,
      if (runs != null) #runs: runs,
      if (questions != null) #questions: questions,
      if (automations != null) #automations: automations,
    }),
  );
  @override
  ActivityLocation $make(CopyWithData data) => ActivityLocation(
    visible: data.get(#visible, or: $value.visible),
    section: data.get(#section, or: $value.section),
    runs: data.get(#runs, or: $value.runs),
    questions: data.get(#questions, or: $value.questions),
    automations: data.get(#automations, or: $value.automations),
  );

  @override
  ActivityLocationCopyWith<$R2, ActivityLocation, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _ActivityLocationCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class RunsLocationMapper extends ClassMapperBase<RunsLocation> {
  RunsLocationMapper._();

  static RunsLocationMapper? _instance;
  static RunsLocationMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = RunsLocationMapper._());
      RunBucketMapper.ensureInitialized();
      RunDetailTabMapper.ensureInitialized();
      RunTimelineFilterMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'RunsLocation';

  static String? _$projectId(RunsLocation v) => v.projectId;
  static const Field<RunsLocation, String> _f$projectId = Field(
    'projectId',
    _$projectId,
    opt: true,
  );
  static String? _$workspaceId(RunsLocation v) => v.workspaceId;
  static const Field<RunsLocation, String> _f$workspaceId = Field(
    'workspaceId',
    _$workspaceId,
    opt: true,
  );
  static String _$search(RunsLocation v) => v.search;
  static const Field<RunsLocation, String> _f$search = Field(
    'search',
    _$search,
    opt: true,
    def: '',
  );
  static RunBucket? _$bucket(RunsLocation v) => v.bucket;
  static const Field<RunsLocation, RunBucket> _f$bucket = Field(
    'bucket',
    _$bucket,
    opt: true,
  );
  static String? _$runId(RunsLocation v) => v.runId;
  static const Field<RunsLocation, String> _f$runId = Field(
    'runId',
    _$runId,
    opt: true,
  );
  static RunDetailTab _$tab(RunsLocation v) => v.tab;
  static const Field<RunsLocation, RunDetailTab> _f$tab = Field(
    'tab',
    _$tab,
    opt: true,
    def: RunDetailTab.overview,
  );
  static String? _$taskId(RunsLocation v) => v.taskId;
  static const Field<RunsLocation, String> _f$taskId = Field(
    'taskId',
    _$taskId,
    opt: true,
  );
  static String? _$gateId(RunsLocation v) => v.gateId;
  static const Field<RunsLocation, String> _f$gateId = Field(
    'gateId',
    _$gateId,
    opt: true,
  );
  static int _$gateFocusSequence(RunsLocation v) => v.gateFocusSequence;
  static const Field<RunsLocation, int> _f$gateFocusSequence = Field(
    'gateFocusSequence',
    _$gateFocusSequence,
    opt: true,
    def: 0,
  );
  static RunTimelineFilter _$timelineFilter(RunsLocation v) => v.timelineFilter;
  static const Field<RunsLocation, RunTimelineFilter> _f$timelineFilter = Field(
    'timelineFilter',
    _$timelineFilter,
    opt: true,
    def: RunTimelineFilter.all,
  );

  @override
  final MappableFields<RunsLocation> fields = const {
    #projectId: _f$projectId,
    #workspaceId: _f$workspaceId,
    #search: _f$search,
    #bucket: _f$bucket,
    #runId: _f$runId,
    #tab: _f$tab,
    #taskId: _f$taskId,
    #gateId: _f$gateId,
    #gateFocusSequence: _f$gateFocusSequence,
    #timelineFilter: _f$timelineFilter,
  };

  static RunsLocation _instantiate(DecodingData data) {
    return RunsLocation(
      projectId: data.dec(_f$projectId),
      workspaceId: data.dec(_f$workspaceId),
      search: data.dec(_f$search),
      bucket: data.dec(_f$bucket),
      runId: data.dec(_f$runId),
      tab: data.dec(_f$tab),
      taskId: data.dec(_f$taskId),
      gateId: data.dec(_f$gateId),
      gateFocusSequence: data.dec(_f$gateFocusSequence),
      timelineFilter: data.dec(_f$timelineFilter),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static RunsLocation fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<RunsLocation>(map);
  }

  static RunsLocation fromJson(String json) {
    return ensureInitialized().decodeJson<RunsLocation>(json);
  }
}

mixin RunsLocationMappable {
  String toJson() {
    return RunsLocationMapper.ensureInitialized().encodeJson<RunsLocation>(
      this as RunsLocation,
    );
  }

  Map<String, dynamic> toMap() {
    return RunsLocationMapper.ensureInitialized().encodeMap<RunsLocation>(
      this as RunsLocation,
    );
  }

  RunsLocationCopyWith<RunsLocation, RunsLocation, RunsLocation> get copyWith =>
      _RunsLocationCopyWithImpl<RunsLocation, RunsLocation>(
        this as RunsLocation,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return RunsLocationMapper.ensureInitialized().stringifyValue(
      this as RunsLocation,
    );
  }

  @override
  bool operator ==(Object other) {
    return RunsLocationMapper.ensureInitialized().equalsValue(
      this as RunsLocation,
      other,
    );
  }

  @override
  int get hashCode {
    return RunsLocationMapper.ensureInitialized().hashValue(
      this as RunsLocation,
    );
  }
}

extension RunsLocationValueCopy<$R, $Out>
    on ObjectCopyWith<$R, RunsLocation, $Out> {
  RunsLocationCopyWith<$R, RunsLocation, $Out> get $asRunsLocation =>
      $base.as((v, t, t2) => _RunsLocationCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class RunsLocationCopyWith<$R, $In extends RunsLocation, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    String? projectId,
    String? workspaceId,
    String? search,
    RunBucket? bucket,
    String? runId,
    RunDetailTab? tab,
    String? taskId,
    String? gateId,
    int? gateFocusSequence,
    RunTimelineFilter? timelineFilter,
  });
  RunsLocationCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _RunsLocationCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, RunsLocation, $Out>
    implements RunsLocationCopyWith<$R, RunsLocation, $Out> {
  _RunsLocationCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<RunsLocation> $mapper =
      RunsLocationMapper.ensureInitialized();
  @override
  $R call({
    Object? projectId = $none,
    Object? workspaceId = $none,
    String? search,
    Object? bucket = $none,
    Object? runId = $none,
    RunDetailTab? tab,
    Object? taskId = $none,
    Object? gateId = $none,
    int? gateFocusSequence,
    RunTimelineFilter? timelineFilter,
  }) => $apply(
    FieldCopyWithData({
      if (projectId != $none) #projectId: projectId,
      if (workspaceId != $none) #workspaceId: workspaceId,
      if (search != null) #search: search,
      if (bucket != $none) #bucket: bucket,
      if (runId != $none) #runId: runId,
      if (tab != null) #tab: tab,
      if (taskId != $none) #taskId: taskId,
      if (gateId != $none) #gateId: gateId,
      if (gateFocusSequence != null) #gateFocusSequence: gateFocusSequence,
      if (timelineFilter != null) #timelineFilter: timelineFilter,
    }),
  );
  @override
  RunsLocation $make(CopyWithData data) => RunsLocation(
    projectId: data.get(#projectId, or: $value.projectId),
    workspaceId: data.get(#workspaceId, or: $value.workspaceId),
    search: data.get(#search, or: $value.search),
    bucket: data.get(#bucket, or: $value.bucket),
    runId: data.get(#runId, or: $value.runId),
    tab: data.get(#tab, or: $value.tab),
    taskId: data.get(#taskId, or: $value.taskId),
    gateId: data.get(#gateId, or: $value.gateId),
    gateFocusSequence: data.get(
      #gateFocusSequence,
      or: $value.gateFocusSequence,
    ),
    timelineFilter: data.get(#timelineFilter, or: $value.timelineFilter),
  );

  @override
  RunsLocationCopyWith<$R2, RunsLocation, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _RunsLocationCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class QuestionsLocationMapper extends ClassMapperBase<QuestionsLocation> {
  QuestionsLocationMapper._();

  static QuestionsLocationMapper? _instance;
  static QuestionsLocationMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = QuestionsLocationMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'QuestionsLocation';

  static String? _$inboxFilter(QuestionsLocation v) => v.inboxFilter;
  static const Field<QuestionsLocation, String> _f$inboxFilter = Field(
    'inboxFilter',
    _$inboxFilter,
    opt: true,
  );
  static InboxQuestionStatus? _$statusFilter(QuestionsLocation v) =>
      v.statusFilter;
  static const Field<QuestionsLocation, InboxQuestionStatus> _f$statusFilter =
      Field('statusFilter', _$statusFilter, opt: true);
  static String? _$selectedThreadId(QuestionsLocation v) => v.selectedThreadId;
  static const Field<QuestionsLocation, String> _f$selectedThreadId = Field(
    'selectedThreadId',
    _$selectedThreadId,
    opt: true,
  );
  static InboxComposeRequest? _$compose(QuestionsLocation v) => v.compose;
  static const Field<QuestionsLocation, InboxComposeRequest> _f$compose = Field(
    'compose',
    _$compose,
    opt: true,
  );
  static int _$composeSequence(QuestionsLocation v) => v.composeSequence;
  static const Field<QuestionsLocation, int> _f$composeSequence = Field(
    'composeSequence',
    _$composeSequence,
    opt: true,
    def: 0,
  );

  @override
  final MappableFields<QuestionsLocation> fields = const {
    #inboxFilter: _f$inboxFilter,
    #statusFilter: _f$statusFilter,
    #selectedThreadId: _f$selectedThreadId,
    #compose: _f$compose,
    #composeSequence: _f$composeSequence,
  };

  static QuestionsLocation _instantiate(DecodingData data) {
    return QuestionsLocation(
      inboxFilter: data.dec(_f$inboxFilter),
      statusFilter: data.dec(_f$statusFilter),
      selectedThreadId: data.dec(_f$selectedThreadId),
      compose: data.dec(_f$compose),
      composeSequence: data.dec(_f$composeSequence),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static QuestionsLocation fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<QuestionsLocation>(map);
  }

  static QuestionsLocation fromJson(String json) {
    return ensureInitialized().decodeJson<QuestionsLocation>(json);
  }
}

mixin QuestionsLocationMappable {
  String toJson() {
    return QuestionsLocationMapper.ensureInitialized()
        .encodeJson<QuestionsLocation>(this as QuestionsLocation);
  }

  Map<String, dynamic> toMap() {
    return QuestionsLocationMapper.ensureInitialized()
        .encodeMap<QuestionsLocation>(this as QuestionsLocation);
  }

  QuestionsLocationCopyWith<
    QuestionsLocation,
    QuestionsLocation,
    QuestionsLocation
  >
  get copyWith =>
      _QuestionsLocationCopyWithImpl<QuestionsLocation, QuestionsLocation>(
        this as QuestionsLocation,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return QuestionsLocationMapper.ensureInitialized().stringifyValue(
      this as QuestionsLocation,
    );
  }

  @override
  bool operator ==(Object other) {
    return QuestionsLocationMapper.ensureInitialized().equalsValue(
      this as QuestionsLocation,
      other,
    );
  }

  @override
  int get hashCode {
    return QuestionsLocationMapper.ensureInitialized().hashValue(
      this as QuestionsLocation,
    );
  }
}

extension QuestionsLocationValueCopy<$R, $Out>
    on ObjectCopyWith<$R, QuestionsLocation, $Out> {
  QuestionsLocationCopyWith<$R, QuestionsLocation, $Out>
  get $asQuestionsLocation => $base.as(
    (v, t, t2) => _QuestionsLocationCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class QuestionsLocationCopyWith<
  $R,
  $In extends QuestionsLocation,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    String? inboxFilter,
    InboxQuestionStatus? statusFilter,
    String? selectedThreadId,
    InboxComposeRequest? compose,
    int? composeSequence,
  });
  QuestionsLocationCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _QuestionsLocationCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, QuestionsLocation, $Out>
    implements QuestionsLocationCopyWith<$R, QuestionsLocation, $Out> {
  _QuestionsLocationCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<QuestionsLocation> $mapper =
      QuestionsLocationMapper.ensureInitialized();
  @override
  $R call({
    Object? inboxFilter = $none,
    Object? statusFilter = $none,
    Object? selectedThreadId = $none,
    Object? compose = $none,
    int? composeSequence,
  }) => $apply(
    FieldCopyWithData({
      if (inboxFilter != $none) #inboxFilter: inboxFilter,
      if (statusFilter != $none) #statusFilter: statusFilter,
      if (selectedThreadId != $none) #selectedThreadId: selectedThreadId,
      if (compose != $none) #compose: compose,
      if (composeSequence != null) #composeSequence: composeSequence,
    }),
  );
  @override
  QuestionsLocation $make(CopyWithData data) => QuestionsLocation(
    inboxFilter: data.get(#inboxFilter, or: $value.inboxFilter),
    statusFilter: data.get(#statusFilter, or: $value.statusFilter),
    selectedThreadId: data.get(#selectedThreadId, or: $value.selectedThreadId),
    compose: data.get(#compose, or: $value.compose),
    composeSequence: data.get(#composeSequence, or: $value.composeSequence),
  );

  @override
  QuestionsLocationCopyWith<$R2, QuestionsLocation, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _QuestionsLocationCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class AutomationsLocationMapper extends ClassMapperBase<AutomationsLocation> {
  AutomationsLocationMapper._();

  static AutomationsLocationMapper? _instance;
  static AutomationsLocationMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = AutomationsLocationMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'AutomationsLocation';

  static AutomationScope _$scope(AutomationsLocation v) => v.scope;
  static const Field<AutomationsLocation, AutomationScope> _f$scope = Field(
    'scope',
    _$scope,
    opt: true,
    def: AutomationScope.all,
  );
  static AutomationCatalogFilters _$filters(AutomationsLocation v) => v.filters;
  static const Field<AutomationsLocation, AutomationCatalogFilters> _f$filters =
      Field(
        'filters',
        _$filters,
        opt: true,
        def: const AutomationCatalogFilters(),
      );
  static String? _$selectedId(AutomationsLocation v) => v.selectedId;
  static const Field<AutomationsLocation, String> _f$selectedId = Field(
    'selectedId',
    _$selectedId,
    opt: true,
  );
  static String? _$selectedRunId(AutomationsLocation v) => v.selectedRunId;
  static const Field<AutomationsLocation, String> _f$selectedRunId = Field(
    'selectedRunId',
    _$selectedRunId,
    opt: true,
  );
  static AutomationAuthoringRequest? _$authoring(AutomationsLocation v) =>
      v.authoring;
  static const Field<AutomationsLocation, AutomationAuthoringRequest>
  _f$authoring = Field('authoring', _$authoring, opt: true);
  static int _$authoringSequence(AutomationsLocation v) => v.authoringSequence;
  static const Field<AutomationsLocation, int> _f$authoringSequence = Field(
    'authoringSequence',
    _$authoringSequence,
    opt: true,
    def: 0,
  );

  @override
  final MappableFields<AutomationsLocation> fields = const {
    #scope: _f$scope,
    #filters: _f$filters,
    #selectedId: _f$selectedId,
    #selectedRunId: _f$selectedRunId,
    #authoring: _f$authoring,
    #authoringSequence: _f$authoringSequence,
  };

  static AutomationsLocation _instantiate(DecodingData data) {
    return AutomationsLocation(
      scope: data.dec(_f$scope),
      filters: data.dec(_f$filters),
      selectedId: data.dec(_f$selectedId),
      selectedRunId: data.dec(_f$selectedRunId),
      authoring: data.dec(_f$authoring),
      authoringSequence: data.dec(_f$authoringSequence),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static AutomationsLocation fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<AutomationsLocation>(map);
  }

  static AutomationsLocation fromJson(String json) {
    return ensureInitialized().decodeJson<AutomationsLocation>(json);
  }
}

mixin AutomationsLocationMappable {
  String toJson() {
    return AutomationsLocationMapper.ensureInitialized()
        .encodeJson<AutomationsLocation>(this as AutomationsLocation);
  }

  Map<String, dynamic> toMap() {
    return AutomationsLocationMapper.ensureInitialized()
        .encodeMap<AutomationsLocation>(this as AutomationsLocation);
  }

  AutomationsLocationCopyWith<
    AutomationsLocation,
    AutomationsLocation,
    AutomationsLocation
  >
  get copyWith =>
      _AutomationsLocationCopyWithImpl<
        AutomationsLocation,
        AutomationsLocation
      >(this as AutomationsLocation, $identity, $identity);
  @override
  String toString() {
    return AutomationsLocationMapper.ensureInitialized().stringifyValue(
      this as AutomationsLocation,
    );
  }

  @override
  bool operator ==(Object other) {
    return AutomationsLocationMapper.ensureInitialized().equalsValue(
      this as AutomationsLocation,
      other,
    );
  }

  @override
  int get hashCode {
    return AutomationsLocationMapper.ensureInitialized().hashValue(
      this as AutomationsLocation,
    );
  }
}

extension AutomationsLocationValueCopy<$R, $Out>
    on ObjectCopyWith<$R, AutomationsLocation, $Out> {
  AutomationsLocationCopyWith<$R, AutomationsLocation, $Out>
  get $asAutomationsLocation => $base.as(
    (v, t, t2) => _AutomationsLocationCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class AutomationsLocationCopyWith<
  $R,
  $In extends AutomationsLocation,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    AutomationScope? scope,
    AutomationCatalogFilters? filters,
    String? selectedId,
    String? selectedRunId,
    AutomationAuthoringRequest? authoring,
    int? authoringSequence,
  });
  AutomationsLocationCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _AutomationsLocationCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, AutomationsLocation, $Out>
    implements AutomationsLocationCopyWith<$R, AutomationsLocation, $Out> {
  _AutomationsLocationCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<AutomationsLocation> $mapper =
      AutomationsLocationMapper.ensureInitialized();
  @override
  $R call({
    AutomationScope? scope,
    AutomationCatalogFilters? filters,
    Object? selectedId = $none,
    Object? selectedRunId = $none,
    Object? authoring = $none,
    int? authoringSequence,
  }) => $apply(
    FieldCopyWithData({
      if (scope != null) #scope: scope,
      if (filters != null) #filters: filters,
      if (selectedId != $none) #selectedId: selectedId,
      if (selectedRunId != $none) #selectedRunId: selectedRunId,
      if (authoring != $none) #authoring: authoring,
      if (authoringSequence != null) #authoringSequence: authoringSequence,
    }),
  );
  @override
  AutomationsLocation $make(CopyWithData data) => AutomationsLocation(
    scope: data.get(#scope, or: $value.scope),
    filters: data.get(#filters, or: $value.filters),
    selectedId: data.get(#selectedId, or: $value.selectedId),
    selectedRunId: data.get(#selectedRunId, or: $value.selectedRunId),
    authoring: data.get(#authoring, or: $value.authoring),
    authoringSequence: data.get(
      #authoringSequence,
      or: $value.authoringSequence,
    ),
  );

  @override
  AutomationsLocationCopyWith<$R2, AutomationsLocation, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _AutomationsLocationCopyWithImpl<$R2, $Out2>($value, $cast, t);
}
