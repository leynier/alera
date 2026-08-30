// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'run_board_pages.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(runBoardAttention)
final runBoardAttentionProvider = RunBoardAttentionProvider._();

final class RunBoardAttentionProvider
    extends
        $FunctionalProvider<
          AsyncValue<RunBoardCounts>,
          RunBoardCounts,
          Stream<RunBoardCounts>
        >
    with $FutureModifier<RunBoardCounts>, $StreamProvider<RunBoardCounts> {
  RunBoardAttentionProvider._()
    : super(
        from: null,
        argument: null,
        retry: _noRetry,
        name: r'runBoardAttentionProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$runBoardAttentionHash();

  @$internal
  @override
  $StreamProviderElement<RunBoardCounts> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<RunBoardCounts> create(Ref ref) {
    return runBoardAttention(ref);
  }
}

String _$runBoardAttentionHash() => r'5d64f77b61d7afb562bd7c272391ddeabcc18d8d';

@ProviderFor(RunBoardListPage)
final runBoardListPageProvider = RunBoardListPageFamily._();

final class RunBoardListPageProvider
    extends
        $StreamNotifierProvider<
          RunBoardListPage,
          RunBoardRead<RunBoardSnapshot>
        > {
  RunBoardListPageProvider._({
    required RunBoardListPageFamily super.from,
    required ({
      String? projectId,
      String? workspaceId,
      String search,
      RunBoardBucket? bucket,
    })
    super.argument,
  }) : super(
         retry: _noRetry,
         name: r'runBoardListPageProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$runBoardListPageHash();

  @override
  String toString() {
    return r'runBoardListPageProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  RunBoardListPage create() => RunBoardListPage();

  @override
  bool operator ==(Object other) {
    return other is RunBoardListPageProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$runBoardListPageHash() => r'0dcebf9e5203ea260ade8118aced375ff3721933';

final class RunBoardListPageFamily extends $Family
    with
        $ClassFamilyOverride<
          RunBoardListPage,
          AsyncValue<RunBoardRead<RunBoardSnapshot>>,
          RunBoardRead<RunBoardSnapshot>,
          Stream<RunBoardRead<RunBoardSnapshot>>,
          ({
            String? projectId,
            String? workspaceId,
            String search,
            RunBoardBucket? bucket,
          })
        > {
  RunBoardListPageFamily._()
    : super(
        retry: _noRetry,
        name: r'runBoardListPageProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  RunBoardListPageProvider call({
    String? projectId,
    String? workspaceId,
    String search = '',
    RunBoardBucket? bucket,
  }) => RunBoardListPageProvider._(
    argument: (
      projectId: projectId,
      workspaceId: workspaceId,
      search: search,
      bucket: bucket,
    ),
    from: this,
  );

  @override
  String toString() => r'runBoardListPageProvider';
}

abstract class _$RunBoardListPage
    extends $StreamNotifier<RunBoardRead<RunBoardSnapshot>> {
  late final _$args =
      ref.$arg
          as ({
            String? projectId,
            String? workspaceId,
            String search,
            RunBoardBucket? bucket,
          });
  String? get projectId => _$args.projectId;
  String? get workspaceId => _$args.workspaceId;
  String get search => _$args.search;
  RunBoardBucket? get bucket => _$args.bucket;

  Stream<RunBoardRead<RunBoardSnapshot>> build({
    String? projectId,
    String? workspaceId,
    String search = '',
    RunBoardBucket? bucket,
  });
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<RunBoardRead<RunBoardSnapshot>>,
              RunBoardRead<RunBoardSnapshot>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<RunBoardRead<RunBoardSnapshot>>,
                RunBoardRead<RunBoardSnapshot>
              >,
              AsyncValue<RunBoardRead<RunBoardSnapshot>>,
              Object?,
              Object?
            >;
    return element.handleCreate(
      ref,
      () => build(
        projectId: _$args.projectId,
        workspaceId: _$args.workspaceId,
        search: _$args.search,
        bucket: _$args.bucket,
      ),
    );
  }
}

@ProviderFor(RunTaskPage)
final runTaskPageProvider = RunTaskPageFamily._();

final class RunTaskPageProvider
    extends $StreamNotifierProvider<RunTaskPage, RunBoardRead<RunSnapshot>> {
  RunTaskPageProvider._({
    required RunTaskPageFamily super.from,
    required String super.argument,
  }) : super(
         retry: _noRetry,
         name: r'runTaskPageProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$runTaskPageHash();

  @override
  String toString() {
    return r'runTaskPageProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  RunTaskPage create() => RunTaskPage();

  @override
  bool operator ==(Object other) {
    return other is RunTaskPageProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$runTaskPageHash() => r'0863be7942f24c91a3af8437594b8b3ee6a1fb58';

final class RunTaskPageFamily extends $Family
    with
        $ClassFamilyOverride<
          RunTaskPage,
          AsyncValue<RunBoardRead<RunSnapshot>>,
          RunBoardRead<RunSnapshot>,
          Stream<RunBoardRead<RunSnapshot>>,
          String
        > {
  RunTaskPageFamily._()
    : super(
        retry: _noRetry,
        name: r'runTaskPageProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  RunTaskPageProvider call(String runId) =>
      RunTaskPageProvider._(argument: runId, from: this);

  @override
  String toString() => r'runTaskPageProvider';
}

abstract class _$RunTaskPage
    extends $StreamNotifier<RunBoardRead<RunSnapshot>> {
  late final _$args = ref.$arg as String;
  String get runId => _$args;

  Stream<RunBoardRead<RunSnapshot>> build(String runId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<RunBoardRead<RunSnapshot>>,
              RunBoardRead<RunSnapshot>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<RunBoardRead<RunSnapshot>>,
                RunBoardRead<RunSnapshot>
              >,
              AsyncValue<RunBoardRead<RunSnapshot>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

@ProviderFor(RunTaskInspectionPage)
final runTaskInspectionPageProvider = RunTaskInspectionPageFamily._();

final class RunTaskInspectionPageProvider
    extends
        $StreamNotifierProvider<
          RunTaskInspectionPage,
          RunBoardRead<TaskInspectionPage>
        > {
  RunTaskInspectionPageProvider._({
    required RunTaskInspectionPageFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: _noRetry,
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
    r'999026397c59cbe1d046587f9acd87ba690515f2';

final class RunTaskInspectionPageFamily extends $Family
    with
        $ClassFamilyOverride<
          RunTaskInspectionPage,
          AsyncValue<RunBoardRead<TaskInspectionPage>>,
          RunBoardRead<TaskInspectionPage>,
          Stream<RunBoardRead<TaskInspectionPage>>,
          (String, String)
        > {
  RunTaskInspectionPageFamily._()
    : super(
        retry: _noRetry,
        name: r'runTaskInspectionPageProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  RunTaskInspectionPageProvider call(String runId, String taskId) =>
      RunTaskInspectionPageProvider._(argument: (runId, taskId), from: this);

  @override
  String toString() => r'runTaskInspectionPageProvider';
}

abstract class _$RunTaskInspectionPage
    extends $StreamNotifier<RunBoardRead<TaskInspectionPage>> {
  late final _$args = ref.$arg as (String, String);
  String get runId => _$args.$1;
  String get taskId => _$args.$2;

  Stream<RunBoardRead<TaskInspectionPage>> build(String runId, String taskId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<RunBoardRead<TaskInspectionPage>>,
              RunBoardRead<TaskInspectionPage>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<RunBoardRead<TaskInspectionPage>>,
                RunBoardRead<TaskInspectionPage>
              >,
              AsyncValue<RunBoardRead<TaskInspectionPage>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}
