// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'run_detail_pages.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// One run: Overview, Tasks and the planning view all read it.

@ProviderFor(RunDetail)
final runDetailProvider = RunDetailFamily._();

/// One run: Overview, Tasks and the planning view all read it.
final class RunDetailProvider
    extends $StreamNotifierProvider<RunDetail, RunPageRead<RunSnapshot>> {
  /// One run: Overview, Tasks and the planning view all read it.
  RunDetailProvider._({
    required RunDetailFamily super.from,
    required String super.argument,
  }) : super(
         retry: runNoRetry,
         name: r'runDetailProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$runDetailHash();

  @override
  String toString() {
    return r'runDetailProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  RunDetail create() => RunDetail();

  @override
  bool operator ==(Object other) {
    return other is RunDetailProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$runDetailHash() => r'd966ac34733fdd30a66b5986a06755bb67b29baf';

/// One run: Overview, Tasks and the planning view all read it.

final class RunDetailFamily extends $Family
    with
        $ClassFamilyOverride<
          RunDetail,
          AsyncValue<RunPageRead<RunSnapshot>>,
          RunPageRead<RunSnapshot>,
          Stream<RunPageRead<RunSnapshot>>,
          String
        > {
  RunDetailFamily._()
    : super(
        retry: runNoRetry,
        name: r'runDetailProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// One run: Overview, Tasks and the planning view all read it.

  RunDetailProvider call(String runId) =>
      RunDetailProvider._(argument: runId, from: this);

  @override
  String toString() => r'runDetailProvider';
}

/// One run: Overview, Tasks and the planning view all read it.

abstract class _$RunDetail extends $StreamNotifier<RunPageRead<RunSnapshot>> {
  late final _$args = ref.$arg as String;
  String get runId => _$args;

  Stream<RunPageRead<RunSnapshot>> build(String runId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<RunPageRead<RunSnapshot>>,
              RunPageRead<RunSnapshot>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<RunPageRead<RunSnapshot>>,
                RunPageRead<RunSnapshot>
              >,
              AsyncValue<RunPageRead<RunSnapshot>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// One task with its history; older history loads on demand.

@ProviderFor(RunTaskInspectionPage)
final runTaskInspectionPageProvider = RunTaskInspectionPageFamily._();

/// One task with its history; older history loads on demand.
final class RunTaskInspectionPageProvider
    extends
        $StreamNotifierProvider<
          RunTaskInspectionPage,
          RunPageRead<TaskInspection>
        > {
  /// One task with its history; older history loads on demand.
  RunTaskInspectionPageProvider._({
    required RunTaskInspectionPageFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: runNoRetry,
         name: r'runTaskInspectionPageProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$runTaskInspectionPageHash();

  @override
  String toString() {
    return r'runTaskInspectionPageProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  RunTaskInspectionPage create() => RunTaskInspectionPage();

  @override
  bool operator ==(Object other) {
    return other is RunTaskInspectionPageProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$runTaskInspectionPageHash() =>
    r'563e657fcb284e1d12bae0ec34099b8a19639ba2';

/// One task with its history; older history loads on demand.

final class RunTaskInspectionPageFamily extends $Family
    with
        $ClassFamilyOverride<
          RunTaskInspectionPage,
          AsyncValue<RunPageRead<TaskInspection>>,
          RunPageRead<TaskInspection>,
          Stream<RunPageRead<TaskInspection>>,
          (String, String)
        > {
  RunTaskInspectionPageFamily._()
    : super(
        retry: runNoRetry,
        name: r'runTaskInspectionPageProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// One task with its history; older history loads on demand.

  RunTaskInspectionPageProvider call(String runId, String taskId) =>
      RunTaskInspectionPageProvider._(argument: (runId, taskId), from: this);

  @override
  String toString() => r'runTaskInspectionPageProvider';
}

/// One task with its history; older history loads on demand.

abstract class _$RunTaskInspectionPage
    extends $StreamNotifier<RunPageRead<TaskInspection>> {
  late final _$args = ref.$arg as (String, String);
  String get runId => _$args.$1;
  String get taskId => _$args.$2;

  Stream<RunPageRead<TaskInspection>> build(String runId, String taskId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<RunPageRead<TaskInspection>>,
              RunPageRead<TaskInspection>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<RunPageRead<TaskInspection>>,
                RunPageRead<TaskInspection>
              >,
              AsyncValue<RunPageRead<TaskInspection>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}

/// A gate with its plan and evidence, read when a card expands.

@ProviderFor(runGateDetail)
final runGateDetailProvider = RunGateDetailFamily._();

/// A gate with its plan and evidence, read when a card expands.

final class RunGateDetailProvider
    extends
        $FunctionalProvider<
          AsyncValue<RunGateDetail>,
          RunGateDetail,
          Stream<RunGateDetail>
        >
    with $FutureModifier<RunGateDetail>, $StreamProvider<RunGateDetail> {
  /// A gate with its plan and evidence, read when a card expands.
  RunGateDetailProvider._({
    required RunGateDetailFamily super.from,
    required String super.argument,
  }) : super(
         retry: runNoRetry,
         name: r'runGateDetailProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$runGateDetailHash();

  @override
  String toString() {
    return r'runGateDetailProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<RunGateDetail> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<RunGateDetail> create(Ref ref) {
    final argument = this.argument as String;
    return runGateDetail(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is RunGateDetailProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$runGateDetailHash() => r'3b08d1d2924909c9d29cea9d3261e63a6931e342';

/// A gate with its plan and evidence, read when a card expands.

final class RunGateDetailFamily extends $Family
    with $FunctionalFamilyOverride<Stream<RunGateDetail>, String> {
  RunGateDetailFamily._()
    : super(
        retry: runNoRetry,
        name: r'runGateDetailProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// A gate with its plan and evidence, read when a card expands.

  RunGateDetailProvider call(String gateId) =>
      RunGateDetailProvider._(argument: gateId, from: this);

  @override
  String toString() => r'runGateDetailProvider';
}

/// The current plan of a run, for the approver and recipe facts. Keyed by
/// revision and approval state, so it re-reads when either changes.

@ProviderFor(runPlan)
final runPlanProvider = RunPlanFamily._();

/// The current plan of a run, for the approver and recipe facts. Keyed by
/// revision and approval state, so it re-reads when either changes.

final class RunPlanProvider
    extends
        $FunctionalProvider<
          AsyncValue<RunPlanView?>,
          RunPlanView?,
          FutureOr<RunPlanView?>
        >
    with $FutureModifier<RunPlanView?>, $FutureProvider<RunPlanView?> {
  /// The current plan of a run, for the approver and recipe facts. Keyed by
  /// revision and approval state, so it re-reads when either changes.
  RunPlanProvider._({
    required RunPlanFamily super.from,
    required (String, {int? revision, String? state}) super.argument,
  }) : super(
         retry: runNoRetry,
         name: r'runPlanProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$runPlanHash();

  @override
  String toString() {
    return r'runPlanProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<RunPlanView?> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<RunPlanView?> create(Ref ref) {
    final argument = this.argument as (String, {int? revision, String? state});
    return runPlan(
      ref,
      argument.$1,
      revision: argument.revision,
      state: argument.state,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is RunPlanProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$runPlanHash() => r'1ee1356bfdc24f08ce73900ce903562a208199f3';

/// The current plan of a run, for the approver and recipe facts. Keyed by
/// revision and approval state, so it re-reads when either changes.

final class RunPlanFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<RunPlanView?>,
          (String, {int? revision, String? state})
        > {
  RunPlanFamily._()
    : super(
        retry: runNoRetry,
        name: r'runPlanProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The current plan of a run, for the approver and recipe facts. Keyed by
  /// revision and approval state, so it re-reads when either changes.

  RunPlanProvider call(String runId, {int? revision, String? state}) =>
      RunPlanProvider._(
        argument: (runId, revision: revision, state: state),
        from: this,
      );

  @override
  String toString() => r'runPlanProvider';
}
