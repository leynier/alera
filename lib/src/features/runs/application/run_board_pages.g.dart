// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'run_board_pages.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The attention bucket: its count for the chip and rail, and its newest rows
/// for the hover card. Hidden windows do no reads.

@ProviderFor(runBoardAttention)
final runBoardAttentionProvider = RunBoardAttentionProvider._();

/// The attention bucket: its count for the chip and rail, and its newest rows
/// for the hover card. Hidden windows do no reads.

final class RunBoardAttentionProvider
    extends
        $FunctionalProvider<
          AsyncValue<RunBoardPage>,
          RunBoardPage,
          Stream<RunBoardPage>
        >
    with $FutureModifier<RunBoardPage>, $StreamProvider<RunBoardPage> {
  /// The attention bucket: its count for the chip and rail, and its newest rows
  /// for the hover card. Hidden windows do no reads.
  RunBoardAttentionProvider._()
    : super(
        from: null,
        argument: null,
        retry: runNoRetry,
        name: r'runBoardAttentionProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$runBoardAttentionHash();

  @$internal
  @override
  $StreamProviderElement<RunBoardPage> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<RunBoardPage> create(Ref ref) {
    return runBoardAttention(ref);
  }
}

String _$runBoardAttentionHash() => r'c38f6a53d611b7bca2879a9e27d97cfdcd9f44d1';

@ProviderFor(RunBoardListPage)
final runBoardListPageProvider = RunBoardListPageFamily._();

final class RunBoardListPageProvider
    extends
        $StreamNotifierProvider<RunBoardListPage, RunPageRead<RunBoardPage>> {
  RunBoardListPageProvider._({
    required RunBoardListPageFamily super.from,
    required ({
      String? projectId,
      String? workspaceId,
      String search,
      RunBucket? bucket,
    })
    super.argument,
  }) : super(
         retry: runNoRetry,
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

String _$runBoardListPageHash() => r'fa1349f76a6e5f8838699bae4fd7421a1f3f54dc';

final class RunBoardListPageFamily extends $Family
    with
        $ClassFamilyOverride<
          RunBoardListPage,
          AsyncValue<RunPageRead<RunBoardPage>>,
          RunPageRead<RunBoardPage>,
          Stream<RunPageRead<RunBoardPage>>,
          ({
            String? projectId,
            String? workspaceId,
            String search,
            RunBucket? bucket,
          })
        > {
  RunBoardListPageFamily._()
    : super(
        retry: runNoRetry,
        name: r'runBoardListPageProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  RunBoardListPageProvider call({
    String? projectId,
    String? workspaceId,
    String search = '',
    RunBucket? bucket,
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
    extends $StreamNotifier<RunPageRead<RunBoardPage>> {
  late final _$args =
      ref.$arg
          as ({
            String? projectId,
            String? workspaceId,
            String search,
            RunBucket? bucket,
          });
  String? get projectId => _$args.projectId;
  String? get workspaceId => _$args.workspaceId;
  String get search => _$args.search;
  RunBucket? get bucket => _$args.bucket;

  Stream<RunPageRead<RunBoardPage>> build({
    String? projectId,
    String? workspaceId,
    String search = '',
    RunBucket? bucket,
  });
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<RunPageRead<RunBoardPage>>,
              RunPageRead<RunBoardPage>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<RunPageRead<RunBoardPage>>,
                RunPageRead<RunBoardPage>
              >,
              AsyncValue<RunPageRead<RunBoardPage>>,
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
