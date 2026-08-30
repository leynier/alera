// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'run_board_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(runBoardRepository)
final runBoardRepositoryProvider = RunBoardRepositoryProvider._();

final class RunBoardRepositoryProvider
    extends
        $FunctionalProvider<
          RuntimeRunBoardRepository,
          RuntimeRunBoardRepository,
          RuntimeRunBoardRepository
        >
    with $Provider<RuntimeRunBoardRepository> {
  RunBoardRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'runBoardRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$runBoardRepositoryHash();

  @$internal
  @override
  $ProviderElement<RuntimeRunBoardRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  RuntimeRunBoardRepository create(Ref ref) {
    return runBoardRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RuntimeRunBoardRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RuntimeRunBoardRepository>(value),
    );
  }
}

String _$runBoardRepositoryHash() =>
    r'57d22ca531c28220b096a2e1c2d1c2e9f7d9feaf';

@ProviderFor(runBoardSnapshot)
final runBoardSnapshotProvider = RunBoardSnapshotFamily._();

final class RunBoardSnapshotProvider
    extends
        $FunctionalProvider<
          AsyncValue<RunBoardSnapshot>,
          RunBoardSnapshot,
          Stream<RunBoardSnapshot>
        >
    with $FutureModifier<RunBoardSnapshot>, $StreamProvider<RunBoardSnapshot> {
  RunBoardSnapshotProvider._({
    required RunBoardSnapshotFamily super.from,
    required ({
      String? projectId,
      String? workspaceId,
      String? search,
      RunBoardBucket? bucket,
    })
    super.argument,
  }) : super(
         retry: null,
         name: r'runBoardSnapshotProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$runBoardSnapshotHash();

  @override
  String toString() {
    return r'runBoardSnapshotProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $StreamProviderElement<RunBoardSnapshot> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<RunBoardSnapshot> create(Ref ref) {
    final argument =
        this.argument
            as ({
              String? projectId,
              String? workspaceId,
              String? search,
              RunBoardBucket? bucket,
            });
    return runBoardSnapshot(
      ref,
      projectId: argument.projectId,
      workspaceId: argument.workspaceId,
      search: argument.search,
      bucket: argument.bucket,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is RunBoardSnapshotProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$runBoardSnapshotHash() => r'e7b22a7013dd09e0ac85162328246c93cdc76086';

final class RunBoardSnapshotFamily extends $Family
    with
        $FunctionalFamilyOverride<
          Stream<RunBoardSnapshot>,
          ({
            String? projectId,
            String? workspaceId,
            String? search,
            RunBoardBucket? bucket,
          })
        > {
  RunBoardSnapshotFamily._()
    : super(
        retry: null,
        name: r'runBoardSnapshotProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  RunBoardSnapshotProvider call({
    String? projectId,
    String? workspaceId,
    String? search,
    RunBoardBucket? bucket,
  }) => RunBoardSnapshotProvider._(
    argument: (
      projectId: projectId,
      workspaceId: workspaceId,
      search: search,
      bucket: bucket,
    ),
    from: this,
  );

  @override
  String toString() => r'runBoardSnapshotProvider';
}

@ProviderFor(orchestrationRunSnapshot)
final orchestrationRunSnapshotProvider = OrchestrationRunSnapshotFamily._();

final class OrchestrationRunSnapshotProvider
    extends
        $FunctionalProvider<
          AsyncValue<RunSnapshot>,
          RunSnapshot,
          Stream<RunSnapshot>
        >
    with $FutureModifier<RunSnapshot>, $StreamProvider<RunSnapshot> {
  OrchestrationRunSnapshotProvider._({
    required OrchestrationRunSnapshotFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'orchestrationRunSnapshotProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$orchestrationRunSnapshotHash();

  @override
  String toString() {
    return r'orchestrationRunSnapshotProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<RunSnapshot> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<RunSnapshot> create(Ref ref) {
    final argument = this.argument as String;
    return orchestrationRunSnapshot(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is OrchestrationRunSnapshotProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$orchestrationRunSnapshotHash() =>
    r'aceeb80c3fe4d29025cf6083e6c314c029f6a641';

final class OrchestrationRunSnapshotFamily extends $Family
    with $FunctionalFamilyOverride<Stream<RunSnapshot>, String> {
  OrchestrationRunSnapshotFamily._()
    : super(
        retry: null,
        name: r'orchestrationRunSnapshotProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  OrchestrationRunSnapshotProvider call(String runId) =>
      OrchestrationRunSnapshotProvider._(argument: runId, from: this);

  @override
  String toString() => r'orchestrationRunSnapshotProvider';
}
