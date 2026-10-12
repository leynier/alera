// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mobile_run_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The paired runtime as the run screens see it. Rebuilds with every
/// reconnection; a host without `runsV1` fails with [RunsUpdateRequired].

@ProviderFor(mobileRunsClient)
final mobileRunsClientProvider = MobileRunsClientFamily._();

/// The paired runtime as the run screens see it. Rebuilds with every
/// reconnection; a host without `runsV1` fails with [RunsUpdateRequired].

final class MobileRunsClientProvider
    extends
        $FunctionalProvider<
          AsyncValue<MobileRunsClient>,
          MobileRunsClient,
          FutureOr<MobileRunsClient>
        >
    with $FutureModifier<MobileRunsClient>, $FutureProvider<MobileRunsClient> {
  /// The paired runtime as the run screens see it. Rebuilds with every
  /// reconnection; a host without `runsV1` fails with [RunsUpdateRequired].
  MobileRunsClientProvider._({
    required MobileRunsClientFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'mobileRunsClientProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileRunsClientHash();

  @override
  String toString() {
    return r'mobileRunsClientProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<MobileRunsClient> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<MobileRunsClient> create(Ref ref) {
    final argument = this.argument as String;
    return mobileRunsClient(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is MobileRunsClientProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileRunsClientHash() => r'eafc88dc12e1b2c3bb3659f4523a104d0ca4a210';

/// The paired runtime as the run screens see it. Rebuilds with every
/// reconnection; a host without `runsV1` fails with [RunsUpdateRequired].

final class MobileRunsClientFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<MobileRunsClient>, String> {
  MobileRunsClientFamily._()
    : super(
        retry: null,
        name: r'mobileRunsClientProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The paired runtime as the run screens see it. Rebuilds with every
  /// reconnection; a host without `runsV1` fails with [RunsUpdateRequired].

  MobileRunsClientProvider call(String hostId) =>
      MobileRunsClientProvider._(argument: hostId, from: this);

  @override
  String toString() => r'mobileRunsClientProvider';
}

@ProviderFor(mobileRunRepository)
final mobileRunRepositoryProvider = MobileRunRepositoryFamily._();

final class MobileRunRepositoryProvider
    extends
        $FunctionalProvider<
          AsyncValue<MobileRuntimeRunRepository>,
          MobileRuntimeRunRepository,
          FutureOr<MobileRuntimeRunRepository>
        >
    with
        $FutureModifier<MobileRuntimeRunRepository>,
        $FutureProvider<MobileRuntimeRunRepository> {
  MobileRunRepositoryProvider._({
    required MobileRunRepositoryFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'mobileRunRepositoryProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileRunRepositoryHash();

  @override
  String toString() {
    return r'mobileRunRepositoryProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<MobileRuntimeRunRepository> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<MobileRuntimeRunRepository> create(Ref ref) {
    final argument = this.argument as String;
    return mobileRunRepository(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is MobileRunRepositoryProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileRunRepositoryHash() =>
    r'3319eb16fbe841d91c4dca56aba22242948616fb';

final class MobileRunRepositoryFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<MobileRuntimeRunRepository>,
          String
        > {
  MobileRunRepositoryFamily._()
    : super(
        retry: null,
        name: r'mobileRunRepositoryProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  MobileRunRepositoryProvider call(String hostId) =>
      MobileRunRepositoryProvider._(argument: hostId, from: this);

  @override
  String toString() => r'mobileRunRepositoryProvider';
}

/// One board group, filtered by the runtime, a page at a time. A change or
/// new filters start again from the first page.

@ProviderFor(MobileRunBoard)
final mobileRunBoardProvider = MobileRunBoardFamily._();

/// One board group, filtered by the runtime, a page at a time. A change or
/// new filters start again from the first page.
final class MobileRunBoardProvider
    extends $AsyncNotifierProvider<MobileRunBoard, RunBoardPage> {
  /// One board group, filtered by the runtime, a page at a time. A change or
  /// new filters start again from the first page.
  MobileRunBoardProvider._({
    required MobileRunBoardFamily super.from,
    required (String, {RunBucket? bucket, String? search, String? workspaceId})
    super.argument,
  }) : super(
         retry: null,
         name: r'mobileRunBoardProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileRunBoardHash();

  @override
  String toString() {
    return r'mobileRunBoardProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  MobileRunBoard create() => MobileRunBoard();

  @override
  bool operator ==(Object other) {
    return other is MobileRunBoardProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileRunBoardHash() => r'3208417afadbf305f2127c198d4f9655e1601fed';

/// One board group, filtered by the runtime, a page at a time. A change or
/// new filters start again from the first page.

final class MobileRunBoardFamily extends $Family
    with
        $ClassFamilyOverride<
          MobileRunBoard,
          AsyncValue<RunBoardPage>,
          RunBoardPage,
          FutureOr<RunBoardPage>,
          (String, {RunBucket? bucket, String? search, String? workspaceId})
        > {
  MobileRunBoardFamily._()
    : super(
        retry: null,
        name: r'mobileRunBoardProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// One board group, filtered by the runtime, a page at a time. A change or
  /// new filters start again from the first page.

  MobileRunBoardProvider call(
    String hostId, {
    RunBucket? bucket,
    String? search,
    String? workspaceId,
  }) => MobileRunBoardProvider._(
    argument: (
      hostId,
      bucket: bucket,
      search: search,
      workspaceId: workspaceId,
    ),
    from: this,
  );

  @override
  String toString() => r'mobileRunBoardProvider';
}

/// One board group, filtered by the runtime, a page at a time. A change or
/// new filters start again from the first page.

abstract class _$MobileRunBoard extends $AsyncNotifier<RunBoardPage> {
  late final _$args =
      ref.$arg
          as (String, {RunBucket? bucket, String? search, String? workspaceId});
  String get hostId => _$args.$1;
  RunBucket? get bucket => _$args.bucket;
  String? get search => _$args.search;
  String? get workspaceId => _$args.workspaceId;

  FutureOr<RunBoardPage> build(
    String hostId, {
    RunBucket? bucket,
    String? search,
    String? workspaceId,
  });
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<RunBoardPage>, RunBoardPage>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<RunBoardPage>, RunBoardPage>,
              AsyncValue<RunBoardPage>,
              Object?,
              Object?
            >;
    return element.handleCreate(
      ref,
      () => build(
        _$args.$1,
        bucket: _$args.bucket,
        search: _$args.search,
        workspaceId: _$args.workspaceId,
      ),
    );
  }
}

/// Runs needing attention, for the dashboard and the Runs segment.

@ProviderFor(mobileRunAttentionCount)
final mobileRunAttentionCountProvider = MobileRunAttentionCountFamily._();

/// Runs needing attention, for the dashboard and the Runs segment.

final class MobileRunAttentionCountProvider
    extends $FunctionalProvider<AsyncValue<int>, int, FutureOr<int>>
    with $FutureModifier<int>, $FutureProvider<int> {
  /// Runs needing attention, for the dashboard and the Runs segment.
  MobileRunAttentionCountProvider._({
    required MobileRunAttentionCountFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'mobileRunAttentionCountProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileRunAttentionCountHash();

  @override
  String toString() {
    return r'mobileRunAttentionCountProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<int> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<int> create(Ref ref) {
    final argument = this.argument as String;
    return mobileRunAttentionCount(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is MobileRunAttentionCountProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileRunAttentionCountHash() =>
    r'70f6cde768228d53e6985828551de0c5b1c583ec';

/// Runs needing attention, for the dashboard and the Runs segment.

final class MobileRunAttentionCountFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<int>, String> {
  MobileRunAttentionCountFamily._()
    : super(
        retry: null,
        name: r'mobileRunAttentionCountProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Runs needing attention, for the dashboard and the Runs segment.

  MobileRunAttentionCountProvider call(String hostId) =>
      MobileRunAttentionCountProvider._(argument: hostId, from: this);

  @override
  String toString() => r'mobileRunAttentionCountProvider';
}

/// One run. A failed refresh keeps the last snapshot in `state.value`.

@ProviderFor(MobileRunDetail)
final mobileRunDetailProvider = MobileRunDetailFamily._();

/// One run. A failed refresh keeps the last snapshot in `state.value`.
final class MobileRunDetailProvider
    extends $AsyncNotifierProvider<MobileRunDetail, RunDetail> {
  /// One run. A failed refresh keeps the last snapshot in `state.value`.
  MobileRunDetailProvider._({
    required MobileRunDetailFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'mobileRunDetailProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileRunDetailHash();

  @override
  String toString() {
    return r'mobileRunDetailProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  MobileRunDetail create() => MobileRunDetail();

  @override
  bool operator ==(Object other) {
    return other is MobileRunDetailProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileRunDetailHash() => r'715e95f176591d8f6f0e25c4cdfb43ed07d070d3';

/// One run. A failed refresh keeps the last snapshot in `state.value`.

final class MobileRunDetailFamily extends $Family
    with
        $ClassFamilyOverride<
          MobileRunDetail,
          AsyncValue<RunDetail>,
          RunDetail,
          FutureOr<RunDetail>,
          (String, String)
        > {
  MobileRunDetailFamily._()
    : super(
        retry: null,
        name: r'mobileRunDetailProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// One run. A failed refresh keeps the last snapshot in `state.value`.

  MobileRunDetailProvider call(String hostId, String runId) =>
      MobileRunDetailProvider._(argument: (hostId, runId), from: this);

  @override
  String toString() => r'mobileRunDetailProvider';
}

/// One run. A failed refresh keeps the last snapshot in `state.value`.

abstract class _$MobileRunDetail extends $AsyncNotifier<RunDetail> {
  late final _$args = ref.$arg as (String, String);
  String get hostId => _$args.$1;
  String get runId => _$args.$2;

  FutureOr<RunDetail> build(String hostId, String runId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<RunDetail>, RunDetail>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<RunDetail>, RunDetail>,
              AsyncValue<RunDetail>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}

/// A run's timeline, newest first; Load Older Events appends a page.

@ProviderFor(MobileRunTimeline)
final mobileRunTimelineProvider = MobileRunTimelineFamily._();

/// A run's timeline, newest first; Load Older Events appends a page.
final class MobileRunTimelineProvider
    extends $AsyncNotifierProvider<MobileRunTimeline, RunTimelinePage> {
  /// A run's timeline, newest first; Load Older Events appends a page.
  MobileRunTimelineProvider._({
    required MobileRunTimelineFamily super.from,
    required (String, String, {String? taskId}) super.argument,
  }) : super(
         retry: null,
         name: r'mobileRunTimelineProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileRunTimelineHash();

  @override
  String toString() {
    return r'mobileRunTimelineProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  MobileRunTimeline create() => MobileRunTimeline();

  @override
  bool operator ==(Object other) {
    return other is MobileRunTimelineProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileRunTimelineHash() => r'1c6e8cd1ec020788d5e19a7048fbbbde226d4420';

/// A run's timeline, newest first; Load Older Events appends a page.

final class MobileRunTimelineFamily extends $Family
    with
        $ClassFamilyOverride<
          MobileRunTimeline,
          AsyncValue<RunTimelinePage>,
          RunTimelinePage,
          FutureOr<RunTimelinePage>,
          (String, String, {String? taskId})
        > {
  MobileRunTimelineFamily._()
    : super(
        retry: null,
        name: r'mobileRunTimelineProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// A run's timeline, newest first; Load Older Events appends a page.

  MobileRunTimelineProvider call(
    String hostId,
    String runId, {
    String? taskId,
  }) => MobileRunTimelineProvider._(
    argument: (hostId, runId, taskId: taskId),
    from: this,
  );

  @override
  String toString() => r'mobileRunTimelineProvider';
}

/// A run's timeline, newest first; Load Older Events appends a page.

abstract class _$MobileRunTimeline extends $AsyncNotifier<RunTimelinePage> {
  late final _$args = ref.$arg as (String, String, {String? taskId});
  String get hostId => _$args.$1;
  String get runId => _$args.$2;
  String? get taskId => _$args.taskId;

  FutureOr<RunTimelinePage> build(
    String hostId,
    String runId, {
    String? taskId,
  });
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<RunTimelinePage>, RunTimelinePage>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<RunTimelinePage>, RunTimelinePage>,
              AsyncValue<RunTimelinePage>,
              Object?,
              Object?
            >;
    return element.handleCreate(
      ref,
      () => build(_$args.$1, _$args.$2, taskId: _$args.taskId),
    );
  }
}

/// One gate with its plan or evidence.

@ProviderFor(MobileRunGate)
final mobileRunGateProvider = MobileRunGateFamily._();

/// One gate with its plan or evidence.
final class MobileRunGateProvider
    extends $AsyncNotifierProvider<MobileRunGate, RunGateDetail> {
  /// One gate with its plan or evidence.
  MobileRunGateProvider._({
    required MobileRunGateFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'mobileRunGateProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileRunGateHash();

  @override
  String toString() {
    return r'mobileRunGateProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  MobileRunGate create() => MobileRunGate();

  @override
  bool operator ==(Object other) {
    return other is MobileRunGateProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileRunGateHash() => r'2801dc061579279bf046a34168a5adf77d647efa';

/// One gate with its plan or evidence.

final class MobileRunGateFamily extends $Family
    with
        $ClassFamilyOverride<
          MobileRunGate,
          AsyncValue<RunGateDetail>,
          RunGateDetail,
          FutureOr<RunGateDetail>,
          (String, String)
        > {
  MobileRunGateFamily._()
    : super(
        retry: null,
        name: r'mobileRunGateProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// One gate with its plan or evidence.

  MobileRunGateProvider call(String hostId, String gateId) =>
      MobileRunGateProvider._(argument: (hostId, gateId), from: this);

  @override
  String toString() => r'mobileRunGateProvider';
}

/// One gate with its plan or evidence.

abstract class _$MobileRunGate extends $AsyncNotifier<RunGateDetail> {
  late final _$args = ref.$arg as (String, String);
  String get hostId => _$args.$1;
  String get gateId => _$args.$2;

  FutureOr<RunGateDetail> build(String hostId, String gateId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<RunGateDetail>, RunGateDetail>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<RunGateDetail>, RunGateDetail>,
              AsyncValue<RunGateDetail>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}

/// One task with its result, attempt, gates and history.

@ProviderFor(MobileRunTask)
final mobileRunTaskProvider = MobileRunTaskFamily._();

/// One task with its result, attempt, gates and history.
final class MobileRunTaskProvider
    extends $AsyncNotifierProvider<MobileRunTask, RunTaskInspection> {
  /// One task with its result, attempt, gates and history.
  MobileRunTaskProvider._({
    required MobileRunTaskFamily super.from,
    required (String, String, String) super.argument,
  }) : super(
         retry: null,
         name: r'mobileRunTaskProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileRunTaskHash();

  @override
  String toString() {
    return r'mobileRunTaskProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  MobileRunTask create() => MobileRunTask();

  @override
  bool operator ==(Object other) {
    return other is MobileRunTaskProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileRunTaskHash() => r'ba421419dd623115711b41537cc0c78253a0e591';

/// One task with its result, attempt, gates and history.

final class MobileRunTaskFamily extends $Family
    with
        $ClassFamilyOverride<
          MobileRunTask,
          AsyncValue<RunTaskInspection>,
          RunTaskInspection,
          FutureOr<RunTaskInspection>,
          (String, String, String)
        > {
  MobileRunTaskFamily._()
    : super(
        retry: null,
        name: r'mobileRunTaskProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// One task with its result, attempt, gates and history.

  MobileRunTaskProvider call(String hostId, String runId, String taskId) =>
      MobileRunTaskProvider._(argument: (hostId, runId, taskId), from: this);

  @override
  String toString() => r'mobileRunTaskProvider';
}

/// One task with its result, attempt, gates and history.

abstract class _$MobileRunTask extends $AsyncNotifier<RunTaskInspection> {
  late final _$args = ref.$arg as (String, String, String);
  String get hostId => _$args.$1;
  String get runId => _$args.$2;
  String get taskId => _$args.$3;

  FutureOr<RunTaskInspection> build(String hostId, String runId, String taskId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<RunTaskInspection>, RunTaskInspection>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<RunTaskInspection>, RunTaskInspection>,
              AsyncValue<RunTaskInspection>,
              Object?,
              Object?
            >;
    return element.handleCreate(
      ref,
      () => build(_$args.$1, _$args.$2, _$args.$3),
    );
  }
}

/// Templates New Run offers, project recipes of [workspaceId] included.

@ProviderFor(mobileRecipeCatalog)
final mobileRecipeCatalogProvider = MobileRecipeCatalogFamily._();

/// Templates New Run offers, project recipes of [workspaceId] included.

final class MobileRecipeCatalogProvider
    extends
        $FunctionalProvider<
          AsyncValue<RecipeCatalog>,
          RecipeCatalog,
          FutureOr<RecipeCatalog>
        >
    with $FutureModifier<RecipeCatalog>, $FutureProvider<RecipeCatalog> {
  /// Templates New Run offers, project recipes of [workspaceId] included.
  MobileRecipeCatalogProvider._({
    required MobileRecipeCatalogFamily super.from,
    required (String, {String? workspaceId}) super.argument,
  }) : super(
         retry: null,
         name: r'mobileRecipeCatalogProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileRecipeCatalogHash();

  @override
  String toString() {
    return r'mobileRecipeCatalogProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<RecipeCatalog> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<RecipeCatalog> create(Ref ref) {
    final argument = this.argument as (String, {String? workspaceId});
    return mobileRecipeCatalog(
      ref,
      argument.$1,
      workspaceId: argument.workspaceId,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is MobileRecipeCatalogProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileRecipeCatalogHash() =>
    r'f3fcb848e8841b7e8a28f9548ad6c3e36d7fe6f7';

/// Templates New Run offers, project recipes of [workspaceId] included.

final class MobileRecipeCatalogFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<RecipeCatalog>,
          (String, {String? workspaceId})
        > {
  MobileRecipeCatalogFamily._()
    : super(
        retry: null,
        name: r'mobileRecipeCatalogProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Templates New Run offers, project recipes of [workspaceId] included.

  MobileRecipeCatalogProvider call(String hostId, {String? workspaceId}) =>
      MobileRecipeCatalogProvider._(
        argument: (hostId, workspaceId: workspaceId),
        from: this,
      );

  @override
  String toString() => r'mobileRecipeCatalogProvider';
}

@ProviderFor(mobileRunWorkspaces)
final mobileRunWorkspacesProvider = MobileRunWorkspacesFamily._();

final class MobileRunWorkspacesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<WorkspaceSummary>>,
          List<WorkspaceSummary>,
          FutureOr<List<WorkspaceSummary>>
        >
    with
        $FutureModifier<List<WorkspaceSummary>>,
        $FutureProvider<List<WorkspaceSummary>> {
  MobileRunWorkspacesProvider._({
    required MobileRunWorkspacesFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'mobileRunWorkspacesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileRunWorkspacesHash();

  @override
  String toString() {
    return r'mobileRunWorkspacesProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<WorkspaceSummary>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<WorkspaceSummary>> create(Ref ref) {
    final argument = this.argument as String;
    return mobileRunWorkspaces(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is MobileRunWorkspacesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileRunWorkspacesHash() =>
    r'081027661aa51d09217683d83a9509cfe1d8227f';

final class MobileRunWorkspacesFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<WorkspaceSummary>>, String> {
  MobileRunWorkspacesFamily._()
    : super(
        retry: null,
        name: r'mobileRunWorkspacesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  MobileRunWorkspacesProvider call(String hostId) =>
      MobileRunWorkspacesProvider._(argument: hostId, from: this);

  @override
  String toString() => r'mobileRunWorkspacesProvider';
}

@ProviderFor(mobileRunAgentProfiles)
final mobileRunAgentProfilesProvider = MobileRunAgentProfilesFamily._();

final class MobileRunAgentProfilesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<AgentProfileSummary>>,
          List<AgentProfileSummary>,
          FutureOr<List<AgentProfileSummary>>
        >
    with
        $FutureModifier<List<AgentProfileSummary>>,
        $FutureProvider<List<AgentProfileSummary>> {
  MobileRunAgentProfilesProvider._({
    required MobileRunAgentProfilesFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'mobileRunAgentProfilesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileRunAgentProfilesHash();

  @override
  String toString() {
    return r'mobileRunAgentProfilesProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<AgentProfileSummary>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<AgentProfileSummary>> create(Ref ref) {
    final argument = this.argument as String;
    return mobileRunAgentProfiles(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is MobileRunAgentProfilesProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileRunAgentProfilesHash() =>
    r'3ea1b6d35abedb25865a3aa9f36c20eb9845e51b';

final class MobileRunAgentProfilesFamily extends $Family
    with
        $FunctionalFamilyOverride<FutureOr<List<AgentProfileSummary>>, String> {
  MobileRunAgentProfilesFamily._()
    : super(
        retry: null,
        name: r'mobileRunAgentProfilesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  MobileRunAgentProfilesProvider call(String hostId) =>
      MobileRunAgentProfilesProvider._(argument: hostId, from: this);

  @override
  String toString() => r'mobileRunAgentProfilesProvider';
}

/// The commit an isolated run in [workspaceId] would start from.

@ProviderFor(mobileRunSource)
final mobileRunSourceProvider = MobileRunSourceFamily._();

/// The commit an isolated run in [workspaceId] would start from.

final class MobileRunSourceProvider
    extends
        $FunctionalProvider<
          AsyncValue<RunSourceSnapshot>,
          RunSourceSnapshot,
          FutureOr<RunSourceSnapshot>
        >
    with
        $FutureModifier<RunSourceSnapshot>,
        $FutureProvider<RunSourceSnapshot> {
  /// The commit an isolated run in [workspaceId] would start from.
  MobileRunSourceProvider._({
    required MobileRunSourceFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'mobileRunSourceProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileRunSourceHash();

  @override
  String toString() {
    return r'mobileRunSourceProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<RunSourceSnapshot> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<RunSourceSnapshot> create(Ref ref) {
    final argument = this.argument as (String, String);
    return mobileRunSource(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is MobileRunSourceProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileRunSourceHash() => r'fbbbcbb4677d54c9d58a8778b847057aa46828a8';

/// The commit an isolated run in [workspaceId] would start from.

final class MobileRunSourceFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<RunSourceSnapshot>,
          (String, String)
        > {
  MobileRunSourceFamily._()
    : super(
        retry: null,
        name: r'mobileRunSourceProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The commit an isolated run in [workspaceId] would start from.

  MobileRunSourceProvider call(String hostId, String workspaceId) =>
      MobileRunSourceProvider._(argument: (hostId, workspaceId), from: this);

  @override
  String toString() => r'mobileRunSourceProvider';
}

/// Filters of the runs list, kept per host while the app runs.

@ProviderFor(MobileRunListController)
final mobileRunListControllerProvider = MobileRunListControllerFamily._();

/// Filters of the runs list, kept per host while the app runs.
final class MobileRunListControllerProvider
    extends $NotifierProvider<MobileRunListController, MobileRunListState> {
  /// Filters of the runs list, kept per host while the app runs.
  MobileRunListControllerProvider._({
    required MobileRunListControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'mobileRunListControllerProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileRunListControllerHash();

  @override
  String toString() {
    return r'mobileRunListControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  MobileRunListController create() => MobileRunListController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MobileRunListState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MobileRunListState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is MobileRunListControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileRunListControllerHash() =>
    r'2630afa302791e4021fab2884ebf63219a9db973';

/// Filters of the runs list, kept per host while the app runs.

final class MobileRunListControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          MobileRunListController,
          MobileRunListState,
          MobileRunListState,
          MobileRunListState,
          String
        > {
  MobileRunListControllerFamily._()
    : super(
        retry: null,
        name: r'mobileRunListControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Filters of the runs list, kept per host while the app runs.

  MobileRunListControllerProvider call(String hostId) =>
      MobileRunListControllerProvider._(argument: hostId, from: this);

  @override
  String toString() => r'mobileRunListControllerProvider';
}

/// Filters of the runs list, kept per host while the app runs.

abstract class _$MobileRunListController extends $Notifier<MobileRunListState> {
  late final _$args = ref.$arg as String;
  String get hostId => _$args;

  MobileRunListState build(String hostId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<MobileRunListState, MobileRunListState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<MobileRunListState, MobileRunListState>,
              MobileRunListState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
